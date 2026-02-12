//SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.29;

abstract contract Events {
    event LogBuyback(address indexed tokenIn, address indexed tokenOut, uint256 sellAmount, uint256 buyAmount);
    event LogTokenSwap(address indexed tokenIn, address indexed tokenOut, uint256 sellAmount, uint256 buyAmount);
    event LogUpdateRebalancer(address indexed rebalancer, bool indexed isActive);
    event LogCollectFluidTokensToTreasury(uint256 indexed amount);
    event LogCollectTokensToTreasury(address indexed token, uint256 indexed amount);
}
