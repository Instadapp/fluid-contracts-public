// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidVaultResolver } from "../vault/iVaultResolver.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";

contract Variables {
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    IFluidVaultResolver public immutable VAULT_RESOLVER;

    /// @notice address of the liquidity contract
    IFluidLiquidity public immutable LIQUIDITY;

    constructor(IFluidVaultResolver vaultResolver_, IFluidLiquidity liquidity_) {
        VAULT_RESOLVER = vaultResolver_;
        LIQUIDITY = liquidity_;
    }
}
