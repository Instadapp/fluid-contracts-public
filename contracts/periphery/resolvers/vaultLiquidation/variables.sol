// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidVaultResolver } from "../vault/iVaultResolver.sol";

contract Variables {
    IFluidVaultResolver public immutable VAULT_RESOLVER;

    constructor(IFluidVaultResolver vaultResolver_) {
        VAULT_RESOLVER = vaultResolver_;
    }
}
