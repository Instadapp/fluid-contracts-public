// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidOracle } from "./interfaces/iFluidOracle.sol";

/// @title   FluidOracle
/// @notice  Base contract that any Fluid Oracle must implement
abstract contract FluidOracle is IFluidOracle {
    /// @inheritdoc IFluidOracle
    function getExchangeRate() external view virtual returns (uint256 exchangeRate_);
}
