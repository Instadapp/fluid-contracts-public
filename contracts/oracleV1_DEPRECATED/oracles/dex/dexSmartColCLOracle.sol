// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle, IFluidOracle } from "../../fluidOracle.sol";
import { DexOracleAdjustResult } from "../../implementations/dex/dexOracleBase.sol";
import { DexSmartColOracleImpl } from "../../implementations/dex/dexSmartColOracleImpl.sol";

import { DexColDebtPriceFluidOracle } from "../../implementations/dex/colDebtPrices/colDebtPriceFluidOracle.sol";
import { DexConversionPriceCL, ChainlinkOracleImpl } from "../../implementations/dex/conversionPriceGetters/conversionPriceCL.sol";
import { DexReservesFromPEX } from "../../implementations/dex/reserveGetters/reservesFromPEX.sol";

/// @title   Fluid Dex Smart Col Chainlink oracle.
/// @notice  Gets the exchange rate between a Fluid Dex smart collateral shares and normal debt.
/// @dev -> Reserves from Liquidity, adjusted for conversion price.
///      -> Reserves conversion price from Chainlink feeds.
///      -> colDebt Price Oracle is an IFluidOracle.
contract DexSmartColCLOracle is
    FluidOracle,
    DexSmartColOracleImpl,
    DexColDebtPriceFluidOracle,
    DexConversionPriceCL,
    DexReservesFromPEX
{
    struct DexSmartColCLOracleParams {
        string infoName;
        uint8 targetDecimals;
        address dexPool;
        bool quoteInToken0;
        IFluidOracle colDebtOracle;
        bool colDebtInvert;
        ChainlinkOracleImpl.ChainlinkConstructorParams reservesConversion;
        uint256 reservesConversionPriceMultiplier;
        uint256 reservesConversionPriceDivisor;
        uint256 resultMultiplier;
        uint256 resultDivisor;
    }

    constructor(
        DexSmartColCLOracleParams memory params_
    )
        FluidOracle(params_.infoName, params_.targetDecimals)
        DexOracleAdjustResult(params_.resultMultiplier, params_.resultDivisor)
        DexReservesFromPEX(params_.dexPool, params_.quoteInToken0)
        DexColDebtPriceFluidOracle(params_.colDebtOracle, params_.colDebtInvert)
        DexConversionPriceCL(
            params_.reservesConversion,
            params_.reservesConversionPriceMultiplier,
            params_.reservesConversionPriceDivisor
        )
    {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        uint256 conversionPrice_ = _getDexReservesConversionPriceOperate();

        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexCollateralReserves(
            conversionPrice_,
            _getPricesAndExchangePrices()
        );

        uint256 quoteTokensPer1ColShare_ = _getDexSmartColExchangeRate(
            conversionPrice_,
            token0Reserves_,
            token1Reserves_
        );

        return
            (quoteTokensPer1ColShare_ * _getDexColDebtPriceOperate() * RESULT_MULTIPLIER) /
            (DEX_COL_DEBT_ORACLE_PRECISION * RESULT_DIVISOR);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        uint256 conversionPrice_ = _getDexReservesConversionPriceLiquidate();

        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexCollateralReserves(
            conversionPrice_,
            _getPricesAndExchangePrices()
        );

        uint256 quoteTokensPer1ColShare_ = _getDexSmartColExchangeRate(
            conversionPrice_,
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
        {
            uint256 conversionPrice_ = _getDexReservesConversionPriceOperate();

            (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexCollateralReserves(
                conversionPrice_,
                _getPricesAndExchangePrices()
            );

            operate_ = _getDexSmartColExchangeRate(conversionPrice_, token0Reserves_, token1Reserves_);
        }

        {
            uint256 conversionPrice_ = _getDexReservesConversionPriceLiquidate();

            (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexCollateralReserves(
                conversionPrice_,
                _getPricesAndExchangePrices()
            );

            liquidate_ = _getDexSmartColExchangeRate(conversionPrice_, token0Reserves_, token1Reserves_);
        }
    }
}
