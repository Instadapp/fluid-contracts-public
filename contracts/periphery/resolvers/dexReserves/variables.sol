// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidDexFactory } from "../../../protocols/dex/interfaces/iDexFactory.sol";
import { IFluidLiquidityResolver } from "../liquidity/iLiquidityResolver.sol";

interface IFluidLiquidity {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}

abstract contract Variables {
    uint256 internal constant X10 = 0x3ff;
    uint256 internal constant X17 = 0x1ffff;

    uint256 internal constant ORACLE_LIMIT = 5 * 1e16; // 5%

    /// @dev address that is mapped to the chain native token
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IFluidDexFactory public immutable FACTORY;
    IFluidLiquidity public immutable LIQUIDITY;
    IFluidLiquidityResolver public immutable LIQUIDITY_RESOLVER;

    constructor(address factory_, address liquidity_, address liquidityResolver_) {
        FACTORY = IFluidDexFactory(factory_);
        LIQUIDITY = IFluidLiquidity(liquidity_);
        LIQUIDITY_RESOLVER = IFluidLiquidityResolver(liquidityResolver_);
    }
}
