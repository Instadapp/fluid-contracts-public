// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle, IFluidOracle } from "../../fluidOracle.sol";
import { DexOracleAdjustResult } from "../../implementations/dex/dexOracleBase.sol";
import { DexSmartDebtOracleImpl } from "../../implementations/dex/dexSmartDebtOracleImpl.sol";

import { DexColDebtPriceFluidOracle } from "../../implementations/dex/colDebtPrices/colDebtPriceFluidOracle.sol";
import { DexConversionPriceCL, ChainlinkOracleImpl } from "../../implementations/dex/conversionPriceGetters/conversionPriceCL.sol";
import { DexReservesFromPEX } from "../../implementations/dex/reserveGetters/reservesFromPEX.sol";

/// @title   Fluid Dex Smart Debt Chainlink oracle.
/// @notice  Gets the exchange rate between a Fluid Dex normal collateral and smart debt shares.
/// @dev -> Reserves from Liquidity, adjusted for conversion price.
///      -> Reserves conversion price from Chainlink feeds.
///      -> colDebt Price Oracle is an IFluidOracle.
contract DexSmartDebtCLOracle is
    FluidOracle,
    DexSmartDebtOracleImpl,
    DexColDebtPriceFluidOracle,
    DexConversionPriceCL,
    DexReservesFromPEX
{
    struct DexSmartDebtCLOracleParams {
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
        DexSmartDebtCLOracleParams memory params_
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

        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexDebtReserves(
            conversionPrice_,
            _getPricesAndExchangePrices()
        );

        uint256 debtSharesPer1QuoteToken_ = _getDexSmartDebtExchangeRate(
            conversionPrice_,
            token0Reserves_,
            token1Reserves_
        );

        // to get debt/col rate of col per 1 debt share (SHARE/COL_TOKEN) :
        // _getDexSmartDebtExchangeRate() = debt token0 or debt token1 per 1 share (DEBT_TOKEN/SHARE).
        // _getDexColDebtPriceOperate() = debt token per 1 col token = DEBT_TOKEN/COL_TOKEN.
        // so (1 / DEBT_TOKEN/SHARE) * DEBT_TOKEN/COL_TOKEN =
        // SHARE/DEBT_TOKEN * DEBT_TOKEN/COL_TOKEN = SHARE/COL_TOKEN
        return
            (debtSharesPer1QuoteToken_ * _getDexColDebtPriceOperate() * RESULT_MULTIPLIER) /
            (DEX_COL_DEBT_ORACLE_PRECISION * RESULT_DIVISOR);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        uint256 conversionPrice_ = _getDexReservesConversionPriceLiquidate();

        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexDebtReserves(
            conversionPrice_,
            _getPricesAndExchangePrices()
        );

        uint256 debtSharesPer1QuoteToken_ = _getDexSmartDebtExchangeRate(
            conversionPrice_,
            token0Reserves_,
            token1Reserves_
        );

        return
            (debtSharesPer1QuoteToken_ * _getDexColDebtPriceLiquidate() * RESULT_MULTIPLIER) /
            (DEX_COL_DEBT_ORACLE_PRECISION * RESULT_DIVISOR);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRate() public view virtual override returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }

    /// @inheritdoc DexSmartDebtOracleImpl
    function dexSmartDebtSharesRates() public view override returns (uint256 operate_, uint256 liquidate_) {
        {
            uint256 conversionPrice_ = _getDexReservesConversionPriceOperate();

            (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexDebtReserves(
                conversionPrice_,
                _getPricesAndExchangePrices()
            );

            operate_ = _getDexSmartDebtExchangeRate(conversionPrice_, token0Reserves_, token1Reserves_);
        }

        {
            uint256 conversionPrice_ = _getDexReservesConversionPriceLiquidate();

            (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexDebtReserves(
                conversionPrice_,
                _getPricesAndExchangePrices()
            );

            liquidate_ = _getDexSmartDebtExchangeRate(conversionPrice_, token0Reserves_, token1Reserves_);
        }
    }
}
