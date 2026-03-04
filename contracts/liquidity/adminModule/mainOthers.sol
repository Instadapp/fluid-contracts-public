// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { FluidLiquidityAdminModule } from "./main.sol";
import { CommonHelpersOthers } from "../common/helpersOthers.sol";

contract FluidLiquidityAdminModuleOthers is FluidLiquidityAdminModule, CommonHelpersOthers {
    constructor(uint256 nativeTokenMaxBorrowLimitCap_) FluidLiquidityAdminModule(nativeTokenMaxBorrowLimitCap_) {}
}
