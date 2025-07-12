// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle, IFluidOracle } from "../../fluidOracle.sol";
import { DexOracleAdjustResult } from "../../implementations/dex/dexOracleBase.sol";
import { DexSmartColOracleImpl } from "../../implementations/dex/dexSmartColOracleImpl.sol";
import { DexSmartDebtOracleImpl } from "../../implementations/dex/dexSmartDebtOracleImpl.sol";

import { DexReservesFromPEX } from "../../implementations/dex/reserveGetters/reservesFromPEX.sol";
import { DexConversionPriceCL, ChainlinkOracleImpl } from "../../implementations/dex/conversionPriceGetters/conversionPriceCL.sol";

/// @title   Fluid Dex Smart Col Debt VaultT4 Oracle
/// @notice  Gets the exchange rate between a Fluid Dex smart collateral and smart debt for a T4 vault.
///          returns amount of debt shares per 1 col share.
/// @dev -> Reserves from Liquidity, adjusted for conversion price.
///      -> Reserves conversion price from Chainlink feeds.
contract DexSmartT4CLOracle is
    FluidOracle,
    DexSmartColOracleImpl,
    DexSmartDebtOracleImpl,
    DexConversionPriceCL,
    DexReservesFromPEX
{
    struct DexSmartT4CLOracleParams {
        string infoName;
        uint8 targetDecimals;
        address dexPool;
        bool quoteInToken0;
        ChainlinkOracleImpl.ChainlinkConstructorParams reservesConversion;
        uint256 reservesConversionPriceMultiplier;
        uint256 reservesConversionPriceDivisor;
        uint256 resultMultiplier;
        uint256 resultDivisor;
    }

    constructor(
        DexSmartT4CLOracleParams memory params_
    )
        FluidOracle(params_.infoName, params_.targetDecimals)
        DexOracleAdjustResult(params_.resultMultiplier, params_.resultDivisor)
        DexReservesFromPEX(params_.dexPool, params_.quoteInToken0)
        DexConversionPriceCL(
            params_.reservesConversion,
            params_.reservesConversionPriceMultiplier,
            params_.reservesConversionPriceDivisor
        )
    {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        uint256 conversionPrice_ = _getDexReservesConversionPriceOperate();
        PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices();

        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexCollateralReserves(conversionPrice_, pex_);

        uint256 quoteTokensPer1ColShare_ = _getDexSmartColExchangeRate(
            conversionPrice_,
            token0Reserves_,
            token1Reserves_
        );

        (token0Reserves_, token1Reserves_) = _getDexDebtReserves(conversionPrice_, pex_);
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
        PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices();

        (uint256 token0Reserves_, uint256 token1Reserves_) = _getDexCollateralReserves(conversionPrice_, pex_);

        uint256 quoteTokensPer1ColShare_ = _getDexSmartColExchangeRate(
            conversionPrice_,
            token0Reserves_,
            token1Reserves_
        );

        (token0Reserves_, token1Reserves_) = _getDexDebtReserves(conversionPrice_, pex_);
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
