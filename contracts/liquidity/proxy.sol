// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { Proxy } from "../infiniteProxy/proxy.sol";

/// @notice Fluid Liquidity infinte proxy.
/// Liquidity is the central point of the Instadapp Fluid architecture, it is the core interaction point
/// for all allow-listed protocols, such as fTokens, Vault, Flashloan, StETH protocol, DEX protocol etc.
contract FluidLiquidityProxy is Proxy {
    constructor(address admin_, address dummyImplementation_) Proxy(admin_, dummyImplementation_) {}
}
