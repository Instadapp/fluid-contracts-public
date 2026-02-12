// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidityResolver } from "../liquidity/iLiquidityResolver.sol";
import { IFluidDexFactory } from "../../../protocols/dex/interfaces/iDexFactory.sol";

interface IFluidLiquidity {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}

abstract contract Variables {
    IFluidDexFactory public immutable FACTORY;
    IFluidLiquidity public immutable LIQUIDITY;
    IFluidLiquidityResolver public immutable LIQUIDITY_RESOLVER;
    /// @dev Address of contract used for deploying center price & hook related contract
    address public immutable DEPLOYER_CONTRACT;

    uint256 internal constant X2 = 0x3;
    uint256 internal constant X3 = 0x7;
    uint256 internal constant X5 = 0x1f;
    uint256 internal constant X7 = 0x7f;
    uint256 internal constant X8 = 0xff;
    uint256 internal constant X9 = 0x1ff;
    uint256 internal constant X10 = 0x3ff;
    uint256 internal constant X11 = 0x7ff;
    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X16 = 0xffff;
    uint256 internal constant X17 = 0x1ffff;
    uint256 internal constant X20 = 0xfffff;
    uint256 internal constant X22 = 0x3fffff;
    uint256 internal constant X23 = 0x7fffff;
    uint256 internal constant X24 = 0xffffff;
    uint256 internal constant X28 = 0xfffffff;
    uint256 internal constant X30 = 0x3fffffff;
    uint256 internal constant X32 = 0xffffffff;
    uint256 internal constant X33 = 0x1ffffffff;
    uint256 internal constant X40 = 0xffffffffff;
    uint256 internal constant X64 = 0xffffffffffffffff;
    uint256 internal constant X128 = 0xffffffffffffffffffffffffffffffff;

    /// @dev address that is mapped to the chain native token
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(address factory_, address liquidity_, address liquidityResolver_, address deployer_) {
        FACTORY = IFluidDexFactory(factory_);
        LIQUIDITY = IFluidLiquidity(liquidity_);
        LIQUIDITY_RESOLVER = IFluidLiquidityResolver(liquidityResolver_);
        DEPLOYER_CONTRACT = deployer_;
    }
}
