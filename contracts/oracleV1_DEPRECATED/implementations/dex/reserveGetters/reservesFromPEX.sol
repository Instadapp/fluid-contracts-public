// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { DexPricesAndExchangePrices } from "../dexPricesAndExchangePrices.sol";
import { DexOracleBase } from "../dexOracleBase.sol";
import { ErrorTypes } from "../../../errorTypes.sol";

/// @notice reads the dex reserves directly from Liquidity (user supply / user debt) but adjusts them for a certain
///         price, incl. adjusted PEX.
abstract contract DexReservesFromPEX is DexOracleBase, DexPricesAndExchangePrices {
    constructor(address dexPool_, bool quoteInToken0_) DexOracleBase(dexPool_, quoteInToken0_) {}

    /// @dev Get the col reserves at the Dex adjusted to 1e12 decimals.
    /// Pass in the conversion price and PEX fetched via `_getPricesAndExchangePrices()`.
    function _getDexCollateralReserves(
        uint256 price_,
        PricesAndExchangePrice memory pex_
    ) internal view returns (uint256 token0Reserves_, uint256 token1Reserves_) {
        CollateralReserves memory collateralReserves_ = _getCollateralReserves(
            pex_.geometricMean,
            pex_.upperRange,
            pex_.lowerRange,
            pex_.supplyToken0ExchangePrice,
            pex_.supplyToken1ExchangePrice
        );

        CollateralReserves memory newCollateralReserves_ = _calculateNewColReserves(pex_, collateralReserves_, price_);

        token0Reserves_ = newCollateralReserves_.token0RealReserves;
        token1Reserves_ = newCollateralReserves_.token1RealReserves;
    }

    /// @dev Get the debt reserves at the Dex adjusted to 1e12 decimals.
    /// Pass in the conversion price and PEX fetched via `_getPricesAndExchangePrices()`.
    function _getDexDebtReserves(
        uint256 price_,
        PricesAndExchangePrice memory pex_
    ) internal view returns (uint256 token0Debt_, uint256 token1Debt_) {
        DebtReserves memory debtReserves_ = _getDebtReserves(
            pex_.geometricMean,
            pex_.upperRange,
            pex_.lowerRange,
            pex_.borrowToken0ExchangePrice,
            pex_.borrowToken1ExchangePrice
        );

        DebtReserves memory newDebtReserves_ = _calculateNewDebtReserves(pex_, debtReserves_, price_);

        token0Debt_ = newDebtReserves_.token0Debt;
        token1Debt_ = newDebtReserves_.token1Debt;
    }
}
