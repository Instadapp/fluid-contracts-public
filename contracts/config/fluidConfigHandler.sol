// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidConfigHandler } from "./interfaces/iFluidConfigHandler.sol";

/// @title   FluidConfigHandler
/// @notice  Base contract that any Fluid Config Handler must implement
abstract contract FluidConfigHandler is IFluidConfigHandler {
    /// @inheritdoc IFluidConfigHandler
    function relativeConfigPercentDiff() public view virtual returns (uint256 relativeConfigPercentDiff_);

    /// @inheritdoc IFluidConfigHandler
    function absoluteConfigDiff() public view virtual returns (uint256 absoluteConfigDiff_);

    /// @inheritdoc IFluidConfigHandler
    function newConfig() public view virtual returns (uint256 newConfig_);

    /// @inheritdoc IFluidConfigHandler
    function currentConfig() public view virtual returns (uint256 currentConfig_);

    /// @inheritdoc IFluidConfigHandler
    function rebalance() external virtual;
}
