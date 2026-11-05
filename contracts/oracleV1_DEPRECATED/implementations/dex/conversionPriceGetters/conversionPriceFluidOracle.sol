// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { DexConversionPriceGetter } from "./dexConversionPriceGetter.sol";
import { IFluidOracle } from "../../../interfaces/iFluidOracle.sol";
import { ErrorTypes } from "../../../errorTypes.sol";

/// @notice returns the reserves conversion price fetched from a separately deployed FluidOracle
abstract contract DexConversionPriceFluidOracle is DexConversionPriceGetter {
    /// @dev external IFluidOracle used to convert token0 into token1 or the other way
    /// around depending on _QUOTE_IN_TOKEN0.
    IFluidOracle internal immutable RESERVES_CONVERSION_ORACLE;
    bool internal immutable RESERVES_CONVERSION_INVERT;
    uint256 internal immutable RESERVES_CONVERSION_PRICE_MULTIPLIER;
    uint256 internal immutable RESERVES_CONVERSION_PRICE_DIVISOR;

    struct DexConversionPriceFluidOracleParams {
        address reservesConversionOracle;
        bool reservesConversionInvert;
        uint256 reservesConversionPriceMultiplier;
        uint256 reservesConversionPriceDivisor;
    }

    /// @dev for multiplier and divisor: a FluidOracle returns the price in token decimals scaled to 1e27 e.g. for USDC per ETH
    ///      it would be 3400e15 USDC if price is 3400$ per ETH. But the Dex internally would have a price of 3400e27. So for that example
    ///      the multiplier would have to be 1e12 and the divisor 1.
    /// @param conversionPriceParams_:
    ///  - reservesConversionOracle The oracle used to convert reserves. Set to address zero if not needed.
    ///  - reservesConversionInvert Whether to invert the reserves conversion. Can be skipped if no reservesConversionOracle is configured.
    ///  - reservesConversionPriceMultiplier The multiplier to bring the fetched price to token1/token0 form as used internally in Dex.
    ///  - reservesConversionPriceDivisor The divisor to bring the fetched price to token1/token0 form as used internally in Dex.
    constructor(DexConversionPriceFluidOracleParams memory conversionPriceParams_) {
        if (
            conversionPriceParams_.reservesConversionPriceMultiplier == 0 ||
            conversionPriceParams_.reservesConversionPriceDivisor == 0
        ) {
            revert FluidOracleError(ErrorTypes.DexOracle__InvalidParams);
        }
        RESERVES_CONVERSION_ORACLE = IFluidOracle(conversionPriceParams_.reservesConversionOracle);
        RESERVES_CONVERSION_INVERT = conversionPriceParams_.reservesConversionInvert;
        RESERVES_CONVERSION_PRICE_MULTIPLIER = conversionPriceParams_.reservesConversionPriceMultiplier;
        RESERVES_CONVERSION_PRICE_DIVISOR = conversionPriceParams_.reservesConversionPriceDivisor;
    }

    function _getDexReservesConversionPriceOperate() internal view override returns (uint256 conversionPrice_) {
        if (address(RESERVES_CONVERSION_ORACLE) == address(0)) {
            return 1e27;
        }

        // bring conversion price to form as used internally in Dex
        conversionPrice_ =
            (RESERVES_CONVERSION_ORACLE.getExchangeRateOperate() * RESERVES_CONVERSION_PRICE_MULTIPLIER) /
            RESERVES_CONVERSION_PRICE_DIVISOR;

        if (RESERVES_CONVERSION_INVERT) {
            conversionPrice_ = 1e54 / conversionPrice_;
        }
    }

    function _getDexReservesConversionPriceLiquidate() internal view override returns (uint256 conversionPrice_) {
        if (address(RESERVES_CONVERSION_ORACLE) == address(0)) {
            return 1e27;
        }

        // bring conversion price to form as used internally in Dex
        conversionPrice_ =
            (RESERVES_CONVERSION_ORACLE.getExchangeRateLiquidate() * RESERVES_CONVERSION_PRICE_MULTIPLIER) /
            RESERVES_CONVERSION_PRICE_DIVISOR;
        if (RESERVES_CONVERSION_INVERT) {
            conversionPrice_ = 1e54 / conversionPrice_;
        }
    }

    /// @notice Returns the configuration data of the DexConversionPriceFluidOracle.
    ///
    /// @return reservesConversionOracle_ The address of the reserves conversion oracle.
    /// @return reservesConversionInvert_ A boolean indicating if reserves conversion should be inverted.
    /// @return reservesConversionPriceMultiplier_ The multiplier for the reserves conversion price.
    /// @return reservesConversionPriceDivisor_ The divisor for the reserves conversion price.
    function getDexConversionPriceFluidOracleData()
        public
        view
        returns (
            address reservesConversionOracle_,
            bool reservesConversionInvert_,
            uint256 reservesConversionPriceMultiplier_,
            uint256 reservesConversionPriceDivisor_
        )
    {
        reservesConversionOracle_ = address(RESERVES_CONVERSION_ORACLE);
        reservesConversionInvert_ = RESERVES_CONVERSION_INVERT;
        reservesConversionPriceMultiplier_ = RESERVES_CONVERSION_PRICE_MULTIPLIER;
        reservesConversionPriceDivisor_ = RESERVES_CONVERSION_PRICE_DIVISOR;
    }
}
