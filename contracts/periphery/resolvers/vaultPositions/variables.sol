// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidVaultResolver } from "../vault/iVaultResolver.sol";
import { IFluidVaultFactory } from "../../../protocols/vault/interfaces/iVaultFactory.sol";

contract Variables {
    IFluidVaultResolver public immutable VAULT_RESOLVER;
    IFluidVaultFactory public immutable FACTORY;

    // 30 bits (used for partials mainly)
    uint internal constant X8 = 0xff;
    uint internal constant X19 = 0x7ffff;
    uint internal constant X24 = 0xffffff;
    uint internal constant X32 = 0xffffffff;
    uint internal constant X64 = 0xffffffffffffffff;

    constructor(IFluidVaultResolver vaultResolver_, IFluidVaultFactory vaultFactory_) {
        VAULT_RESOLVER = vaultResolver_;
        FACTORY = vaultFactory_;
    }
}
