//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Error as FluidDexErrors } from "../../../../contracts/protocols/dex/error.sol";
import { ErrorTypes as FluidDexTypes } from "../../../../contracts/protocols/dex/errorTypes.sol";
import { FluidDexT1Admin } from "../../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import { Structs as DexAdminStructs } from "../../../../contracts/protocols/dex/poolT1/adminModule/structs.sol";

import { PoolT1BaseTest } from "./pool.t.sol";

contract PoolT1AdminGuardsTest is PoolT1BaseTest {
    function test_updateFeeAndRevenueCut_revertsAboveLiquidityTolerance() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(FluidDexErrors.FluidDexError.selector, FluidDexTypes.DexT1Admin__ConfigOverflow)
        );
        FluidDexT1Admin(address(DAI_USDC.dexCol)).updateFeeAndRevenueCut(100_000, 1_000_000);
    }

    function test_updateFeeAndRevenueCut_allowsWithinLiquidityTolerance() public {
        vm.prank(alice);
        FluidDexT1Admin(address(DAI_USDC.dexCol)).updateFeeAndRevenueCut(10_000, 990_000);
    }

    function test_initialize_revertsOnSecondCall() public {
        DexAdminStructs.InitializeVariables memory i_ = DexAdminStructs.InitializeVariables({
            smartCol: true,
            smartDebt: false,
            token0ColAmt: 1e18,
            token0DebtAmt: 0,
            fee: 100,
            revenueCut: 0,
            upperPercent: 10 * 1e4,
            lowerPercent: 10 * 1e4,
            upperShiftThreshold: 5 * 1e4,
            lowerShiftThreshold: 5 * 1e4,
            thresholdShiftTime: 1 days,
            centerPriceAddress: 0,
            hookAddress: 0,
            maxCenterPrice: 2e27,
            minCenterPrice: 1e27,
            centerPrice: 1e27
        });

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(FluidDexErrors.FluidDexError.selector, FluidDexTypes.DexT1Admin__AlreadyInitialized)
        );
        FluidDexT1Admin(address(DAI_USDC.dexCol)).initialize(i_);
    }
}
