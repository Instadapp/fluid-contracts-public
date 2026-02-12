// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";


contract MockWETH is ERC20 {
    constructor () ERC20("WETH", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        Address.sendValue(payable(msg.sender), amount);
    }
}