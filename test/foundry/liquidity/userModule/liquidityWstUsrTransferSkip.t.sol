//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AuthModule, FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { TestERC20 } from "../../testERC20.sol";

contract LiquidityWstUsrTransferSkipTest is LiquidityUserModuleBaseTest {
    address internal constant WSTUSR = 0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055;

    function _setupWstUsr() internal {
        vm.chainId(1);

        TestERC20 wstUsrImpl_ = new TestERC20("wstUSR", "wstUSR");
        vm.etch(WSTUSR, address(wstUsrImpl_).code);

        TestERC20(WSTUSR).mint(alice, 1e50 ether);
        TestERC20(WSTUSR).mint(bob, 1e50 ether);

        _setApproval(IERC20(WSTUSR), address(mockProtocol), alice);
        _setApproval(IERC20(WSTUSR), address(mockProtocol), bob);

        _setDefaultRateDataV1(address(liquidity), admin, WSTUSR);
        _setDefaultTokenConfigs(address(liquidity), admin, WSTUSR);
        _setUserAllowancesDefaultWithModeWithHighLimit(address(liquidity), admin, WSTUSR, address(mockProtocol), true);
    }

    function test_operate_WstUsrWithdrawSkipsTransferOut() public {
        _setupWstUsr();

        _supply(address(liquidity), mockProtocol, WSTUSR, alice, 1000 ether);

        uint256 aliceBalanceBefore_ = IERC20(WSTUSR).balanceOf(alice);
        uint256 liquidityBalanceBefore_ = IERC20(WSTUSR).balanceOf(address(liquidity));

        _withdraw(address(liquidity), mockProtocol, WSTUSR, alice, 100 ether);

        assertEq(IERC20(WSTUSR).balanceOf(alice), aliceBalanceBefore_);
        assertEq(IERC20(WSTUSR).balanceOf(address(liquidity)), liquidityBalanceBefore_);
    }

    function test_operate_WstUsrBorrowStillTransfersOut() public {
        _setupWstUsr();

        _supply(address(liquidity), mockProtocol, WSTUSR, alice, 1000 ether);

        uint256 bobBalanceBefore_ = IERC20(WSTUSR).balanceOf(bob);
        uint256 liquidityBalanceBefore_ = IERC20(WSTUSR).balanceOf(address(liquidity));

        _borrow(mockProtocol, WSTUSR, bob, 100 ether);

        assertEq(IERC20(WSTUSR).balanceOf(bob), bobBalanceBefore_ + 100 ether);
        assertEq(IERC20(WSTUSR).balanceOf(address(liquidity)), liquidityBalanceBefore_ - 100 ether);
    }

    function test_collectRevenue_WstUsrSkipsTransferToCollector() public {
        _setupWstUsr();

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRevenueCollector(admin);

        _supply(address(liquidity), mockProtocol, WSTUSR, alice, 10000 ether);
        _borrow(mockProtocol, WSTUSR, bob, 8000 ether);
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        uint256 adminBalanceBefore_ = IERC20(WSTUSR).balanceOf(admin);
        uint256 liquidityBalanceBefore_ = IERC20(WSTUSR).balanceOf(address(liquidity));

        address[] memory tokens_ = new address[](1);
        tokens_[0] = WSTUSR;

        vm.prank(admin);
        AuthModule(address(liquidity)).collectRevenue(tokens_);

        assertEq(IERC20(WSTUSR).balanceOf(admin), adminBalanceBefore_);
        assertEq(IERC20(WSTUSR).balanceOf(address(liquidity)), liquidityBalanceBefore_);
    }
}
