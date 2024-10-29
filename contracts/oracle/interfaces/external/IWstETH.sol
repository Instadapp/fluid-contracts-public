// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IWstETH {
    /**
     * @notice Get amount of stETH for 1 wstETH
     * @return Amount of stETH for 1 wstETH
     */
    function stEthPerToken() external view returns (uint256);

    /**
     * @notice Get amount of wstETH for 1 stETH
     * @return Amount of wstETH for 1 stETH
     */
    function tokensPerStEth() external view returns (uint256);
}
