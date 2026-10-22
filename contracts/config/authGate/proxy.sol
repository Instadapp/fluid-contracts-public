// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title FluidAuthGateProxy
/// @notice ERC1967 proxy for `FluidAuthGate`. Upgrades via UUPS, authorized by Liquidity governance.
contract FluidAuthGateProxy is ERC1967Proxy {
    constructor(address logic_, bytes memory data_) payable ERC1967Proxy(logic_, data_) {}
}
