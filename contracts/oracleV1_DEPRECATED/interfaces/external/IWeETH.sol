// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IWeETH {
    /**
     * @notice Get amount of eETH for {_weETHAmount} weETH
     * @return Amount of eETH for {_weETHAmount} weETH
     */
    function getEETHByWeETH(uint256 _weETHAmount) external view returns (uint256);

    /**
     * @notice Get amount of weETH for {_eETHAmount} eETH
     * @return Amount of weETH for {_eETHAmount} eETH
     */
    function getWeETHByeETH(uint256 _eETHAmount) external view returns (uint256);
}
