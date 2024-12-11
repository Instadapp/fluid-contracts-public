// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidityResolver } from "../liquidity/iLiquidityResolver.sol";
import { IFluidVaultFactory } from "../../../protocols/vault/interfaces/iVaultFactory.sol";

interface IFluidStorageReadable {
    function readFromStorage(bytes32 slot_) external view returns (uint result_);
}

contract Variables {
    IFluidVaultFactory public immutable FACTORY;
    IFluidLiquidityResolver public immutable LIQUIDITY_RESOLVER;

    // 30 bits (used for partials mainly)
    uint internal constant X8 = 0xff;
    uint internal constant X10 = 0x3ff;
    uint internal constant X14 = 0x3fff;
    uint internal constant X15 = 0x7fff;
    uint internal constant X16 = 0xffff;
    uint internal constant X18 = 0x3ffff;
    uint internal constant X19 = 0x7ffff;
    uint internal constant X20 = 0xfffff;
    uint internal constant X24 = 0xffffff;
    uint internal constant X25 = 0x1ffffff;
    uint internal constant X30 = 0x3fffffff;
    uint internal constant X32 = 0xffffffff;
    uint internal constant X33 = 0x1ffffffff;
    uint internal constant X35 = 0x7ffffffff;
    uint internal constant X40 = 0xffffffffff;
    uint internal constant X50 = 0x3ffffffffffff;
    uint internal constant X64 = 0xffffffffffffffff;
    uint internal constant X96 = 0xffffffffffffffffffffffff;
    uint internal constant X128 = 0xffffffffffffffffffffffffffffffff;
    /// @dev address that is mapped to the chain native token
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    constructor(address factory_, address liquidityResolver_) {
        FACTORY = IFluidVaultFactory(factory_);
        LIQUIDITY_RESOLVER = IFluidLiquidityResolver(liquidityResolver_);
    }
}
