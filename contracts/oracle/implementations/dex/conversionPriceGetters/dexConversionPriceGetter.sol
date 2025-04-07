// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { DexOracleBase } from "../dexOracleBase.sol";

/// @dev abstract contract that any Dex Oracle ConversionPriceGetter should implement
abstract contract DexConversionPriceGetter is DexOracleBase {
    function _getDexReservesConversionPriceOperate() internal view virtual returns (uint256 conversionPrice_);

    function _getDexReservesConversionPriceLiquidate() internal view virtual returns (uint256 conversionPrice_);
}
