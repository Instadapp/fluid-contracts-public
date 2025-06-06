// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle, IFluidOracle } from "../../fluidOracle.sol";
import { DexOracleAdjustResult } from "../../implementations/dex/dexOracleBase.sol";
import { DexSmartColOracleImpl } from "../../implementations/dex/dexSmartColOracleImpl.sol";

import { DexColDebtPriceFluidOracle } from "../../implementations/dex/colDebtPrices/colDebtPriceFluidOracle.sol";
import { DexConversionPriceDirectNoBorrow } from "../../implementations/dex/conversionPriceGetters/conversionPriceDirectNoBorrow.sol";
import { DexReservesFromLiquidity } from "../../implementations/dex/reserveGetters/reservesFromLiquidity.sol";

/// @title   Fluid Dex Smart Col NO BORROW oracle.
/// @notice  Gets the exchange rate between a Fluid Dex smart collateral shares and normal debt.
/// @dev IMPORTANT: TO BE USED ONLY WITH NO BORROW VAULTS (very tight borrow limits).
/// @dev -> Reserves from Liquidity.
///      -> Reserves conversion price lastStoredPrice from the Fluid Dex pool.
///      -> colDebt Price Oracle is an IFluidOracle.
contract DexSmartColNoBorrowOracle is
    FluidOracle,
    DexSmartColOracleImpl,
    DexColDebtPriceFluidOracle,
    DexConversionPriceDirectNoBorrow,
    DexReservesFromLiquidity
{
    struct DexSmartColNoBorrowOracleParams {
        string infoName;
        uint8 targetDecimals;
        address dexPool;
        bool quoteInToken0;
        IFluidOracle colDebtOracle;
        bool colDebtInvert;
        uint256 resultMultiplier;
        uint256 resultDivisor;
    }

    constructor(
        DexSmartColNoBorrowOracleParams memory params_
    )
        FluidOracle(params_.infoName, params_.targetDecimals)
        DexOracleAdjustResult(params_.resultMultiplier, params_.resultDivisor)
        DexReservesFromLiquidity(params_.dexPool, params_.quoteInToken0)
        DexColDebtPriceFluidOracle(params_.colDebtOracle, params_.colDebtInvert)
        DexConversionPriceDirectNoBorrow()
    {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        // to get debt/col rate of debt token per 1 col share (DEBT_TOKEN/SHARE):
        // _getDexSmartColOperate() = col token0 or col token1 per 1 share (COL_TOKEN/SHARE).
        // _getExternalPrice() = debt token per 1 col token = DEBT_TOKEN/COL_TOKEN.
        // so COL_TOKEN/SHARE * DEBT_TOKEN/COL_TOKEN = DEBT_TOKEN/SHARE

        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexCollateralReserves();

        uint256 quoteTokensPer1ColShare_ = _getDexSmartColExchangeRate(
            _getDexReservesConversionPriceOperate(),
            token0Reserves_,
            token1Reserves_
        );

        return
            (quoteTokensPer1ColShare_ * _getDexColDebtPriceOperate() * RESULT_MULTIPLIER) /
            (DEX_COL_DEBT_ORACLE_PRECISION * RESULT_DIVISOR);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexCollateralReserves();

        uint256 quoteTokensPer1ColShare_ = _getDexSmartColExchangeRate(
            _getDexReservesConversionPriceLiquidate(),
            token0Reserves_,
            token1Reserves_
        );

        return
            (quoteTokensPer1ColShare_ * _getDexColDebtPriceLiquidate() * RESULT_MULTIPLIER) /
            (DEX_COL_DEBT_ORACLE_PRECISION * RESULT_DIVISOR);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRate() public view virtual override returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }

    /// @inheritdoc DexSmartColOracleImpl
    function dexSmartColSharesRates() public view override returns (uint256 operate_, uint256 liquidate_) {
        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexCollateralReserves();

        return (
            _getDexSmartColExchangeRate(_getDexReservesConversionPriceOperate(), token0Reserves_, token1Reserves_),
            _getDexSmartColExchangeRate(_getDexReservesConversionPriceLiquidate(), token0Reserves_, token1Reserves_)
        );
    }
}
