// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFluidConfigHandler {
    /// @notice returns how much the new config would be different from current config in percent (100 = 1%, 1 = 0.01%).
    function configPercentDiff() external view returns (uint256 configPercentDiff_);

    /// @notice Rebalances the configs at Fluid Liquidity based on config handler target.
    /// Reverts if no update is needed.
    /// Can only be called by an authorized rebalancer.
    function rebalance() external;
}
