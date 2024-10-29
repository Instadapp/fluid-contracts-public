// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";

/// @title   Mock oracle that always returns 1e27
contract Mock1e27Oracle is FluidOracle {
    constructor(string memory infoName_) FluidOracle(infoName_) {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public pure override returns (uint256 exchangeRate_) {
        return 1e27;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() external pure override returns (uint256 exchangeRate_) {
        return 1e27;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() external pure override returns (uint256 exchangeRate_) {
        return 1e27;
    }
}
