// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidVaultResolver } from "../vault/iVaultResolver.sol";
import { IFluidVaultFactory } from "../../../protocols/vault/interfaces/iVaultFactory.sol";

contract Variables {
    IFluidVaultResolver public immutable VAULT_RESOLVER;
    IFluidVaultFactory public immutable FACTORY;

    constructor(IFluidVaultResolver vaultResolver_, IFluidVaultFactory vaultFactory_) {
        VAULT_RESOLVER = vaultResolver_;
        FACTORY = vaultFactory_;
    }
}
