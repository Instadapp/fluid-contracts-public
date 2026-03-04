//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { AuthModule, FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";
import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";
import { MockProtocol } from "../../../../contracts/mocks/mockProtocol.sol";

import "forge-std/console2.sol";

abstract contract LiquidityUserModuleWithdrawLimitTests is LiquidityUserModuleBaseTest {
    uint256 constant BASE_WITHDRAW_LIMIT = 0.5 ether;

    // actual values for default values as read from storage for direct comparison in expected results.
    // once converting to BigMath and then back to get actual number after BigMath precision loss.
    uint256 immutable BASE_WITHDRAW_LIMIT_AFTER_BIGMATH;

    uint256 constant DEFAULT_DECAY_DURATION = 1 hours;
    uint256 constant MIN_DECAY_DURATION = 288; // =4m 48s: minimum decay duration after a new deposit, depending on ratio.

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
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);
    }

    function test_operate_WithdrawExactToLimit() public {
        uint256 balanceBefore = USDC.balanceOf(alice);

        // withdraw exactly to withdraw limit. It is not base withdraw limit but actually the fully expanded
        // limit from supplied amount of 1 ether so 1 ether - 20% = 0.8 ether
        // so we can withdraw exactly 0.2 ether
        uint256 withdrawAmount = 0.2 ether;

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, withdrawAmount);

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
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, withdrawAmount);
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
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 10);

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
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, withdrawAmount + 1);

        // expect exact withdrawal limit amount to work
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, withdrawAmount);

        uint256 balanceAfter = USDC.balanceOf(alice);

        // alice should have received the withdraw amount
        assertEq(balanceAfter, balanceBefore + withdrawAmount);
    }

    function test_operate_WithdrawalLimitShrinkedOnWithdraw() public {
        // withdraw 0.1 out of the 0.2 ether possible to withdraw
        uint256 withdrawAmount = 0.1 ether;

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, withdrawAmount);

        uint256 balanceBefore = USDC.balanceOf(alice);

        // try to withdraw more than rest available (0.1 ether) and expect revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__WithdrawalLimitReached)
        );
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, withdrawAmount + 1);

        // expect exact withdrawal limit amount to work
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, withdrawAmount);

        uint256 balanceAfter = USDC.balanceOf(alice);

        // alice should have received the withdraw amount
        assertEq(balanceAfter, balanceBefore + withdrawAmount);
    }

    function test_operate_WithdrawalLimitExpansion() public {
        // withdraw 0.1 out of the 0.2 ether possible to withdraw
        uint256 withdrawAmount = 0.1 ether;

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, withdrawAmount);

        // try to withdraw more than rest available (0.1 ether) and expect revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__WithdrawalLimitReached)
        );
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, withdrawAmount + 1);

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
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, withdrawAmount + 1);

        // expect exact withdrawal limit amount to work
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, withdrawAmount);

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
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 5);
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, (DEFAULT_SUPPLY_AMOUNT / 5) * 4);

        // seed deposit
        _supply(address(liquidity), mockProtocolInterestFree, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        _assertWithdrawalLimits(0, 0, 0, 0);

        console2.log("\n--------- 1. action: deposit of 1 ether ---------");

        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        _assertWithdrawalLimits(
            1 ether, // user supply
            0 ether, // withdrawalLimit
            1 ether, // withdrawableUntilLimit
            1 ether // withdrawable
        );

        console2.log("\n--------- 2. action: deposit of 4.5 ether to 5.5 ether total ---------");

        _supply(address(liquidity), mockProtocol, address(USDC), alice, 4.5 ether);

        _assertWithdrawalLimits(
            5.5 ether, // user supply
            4.4 ether, // withdrawalLimit. fully expanded immediately because of deposits only
            1.1 ether, // withdrawableUntilLimit
            1.1 ether // withdrawable
        );

        console2.log("\n--------- 3. action: deposit of 0.5 ether to 6 ether total ---------");

        _supply(address(liquidity), mockProtocol, address(USDC), alice, 0.5 ether);

        _assertWithdrawalLimits(
            6 ether, // user supply
            4.8 ether, // withdrawalLimit. fully expanded immediately because of deposits only
            1.2 ether, // withdrawableUntilLimit
            1.2 ether // withdrawable
        );

        console2.log("\n--------- 4. action: withdraw 0.01 ether to total 5.99 ---------");

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 0.01 ether);

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

        _supply(address(liquidity), mockProtocol, address(USDC), alice, 1.01 ether);

        _assertWithdrawalLimits(
            7 ether, // user supply
            5.6 ether, // withdrawalLimit. fully expanded immediately because deposit
            1.4 ether, // withdrawableUntilLimit
            1.4 ether // withdrawable
        );

        console2.log("\n--------- 6. action: withdraw 1.4 ether down to 5.6 total ---------");

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 1.4 ether);

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

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 0.1 ether);

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

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 0.51 ether);

        _assertWithdrawalLimits(
            4.99 ether, // user supply
            0 ether, // withdrawalLimit. becomes 0 as below base limit
            4.99 ether, // withdrawableUntilLimit
            4.99 ether // withdrawable
        );

        console2.log("\n--------- 9. action: withdraw 4.99 ether down to 0 total ---------");

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 4.99 ether);

        _assertWithdrawalLimits(
            0 ether, // user supply
            0 ether, // withdrawalLimit.
            0 ether, // withdrawableUntilLimit
            0 ether // withdrawable
        );
    }

    function test_operate_WhenWithdrawalLimitExpandPercentIncreased() public {
        // alice supplies liquidity
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 10);

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

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 2.3 ether);
        _assertWithdrawalLimits(8.7 ether, 7.7 ether, 1 ether, 1 ether);
    }

    function test_operate_WhenWithdrawalLimitExpandPercentDecreased() public {
        // alice supplies liquidity
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 10);

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

    function test_operate_NoDecayOnDepositWithinExtension() public {
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 10);
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 2);

        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        _assertDecayLimits(0, 0);
    }

    function test_operate_DecayOnExcessDeposit() public {
        _assertDecayLimits(0, 0);

        // default supply amount = 1 ether. default expansion = 20%. Already supplied = 1 eth
        // adding 1 eth means 2 eth total supply, 20% fully expanded, so 0.4 eth total, 0.2 eth was already, so expanded by 0.2 eth
        // rest of 0.8 ETH should be decaying.
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // also checks default duration 1 hour is set
        _assertDecayLimits(0.8 ether, DEFAULT_DECAY_DURATION);
    }

    function test_operate_NoDecayWhenAfterLimitZero() public {
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        _assertDecayLimits(0.8 ether, DEFAULT_DECAY_DURATION);

        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: 10 * 1e2, // decreased from 20% to 10%
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: DEFAULT_SUPPLY_AMOUNT * 100
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 1e12);

        _assertDecayLimits(0, 0);
    }

    function test_operate_DecayAfterFullDecay() public {
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        _assertDecayLimits(0.8 ether, DEFAULT_DECAY_DURATION);

        vm.warp(block.timestamp + DEFAULT_DECAY_DURATION);

        _assertDecayLimits(0, 0);
    }

    function test_operate_DecayAfterHalfDecay() public {
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        _assertDecayLimits(0.8 ether, DEFAULT_DECAY_DURATION);

        vm.warp(block.timestamp + DEFAULT_DECAY_DURATION / 2);

        _assertDecayLimits(0.4 ether, DEFAULT_DECAY_DURATION / 2);
    }

    function test_operate_DecayClearedAfterUpdateUserSupplyConfig() public {
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        _assertDecayLimits(0.8 ether, DEFAULT_DECAY_DURATION);

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

        _assertDecayLimits(0, 0);
    }

    function test_operate_DecayClearedAfterUpdateUserWithdrawLimit() public {
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        _assertDecayLimits(0.8 ether, DEFAULT_DECAY_DURATION);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            type(uint256).max
        );

        _assertDecayLimits(0, 0);
    }

    function test_operate_DecayTimeRatioOnExistingDecay() public {
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        _assertDecayLimits(0.8 ether, DEFAULT_DECAY_DURATION);

        vm.warp(block.timestamp + DEFAULT_DECAY_DURATION / 2);

        _assertDecayLimits(0.4 ether, DEFAULT_DECAY_DURATION / 2);

        // default supply amount = 1 ether. default expansion = 20%. Already supplied = 2 eth
        // adding 1 eth means 3 eth total supply, 20% fully expanded, so 0.6 eth total, 0.4 eth was already, so expanded by 0.2 eth
        // rest of 0.8 ETH should be decaying.
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // duration should end up at 0.4 @ 30min vs 0.8 @ 60 min so 2/3 (66.66%) towards 60min = 50min but most precise possible is 0.1% so 3600 * 0.833 = 2998
        _assertDecayLimits(1.2 ether, 2998);
    }

    function test_operate_DecayTimeCappedMin() public {
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 100);

        _assertDecayLimits(80 ether, DEFAULT_DECAY_DURATION);

        vm.warp(block.timestamp + 59 minutes); // decay almost fully over

        // 80 / 60 = 1.333 eth per minute
        _assertDecayLimits(1.33333333333 ether, 1 minutes);

        // supply dust compared to left over 1.3 eth decay
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 0.01 ether);

        // duration should end up at 1.33 @ 1min vs 0.008 @ 60 min so very much towards 1 min but min duration is 288s
        _assertDecayLimits(1.368 ether, MIN_DECAY_DURATION);
    }

    function test_operate_DecayEdgeCaseBelowBaseLimitBeforeButAfterSlightlyAbove() public {
        // Implements case:
        // in this case it is possible that after is < before! when user supply ends up slightly above base then expansion
        // of the limit can reach below base withdrwal limit! Ref #412521521521

        // set base limit to 5 ether
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

        // deposit to 4.8 ether TVL
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 3.8 ether);

        _assertWithdrawalLimits(
            4.8 ether, // user supply
            0 ether, // withdrawalLimit
            4.8 ether, // withdrawableUntilLimit
            4.8 ether // withdrawable
        );
        _assertDecayLimits(0, 0);

        // deposit to above base limit -> 5.3 eth total
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 0.5 ether);

        _assertDecayLimits(0, 0);
    }

    function test_operate_DecayEdgeCaseBelowBaseLimitBeforeButAfterMuchAbove() public {
        // set base limit to 5 ether
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

        // deposit to 4.8 ether TVL
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 3.8 ether);

        _assertWithdrawalLimits(
            4.8 ether, // user supply
            0 ether, // withdrawalLimit
            4.8 ether, // withdrawableUntilLimit
            4.8 ether // withdrawable
        );
        _assertDecayLimits(0, 0);

        // deposit to above base limit -> 8 eth total. 20% = 1.6 ether, rest should decay
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 3.2 ether);

        _assertDecayLimits(1.401 ether, DEFAULT_DECAY_DURATION);

        _assertWithdrawalLimits(
            8 ether, // user supply
            6.4 ether, // withdrawalLimit
            1.6 ether, // withdrawableUntilLimit
            1.6 ether // withdrawable
        );
    }

    // @dev skipping test in default runs as the loop takes long
    function test_operate_DecaySupplyLoopBlockTime() public {
        uint256 blockTime = 12 seconds;
        bool runOthers = false;
        try vm.envBool("RUN_OTHERS") returns (bool val) {
            runOthers = val;
        } catch {}
        if (runOthers) {
            blockTime = 1 seconds;
        }

        // blockTime = 1 seconds;

        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // goal is to confirm that the decay declines if there is only dust amount deposits each block
        // and rounding has no unexpected effects.

        _assertDecayLimits(0.8 ether, DEFAULT_DECAY_DURATION);

        // supply dust in a loop, not full amount gets decayed so in the end decay will be less than total supplied
        for (uint i = block.timestamp; i < DEFAULT_DECAY_DURATION / 2; i += blockTime) {
            _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 1e6);
            vm.warp(i);
        }

        // expected 0.4 ether but result is slightly off
        if (blockTime == 1 seconds) {
            // with mainnet Checkpoints implementation at 1s block time
            _assertDecayLimits(400351905362671593, DEFAULT_DECAY_DURATION / 2 + 2);
        } else {
            _assertDecayLimits(402783342717970319, DEFAULT_DECAY_DURATION / 2 + 13);
        }
    }

    // @dev skipping test in default runs as the loop takes long
    // function test_operate_DecaySupplyLoop() public {
    //     // push up TVL
    //     _supply(address(liquidity), mockProtocol, address(USDC), alice, 99 ether);
    //     _assertWithdrawalLimits(
    //         100 ether, // user supply
    //         80 ether, // withdrawalLimit
    //         20 ether, // withdrawableUntilLimit
    //         20 ether // withdrawable
    //     );

    //     // supply dust in a loop, not full amount gets decayed so in the end decay will be less than total supplied
    //     for (uint i; i < 1e5; i++) {
    //         _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 1e17);
    //     }

    //     // supplied would be 1e17 * 1e5 = 1e22
    //     // ideally, that should also be the decay amount, but it is being rounded down, thus ends up at
    //     // 10000000000000000000000
    //     //  7294858618820691492864

    //     _assertDecayLimits(7294858618820691492864, DEFAULT_DECAY_DURATION);
    // }

    function test_operate_DecayLoopDurationPrecisionEffect() public {
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // goal is to confirm that the decay duration stays the same if there is only dust amount withdrawals
        // and rounding has no unexpected effects.

        _assertDecayLimits(0.8 ether, DEFAULT_DECAY_DURATION);

        vm.warp(block.timestamp + 12 seconds);

        _assertDecayLimits(uint256(0.8 ether * (3600 - 12)) / 3600, DEFAULT_DECAY_DURATION - 12 seconds);
        // decayEndTimestamp 3601

        // withdraw dust in a loop
        for (uint i; i < 100; i++) {
            _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 1e11);
        }

        // ideally the decay amount would be 0.4 ether - 1e11 * 100 -> 797329211395872741
        // but amount gets rounded so it ends up                    -> 797159124277133312
        // diff is ~0,021%
        //    797595876683965006
        _assertDecayLimits(797159124277133312, DEFAULT_DECAY_DURATION - 12 seconds + 1);

        // goal decayEndTimestamp same as above -> 3601
        // without any +1 rounding 3595
        // with +1 on reading decayDuration 3598
        // with +1 on setting decayDuration 3604
        // with +1 on setting decayDuration with modulo 3602
    }

    function test_operate_DecayWithdrawFullDecay() public {
        // push up TVL
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 99 ether);
        _assertWithdrawalLimits(
            100 ether, // user supply
            80 ether, // withdrawalLimit
            20 ether, // withdrawableUntilLimit
            20 ether // withdrawable
        );

        // limit expands to 21 ether, rest 4 ether must be covered by decay
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 5 ether);

        _assertDecayLimits(4 ether, DEFAULT_DECAY_DURATION);

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 5 ether);

        _assertDecayLimits(0, 0);

        // because of decay limit getting rounded down with big math, withdraw limit in the end actually ends up
        // ~ 0,00001485 % higher
        _assertWithdrawalLimits(
            100 ether, // user supply
            80000011882523000832, // withdrawalLimit
            100 ether - 80000011882523000832, // withdrawableUntilLimit
            100 ether - 80000011882523000832 // withdrawable
        );
    }

    function test_operate_DecayWithdrawNotFullExpansion() public {
        // e.g. -> 100M supply, 20% expand, status 90% of expansion through, so 18% expansion ATM, so 18M withdrawable. (limit = 82M)
        // -> DEPOSIT CASE B: PUSHING ABOVE FULL EXPANSION
        // new deposit of 5M. new supply 105M, full expansion would be 21M (limit = 84M) + decaying limit must be 2M
        // even with instant same withdrawal, the withdrawable amount stays the exact same at 18M afterwards, see withdrawal case A:
        // -> WITHDRAWAL CASE A: MORE THAN DECAY AMOUNT (after deposit case B)
        // instant withdrawal of 5M: new supply is 100M, 2M is taken from decay, 3M is taken from withdrawal limit, final withdrawal limit
        // must end up at 82M again (which is not full expansion!) -> initial withdrawal limit of 84M is pushed down by 2M used from decay.

        // push up TVL
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 103 ether);
        _assertWithdrawalLimits(
            104 ether, // user supply
            83.2 ether, // withdrawalLimit
            20.8 ether, // withdrawableUntilLimit
            20.8 ether // withdrawable
        );

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 4 ether);

        _assertWithdrawalLimits(
            100 ether, // user supply
            83.2 ether, // withdrawalLimit
            16.8 ether, // withdrawableUntilLimit
            16.8 ether // withdrawable
        );

        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 10 ether);

        // withdraw limit expands from 83.2 to full expansion 88, so 4.8 increase must be decay, rest of 5.2 eth is covered by limit
        _assertDecayLimits(4.8 ether, DEFAULT_DECAY_DURATION);

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 10 ether);

        _assertDecayLimits(0, 0);

        // because of decay limit getting rounded down with big math
        _assertWithdrawalLimits(
            100 ether, // user supply
            83200007222153183232, // withdrawalLimit
            100 ether - 83200007222153183232, // withdrawableUntilLimit
            100 ether - 83200007222153183232 // withdrawable
        );
    }

    function test_operate_DecayWithdrawPartialDecayWhenTakenAmountNotCoveredByPushDownLimit() public {
        // Implements case:
        // Note not full amount taken from decay might be reflected in pushed down limit because of max expansion being hit
        //  -> handled below Ref #43681765878

        // push up TVL
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 99 ether);
        _assertWithdrawalLimits(
            100 ether, // user supply
            80 ether, // withdrawalLimit
            20 ether, // withdrawableUntilLimit
            20 ether // withdrawable
        );

        // limit expands to 21 ether, rest 4 ether must be covered by decay
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 5 ether);

        _assertDecayLimits(4 ether, DEFAULT_DECAY_DURATION);

        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 2 ether);

        // total 103ETH, 20% = 20.6 eth, so 0.4 reduced which becomes decay. 2 eth from decay, so +0.4 -2 = 2.4 eth decay
        _assertDecayLimits(2.4 ether, DEFAULT_DECAY_DURATION);

        // because of decay limit getting rounded down with big math, withdraw limit in the end actually ends up
        // ~ 0,00001485 % higher
        _assertWithdrawalLimits(
            103 ether, // user supply
            82.4 ether, // withdrawalLimit
            20.6 ether, // withdrawableUntilLimit
            20.6 ether // withdrawable
        );
    }

    function test_operate_DecayWithdrawInMaxExpandChunks() public {
        // push up TVL
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 9 ether);
        _assertWithdrawalLimits(
            10 ether, // user supply
            8 ether, // withdrawalLimit
            2 ether, // withdrawableUntilLimit
            2 ether // withdrawable
        );

        // supply to push to 100x from 10 to 1000
        // limit expands to 200 ether, rest 792 ether must be covered by decay
        _supplyWithDecay(address(liquidity), mockProtocol, address(USDC), alice, 990 ether);

        _assertDecayLimits(792 ether, DEFAULT_DECAY_DURATION);

        // try withdraw more than 20% at once, should revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__WithdrawalLimitReached)
        );
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 200 ether + 1);

        // withdraw 20%
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 200 ether - 10);

        // total 800 ETH, 20% = 160 eth, so 40 reduced which becomes decay. 792 - 200 + 40 = 632 eth
        _assertDecayLimits(632 ether, DEFAULT_DECAY_DURATION);

        // try withdraw more than 20% at once, should revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__WithdrawalLimitReached)
        );
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 160 ether + 1);

        // withdraw 20%
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, 160 ether - 10);

        // total 640 ETH, 20% = 128 eth, so 32 reduced which becomes decay. 632 - 160 + 32 = 504 eth
        _assertDecayLimits(504 ether, DEFAULT_DECAY_DURATION);

        _assertWithdrawalLimits(
            640 ether, // user supply
            512 ether, // withdrawalLimit
            640 ether - 512 ether, // withdrawableUntilLimit
            640 ether - 512 ether // withdrawable
        );
    }

    function _supplyWithDecay(
        address liquidity,
        MockProtocol mockProtocol,
        address token,
        address user,
        uint256 amount
    ) internal {
        vm.prank(user);
        mockProtocol.operate(token, int256(amount), 0, address(0), address(0), abi.encode(user));
    }

    function _assertDecayLimits(uint256 decayAmount, uint256 decayDuration) internal view {
        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        console2.log("decayEndTimestamp", userSupplyData.decayEndTimestamp);
        console2.log("decayAmount", userSupplyData.decayAmount);
        console2.log("block.timestamp", block.timestamp);

        assertApproxEqAbs(userSupplyData.decayAmount, decayAmount, decayAmount / 1e4);
        assertEq(userSupplyData.decayEndTimestamp, block.timestamp + decayDuration);
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
            _withdraw(address(liquidity), mockProtocol, address(USDC), alice, userSupplyData.withdrawable + 1);
        }

        if (userSupplyData.withdrawable > 0) {
            // assert withdrawing exactly works
            _withdraw(address(liquidity), mockProtocol, address(USDC), alice, userSupplyData.withdrawable);
            // supply it back
            _supply(address(liquidity), mockProtocol, address(USDC), alice, userSupplyData.withdrawable);
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
