//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { LiquidityCalcsTestHelper } from "./liquidityCalcsTestHelper.sol";
import { LiquiditySimulateStorageSlot } from "../../liquidity/liquidityTestHelpers.sol";

contract LibraryLiquidityCalcsBaseTest is Test, LiquiditySimulateStorageSlot {
    // use testHelper contract to measure gas for library methods via forge --gas-report
    LiquidityCalcsTestHelper testHelper;

    function setUp() public virtual {
        testHelper = new LiquidityCalcsTestHelper();
    }
}
