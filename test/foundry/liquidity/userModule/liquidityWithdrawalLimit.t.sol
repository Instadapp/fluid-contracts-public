//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { AuthModule, FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";
import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";

import "forge-std/console2.sol";

abstract contract LiquidityUserModuleWithdrawLimitTests is LiquidityUserModuleBaseTest {
    uint256 constant BASE_WITHDRAW_LIMIT = 0.5 ether;

    // actual values for default values as read from storage for direct comparison in expected results.
    // once converting to BigMath and then back to get actual number after BigMath precision loss.
    uint256 immutable BASE_WITHDRAW_LIMIT_AFTER_BIGMATH;

    constructor() {
        BASE_WITHDRAW_LIMIT_AFTER_BIGMATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                BASE_WITHDRAW_LIMIT,
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
    }

    function _getInterestMode() internal pure virtual returns (uint8);

    function setUp() public virtual override {
        super.setUp();

        // Set withdraw config with actual limits
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: BASE_WITHDRAW_LIMIT
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);
    }

    function test_operate_WithdrawExactToLimit() public {
        uint256 balanceBefore = USDC.balanceOf(alice);

        // withdraw exactly to withdraw limit. It is not base withdraw limit but actually the fully expanded
        // limit from supplied amount of 1 ether so 1 ether - 20% = 0.8 ether
        // so we can withdraw exactly 0.2 ether
        uint256 withdrawAmount = 0.2 ether;

        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount);

        uint256 balanceAfter = USDC.balanceOf(alice);

        // alice should have received the withdraw amount
        assertEq(balanceAfter, balanceBefore + withdrawAmount);
    }

    function test_operate_RevertIfWithdrawLimitReached() public {
        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData_.withdrawalLimit, 0.8 ether);
        // withdraw limit is not base withdraw limit but actually the fully expanded
        // limit from supplied amount of 1 ether so 1 ether - 20% = 0.8 ether.
        // so we can withdraw exactly 0.2 ether
        uint256 withdrawAmount = 0.2 ether + 1;

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__WithdrawalLimitReached)
        );
        // withdraw more than base withdraw limit -> should revert
        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount);
    }

    function test_operate_RevertIfWithdrawLimitReachedForWithdrawAndBorrow() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__WithdrawalLimitReached)
        );
        uint256 withdrawAmount = 0.2 ether + 1;

        // execute operate with withdraw AND borrow
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            -int256(withdrawAmount),
            int256(0.1 ether),
            alice,
            alice,
            abi.encode(alice)
        );
    }

    function test_operate_RevertIfWithdrawLimitReachedForWithdrawAndPayback() public {
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__WithdrawalLimitReached)
        );
        uint256 withdrawAmount = 0.2 ether + 1;

        // execute operate with supply AND borrow
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            -int256(withdrawAmount),
            -int256(0.1 ether),
            alice,
            address(0),
            abi.encode(alice)
        );
    }

    function test_operate_WithdrawalLimitInstantlyExpandedOnDeposit() public {
        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 10);

        uint256 balanceBefore = USDC.balanceOf(alice);

        // withdraw exactly to withdraw limit. It is not base withdraw limit but actually the fully expanded
        // limit from supplied amount of 11 ether so 11 ether - 20% = 8.8 ether
        // so we can withdraw exactly 2.2 ether
        uint256 withdrawAmount = 2.2 ether;

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData_.withdrawalLimit, 8.8 ether);

        // try to withdraw more and expect revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__WithdrawalLimitReached)
        );
        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount + 1);

        // expect exact withdrawal limit amount to work
        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount);

        uint256 balanceAfter = USDC.balanceOf(alice);

        // alice should have received the withdraw amount
        assertEq(balanceAfter, balanceBefore + withdrawAmount);
    }

    function test_operate_WithdrawalLimitShrinkedOnWithdraw() public {
        // withdraw 0.1 out of the 0.2 ether possible to withdraw
        uint256 withdrawAmount = 0.1 ether;

        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount);

        uint256 balanceBefore = USDC.balanceOf(alice);

        // try to withdraw more than rest available (0.1 ether) and expect revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__WithdrawalLimitReached)
        );
        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount + 1);

        // expect exact withdrawal limit amount to work
        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount);

        uint256 balanceAfter = USDC.balanceOf(alice);

        // alice should have received the withdraw amount
        assertEq(balanceAfter, balanceBefore + withdrawAmount);
    }

    function test_operate_WithdrawalLimitExpansion() public {
        // withdraw 0.1 out of the 0.2 ether possible to withdraw
        uint256 withdrawAmount = 0.1 ether;

        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount);

        // try to withdraw more than rest available (0.1 ether) and expect revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__WithdrawalLimitReached)
        );
        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount + 1);

        // full expansion of 0.9 ether is at 0.72 ether
        // but we are starting at 0.8 ether as last withdrawal limit.
        // so expanding total 0.18 ether, 10% of that is 0.018 ether.
        // so after 10% expansion time, the limit should be 0.8 - 0.018 = 0.782 ether
        vm.warp(block.timestamp + DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION / 10);

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userSupplyData_.withdrawalLimit, 0.782 ether);

        uint256 balanceBefore = USDC.balanceOf(alice);

        // expect withdraw more than limit to revert
        withdrawAmount = 0.9 ether - 0.782 ether;

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__WithdrawalLimitReached)
        );
        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount + 1);

        // expect exact withdrawal limit amount to work
        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount);

        uint256 balanceAfter = USDC.balanceOf(alice);

        // alice should have received the withdraw amount
        assertEq(balanceAfter, balanceBefore + withdrawAmount);
    }

    function test_operate_WithdrawalLimitSequence() public {
        uint256 baseLimit = 5 ether;
        // Set withdraw config with actual limits
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT, // 20%
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION, // 2 days;
            baseWithdrawalLimit: baseLimit
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        // withdraw supplied from setUp()
        _withdraw(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 5);
        _withdraw(mockProtocol, address(USDC), alice, (DEFAULT_SUPPLY_AMOUNT / 5) * 4);

        // seed deposit
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        _assertWithdrawalLimits(0, 0, 0, 0);

        console2.log("\n--------- 1. action: deposit of 1 ether ---------");

        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        _assertWithdrawalLimits(
            1 ether, // user supply
            0 ether, // withdrawalLimit
            1 ether, // withdrawableUntilLimit
            1 ether // withdrawable
        );

        console2.log("\n--------- 2. action: deposit of 4.5 ether to 5.5 ether total ---------");

        _supply(mockProtocol, address(USDC), alice, 4.5 ether);

        _assertWithdrawalLimits(
            5.5 ether, // user supply
            4.4 ether, // withdrawalLimit. fully expanded immediately because of deposits only
            1.1 ether, // withdrawableUntilLimit
            1.1 ether // withdrawable
        );

        console2.log("\n--------- 3. action: deposit of 0.5 ether to 6 ether total ---------");

        _supply(mockProtocol, address(USDC), alice, 0.5 ether);

        _assertWithdrawalLimits(
            6 ether, // user supply
            4.8 ether, // withdrawalLimit. fully expanded immediately because of deposits only
            1.2 ether, // withdrawableUntilLimit
            1.2 ether // withdrawable
        );

        console2.log("\n--------- 4. action: withdraw 0.01 ether to total 5.99 ---------");

        _withdraw(mockProtocol, address(USDC), alice, 0.01 ether);

        _assertWithdrawalLimits(
            5.99 ether, // user supply
            4.8 ether, // withdrawalLimit. stays the same, expansion start point
            1.19 ether, // withdrawableUntilLimit
            1.19 ether // withdrawable
        );

        // time warp to full expansion
        console2.log("--------- TIME WARP to full expansion ---------");
        vm.warp(block.timestamp + 2 days);

        _assertWithdrawalLimits(
            5.99 ether, // user supply
            4.792 ether, // withdrawalLimit. fully expanded from 5.99
            1.198 ether, // withdrawableUntilLimit
            1.198 ether // withdrawable
        );

        console2.log("\n--------- 5. action: deposit of 1.01 ether to 7 ether total ---------");

        _supply(mockProtocol, address(USDC), alice, 1.01 ether);

        _assertWithdrawalLimits(
            7 ether, // user supply
            5.6 ether, // withdrawalLimit. fully expanded immediately because deposit
            1.4 ether, // withdrawableUntilLimit
            1.4 ether // withdrawable
        );

        console2.log("\n--------- 6. action: withdraw 1.4 ether down to 5.6 total ---------");

        _withdraw(mockProtocol, address(USDC), alice, 1.4 ether);

        _assertWithdrawalLimits(
            5.6 ether, // user supply
            5.6 ether, // withdrawalLimit.
            0 ether, // withdrawableUntilLimit
            0 ether // withdrawable
        );

        console2.log("--------- TIME WARP 20% of duration (20% of 20% epanded, 0.224 down to 5.376) ---------\n");
        vm.warp(block.timestamp + (2 days / 5));

        _assertWithdrawalLimits(
            5.6 ether, // user supply
            5.376 ether, // withdrawalLimit.
            0.224 ether, // withdrawableUntilLimit
            0.224 ether // withdrawable
        );

        console2.log("\n--------- 7. action: withdraw 0.1 ether down to 5.5 total ---------");

        _withdraw(mockProtocol, address(USDC), alice, 0.1 ether);

        _assertWithdrawalLimits(
            5.5 ether, // user supply
            5.376 ether, // withdrawalLimit.
            0.124 ether, // withdrawableUntilLimit
            0.124 ether // withdrawable
        );

        // time warp to full expansion
        console2.log("--------- TIME WARP to full expansion (4.4 ether) ---------");
        vm.warp(block.timestamp + 2 days);

        _assertWithdrawalLimits(
            5.5 ether, // user supply
            4.4 ether, // withdrawalLimit.
            1.1 ether, // withdrawableUntilLimit
            1.1 ether // withdrawable
        );

        console2.log("\n--------- 8. action: withdraw 0.51 ether down to 4.99 total ---------");

        _withdraw(mockProtocol, address(USDC), alice, 0.51 ether);

        _assertWithdrawalLimits(
            4.99 ether, // user supply
            0 ether, // withdrawalLimit. becomes 0 as below base limit
            4.99 ether, // withdrawableUntilLimit
            4.99 ether // withdrawable
        );

        console2.log("\n--------- 9. action: withdraw 4.99 ether down to 0 total ---------");

        _withdraw(mockProtocol, address(USDC), alice, 4.99 ether);

        _assertWithdrawalLimits(
            0 ether, // user supply
            0 ether, // withdrawalLimit.
            0 ether, // withdrawableUntilLimit
            0 ether // withdrawable
        );
    }

    function test_operate_WhenWithdrawalLimitExpandPercentIncreased() public {
        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 10);

        // withdraw exactly to withdraw limit. It is not base withdraw limit but actually the fully expanded
        // limit from supplied amount of 11 ether so 11 ether - 20% = 8.8 ether
        // so we can withdraw exactly 2.2 ether
        _assertWithdrawalLimits(11 ether, 8.8 ether, 2.2 ether, 2.2 ether);

        // case increase normal when was fully expanded
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: 30 * 1e2, // increased from 20% to 30%
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: BASE_WITHDRAW_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        // after increase, timestamp is still from last interaction so 0% has elpased so it is still the old limit
        _assertWithdrawalLimits(11 ether, 8.8 ether, 2.2 ether, 2.2 ether);

        // let 10% expand
        vm.warp(block.timestamp + DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION / 10);

        // limit from supplied amount of 11 ether so 11 ether - 30% = 7.7 ether
        // so we can withdraw exactly 3.3 ether. 10% of that is 0.33 ether so amount should be:
        _assertWithdrawalLimits(11 ether, 8.47 ether, 2.53 ether, 2.53 ether);

        // let fully expand
        vm.warp(block.timestamp + DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION);
        _assertWithdrawalLimits(11 ether, 7.7 ether, 3.3 ether, 3.3 ether);

        _withdraw(mockProtocol, address(USDC), alice, 2.3 ether);
        _assertWithdrawalLimits(8.7 ether, 7.7 ether, 1 ether, 1 ether);
    }

    function test_operate_WhenWithdrawalLimitExpandPercentDecreased() public {
        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 10);

        // withdraw exactly to withdraw limit. It is not base withdraw limit but actually the fully expanded
        // limit from supplied amount of 11 ether so 11 ether - 20% = 8.8 ether
        // so we can withdraw exactly 2.2 ether
        _assertWithdrawalLimits(11 ether, 8.8 ether, 2.2 ether, 2.2 ether);

        // case increase normal when was fully expanded
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: 10 * 1e2, // decreased from 20% to 10%
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: BASE_WITHDRAW_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        // after decrease shrinking should be instant
        _assertWithdrawalLimits(11 ether, 9.9 ether, 1.1 ether, 1.1 ether);
    }

    function _assertWithdrawalLimits(
        uint256 supply,
        uint256 withdrawalLimit,
        uint256 withdrawableUntilLimit,
        uint256 withdrawable
    ) internal {
        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData.supply, supply);
        assertEq(userSupplyData.withdrawalLimit, withdrawalLimit);
        assertEq(userSupplyData.withdrawableUntilLimit, withdrawableUntilLimit);
        assertEq(userSupplyData.withdrawable, withdrawable);

        if (userSupplyData.supply > 0 && userSupplyData.withdrawable < userSupplyData.supply) {
            // assert reverts if withdrawing more
            vm.expectRevert(
                abi.encodeWithSelector(
                    Error.FluidLiquidityError.selector,
                    ErrorTypes.UserModule__WithdrawalLimitReached
                )
            );
            _withdraw(mockProtocol, address(USDC), alice, userSupplyData.withdrawable + 1);
        }

        if (userSupplyData.withdrawable > 0) {
            // assert withdrawing exactly works
            _withdraw(mockProtocol, address(USDC), alice, userSupplyData.withdrawable);
            // supply it back
            _supply(mockProtocol, address(USDC), alice, userSupplyData.withdrawable);
        }
    }
}

contract LiquidityUserModuleWithdrawLimitTestsWithInterest is LiquidityUserModuleWithdrawLimitTests {
    function _getInterestMode() internal pure virtual override returns (uint8) {
        return 1;
    }
}

contract LiquidityUserModuleWithdrawLimitTestsInterestFree is LiquidityUserModuleWithdrawLimitTests {
    function _getInterestMode() internal pure virtual override returns (uint8) {
        return 0;
    }
}
