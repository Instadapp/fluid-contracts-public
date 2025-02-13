// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { CalcsSimulatedTime } from "./calcsSimulatedTime.sol";

/// @dev this is the exact same code as in vault protocol codebase, just that it supports a simulated
/// block.timestamp to expose historical calculations.
library CalcsVaultSimulatedTime {
    error FluidCalcsVaultSimulatedTimeError();

    uint256 internal constant X16 = 0xffff;
    uint256 internal constant X64 = 0xffffffffffffffff;

    // @dev copied from vault protocol helper.sol and adjusted to have liquidity storage data and vault rates
    // storage data passed in instead of read

    /// @dev Calculates new vault exchange prices.
    /// @param vaultVariables2_ vaultVariables2 read from storage for the vault (VaultResolver.getRateRaw)
    /// @param vaultRates_ rates read from storage for the vault (VaultResolver.getVaultVariables2Raw)
    /// @param liquiditySupplyExchangePricesAndConfig_ exchange prices and config packed uint256 read from storage for supply token
    /// @param liquidityBorrowExchangePricesAndConfig_ exchange prices and config packed uint256 read from storage for borrow token
    /// @param blockTimestamp_ simulated block.timestamp
    /// @return liqSupplyExPrice_ latest liquidity's supply token supply exchange price
    /// @return liqBorrowExPrice_ latest liquidity's borrow token borrow exchange price
    /// @return vaultSupplyExPrice_ latest vault's supply token exchange price
    /// @return vaultBorrowExPrice_ latest vault's borrow token exchange price
    function updateExchangePrices(
        uint256 vaultVariables2_,
        uint256 vaultRates_,
        uint256 liquiditySupplyExchangePricesAndConfig_,
        uint256 liquidityBorrowExchangePricesAndConfig_,
        uint256 blockTimestamp_
    )
        internal
        pure
        returns (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        )
    {
        (liqSupplyExPrice_, ) = CalcsSimulatedTime.calcExchangePrices(
            liquiditySupplyExchangePricesAndConfig_,
            blockTimestamp_
        );
        (, liqBorrowExPrice_) = CalcsSimulatedTime.calcExchangePrices(
            liquidityBorrowExchangePricesAndConfig_,
            blockTimestamp_
        );

        uint256 oldLiqSupplyExPrice_ = (vaultRates_ & X64);
        uint256 oldLiqBorrowExPrice_ = ((vaultRates_ >> 64) & X64);
        if (liqSupplyExPrice_ < oldLiqSupplyExPrice_ || liqBorrowExPrice_ < oldLiqBorrowExPrice_) {
            // new liquidity exchange price is < than the old one. liquidity exchange price should only ever increase.
            // If not, something went wrong and avoid proceeding with unknown outcome.
            revert FluidCalcsVaultSimulatedTimeError();
        }

        // liquidity Exchange Prices always increases in next block. Hence substraction with old will never be negative
        // uint64 * 1e18 is the max the number that could be
        unchecked {
            // Calculating increase in supply exchange price w.r.t last stored liquidity's exchange price
            // vaultSupplyExPrice_ => supplyIncreaseInPercent_
            vaultSupplyExPrice_ =
                ((((liqSupplyExPrice_ * 1e18) / oldLiqSupplyExPrice_) - 1e18) * (vaultVariables2_ & X16)) /
                10000; // supply rate magnifier

            // Calculating increase in borrow exchange price w.r.t last stored liquidity's exchange price
            // vaultBorrowExPrice_ => borrowIncreaseInPercent_
            vaultBorrowExPrice_ =
                ((((liqBorrowExPrice_ * 1e18) / oldLiqBorrowExPrice_) - 1e18) * ((vaultVariables2_ >> 16) & X16)) /
                10000; // borrow rate magnifier

            // It's extremely hard the exchange prices to overflow even in 100 years but if it does it's not an
            // issue here as we are not updating on storage
            // (vaultRates_ >> 128) & X64) -> last stored vault's supply token exchange price
            vaultSupplyExPrice_ = (((vaultRates_ >> 128) & X64) * (1e18 + vaultSupplyExPrice_)) / 1e18;
            // (vaultRates_ >> 192) -> last stored vault's borrow token exchange price (no need to mask with & X64 as it is anyway max 64 bits)
            vaultBorrowExPrice_ = ((vaultRates_ >> 192) * (1e18 + vaultBorrowExPrice_)) / 1e18;
        }
    }
}
