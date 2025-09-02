// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { DexCalcs } from "../../libraries/dexCalcs.sol";
import { IFluidDexT1 } from "../../protocols/dex/interfaces/iDexT1.sol";
import { Structs as AdminModuleStructs } from "../../protocols/dex/poolT1/adminModule/structs.sol";
import { BigMathMinified } from "../../libraries/bigMathMinified.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

interface IFluidDexT1Admin {
    function updateUserSupplyConfigs(AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_) external;

    function updateUserBorrowConfigs(AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_) external;

    function updateMaxBorrowShares(uint maxBorrowShares_) external;

    function updateMaxSupplyShares(uint maxSupplyShares_) external;

    /// @notice sets a new withdrawal limit as the current limit for a certain user
    /// @param user_ user address for which to update the withdrawal limit
    /// @param newLimit_ new limit until which user supply can decrease to.
    ///                  Important: input in raw. Must account for exchange price in input param calculation.
    ///                  Note any limit that is < max expansion or > current user supply will set max expansion limit or
    ///                  current user supply as limit respectively.
    ///                  - set 0 to make maximum possible withdrawable: instant full expansion, and if that goes
    ///                  below base limit then fully down to 0.
    ///                  - set type(uint256).max to make current withdrawable 0 (sets current user supply as limit).
    function updateUserWithdrawalLimit(address user_, uint256 newLimit_) external;
}

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
}

abstract contract Constants {
    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X24 = 0xffffff;

    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    /// @dev Set this to 20 for a +/-20% limit
    uint256 internal constant MAX_PERCENT_CHANGE = 20;

    /// @notice Team multisigs allowed to trigger methods
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

    uint256 internal constant COOLDOWN_PERIOD = 4 days;
}

abstract contract Variables is Constants {
    // dex => user => lastUpdateTime for cooldown checks
    mapping(address => mapping(address => uint256)) public lastUpdateTime;
}

contract FluidLimitsAuthDex is Variables, Error, Events {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__InvalidParams);
        }
        _;
    }

    /// @dev Validates that an address is the team multisig
    modifier onlyMultisig() {
        if (TEAM_MULTISIG != msg.sender && TEAM_MULTISIG2 != msg.sender) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__Unauthorized);
        }
        _;
    }

    /// @notice Sets the withdrawal limit for a specific user at a dex
    /// @dev This function can only be called by team multisig
    /// @param dex_ The address of the dex
    /// @param user_ The address of the user for which to set the withdrawal limit
    /// @param newLimit_ The new withdrawal limit to be set
    function setWithdrawalLimit(address dex_, address user_, uint256 newLimit_) external onlyMultisig {
        IFluidDexT1Admin(dex_).updateUserWithdrawalLimit(user_, newLimit_);
        emit LogSetWithdrawalLimit(dex_, user_, newLimit_);
    }

    /// @notice Sets the user withdraw base limit at a specific dex for a user (vault) without restrictions. Can only be called by team multisig.
    /// @param dex_ The address of the dex at which to set the user withdraw limit
    /// @param user_ The address of the user for which to set the user withdraw limit
    /// @param baseLimit_ The base limit for the user supply. Set to 0 to keep current value.
    /// @param skipMaxPercentChangeCheck_ allow full range of limit check. Keep to false by default to have additional human error check.
    function setUserWithdrawLimit(
        address dex_,
        address user_,
        uint256 baseLimit_,
        bool skipMaxPercentChangeCheck_
    ) external onlyMultisig {
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

        IFluidDexT1Admin(dex_).updateUserSupplyConfigs(userSupplyConfigs);

        emit LogSetUserWithdrawLimit(dex_, user_, userSupplyConfigs[0].baseWithdrawalLimit);
    }

    /// @notice Sets the user borrow limits at a specific dex for a user (vault), with time and max percent change restrictions.
    ///         Can only be called by team multisig.
    /// @param dex_ The address of the dex at which to set the user borrow limit
    /// @param user_ The address of the user for which to set the user borrow limit
    /// @param baseLimit_ The base limit for the user borrow. Set to 0 to keep current value.
    /// @param maxLimit_ The max limit for the user borrow. Set to 0 to keep current value.
    function setUserBorrowLimits(
        address dex_,
        address user_,
        uint256 baseLimit_,
        uint256 maxLimit_
    ) external onlyMultisig {
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

        IFluidDexT1Admin(dex_).updateUserBorrowConfigs(userBorrowConfigs);

        emit LogSetUserBorrowLimits(
            dex_,
            user_,
            userBorrowConfigs[0].baseDebtCeiling,
            userBorrowConfigs[0].maxDebtCeiling
        );
    }

    /// @notice Sets the max borrow shares of a DEX. To update max supply and max borrow shares at once within same coolDown, use setMaxShares.
    /// @dev This function can only be called by team multisig
    /// @param dex_ The address of the dex at which to set the max borrow shares
    /// @param maxBorrowShares_ The max borrow shares.
    /// @param confirmLiquidityLimitsCoverCap_  Reminder to manually confirm that the limits for the dex at liquidity layer cover the cap.
    function setMaxBorrowShares(
        address dex_,
        uint256 maxBorrowShares_,
        bool confirmLiquidityLimitsCoverCap_
    ) external onlyMultisig {
        _validateSetDexShares(dex_, confirmLiquidityLimitsCoverCap_);
        _setMaxBorrowShares(dex_, maxBorrowShares_);
    }

    /// @notice Sets the max supply shares of a DEX. To update max supply and max borrow shares at once within same coolDown, use setMaxShares.
    /// @dev This function can only be called by team multisig
    /// @param dex_ The address of the dex at which to set the max supply shares
    /// @param maxSupplyShares_ The max supply shares.
    /// @param confirmLiquidityLimitsCoverCap_  Reminder to manually confirm that the limits for the dex at liquidity layer cover the cap.
    function setMaxSupplyShares(
        address dex_,
        uint256 maxSupplyShares_,
        bool confirmLiquidityLimitsCoverCap_
    ) external onlyMultisig {
        _validateSetDexShares(dex_, confirmLiquidityLimitsCoverCap_);
        _setMaxSupplyShares(dex_, maxSupplyShares_);
    }

    /// @notice Sets both max borrow shares and max supply shares of a DEX at once.
    /// @dev This function can only be called by team multisig
    /// @param dex_ The address of the dex at which to set the max shares
    /// @param maxSupplyShares_ The max supply shares.
    /// @param maxBorrowShares_ The max borrow shares.
    /// @param confirmLiquidityLimitsCoverCap_  Reminder to manually confirm that the limits for the dex at liquidity layer cover the cap.
    function setMaxShares(
        address dex_,
        uint256 maxSupplyShares_,
        uint256 maxBorrowShares_,
        bool confirmLiquidityLimitsCoverCap_
    ) external onlyMultisig {
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
