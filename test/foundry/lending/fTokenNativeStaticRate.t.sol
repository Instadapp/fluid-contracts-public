// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FluidLendingStaticRateModel } from "../../../contracts/protocols/lending/lendingStaticRateModel/main.sol";
import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { IFluidLendingStaticRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingStaticRateModel.sol";
import { fTokenNativeUnderlying } from "../../../contracts/protocols/lending/fToken/nativeUnderlying/fTokenNativeUnderlying.sol";
import { IFTokenNativeUnderlying } from "../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { fTokenNativeTestBase } from "./fTokenNative.t.sol";
import { Events as fTokenEvents } from "../../../contracts/protocols/lending/fToken/events.sol";
import { TestERC20 } from "../testERC20.sol";

/// @dev Static-rate + bidirectional native rebalance (rewards in / fees out via msg.value refund path).
contract fTokenNativeStaticRateTest is fTokenNativeTestBase, fTokenEvents {
    uint256 constant RATE_PRECISION = 1e12;
    uint256 constant STATIC_TARGET_RATE = 3 * RATE_PRECISION;
    uint256 constant OPEN_ENDED_DURATION = 100 * 365 days;

    FluidLendingStaticRateModel staticModel;

    function _createToken(FluidLendingFactory lendingFactory_, IERC20) internal override returns (IERC4626) {
        vm.prank(admin);
        factory.setFTokenCreationCode("NativeUnderlying", type(fTokenNativeUnderlying).creationCode);
        vm.prank(admin);
        return IERC4626(lendingFactory_.createToken(WETH_ADDRESS, "NativeUnderlying", true));
    }

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        super.setUp();

        vm.prank(0x57757E3D981446D585Af0D9Ae4d7DF6D64647806);
        IERC20(WETH_ADDRESS).transfer(alice, 1000 ether);
        underlying = TestERC20(WETH_ADDRESS);

        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(lendingFToken));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));

        staticModel = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            OPEN_ENDED_DURATION
        );
        vm.prank(admin);
        factory.setAuth(address(staticModel), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(staticModel)));
    }

    function _bootstrapNativeLiquidityYield() internal {
        uint256 extraSupply_ = DEFAULT_AMOUNT * 9;
        vm.deal(alice, extraSupply_);
        _supplyNative(address(liquidity), mockProtocol, alice, extraSupply_);
        _borrowNative(mockProtocol, bob, DEFAULT_AMOUNT * 8);
    }

    function test_nativeRebalance_depositsRewardsWhenStaticAboveLiquidity() public {
        vm.prank(admin);
        staticModel.setStaticRate(int256(20 * RATE_PRECISION), OPEN_ENDED_DURATION);

        vm.deal(alice, DEFAULT_AMOUNT);
        vm.prank(alice);
        IFTokenNativeUnderlying(address(lendingFToken)).depositNative{ value: DEFAULT_AMOUNT }(alice);

        vm.warp(block.timestamp + 365 days);

        uint256 totalAssetsBefore_ = lendingFToken.totalAssets();
        (, , , , , , uint256 liquidityBalanceBefore_, , ) = lendingFToken.getData();
        assertGt(totalAssetsBefore_, liquidityBalanceBefore_, "rewards gap should open");

        uint256 adminBalanceBefore_ = admin.balance;
        uint256 expectedDeposit_ = totalAssetsBefore_ - liquidityBalanceBefore_;
        vm.deal(admin, adminBalanceBefore_ + DEFAULT_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit LogRebalance(int256(expectedDeposit_));
        vm.prank(admin);
        uint256 deposited_ = lendingFToken.rebalance{ value: DEFAULT_AMOUNT }();

        assertGt(deposited_, 0);
        assertEq(deposited_, expectedDeposit_);
        assertEq(lendingFToken.totalAssets(), totalAssetsBefore_);
        (, , , , , , uint256 liquidityBalanceAfter_, , ) = lendingFToken.getData();
        assertApproxEqAbs(liquidityBalanceAfter_, totalAssetsBefore_, 1e12);
        assertLe(admin.balance, adminBalanceBefore_ + DEFAULT_AMOUNT, "native rewards rebalance spends ETH");
    }

    function test_nativeRebalance_withdrawsFeesWhenStaticBelowLiquidity() public {
        _bootstrapNativeLiquidityYield();

        // negative offset so share EP grows slower than Liquidity EP → surplus at Liquidity
        vm.prank(admin);
        staticModel.setStaticRate(-int256(2 * RATE_PRECISION), OPEN_ENDED_DURATION);

        vm.deal(alice, DEFAULT_AMOUNT);
        vm.prank(alice);
        IFTokenNativeUnderlying(address(lendingFToken)).depositNative{ value: DEFAULT_AMOUNT }(alice);

        vm.warp(block.timestamp + 365 days);

        uint256 totalAssetsBefore_ = lendingFToken.totalAssets();
        (, , , , , , uint256 liquidityBalanceBefore_, , ) = lendingFToken.getData();
        assertGt(liquidityBalanceBefore_, totalAssetsBefore_, "fees should accrue at Liquidity");

        uint256 adminBalanceBefore_ = admin.balance;
        uint256 expectedWithdraw_ = liquidityBalanceBefore_ - totalAssetsBefore_;
        vm.expectEmit(true, true, true, true);
        emit LogRebalance(-int256(expectedWithdraw_));
        vm.prank(admin);
        uint256 withdrawn_ = lendingFToken.rebalance();

        assertGt(withdrawn_, 0);
        assertEq(withdrawn_, expectedWithdraw_);
        assertEq(lendingFToken.totalAssets(), totalAssetsBefore_);
        assertGt(admin.balance, adminBalanceBefore_);
        (, , , , , , uint256 liquidityBalanceAfter_, , ) = lendingFToken.getData();
        assertApproxEqAbs(liquidityBalanceAfter_, totalAssetsBefore_, 1e12);
    }

    function test_nativeRebalance_refundsExcessMsgValueOnFeesPath() public {
        _bootstrapNativeLiquidityYield();

        vm.prank(admin);
        staticModel.setStaticRate(-int256(2 * RATE_PRECISION), OPEN_ENDED_DURATION);

        vm.deal(alice, DEFAULT_AMOUNT);
        vm.prank(alice);
        IFTokenNativeUnderlying(address(lendingFToken)).depositNative{ value: DEFAULT_AMOUNT }(alice);

        vm.warp(block.timestamp + 365 days);

        uint256 adminBalanceBefore_ = admin.balance;
        vm.deal(admin, adminBalanceBefore_ + 1 ether);
        vm.prank(admin);
        lendingFToken.rebalance{ value: 1 ether }();

        assertGe(admin.balance, adminBalanceBefore_ + 1 ether, "excess msg.value should be refunded on fees path");
    }
}
