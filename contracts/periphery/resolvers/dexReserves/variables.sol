// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidDexFactory } from "../../../protocols/dex/interfaces/iDexFactory.sol";

abstract contract Variables {
    uint256 internal constant X17 = 0x1ffff;

    IFluidDexFactory public immutable FACTORY;

    constructor(address factory_) {
        FACTORY = IFluidDexFactory(factory_);
    }
}
