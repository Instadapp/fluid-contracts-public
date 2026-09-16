// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidVaultResolver } from "../vault/iVaultResolver.sol";

contract Variables {
    IFluidVaultResolver public immutable VAULT_RESOLVER;

    uint internal constant X8 = 0xff;
    uint internal constant X19 = 0x7ffff;
    uint internal constant X20 = 0xfffff;
    uint internal constant X30 = 0x3fffffff;
    uint internal constant X50 = 0x3ffffffffffff;
    uint internal constant X64 = 0xffffffffffffffff;

    constructor(IFluidVaultResolver vaultResolver_) {
        VAULT_RESOLVER = vaultResolver_;
    }
}
