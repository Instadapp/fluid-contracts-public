//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { LiquidityBaseTest } from "../../liquidity/liquidityBaseTest.t.sol";
import { FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

contract FluidLiquidityResolverPauseStatusTest is LiquidityBaseTest {
    FluidLiquidityResolver internal liquidityResolver;

    address internal pauseUser;
    address internal pauseToken;

    function setUp() public virtual override {
        super.setUp();

        liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(address(liquidity)));

        pauseUser = address(DAI);
        pauseToken = address(USDC);

        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: pauseUser,
            token: pauseToken,
            mode: 1,
            expandPercent: 5000,
            expandDuration: 60,
            baseWithdrawalLimit: 1000 ether
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: pauseUser,
            token: pauseToken,
            mode: 1,
            expandPercent: 5000,
            expandDuration: 60,
            baseDebtCeiling: 1000 ether,
            maxDebtCeiling: 1000 ether
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);
    }

    function _pauseTokens() internal view returns (address[] memory tokens_) {
        tokens_ = new address[](1);
        tokens_[0] = pauseToken;
    }

    function _setUserClass(uint256 class_) internal {
        AdminModuleStructs.AddressUint256[] memory userClasses_ = new AdminModuleStructs.AddressUint256[](1);
        userClasses_[0] = AdminModuleStructs.AddressUint256(pauseUser, class_);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserClasses(userClasses_);
    }

    function _assertPaused(bool supplyPaused_, bool withdrawPaused_, bool borrowPaused_, bool paybackPaused_) internal {
        (bool supply_, bool withdraw_, bool borrow_, bool payback_) = liquidityResolver.getUserOperationsPaused(
            pauseUser,
            pauseToken
        );
        assertEq(supply_, supplyPaused_, "supplyPaused");
        assertEq(withdraw_, withdrawPaused_, "withdrawPaused");
        assertEq(borrow_, borrowPaused_, "borrowPaused");
        assertEq(payback_, paybackPaused_, "paybackPaused");
    }

    function test_getUserOperationsPaused_NothingPaused() public {
        _assertPaused(false, false, false, false);
    }

    function test_getUserOperationsPaused_UserSupplyPauseOnly() public {
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseUserSupply(pauseUser, _pauseTokens(), true, false);

        _assertPaused(true, false, false, false);
    }

    function test_getUserOperationsPaused_UserWithdrawPauseOnly() public {
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseUserSupply(pauseUser, _pauseTokens(), false, true);

        _assertPaused(false, true, false, false);
    }

    function test_getUserOperationsPaused_UserBorrowAndPaybackPause() public {
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseUserBorrow(pauseUser, _pauseTokens(), true, true);

        _assertPaused(false, false, true, true);
    }

    function test_getUserOperationsPaused_TokenBorrowPauseClass0User() public {
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseTokens(_pauseTokens(), false, false, true, false);

        _assertPaused(false, false, true, false);
    }

    function test_getUserOperationsPaused_TokenWithdrawPauseClass1UserExempt() public {
        _setUserClass(1);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseTokens(_pauseTokens(), false, true, false, false);

        _assertPaused(false, false, false, false);
    }

    function test_getUserOperationsPaused_TokenSupplyAndBorrowPauseClass1User() public {
        _setUserClass(1);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseTokens(_pauseTokens(), true, false, true, false);

        _assertPaused(true, false, true, false);
    }

    function test_getUserOperationsPaused_TokenAllPausesClass2UserExempt() public {
        _setUserClass(2);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseTokens(_pauseTokens(), true, true, true, true);

        _assertPaused(false, false, false, false);
    }

    function test_getUserOperationsPaused_GlobalStatusPaused() public {
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).changeStatus(2);

        _assertPaused(true, true, true, true);

        // changeStatus(0) reverts (AdminModule__InvalidParams), so restore to the non-paused status 1
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).changeStatus(1);
    }
}
