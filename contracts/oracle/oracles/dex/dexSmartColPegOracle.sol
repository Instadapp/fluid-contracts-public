// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle, IFluidOracle } from "../../fluidOracle.sol";
import { DexOracleAdjustResult } from "../../implementations/dex/dexOracleBase.sol";
import { DexSmartColOracleImpl } from "../../implementations/dex/dexSmartColOracleImpl.sol";

import { DexColDebtPriceFluidOracle } from "../../implementations/dex/colDebtPrices/colDebtPriceFluidOracle.sol";
import { DexConversionPriceFluidOracle } from "../../implementations/dex/conversionPriceGetters/conversionPriceFluidOracle.sol";
import { DexReservesFromLiquidityPeg } from "../../implementations/dex/reserveGetters/reservesFromLiquidityPeg.sol";

/// @title   Fluid Dex Smart Col Pegged Oracle for assets ~1=~1
/// @notice  Gets the exchange rate between a Fluid Dex smart collateral shares and normal debt.
/// @dev -> Reserves from Liquidity with Peg buffer percent.
///      -> Reserves conversion price from separately deployed FluidOracle (optional e.g. needed for wstETH-ETH).
///      -> colDebt Price Oracle is an IFluidOracle.
contract DexSmartColPegOracle is
    FluidOracle,
    DexSmartColOracleImpl,
    DexColDebtPriceFluidOracle,
    DexConversionPriceFluidOracle,
    DexReservesFromLiquidityPeg
{
    struct DexSmartColPegOracleParams {
        string infoName;
        uint8 targetDecimals;
        address dexPool;
        bool quoteInToken0;
        IFluidOracle colDebtOracle;
        bool colDebtInvert;
        uint256 pegBufferPercent;
        DexConversionPriceFluidOracleParams reservesConversionParams;
        uint256 resultMultiplier;
        uint256 resultDivisor;
    }

    constructor(
        DexSmartColPegOracleParams memory params_
    )
        FluidOracle(params_.infoName, params_.targetDecimals)
        DexOracleAdjustResult(params_.resultMultiplier, params_.resultDivisor)
        DexReservesFromLiquidityPeg(params_.dexPool, params_.quoteInToken0, params_.pegBufferPercent)
        DexColDebtPriceFluidOracle(params_.colDebtOracle, params_.colDebtInvert)
        DexConversionPriceFluidOracle(params_.reservesConversionParams)
    {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
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
