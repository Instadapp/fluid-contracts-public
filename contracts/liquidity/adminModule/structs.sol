// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

abstract contract Structs {
    struct AddressBool {
        address addr;
        bool value;
    }

    struct AddressUint256 {
        address addr;
        uint256 value;
    }

    /// @notice struct to set borrow rate data for version 1
    struct RateDataV1Params {
        ///
        /// @param token for rate data
        address token;
        ///
        /// @param kink in borrow rate. in 1e2: 100% = 10_000; 1% = 100
        /// utilization below kink usually means slow increase in rate, once utilization is above kink borrow rate increases fast
        uint256 kink;
        ///
        /// @param rateAtUtilizationZero desired borrow rate when utilization is zero. in 1e2: 100% = 10_000; 1% = 100
        /// i.e. constant minimum borrow rate
        /// e.g. at utilization = 0.01% rate could still be at least 4% (rateAtUtilizationZero would be 400 then)
        uint256 rateAtUtilizationZero;
        ///
        /// @param rateAtUtilizationKink borrow rate when utilization is at kink. in 1e2: 100% = 10_000; 1% = 100
        /// e.g. when rate should be 7% at kink then rateAtUtilizationKink would be 700
        uint256 rateAtUtilizationKink;
        ///
        /// @param rateAtUtilizationMax borrow rate when utilization is maximum at 100%. in 1e2: 100% = 10_000; 1% = 100
        /// e.g. when rate should be 125% at 100% then rateAtUtilizationMax would be 12_500
        uint256 rateAtUtilizationMax;
    }

    /// @notice struct to set borrow rate data for version 2
    struct RateDataV2Params {
        ///
        /// @param token for rate data
        address token;
        ///
        /// @param kink1 first kink in borrow rate. in 1e2: 100% = 10_000; 1% = 100
        /// utilization below kink 1 usually means slow increase in rate, once utilization is above kink 1 borrow rate increases faster
        uint256 kink1;
        ///
        /// @param kink2 second kink in borrow rate. in 1e2: 100% = 10_000; 1% = 100
        /// utilization below kink 2 usually means slow / medium increase in rate, once utilization is above kink 2 borrow rate increases fast
        uint256 kink2;
        ///
        /// @param rateAtUtilizationZero desired borrow rate when utilization is zero. in 1e2: 100% = 10_000; 1% = 100
        /// i.e. constant minimum borrow rate
        /// e.g. at utilization = 0.01% rate could still be at least 4% (rateAtUtilizationZero would be 400 then)
        uint256 rateAtUtilizationZero;
        ///
        /// @param rateAtUtilizationKink1 desired borrow rate when utilization is at first kink. in 1e2: 100% = 10_000; 1% = 100
        /// e.g. when rate should be 7% at first kink then rateAtUtilizationKink would be 700
        uint256 rateAtUtilizationKink1;
        ///
        /// @param rateAtUtilizationKink2 desired borrow rate when utilization is at second kink. in 1e2: 100% = 10_000; 1% = 100
        /// e.g. when rate should be 7% at second kink then rateAtUtilizationKink would be 1_200
        uint256 rateAtUtilizationKink2;
        ///
        /// @param rateAtUtilizationMax desired borrow rate when utilization is maximum at 100%. in 1e2: 100% = 10_000; 1% = 100
        /// e.g. when rate should be 125% at 100% then rateAtUtilizationMax would be 12_500
        uint256 rateAtUtilizationMax;
    }

    /// @notice struct to set token config
    struct TokenConfig {
        ///
        /// @param token address
        address token;
        ///
        /// @param fee charges on borrower's interest. in 1e2: 100% = 10_000; 1% = 100
        uint256 fee;
        ///
        /// @param threshold on when to update the storage slot. in 1e2: 100% = 10_000; 1% = 100
        uint256 threshold;
        ///
        /// @param maxUtilization maximum allowed utilization. in 1e2: 100% = 10_000; 1% = 100
        ///                       set to 100% to disable and have default limit of 100% (avoiding SLOAD).
        uint256 maxUtilization;
    }

    /// @notice struct to set user supply & withdrawal config
    struct UserSupplyConfig {
        ///
        /// @param user address
        address user;
        ///
        /// @param token address
        address token;
        ///
        /// @param mode: 0 = without interest. 1 = with interest
        uint8 mode;
        ///
        /// @param expandPercent withdrawal limit expand percent. in 1e2: 100% = 10_000; 1% = 100
        /// Also used to calculate rate at which withdrawal limit should decrease (instant).
        uint256 expandPercent;
        ///
        /// @param expandDuration withdrawal limit expand duration in seconds.
        /// used to calculate rate together with expandPercent
        uint256 expandDuration;
        ///
        /// @param baseWithdrawalLimit base limit, below this, user can withdraw the entire amount.
        /// amount in raw (to be multiplied with exchange price) or normal depends on configured mode in user config for the token:
        /// with interest -> raw, without interest -> normal
        uint256 baseWithdrawalLimit;
    }

    /// @notice struct to set user borrow & payback config
    struct UserBorrowConfig {
        ///
        /// @param user address
        address user;
        ///
        /// @param token address
        address token;
        ///
        /// @param mode: 0 = without interest. 1 = with interest
        uint8 mode;
        ///
        /// @param expandPercent debt limit expand percent. in 1e2: 100% = 10_000; 1% = 100
        /// Also used to calculate rate at which debt limit should decrease (instant).
        uint256 expandPercent;
        ///
        /// @param expandDuration debt limit expand duration in seconds.
        /// used to calculate rate together with expandPercent
        uint256 expandDuration;
        ///
        /// @param baseDebtCeiling base borrow limit. until here, borrow limit remains as baseDebtCeiling
        /// (user can borrow until this point at once without stepped expansion). Above this, automated limit comes in place.
        /// amount in raw (to be multiplied with exchange price) or normal depends on configured mode in user config for the token:
        /// with interest -> raw, without interest -> normal
        uint256 baseDebtCeiling;
        ///
        /// @param maxDebtCeiling max borrow ceiling, maximum amount the user can borrow.
        /// amount in raw (to be multiplied with exchange price) or normal depends on configured mode in user config for the token:
        /// with interest -> raw, without interest -> normal
        uint256 maxDebtCeiling;
    }
}
