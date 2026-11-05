// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFluidConfigHandler {
    /// @notice returns how much the new config would be different from current config in percent (100 = 1%, 1 = 0.01%).
    function relativeConfigPercentDiff() external view returns (uint256 relativeConfigPercentDiff_);

    /// @notice returns how much the new config would be different from current config.
    function absoluteConfigDiff() external view returns (uint256 absoluteConfigDiff_);

    /// @notice returns the new config.
    function newConfig() external view returns (uint256 newConfig_);

    /// @notice returns the current config.
    function currentConfig() external view returns (uint256 currentConfig_);

    /// @notice Rebalances the configs at Fluid Liquidity based on config handler target.
    /// Reverts if no update is needed.
    /// Can only be called by an authorized rebalancer.
    function rebalance() external;
}
