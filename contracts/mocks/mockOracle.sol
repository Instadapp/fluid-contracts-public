// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../oracle/fluidOracle.sol";

/// @notice Mock Oracle for testing
contract MockOracle is FluidOracle {
    uint256 public price;

    constructor() FluidOracle("someName", 20) {}

    // Price is in 1e27 decimals between 2 tokens.
    // For example: if 1 ETH = 2000 USDC, that means 1e18 of ETH = 2000 * 1e6 of USDC
    // debt per col = 2000 * 1e6 * 1e27 / 1e18;

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() external view override returns (uint256 exchangeRate_) {
        return price;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() external view override returns (uint256 exchangeRate_) {
        return price;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() external view override returns (uint256 exchangeRate_) {
        return price;
    }

    function setPrice(uint256 price_) external {
        price = price_;
    }
}
