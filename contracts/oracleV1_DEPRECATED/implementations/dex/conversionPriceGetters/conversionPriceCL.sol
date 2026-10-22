// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { DexConversionPriceGetter } from "./dexConversionPriceGetter.sol";
import { ChainlinkOracleImpl } from "../../../implementations/chainlinkOracleImpl.sol";
import { ErrorTypes } from "../../../errorTypes.sol";

/// @notice returns the reserves conversion price fetched from Chainlink feeds
abstract contract DexConversionPriceCL is DexConversionPriceGetter, ChainlinkOracleImpl {
    uint256 internal immutable RESERVES_CONVERSION_PRICE_MULTIPLIER;
    uint256 internal immutable RESERVES_CONVERSION_PRICE_DIVISOR;

    /// @dev for multiplier and divisor: a Fluid ChainlinkOracle returns the price in token decimals scaled to 1e27 e.g. for USDC per ETH
    ///      it would be 3400e15 USDC if price is 3400$ per ETH. But the Dex internally would have a price of 3400e27. So for that example
    ///      the multiplier would have to be 1e12 and the divisor 1.
    /// @param reservesConversionPriceMultiplier_ The multiplier to bring the fetched price to token1/token0 form as used internally in Dex.
    /// @param reservesConversionPriceDivisor_ The divisor to bring the fetched price to token1/token0 form as used internally in Dex.
    constructor(
        ChainlinkOracleImpl.ChainlinkConstructorParams memory reservesConversion_,
        uint256 reservesConversionPriceMultiplier_,
        uint256 reservesConversionPriceDivisor_
    ) ChainlinkOracleImpl(reservesConversion_) {
        if (reservesConversionPriceMultiplier_ == 0 || reservesConversionPriceDivisor_ == 0) {
            revert FluidOracleError(ErrorTypes.DexOracle__InvalidParams);
        }
        RESERVES_CONVERSION_PRICE_MULTIPLIER = reservesConversionPriceMultiplier_;
        RESERVES_CONVERSION_PRICE_DIVISOR = reservesConversionPriceDivisor_;
    }

    function _getDexReservesConversionPriceOperate() internal view override returns (uint256 conversionPrice_) {
        // bring conversion price to form as used internally in Dex
        conversionPrice_ =
            (_getChainlinkExchangeRate() * RESERVES_CONVERSION_PRICE_MULTIPLIER) /
            RESERVES_CONVERSION_PRICE_DIVISOR;

        if (conversionPrice_ == 0) {
            revert FluidOracleError(ErrorTypes.DexOracle__ExchangeRateZero);
        }
    }

    function _getDexReservesConversionPriceLiquidate() internal view override returns (uint256 conversionPrice_) {
        // bring conversion price to form as used internally in Dex
        conversionPrice_ =
            (_getChainlinkExchangeRate() * RESERVES_CONVERSION_PRICE_MULTIPLIER) /
            RESERVES_CONVERSION_PRICE_DIVISOR;

        if (conversionPrice_ == 0) {
            revert FluidOracleError(ErrorTypes.DexOracle__ExchangeRateZero);
        }
    }

    /// @notice Returns the configuration data of the DexConversionPriceFluidOracle.
    ///
    /// @return reservesConversionPriceMultiplier_ The multiplier for the reserves conversion price.
    /// @return reservesConversionPriceDivisor_ The divisor for the reserves conversion price.
    function getDexConversionPriceFluidOracleData()
        public
        view
        returns (uint256 reservesConversionPriceMultiplier_, uint256 reservesConversionPriceDivisor_)
    {
        reservesConversionPriceMultiplier_ = RESERVES_CONVERSION_PRICE_MULTIPLIER;
        reservesConversionPriceDivisor_ = RESERVES_CONVERSION_PRICE_DIVISOR;
    }
}
