//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Error } from "../../../contracts/config/error.sol";
import { ErrorTypes } from "../../../contracts/config/errorTypes.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidReserveContract } from "../../../contracts/reserve/interfaces/iReserveContract.sol";
import { FluidVaultFeeRewardsAuth } from "../../../contracts/config/vaultFeeRewardsAuth/main.sol";
import { FluidVaultFactory } from "../../../contracts/protocols/vault/factory/main.sol";

contract VaultFeeRewardsAuthTest is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidReserveContract internal constant RESERVE_CONTRACT =
        IFluidReserveContract(0x264786EF916af64a1DB19F513F24a3681734ce92);

    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;
    address internal constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address internal constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;
    address bob = address(0xB0B);

    // These are placeholder addresses for the 4 vault types. Replace with real ones for integration.
    address constant VAULT_T1 = 0xB94887D3A6fB124901800b79AEa69B732b71450a; // NORMAL COL/DEBT
    address constant VAULT_T2 = 0x87882Fb36C59344798D4cAC68396A9BAFa60131D; // SMART COL
    address constant VAULT_T3 = 0xe210d8ded13Abe836a10E8Aa956dd424658d0034; // SMART DEBT
    address constant VAULT_T4 = 0x0a90ED6964f6bA56902fD35EE11857A810Dd5543; // SMART COL + SMART DEBT

    FluidVaultFeeRewardsAuth handler;

    address internal constant VAULT_FACTORY = 0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(22905363);

        handler = new FluidVaultFeeRewardsAuth();

        vm.prank(GOVERNANCE);
        FluidVaultFactory(VAULT_FACTORY).setGlobalAuth(address(handler), true);
    }

    function test_onlyMultisigModifier_revertsForNonMultisig() public {
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__Unauthorized)
        );
        handler.updateSupplyRate(VAULT_T2, 100);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__Unauthorized)
        );
        handler.updateBorrowRate(VAULT_T3, 100);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__Unauthorized)
        );
        handler.updateSupplyRateMagnifier(VAULT_T1, 2e3);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__Unauthorized)
        );
        handler.updateBorrowRateMagnifier(VAULT_T1, 2e3);
        vm.stopPrank();
    }

    function test_updateSupplyRate_revertsForWrongVaultType() public {
        // Only SMART COL or T4 (col+debt) allowed
        vm.startPrank(TEAM_MULTISIG2);
        // VAULT_T1 is not smart col
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.updateSupplyRate(VAULT_T1, 100);
        // VAULT_T3 is not smart col
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.updateSupplyRate(VAULT_T3, 100);
        vm.stopPrank();
    }

    function test_updateBorrowRate_revertsForWrongVaultType() public {
        // Only SMART DEBT or T4 (col+debt) allowed
        vm.startPrank(TEAM_MULTISIG2);
        // VAULT_T1 is not smart debt
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.updateBorrowRate(VAULT_T1, 100);

        // VAULT_T2 is not smart debt
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.updateBorrowRate(VAULT_T2, 100);
        vm.stopPrank();
    }

    function test_updateSupplyRateMagnifier_revertsForWrongVaultType() public {
        vm.startPrank(TEAM_MULTISIG2);
        // VAULT_T2 is smart col
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.updateSupplyRateMagnifier(VAULT_T2, 2e3);
        // VAULT_T4 is smart col+debt
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.updateSupplyRateMagnifier(VAULT_T4, 2e3);
        vm.stopPrank();
    }

    function test_updateBorrowRateMagnifier_revertsForWrongVaultType() public {
        vm.startPrank(TEAM_MULTISIG2);
        // VAULT_T3 is smart debt
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.updateBorrowRateMagnifier(VAULT_T3, 2e3);
        // VAULT_T4 is smart col+debt
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.updateBorrowRateMagnifier(VAULT_T4, 2e3);
        vm.stopPrank();
    }

    function test_currentSupplyRateMagnifier_revertsForSmartCol() public {
        // Should revert for smart col vaults
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.currentSupplyRateMagnifier(VAULT_T2);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.currentSupplyRateMagnifier(VAULT_T4);
    }

    function test_currentBorrowRateMagnifier_revertsForSmartDebt() public {
        // Should revert for smart debt vaults
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.currentBorrowRateMagnifier(VAULT_T3);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.currentBorrowRateMagnifier(VAULT_T4);
    }

    function test_currentSupplyRate_revertsForNonSmartCol() public {
        // Should revert for non-smart col vaults
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.currentSupplyRate(VAULT_T1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.currentSupplyRate(VAULT_T3);
    }

    function test_currentBorrowRate_revertsForNonSmartDebt() public {
        // Should revert for non-smart debt vaults
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.currentBorrowRate(VAULT_T1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType)
        );
        handler.currentBorrowRate(VAULT_T2);
    }

    function test_integration_setAndGetSupplyRate_forSmartColAndT4() public {
        vm.startPrank(TEAM_MULTISIG);

        // Set and check for T2 (SMART COL)
        handler.updateSupplyRate(VAULT_T2, 1);
        int256 supplyRateT2 = handler.currentSupplyRate(VAULT_T2);
        assertEq(supplyRateT2, 1, "Supply rate for VAULT_T2 not set correctly");

        // Set and check for T4 (SMART COL + SMART DEBT)
        handler.updateSupplyRate(VAULT_T4, -1e3);
        int256 supplyRateT4 = handler.currentSupplyRate(VAULT_T4);
        assertEq(supplyRateT4, -1e3, "Supply rate for VAULT_T4 not set correctly");

        vm.stopPrank();
    }

    function test_integration_setAndGetBorrowRate_forSmartDebtAndT4() public {
        vm.startPrank(TEAM_MULTISIG);

        // Set and check for T3 (SMART DEBT)
        handler.updateBorrowRate(VAULT_T3, 1);
        int256 borrowRateT3 = handler.currentBorrowRate(VAULT_T3);
        assertEq(borrowRateT3, 1, "Borrow rate for VAULT_T3 not set correctly");

        // Set and check for T4 (SMART COL + SMART DEBT)
        handler.updateBorrowRate(VAULT_T4, -1e3);
        int256 borrowRateT4 = handler.currentBorrowRate(VAULT_T4);
        assertEq(borrowRateT4, -1e3, "Borrow rate for VAULT_T4 not set correctly");

        vm.stopPrank();
    }

    function test_integration_setAndGetSupplyRateMagnifier_forT1_and_T3() public {
        vm.startPrank(TEAM_MULTISIG);

        // Test for T1
        handler.updateSupplyRateMagnifier(VAULT_T1, 1);
        uint256 magnifierT1_1 = handler.currentSupplyRateMagnifier(VAULT_T1);
        assertEq(magnifierT1_1, 1, "Supply rate magnifier for VAULT_T1 not set correctly (1)");

        handler.updateSupplyRateMagnifier(VAULT_T1, 1e3);
        uint256 magnifierT1_2 = handler.currentSupplyRateMagnifier(VAULT_T1);
        assertEq(magnifierT1_2, 1e3, "Supply rate magnifier for VAULT_T1 not set correctly (1e3)");

        // Test for T3
        handler.updateSupplyRateMagnifier(VAULT_T3, 2);
        uint256 magnifierT3_1 = handler.currentSupplyRateMagnifier(VAULT_T3);
        assertEq(magnifierT3_1, 2, "Supply rate magnifier for VAULT_T3 not set correctly (2)");

        handler.updateSupplyRateMagnifier(VAULT_T3, 2e3);
        uint256 magnifierT3_2 = handler.currentSupplyRateMagnifier(VAULT_T3);
        assertEq(magnifierT3_2, 2e3, "Supply rate magnifier for VAULT_T3 not set correctly (2e3)");

        vm.stopPrank();
    }

    function test_integration_setAndGetBorrowRateMagnifier_forT1_and_T2() public {
        vm.startPrank(TEAM_MULTISIG);

        // Test for T1
        handler.updateBorrowRateMagnifier(VAULT_T1, 1);
        uint256 magnifierT1_1 = handler.currentBorrowRateMagnifier(VAULT_T1);
        assertEq(magnifierT1_1, 1, "Borrow rate magnifier for VAULT_T1 not set correctly (1)");

        handler.updateBorrowRateMagnifier(VAULT_T1, 1e3);
        uint256 magnifierT1_2 = handler.currentBorrowRateMagnifier(VAULT_T1);
        assertEq(magnifierT1_2, 1e3, "Borrow rate magnifier for VAULT_T1 not set correctly (1e3)");

        // Test for T2
        handler.updateBorrowRateMagnifier(VAULT_T2, 2);
        uint256 magnifierT2_1 = handler.currentBorrowRateMagnifier(VAULT_T2);
        assertEq(magnifierT2_1, 2, "Borrow rate magnifier for VAULT_T2 not set correctly (2)");

        handler.updateBorrowRateMagnifier(VAULT_T2, 2e3);
        uint256 magnifierT2_2 = handler.currentBorrowRateMagnifier(VAULT_T2);
        assertEq(magnifierT2_2, 2e3, "Borrow rate magnifier for VAULT_T2 not set correctly (2e3)");

        vm.stopPrank();
    }
}
