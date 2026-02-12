// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { FluidLiquidityAdminModule } from "./main.sol";
import { CommonHelpersMainnet } from "../common/helpersMainnet.sol";

contract FluidLiquidityAdminModuleMainnet is FluidLiquidityAdminModule, CommonHelpersMainnet {
    constructor(uint256 nativeTokenMaxBorrowLimitCap_) FluidLiquidityAdminModule(nativeTokenMaxBorrowLimitCap_) {}
}
