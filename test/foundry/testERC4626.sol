//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestERC4626 is ERC4626 {
    constructor(IERC20 underlying) ERC4626(underlying) ERC20("TestERC20", "SYM") {}
}
