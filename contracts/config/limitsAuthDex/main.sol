// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { DexCalcs } from "../../libraries/dexCalcs.sol";
import { IFluidDexT1 } from "../../protocols/dex/interfaces/iDexT1.sol";
import { IFluidDexT1Admin } from "../../protocols/dex/interfaces/iDexT1Admin.sol";
import { IFluidAuthGate, IFluidAuthGateLiquidity, FluidAuthLevels } from "../authGate/interfaces/iAuthGate.sol";
import { BasicValidations } from "../../libraries/utils/basicValidations.sol";
import { Structs as AdminModuleStructs } from "../../protocols/dex/poolT1/adminModule/structs.sol";
import { BigMathMinified } from "../../libraries/bigMathMinified.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

abstract contract Events {
    /// @notice emitted when multisig successfully changes the withdrawal limit
    event LogSetWithdrawalLimit(address dex, address user, uint256 newLimit);

    /// @notice emitted when multisig changes the withdrawal limit config
    event LogSetUserWithdrawLimit(address dex, address user, uint256 baseLimit);

    /// @notice emitted when multisig changes the borrow limit config
    event LogSetUserBorrowLimits(address dex, address user, uint256 baseLimit, uint256 maxLimit);

    /// @notice emitted when multisig changes the max borrow shares
    event LogSetMaxBorrowShares(address dex, uint256 maxBorrowShares);

    /// @notice emitted when multisig changes the max supply shares
    event LogSetMaxSupplyShares(address dex, uint256 maxSupplyShares);

    /// @notice emitted when a limits update re-instated a side pause that the pool config update had lifted
    event LogRePauseUser(address dex, address user, bool supply, bool borrow);
}

abstract contract Constants is FluidAuthLevels {
    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X24 = 0xffffff;

    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    /// @dev Set this to 20 for a +/-20% limit
    uint256 internal constant MAX_PERCENT_CHANGE = 20;

    /// @notice auth gate resolving multisig/governance identity; MID-level auths pass `onlyAuthLevelMid`.
    IFluidAuthGate public immutable AUTH_GATE;

    uint256 internal constant COOLDOWN_PERIOD = 4 days;
}

abstract contract Variables is Constants {
    // dex => user => lastUpdateTime for cooldown checks
    mapping(address => mapping(address => uint256)) public lastUpdateTime;
}

contract FluidLimitsAuthDex is Variables, Error, Events, BasicValidations {
    modifier onlyAuthLevelMid() {
        AUTH_GATE.requireAuthLevelMid(msg.sender);
        _;
    }

    constructor(address authGate_) validAddress(authGate_) {
        if (IFluidAuthGateLiquidity(authGate_).LIQUIDITY() == address(0)) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__InvalidParams);
        }
        AUTH_GATE = IFluidAuthGate(authGate_);
    }

    /// @notice Sets the withdrawal limit for a specific user at a dex
    /// @param dex_ The address of the dex
    /// @param user_ The address of the user for which to set the withdrawal limit
    /// @param newLimit_ The new withdrawal limit to be set
    function setWithdrawalLimit(address dex_, address user_, uint256 newLimit_) external onlyAuthLevelMid {
        IFluidDexT1Admin(dex_).updateUserWithdrawalLimit(user_, newLimit_);
        emit LogSetWithdrawalLimit(dex_, user_, newLimit_);
    }

    /// @notice Sets the user withdraw base limit at a specific dex for a user (vault) without restrictions.
    ///         `updateUserSupplyConfigs` force-re-enables the user's supply side on the pool, so if that side was
    ///         paused it is re-paused within the same transaction, emitting `LogRePauseUser`.
    /// @param dex_ The address of the dex at which to set the user withdraw limit
    /// @param user_ The address of the user for which to set the user withdraw limit
    /// @param baseLimit_ The base limit for the user supply; must be non-zero.
    /// @param skipMaxPercentChangeCheck_ allow full range of limit check. Keep to false by default to have additional human error check.
    function setUserWithdrawLimit(
        address dex_,
        address user_,
        uint256 baseLimit_,
        bool skipMaxPercentChangeCheck_
    ) external onlyAuthLevelMid {
        if (baseLimit_ == 0) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__InvalidParams);
        }

        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs[0] = getUserSupplyConfig(dex_, user_);

        if (userSupplyConfigs[0].user == address(0)) {
            // user is not defined yet
            revert FluidConfigError(ErrorTypes.LimitsAuth__UserNotDefinedYet);
        }

        if (!skipMaxPercentChangeCheck_) {
            _validateWithinMaxPercentChange(userSupplyConfigs[0].baseWithdrawalLimit, baseLimit_);
        }

        userSupplyConfigs[0].baseWithdrawalLimit = baseLimit_;

        bool wasPaused_ = _isSidePaused(dex_, user_, DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT);

        IFluidDexT1Admin(dex_).updateUserSupplyConfigs(userSupplyConfigs);

        emit LogSetUserWithdrawLimit(dex_, user_, userSupplyConfigs[0].baseWithdrawalLimit);

        if (wasPaused_) {
            // hard call: a failed re-pause must revert rather than leave the side open
            IFluidDexT1Admin(dex_).pauseUser(user_, true, false);

            emit LogRePauseUser(dex_, user_, true, false);
        }
    }

    /// @notice Sets the user borrow limits at a specific dex for a user (vault), with time and max percent change restrictions.
    ///         `updateUserBorrowConfigs` force-re-enables the user's borrow side on the pool, so if that side was
    ///         paused it is re-paused within the same transaction, emitting `LogRePauseUser`.
    /// @param dex_ The address of the dex at which to set the user borrow limit
    /// @param user_ The address of the user for which to set the user borrow limit
    /// @param baseLimit_ The base limit for the user borrow. Set to 0 to keep current value.
    /// @param maxLimit_ The max limit for the user borrow. Set to 0 to keep current value.
    function setUserBorrowLimits(
        address dex_,
        address user_,
        uint256 baseLimit_,
        uint256 maxLimit_
    ) external onlyAuthLevelMid {
        if (baseLimit_ == 0 && maxLimit_ == 0) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__InvalidParams);
        }

        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs[0] = getUserBorrowConfig(dex_, user_);

        if (userBorrowConfigs[0].user == address(0)) {
            // user is not defined yet
            revert FluidConfigError(ErrorTypes.LimitsAuth__UserNotDefinedYet);
        }

        _validateLastUpdateTime(lastUpdateTime[dex_][user_]);

        if (baseLimit_ != 0) {
            _validateWithinMaxPercentChange(userBorrowConfigs[0].baseDebtCeiling, baseLimit_);
            userBorrowConfigs[0].baseDebtCeiling = baseLimit_;
        }

        if (maxLimit_ != 0) {
            _validateWithinMaxPercentChange(userBorrowConfigs[0].maxDebtCeiling, maxLimit_);
            userBorrowConfigs[0].maxDebtCeiling = maxLimit_;
        }

        lastUpdateTime[dex_][user_] = block.timestamp;

        bool wasPaused_ = _isSidePaused(dex_, user_, DexSlotsLink.DEX_USER_BORROW_MAPPING_SLOT);

        IFluidDexT1Admin(dex_).updateUserBorrowConfigs(userBorrowConfigs);

        emit LogSetUserBorrowLimits(
            dex_,
            user_,
            userBorrowConfigs[0].baseDebtCeiling,
            userBorrowConfigs[0].maxDebtCeiling
        );

        if (wasPaused_) {
            // hard call: a failed re-pause must revert rather than leave the side open
            IFluidDexT1Admin(dex_).pauseUser(user_, false, true);

            emit LogRePauseUser(dex_, user_, false, true);
        }
    }

    /// @notice Sets the max borrow shares of a DEX. To update max supply and max borrow shares at once within same coolDown, use setMaxShares.
    /// @param dex_ The address of the dex at which to set the max borrow shares
    /// @param maxBorrowShares_ The max borrow shares.
    /// @param confirmLiquidityLimitsCoverCap_  Reminder to manually confirm that the limits for the dex at liquidity layer cover the cap.
    function setMaxBorrowShares(
        address dex_,
        uint256 maxBorrowShares_,
        bool confirmLiquidityLimitsCoverCap_
    ) external onlyAuthLevelMid {
        _validateSetDexShares(dex_, confirmLiquidityLimitsCoverCap_);
        _setMaxBorrowShares(dex_, maxBorrowShares_);
    }

    /// @notice Sets the max supply shares of a DEX. To update max supply and max borrow shares at once within same coolDown, use setMaxShares.
    /// @param dex_ The address of the dex at which to set the max supply shares
    /// @param maxSupplyShares_ The max supply shares.
    /// @param confirmLiquidityLimitsCoverCap_  Reminder to manually confirm that the limits for the dex at liquidity layer cover the cap.
    function setMaxSupplyShares(
        address dex_,
        uint256 maxSupplyShares_,
        bool confirmLiquidityLimitsCoverCap_
    ) external onlyAuthLevelMid {
        _validateSetDexShares(dex_, confirmLiquidityLimitsCoverCap_);
        _setMaxSupplyShares(dex_, maxSupplyShares_);
    }

    /// @notice Sets both max borrow shares and max supply shares of a DEX at once.
    /// @param dex_ The address of the dex at which to set the max shares
    /// @param maxSupplyShares_ The max supply shares.
    /// @param maxBorrowShares_ The max borrow shares.
    /// @param confirmLiquidityLimitsCoverCap_  Reminder to manually confirm that the limits for the dex at liquidity layer cover the cap.
    function setMaxShares(
        address dex_,
        uint256 maxSupplyShares_,
        uint256 maxBorrowShares_,
        bool confirmLiquidityLimitsCoverCap_
    ) external onlyAuthLevelMid {
        _validateSetDexShares(dex_, confirmLiquidityLimitsCoverCap_);
        _setMaxSupplyShares(dex_, maxSupplyShares_);
        _setMaxBorrowShares(dex_, maxBorrowShares_);
    }

    ////////////////////////////////// INTERNAL HELPERS ////////////////////////////////////////////////////////

    /// @dev Validates parameters for setting DEX shares.
    function _validateSetDexShares(address dex_, bool confirmLiquidityLimitsCoverCap_) internal {
        if (!confirmLiquidityLimitsCoverCap_) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__InvalidParams);
        }

        _validateLastUpdateTime(lastUpdateTime[dex_][dex_]);
        lastUpdateTime[dex_][dex_] = block.timestamp;
    }

    /// @dev Sets the max borrow shares for a DEX.
    function _setMaxBorrowShares(address dex_, uint256 maxBorrowShares_) internal {
        uint256 currentMaxBorrowShares_ = getMaxBorrowShares(dex_);
        _validateWithinMaxPercentChange(currentMaxBorrowShares_, maxBorrowShares_);

        IFluidDexT1Admin(dex_).updateMaxBorrowShares(maxBorrowShares_);

        emit LogSetMaxBorrowShares(dex_, maxBorrowShares_);
    }

    /// @dev Sets the max supply shares for a DEX.
    function _setMaxSupplyShares(address dex_, uint256 maxSupplyShares_) internal {
        uint256 currentMaxSupplyShares_ = getMaxSupplyShares(dex_);
        _validateWithinMaxPercentChange(currentMaxSupplyShares_, maxSupplyShares_);

        IFluidDexT1Admin(dex_).updateMaxSupplyShares(maxSupplyShares_);

        emit LogSetMaxSupplyShares(dex_, maxSupplyShares_);
    }

    /// @dev Validates that the new limit is within the allowed max percent change.
    function _validateWithinMaxPercentChange(uint256 oldLimit_, uint256 newLimit_) internal pure {
        uint256 maxDelta = (oldLimit_ * MAX_PERCENT_CHANGE) / 100; // 20% of oldLimit_

        if (newLimit_ > oldLimit_ && (newLimit_ - oldLimit_) > maxDelta) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__ExceedAllowedPercentageChange);
        } else if (newLimit_ < oldLimit_ && (oldLimit_ - newLimit_) > maxDelta) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__ExceedAllowedPercentageChange);
        }
    }

    /// @dev Reads bit 0 of the user's packed word at `mappingSlot_` (supply or borrow) on `dex_`. A configured user
    ///      has non-zero data, and bit 0 == 0 there means that whole side is paused.
    function _isSidePaused(address dex_, address user_, uint256 mappingSlot_) internal view returns (bool) {
        uint256 userData_ = IFluidDexT1(dex_).readFromStorage(
            DexSlotsLink.calculateMappingStorageSlot(mappingSlot_, user_)
        );

        return userData_ > 0 && userData_ & 1 == 0;
    }

    /// @dev Validates that the cooldown period has passed since the last update.
    function _validateLastUpdateTime(uint256 lastUpdateTime_) internal view {
        if (block.timestamp - lastUpdateTime_ < COOLDOWN_PERIOD) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__CoolDownPending);
        }
    }

    ////////////////////////////////// GETTERS ////////////////////////////////////////////////////////

    /// @notice Get the max borrow shares of a DEX
    /// @param dex_ The address of the DEX
    /// @return The max borrow shares
    function getMaxBorrowShares(address dex_) public view returns (uint) {
        return IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_TOTAL_BORROW_SHARES_SLOT)) >> 128;
    }

    /// @notice Get the max supply shares of a DEX
    /// @param dex_ The address of the DEX
    /// @return The max supply shares
    function getMaxSupplyShares(address dex_) public view returns (uint) {
        return IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_TOTAL_SUPPLY_SHARES_SLOT)) >> 128;
    }

    /// @notice Returns the user supply config for a given dex and user.
    function getUserSupplyConfig(
        address dex_,
        address user_
    ) public view returns (AdminModuleStructs.UserSupplyConfig memory userSupplyConfigs_) {
        uint256 userSupply_ = IFluidDexT1(dex_).readFromStorage(
            DexSlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT, user_)
        );

        if (userSupply_ > 0) {
            userSupplyConfigs_ = AdminModuleStructs.UserSupplyConfig({
                user: user_,
                baseWithdrawalLimit: BigMathMinified.fromBigNumber(
                    (userSupply_ >> DexSlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT) & X18,
                    DEFAULT_EXPONENT_SIZE,
                    DEFAULT_EXPONENT_MASK
                ),
                expandPercent: (userSupply_ >> DexSlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) & X14,
                expandDuration: (userSupply_ >> DexSlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) & X24
            });
        }
    }

    /// @notice Returns the user borrow config for a given dex and user.
    function getUserBorrowConfig(
        address dex_,
        address user_
    ) public view returns (AdminModuleStructs.UserBorrowConfig memory userBorrowConfigs_) {
        uint256 userBorrow_ = IFluidDexT1(dex_).readFromStorage(
            DexSlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_BORROW_MAPPING_SLOT, user_)
        );

        if (userBorrow_ > 0) {
            userBorrowConfigs_ = AdminModuleStructs.UserBorrowConfig({
                user: user_,
                baseDebtCeiling: BigMathMinified.fromBigNumber(
                    (userBorrow_ >> DexSlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & X18,
                    DEFAULT_EXPONENT_SIZE,
                    DEFAULT_EXPONENT_MASK
                ),
                maxDebtCeiling: BigMathMinified.fromBigNumber(
                    (userBorrow_ >> DexSlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18,
                    DEFAULT_EXPONENT_SIZE,
                    DEFAULT_EXPONENT_MASK
                ),
                expandPercent: (userBorrow_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & X14,
                expandDuration: (userBorrow_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_DURATION) & X24
            });
        }
    }
}
