// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { DexCalcs } from "../../libraries/dexCalcs.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";
import { IFluidDexT1 } from "../../protocols/dex/interfaces/iDexT1.sol";
import { BigMathMinified } from "../../libraries/bigMathMinified.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

interface IFluidDexT1Admin {
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
    event LogRebalanceWithdrawalLimit(address dex, address user, uint256 newLimit);

    /// @notice emitted when multisig successfully changes the withdrawal limit
    event LogSetWithdrawalLimit(address dex, address user, uint256 newLimit);
}

abstract contract Constants {
    uint256 internal constant X64 = 0xffffffffffffffff;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    address public immutable TEAM_MULTISIG;

    IFluidReserveContract public immutable RESERVE_CONTRACT;

    uint256 internal constant MAX_PERCENT_CHANGE = 5; // 5% max percent change at once
}

abstract contract Variables is Structs, Constants {
    mapping(address => UserSupplyHistory) public userData;
}

contract FluidWithdrawLimitAuthDex is Variables, Error, Events {
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
        address multisig_
    ) validAddress(address(reserveContract_)) validAddress(multisig_) {
        RESERVE_CONTRACT = reserveContract_;
        TEAM_MULTISIG = multisig_;
    }

    /// @notice updates the withdrawal limit for a specific user at a dex
    /// @dev This function can only be called by the rebalancer
    /// @param dex_ The address of the dex
    /// @param user_ The address of the user for which to set the withdrawal limit
    /// @param newLimit_ The new withdrawal limit to be set
    function rebalanceWithdrawalLimit(address dex_, address user_, uint256 newLimit_) external onlyRebalancer {
        // getting the user supply data from the dex
        uint256 userSupplyData_ = IFluidDexT1(dex_).readFromStorage(
            DexSlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT, user_)
        );

        uint256 initialUserSupply_ = BigMathMinified.fromBigNumber(
            (userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        uint256 initialWithdrawLimit_ = DexCalcs.calcWithdrawalLimitBeforeOperate(userSupplyData_, initialUserSupply_);

        if (initialUserSupply_ == 0) {
            revert FluidConfigError(ErrorTypes.WithdrawLimitAuth__NoUserSupply);
        }

        uint256 maxPercentOfCurrentLimit_ = (initialWithdrawLimit_ * (100 - MAX_PERCENT_CHANGE)) / 100;

        if (newLimit_ < maxPercentOfCurrentLimit_) {
            revert FluidConfigError(ErrorTypes.WithdrawLimitAuth__ExcessPercentageDifference);
        }

        // getting the limit history from the contract
        UserSupplyHistory memory userSupplyHistory_ = userData[user_];

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
        userData[user_] = userSupplyHistory_;
        IFluidDexT1Admin(dex_).updateUserWithdrawalLimit(user_, newLimit_);
        emit LogRebalanceWithdrawalLimit(dex_, user_, newLimit_);
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

    function getUsersData(
        address dex_,
        address[] memory users_
    ) public view returns (uint256[] memory initialUsersSupply_, uint256[] memory initialWithdrawLimit_) {
        initialUsersSupply_ = new uint256[](users_.length);
        initialWithdrawLimit_ = new uint256[](users_.length);

        for (uint i; i < users_.length; i++) {
            uint256 userSupplyData_ = IFluidDexT1(dex_).readFromStorage(
                DexSlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT, users_[i])
            );

            initialUsersSupply_[i] = BigMathMinified.fromBigNumber(
                (userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );

            initialWithdrawLimit_[i] = DexCalcs.calcWithdrawalLimitBeforeOperate(
                userSupplyData_,
                initialUsersSupply_[i]
            );
        }
    }
}
