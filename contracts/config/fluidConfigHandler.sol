// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidConfigHandler } from "./interfaces/iFluidConfigHandler.sol";

/// @title   FluidConfigHandler
/// @notice  Base contract that any Fluid Config Handler must implement
abstract contract FluidConfigHandler is IFluidConfigHandler {
    /// @inheritdoc IFluidConfigHandler
    function configPercentDiff() public view virtual returns (uint256 configPercentDiff_);

    /// @inheritdoc IFluidConfigHandler
    function rebalance() external virtual;
}
