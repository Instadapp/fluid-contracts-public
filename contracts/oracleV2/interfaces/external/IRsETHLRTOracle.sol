// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IRsETHLRTOracle {
    /// @notice ETH per 1 rsETH exchange rate
    function rsETHPrice() external view returns (uint256 rate);
}
