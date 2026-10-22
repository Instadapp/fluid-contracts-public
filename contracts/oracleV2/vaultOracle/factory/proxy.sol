// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title VaultOracleFactoryProxy
/// @notice ERC1967 UUPS proxy — canonical factory address for integrations and `FluidContractFactory` allow-lists.
/// @dev Rationale (see `vaultOracle/README.md` “Why the factory uses a proxy”, `SPEC.md` §8.0): upgradeable
///      implementation without migrating state; `vaultIdToOracleDeployNonce` persists here across upgrades; one stable
///      address per network for contracts that reference the factory. Not the protocol “infinite proxy” pattern.
contract VaultOracleFactoryProxy is ERC1967Proxy {
    constructor(address implementation_, bytes memory initData_) ERC1967Proxy(implementation_, initData_) {}
}
