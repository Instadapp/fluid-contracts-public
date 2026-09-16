//SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title FluidUsEquityMarketHoursProxy
/// @notice ERC1967 proxy for `FluidUsEquityMarketHours`. Upgrades via UUPS, authorized by Liquidity governance.
contract FluidUsEquityMarketHoursProxy is ERC1967Proxy {
    constructor(address logic_, bytes memory data_) payable ERC1967Proxy(logic_, data_) {}
}
