// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

/// @dev abstract contract that any Dex Oracle ColDebtPriceGetter should implement
abstract contract DexColDebtPriceGetter {
    uint256 internal constant DEX_COL_DEBT_ORACLE_PRECISION = 1e27;

    function _getDexColDebtPriceOperate() internal view virtual returns (uint256 colDebtPrice_);

    function _getDexColDebtPriceLiquidate() internal view virtual returns (uint256 colDebtPrice_);
}
