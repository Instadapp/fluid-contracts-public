// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IEZETHBalancerRateProvider {
    /// @notice Returns the current rate of ezETH in ETH
    function getRate() external view returns (uint256 rate);
}
