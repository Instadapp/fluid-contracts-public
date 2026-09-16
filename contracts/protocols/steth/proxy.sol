//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title    FluidStETHQueueProxy
/// @notice   Default ERC1967Proxy for StETHQueue
contract FluidStETHQueueProxy is ERC1967Proxy {
    constructor(address logic_, bytes memory data_) payable ERC1967Proxy(logic_, data_) {}
}
