// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";

/// @title Static NO BORROW oracle that returns a static price
/// @dev   ATTENTION: ONLY USE THIS FOR MOCKING OR FOR VAULTS WITH NO BORROWING (VERY TIGHT BORROW LIMITS).
contract StaticNoBorrowOracle is FluidOracle {
    uint256 internal immutable STATIC_PRICE;
    bool internal immutable LIQUIDATE_ZERO;

    constructor(
        string memory infoName_,
        uint8 targetDecimals_,
        uint256 staticPrice_,
        bool liquidateZero_
    ) FluidOracle(infoName_, targetDecimals_) {
        if (staticPrice_ == 0) revert("static price 0");
        STATIC_PRICE = staticPrice_;
        LIQUIDATE_ZERO = liquidateZero_;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view override returns (uint256 exchangeRate_) {
        return STATIC_PRICE;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() external view override returns (uint256 exchangeRate_) {
        if (LIQUIDATE_ZERO) return 0; // will lead to a revert at Vault
        return STATIC_PRICE;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() external view override returns (uint256 exchangeRate_) {
        return STATIC_PRICE;
    }
}
