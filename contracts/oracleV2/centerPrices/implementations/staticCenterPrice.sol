// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidCenterPrice } from "../fluidCenterPrice.sol";

/// @title Static Center price that returns a static price
/// @dev   ATTENTION: DO NOT USE THIS ON A LIVE DEX POOL. It can be used to set a center price but then this needs to be removed
///        immediately again.
contract StaticCenterPrice is FluidCenterPrice {
    uint256 internal immutable STATIC_PRICE;

    constructor(string memory infoName_, uint256 staticPrice_) FluidCenterPrice(infoName_) {
        if (staticPrice_ == 0) revert("static price 0");
        STATIC_PRICE = staticPrice_;
    }

    /// @inheritdoc FluidCenterPrice
    function centerPrice() external view override returns (uint256 price_) {
        return STATIC_PRICE;
    }
}
