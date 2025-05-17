// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { LiquidityCalcs } from "../../libraries/liquidityCalcs.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";
import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { BigMathMinified } from "../../libraries/bigMathMinified.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

abstract contract Structs {
    struct UserSupplyHistory {
        uint40 initialDailyTimestamp;
        uint40 initialHourlyTimestamp;
        uint8 rebalancesIn1Hour;
        uint8 rebalancesIn24Hours;
        uint160 leastDailyUserSupply;
    }
}

abstract contract Events {
    /// @notice emitted when rebalancer successfully changes the withdrawal limit
    event LogRebalanceWithdrawalLimit(address user, address token, uint256 newLimit);

    /// @notice emitted when multisig successfully changes the withdrawal limit
    event LogSetWithdrawalLimit(address user, address token, uint256 newLimit);
}

abstract contract Constants {
    uint256 internal constant X64 = 0xffffffffffffffff;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    address public immutable TEAM_MULTISIG;

    IFluidReserveContract public immutable RESERVE_CONTRACT;

    IFluidLiquidity public immutable LIQUIDITY;

    uint256 internal constant MAX_PERCENT_CHANGE = 5; // 5% max percent change at once
}

abstract contract Variables is Structs, Constants {
    mapping(address => mapping(address => UserSupplyHistory)) public userData;
}

contract FluidWithdrawLimitAuth is Variables, Error, Events {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.WithdrawLimitAuth__InvalidParams);
        }
        _;
    }

    /// @dev Validates that an address is a rebalancer (taken from reserve contract)
    modifier onlyRebalancer() {
        if (!RESERVE_CONTRACT.isRebalancer(msg.sender)) {
            revert FluidConfigError(ErrorTypes.WithdrawLimitAuth__Unauthorized);
        }
        _;
    }

    /// @dev Validates that an address is the team multisig
    modifier onlyMultisig() {
        if (msg.sender != TEAM_MULTISIG) {
            revert FluidConfigError(ErrorTypes.WithdrawLimitAuth__Unauthorized);
        }
        _;
    }

    constructor(
        IFluidReserveContract reserveContract_,
        address liquidity_,
        address multisig_
    ) validAddress(address(reserveContract_)) validAddress(liquidity_) validAddress(multisig_) {
        RESERVE_CONTRACT = reserveContract_;
        LIQUIDITY = IFluidLiquidity(liquidity_);
        TEAM_MULTISIG = multisig_;
    }

    /// @notice updates the withdrawal limit for a specific token of a user in the liquidity
    /// @dev This function can only be called by the rebalancer
    /// @param user_ The address of the user for which to set the withdrawal limit
    /// @param token_ The address of the token for which to set the withdrawal limit
    /// @param newLimit_ The new withdrawal limit to be set
    function rebalanceWithdrawalLimit(address user_, address token_, uint256 newLimit_) external onlyRebalancer {
        // getting the user supply data from liquidity
        uint256 userSupplyData_ = LIQUIDITY.readFromStorage(
            LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
                user_,
                token_
            )
        );

        uint256 initialUserSupply_ = BigMathMinified.fromBigNumber(
            (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        uint256 initialWithdrawLimit_ = LiquidityCalcs.calcWithdrawalLimitBeforeOperate(
            userSupplyData_,
            initialUserSupply_
        );

        if (initialUserSupply_ == 0) {
            revert FluidConfigError(ErrorTypes.WithdrawLimitAuth__NoUserSupply);
        }

        uint256 maxPercentOfCurrentLimit_ = (initialWithdrawLimit_ * (100 - MAX_PERCENT_CHANGE)) / 100;

        if (newLimit_ < maxPercentOfCurrentLimit_) {
            revert FluidConfigError(ErrorTypes.WithdrawLimitAuth__ExcessPercentageDifference);
        }

        // getting the limit history from the contract
        UserSupplyHistory memory userSupplyHistory_ = userData[user_][token_];

        // if one day is crossed
        if (block.timestamp - uint256(userSupplyHistory_.initialDailyTimestamp) > 1 days) {
            userSupplyHistory_.leastDailyUserSupply = uint128(newLimit_);
            userSupplyHistory_.rebalancesIn24Hours = 1;
            userSupplyHistory_.rebalancesIn1Hour = 1;
            userSupplyHistory_.initialDailyTimestamp = uint40(block.timestamp);
            userSupplyHistory_.initialHourlyTimestamp = uint40(block.timestamp);
        } else {
            // if one day is not crossed
            if (newLimit_ < userSupplyHistory_.leastDailyUserSupply) {
                if (userSupplyHistory_.rebalancesIn24Hours == 4) {
                    revert FluidConfigError(ErrorTypes.WithdrawLimitAuth__DailyLimitReached);
                }
                if (block.timestamp - uint256(userSupplyHistory_.initialHourlyTimestamp) > 1 hours) {
                    userSupplyHistory_.rebalancesIn1Hour = 1;
                    userSupplyHistory_.rebalancesIn24Hours += 1;
                    userSupplyHistory_.initialHourlyTimestamp = uint40(block.timestamp);
                } else {
                    if (userSupplyHistory_.rebalancesIn1Hour == 2) {
                        revert FluidConfigError(ErrorTypes.WithdrawLimitAuth__HourlyLimitReached);
                    }
                    userSupplyHistory_.rebalancesIn1Hour += 1;
                    userSupplyHistory_.rebalancesIn24Hours += 1;
                }
                userSupplyHistory_.leastDailyUserSupply = uint128(newLimit_);
            }
        }
        userData[user_][token_] = userSupplyHistory_;
        LIQUIDITY.updateUserWithdrawalLimit(user_, token_, newLimit_);
        emit LogRebalanceWithdrawalLimit(user_, token_, newLimit_);
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

    function getUsersData(
        address[] memory users_,
        address[] memory tokens_
    ) public view returns (uint256[] memory initialUsersSupply_, uint256[] memory initialWithdrawLimit_) {
        if (users_.length != tokens_.length) {
            revert FluidConfigError(ErrorTypes.WithdrawLimitAuth__InvalidParams);
        }

        initialUsersSupply_ = new uint256[](users_.length);
        initialWithdrawLimit_ = new uint256[](users_.length);

        for (uint i; i < tokens_.length; i++) {
            uint256 userSupplyData_ = LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
                    users_[i],
                    tokens_[i]
                )
            );

            initialUsersSupply_[i] = BigMathMinified.fromBigNumber(
                (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );

            initialWithdrawLimit_[i] = LiquidityCalcs.calcWithdrawalLimitBeforeOperate(
                userSupplyData_,
                initialUsersSupply_[i]
            );
        }
    }
}
