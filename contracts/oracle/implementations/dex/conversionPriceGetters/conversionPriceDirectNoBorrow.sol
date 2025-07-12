// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { DexSlotsLink } from "../../../../libraries/dexSlotsLink.sol";
import { DexConversionPriceGetter } from "./dexConversionPriceGetter.sol";

/// @notice returns the reserves conversion price fetched directly from the Fluid Dex Pool.
/// @dev IMPORTANT: TO BE USED ONLY WITH NO BORROW VAULTS (very tight borrow limits).
abstract contract DexConversionPriceDirectNoBorrow is DexConversionPriceGetter {
    uint256 private constant X8 = 0xff;
    uint256 private constant X40 = 0xffffffffff;

    /// @dev returns lastStoredPrice at Dex, e.g. for USDC_ETH Dex it returns ETH per 1 USDC, already scaled to 1e27.
    function _getDexReservesConversionPriceOperate() internal view override returns (uint256 conversionPrice_) {
        conversionPrice_ = DEX_.readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES_SLOT));
        conversionPrice_ = (conversionPrice_ >> 1) & X40;
        conversionPrice_ = (conversionPrice_ >> 8) << (conversionPrice_ & X8);
    }

    /// @dev returns lastStoredPrice at Dex, e.g. for USDC_ETH Dex it returns ETH per 1 USDC, already scaled to 1e27.
    function _getDexReservesConversionPriceLiquidate() internal view override returns (uint256 conversionPrice_) {
        conversionPrice_ = DEX_.readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES_SLOT));
        conversionPrice_ = (conversionPrice_ >> 1) & X40;
        conversionPrice_ = (conversionPrice_ >> 8) << (conversionPrice_ & X8);
    }
}
