// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle, IFluidOracle } from "../../fluidOracle.sol";
import { DexOracleAdjustResult } from "../../implementations/dex/dexOracleBase.sol";
import { DexSmartColOracleImpl } from "../../implementations/dex/dexSmartColOracleImpl.sol";
import { DexSmartDebtOracleImpl } from "../../implementations/dex/dexSmartDebtOracleImpl.sol";

import { DexReservesFromLiquidityPeg } from "../../implementations/dex/reserveGetters/reservesFromLiquidityPeg.sol";
import { DexConversionPriceFluidOracle } from "../../implementations/dex/conversionPriceGetters/conversionPriceFluidOracle.sol";

/// @title   Fluid Dex Smart Col Debt Pegged Oracle for assets ~1=~1
/// @notice  Gets the exchange rate between a Fluid Dex smart collateral shares and smart debt shares.
/// @dev -> Reserves from Liquidity with Peg buffer percent.
///      -> Reserves conversion price from separately deployed FluidOracle (optional e.g. needed for wstETH-ETH).
contract DexSmartT4PegOracle is
    FluidOracle,
    DexSmartColOracleImpl,
    DexSmartDebtOracleImpl,
    DexConversionPriceFluidOracle,
    DexReservesFromLiquidityPeg
{
    struct DexSmartT4PegOracleParams {
        string infoName;
        uint8 targetDecimals;
        address dexPool;
        bool quoteInToken0;
        uint256 pegBufferPercent;
        // conversion oracle is optional, set to address zero if not used. See DexConversionPriceFluidOracle
        DexConversionPriceFluidOracleParams reservesConversionParams;
        uint256 resultMultiplier;
        uint256 resultDivisor;
    }

    constructor(
        DexSmartT4PegOracleParams memory params_
    )
        FluidOracle(params_.infoName, params_.targetDecimals)
        DexOracleAdjustResult(params_.resultMultiplier, params_.resultDivisor)
        DexReservesFromLiquidityPeg(params_.dexPool, params_.quoteInToken0, params_.pegBufferPercent)
        DexConversionPriceFluidOracle(params_.reservesConversionParams)
    {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        uint256 conversionPrice_ = _getDexReservesConversionPriceOperate();

        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexCollateralReserves();
        uint256 quoteTokensPer1ColShare_ = _getDexSmartColExchangeRate(
            conversionPrice_,
            token0Reserves_,
            token1Reserves_
        );

        (token0Reserves_, token1Reserves_) = _getDexDebtReserves();
        uint256 debtSharesPer1QuoteToken_ = _getDexSmartDebtExchangeRate(
            conversionPrice_,
            token0Reserves_,
            token1Reserves_
        );

        return (debtSharesPer1QuoteToken_ * quoteTokensPer1ColShare_ * RESULT_MULTIPLIER) / (1e27 * RESULT_DIVISOR);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        uint256 conversionPrice_ = _getDexReservesConversionPriceLiquidate();

        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexCollateralReserves();
        uint256 quoteTokensPer1ColShare_ = _getDexSmartColExchangeRate(
            conversionPrice_,
            token0Reserves_,
            token1Reserves_
        );

        (token0Reserves_, token1Reserves_) = _getDexDebtReserves();
        uint256 debtSharesPer1QuoteToken_ = _getDexSmartDebtExchangeRate(
            conversionPrice_,
            token0Reserves_,
            token1Reserves_
        );

        return (debtSharesPer1QuoteToken_ * quoteTokensPer1ColShare_ * RESULT_MULTIPLIER) / (1e27 * RESULT_DIVISOR);
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

    /// @inheritdoc DexSmartDebtOracleImpl
    function dexSmartDebtSharesRates() public view override returns (uint256 operate_, uint256 liquidate_) {
        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexDebtReserves();

        return (
            _getDexSmartDebtExchangeRate(_getDexReservesConversionPriceOperate(), token0Reserves_, token1Reserves_),
            _getDexSmartDebtExchangeRate(_getDexReservesConversionPriceLiquidate(), token0Reserves_, token1Reserves_)
        );
    }
}
