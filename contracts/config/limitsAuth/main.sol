// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { BigMathMinified } from "../../libraries/bigMathMinified.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { Structs as AdminModuleStructs } from "../../liquidity/adminModule/structs.sol";
import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";

abstract contract Events {
    /// @notice emitted when multisig successfully changes the withdrawal limit
    event LogSetWithdrawalLimit(address user, address token, uint256 newLimit);

    /// @notice emitted when multisig changes the withdrawal limit config
    event LogSetUserWithdrawLimit(address user, address token, uint256 baseLimit);

    /// @notice emitted when multisig changes the borrow limit config
    event LogSetUserBorrowLimits(address user, address token, uint256 baseLimit, uint256 maxLimit);
}

abstract contract Constants {
    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X24 = 0xffffff;

    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    /// @dev This represents 20%.
    uint256 internal constant MAX_PERCENT_CHANGE = 20;

    IFluidLiquidity public immutable LIQUIDITY;
    /// @notice Team multisigs allowed to trigger methods
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

    uint256 internal constant COOLDOWN_PERIOD = 4 days;
}

abstract contract Variables is Constants {
    // user => token => lastUpdateTime for cooldown checks
    mapping(address => mapping(address => uint256)) public lastUpdateTime;
}

contract FluidLimitsAuth is Variables, Events, Error {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__InvalidParams);
        }
        _;
    }

    modifier onlyMultisig() {
        if (TEAM_MULTISIG != msg.sender && TEAM_MULTISIG2 != msg.sender) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__Unauthorized);
        }
        _;
    }

    constructor(address liquidity_) validAddress(liquidity_) {
        LIQUIDITY = IFluidLiquidity(liquidity_);
    }

    /// @notice Sets the withdrawal limit for a specific token of a user in the liquidity
    /// @dev This function can only be called by team multisig
    /// @param user_ The address of the user for which to set the withdrawal limit
    /// @param token_ The address of the token for which to set the withdrawal limit
    /// @param newLimit_ The new withdrawal limit to be set
    function setWithdrawalLimit(address user_, address token_, uint256 newLimit_) external onlyMultisig {
        LIQUIDITY.updateUserWithdrawalLimit(user_, token_, newLimit_);
        emit LogSetWithdrawalLimit(user_, token_, newLimit_);
    }

    /// @notice sets withdraw base limit without restrictions. Can only be called by team multisig.
    /// @param user_ The address of the user for which to set the user withdraw limit
    /// @param token_ The address of the token for which to set the user withdraw limit
    /// @param baseLimit_ The base limit for the user supply. Set to 0 to keep current value.
    /// @param skipMaxPercentChangeCheck_ allow full range of limit check. Keep to false by default to have additional human error check.
    function setUserWithdrawLimit(
        address user_,
        address token_,
        uint256 baseLimit_,
        bool skipMaxPercentChangeCheck_
    ) external onlyMultisig {
        if (baseLimit_ == 0) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__InvalidParams);
        }

        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs[0] = getUserSupplyConfig(user_, token_);

        if (userSupplyConfigs[0].user == address(0)) {
            // user is not defined yet
            revert FluidConfigError(ErrorTypes.LimitsAuth__UserNotDefinedYet);
        }

        if (!skipMaxPercentChangeCheck_) {
            _validateWithinMaxPercentChange(userSupplyConfigs[0].baseWithdrawalLimit, baseLimit_);
        }

        userSupplyConfigs[0].baseWithdrawalLimit = baseLimit_;

        LIQUIDITY.updateUserSupplyConfigs(userSupplyConfigs);

        emit LogSetUserWithdrawLimit(user_, token_, userSupplyConfigs[0].baseWithdrawalLimit);
    }

    /// @notice Sets the user borrow limits for a specific token of a user, with time and max percent change restrictions.
    ///         Can only be called by team multisig.
    /// @dev This function can only be called by team multisig
    /// @param user_ The address of the user for which to set the user borrow limit
    /// @param token_ The address of the token for which to set the user borrow limit
    /// @param baseLimit_ The base limit for the user borrow. Set to 0 to keep current value.
    /// @param maxLimit_ The max limit for the user borrow. Set to 0 to keep current value.
    function setUserBorrowLimits(
        address user_,
        address token_,
        uint256 baseLimit_,
        uint256 maxLimit_
    ) external onlyMultisig {
        if (baseLimit_ == 0 && maxLimit_ == 0) {
            revert FluidConfigError(ErrorTypes.LimitsAuth__InvalidParams);
        }

        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs[0] = getUserBorrowConfig(user_, token_);

        if (userBorrowConfigs[0].user == address(0)) {
            // user is not defined yet
            revert FluidConfigError(ErrorTypes.LimitsAuth__UserNotDefinedYet);
        }

        _validateLastUpdateTime(lastUpdateTime[user_][token_]);

        if (baseLimit_ != 0) {
            _validateWithinMaxPercentChange(userBorrowConfigs[0].baseDebtCeiling, baseLimit_);
            userBorrowConfigs[0].baseDebtCeiling = baseLimit_;
        }

        if (maxLimit_ != 0) {
            _validateWithinMaxPercentChange(userBorrowConfigs[0].maxDebtCeiling, maxLimit_);
            userBorrowConfigs[0].maxDebtCeiling = maxLimit_;
        }

        lastUpdateTime[user_][token_] = block.timestamp;

        LIQUIDITY.updateUserBorrowConfigs(userBorrowConfigs);

        emit LogSetUserBorrowLimits(
            user_,
            token_,
            userBorrowConfigs[0].baseDebtCeiling,
            userBorrowConfigs[0].maxDebtCeiling
        );
    }

    /// @notice Returns the user supply config for a given user and token.
    function getUserSupplyConfig(
        address user_,
        address token_
    ) public view returns (AdminModuleStructs.UserSupplyConfig memory userSupplyConfigs_) {
        uint256 userSupply_ = LIQUIDITY.readFromStorage(
            LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
                user_,
                token_
            )
        );

        if (userSupply_ > 0) {
            userSupplyConfigs_ = AdminModuleStructs.UserSupplyConfig({
                user: user_,
                token: token_,
                mode: uint8(userSupply_ & 1),
                baseWithdrawalLimit: BigMathMinified.fromBigNumber(
                    (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT) & X18,
                    DEFAULT_EXPONENT_SIZE,
                    DEFAULT_EXPONENT_MASK
                ),
                expandPercent: (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) & X14,
                expandDuration: (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) & X24
            });
        }
    }

    /// @notice Returns the user borrow config for a given user and token.
    function getUserBorrowConfig(
        address user_,
        address token_
    ) public view returns (AdminModuleStructs.UserBorrowConfig memory userBorrowConfigs_) {
        uint256 userBorrow_ = LIQUIDITY.readFromStorage(
            LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
                user_,
                token_
            )
        );

        if (userBorrow_ > 0) {
            userBorrowConfigs_ = AdminModuleStructs.UserBorrowConfig({
                user: user_,
                token: token_,
                mode: uint8(userBorrow_ & 1),
                baseDebtCeiling: BigMathMinified.fromBigNumber(
                    (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & X18,
                    DEFAULT_EXPONENT_SIZE,
                    DEFAULT_EXPONENT_MASK
                ),
                maxDebtCeiling: BigMathMinified.fromBigNumber(
                    (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18,
                    DEFAULT_EXPONENT_SIZE,
                    DEFAULT_EXPONENT_MASK
                ),
                expandPercent: (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & X14,
                expandDuration: (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_DURATION) & X24
            });
        }
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
}
