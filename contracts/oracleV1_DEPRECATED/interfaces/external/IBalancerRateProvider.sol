// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IBalancerRateProvider {
    /// @notice Returns the current rate of e.g. ezETH in ETH
    function getRate() external view returns (uint256 rate);
}
