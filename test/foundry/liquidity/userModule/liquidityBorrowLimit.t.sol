//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { AuthModule, FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";
import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";

import "forge-std/console2.sol";

abstract contract LiquidityUserModuleBorrowLimitTests is LiquidityUserModuleBaseTest {
    uint256 constant BASE_BORROW_LIMIT = 1 ether;
    uint256 constant MAX_BORROW_LIMIT = 10 ether;

    // actual values for default values as read from storage for direct comparison in expected results.
    // once converting to BigMath and then back to get actual number after BigMath precision loss.
    uint256 immutable BASE_BORROW_LIMIT_AFTER_BIGMATH;
    uint256 immutable MAX_BORROW_LIMIT_AFTER_BIGMATH;

    constructor() {
        BASE_BORROW_LIMIT_AFTER_BIGMATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                BASE_BORROW_LIMIT,
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        MAX_BORROW_LIMIT_AFTER_BIGMATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                MAX_BORROW_LIMIT,
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

        // Set borrow config with actual limits
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: BASE_BORROW_LIMIT,
            maxDebtCeiling: MAX_BORROW_LIMIT
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);
    }

    function test_operate_BorrowExactToLimit() public {
        uint256 balanceBefore = USDC.balanceOf(alice);

        // borrow exactly to base borrow limit
        _borrow(mockProtocol, address(USDC), alice, BASE_BORROW_LIMIT_AFTER_BIGMATH);

        uint256 balanceAfter = USDC.balanceOf(alice);

        // alice should have received the borrow amount
        assertEq(balanceAfter, balanceBefore + BASE_BORROW_LIMIT_AFTER_BIGMATH);
    }

    function test_operate_BorrowBaseAndMaxLimitVeryClose() public {
        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, 20 ether);

        // Set borrow config
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: 9.9 ether,
            maxDebtCeiling: 10 ether
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        // assert borrow too much would fail
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, 10.01 ether);

        // assert borrow too much would fail
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, 9.91 ether);

        // borrow to base borrow limit
        _borrow(mockProtocol, address(USDC), alice, 9.88 ether);

        // assert borrow more would fail
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, 0.03 ether);

        // after expansion
        vm.warp(block.timestamp + 2 days);

        // assert borrow too much would fail
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, 0.12 ether);

        // borrow to max
        _borrow(mockProtocol, address(USDC), alice, 0.1 ether);

        // assert borrow more would fail
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, 0.03 ether);

        // after expansion
        vm.warp(block.timestamp + 2 days);

        // assert borrow more would fail
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, 0.03 ether);
    }

    function test_operate_BorrowExactToMaxLimitRoundedToAbove() public {
        // user borrow is rounded up, max borrow limit is rounded down, making user borrow end up
        // > than borrow limit. No new borrow should be possible.

        // Set borrow config
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: BASE_BORROW_LIMIT,
            maxDebtCeiling: BASE_BORROW_LIMIT // max same as base
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        uint256 balanceBefore = USDC.balanceOf(alice);

        // borrow exactly to base borrow limit
        _borrow(mockProtocol, address(USDC), alice, BASE_BORROW_LIMIT_AFTER_BIGMATH);

        uint256 balanceAfter = USDC.balanceOf(alice);

        // alice should have received the borrow amount
        assertEq(balanceAfter, balanceBefore + BASE_BORROW_LIMIT_AFTER_BIGMATH);

        // borrow in storage should be higher than last borrow limit
        (ResolverStructs.UserBorrowData memory userBorrowData, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );
        // borrow got rounded up
        uint256 expectedUserBorrow = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                BASE_BORROW_LIMIT_AFTER_BIGMATH,
                DEFAULT_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_UP
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
        assertEq(userBorrowData.borrow, expectedUserBorrow, "borrow off");
        assertEq(userBorrowData.borrowLimit, BASE_BORROW_LIMIT_AFTER_BIGMATH, "borrowLimit off");
        assertEq(userBorrowData.maxBorrowLimit, BASE_BORROW_LIMIT_AFTER_BIGMATH, "maxBorrowLimit off");
        assertEq(userBorrowData.borrowableUntilLimit, 0, "borrowableUntilLimit off");
        assertEq(userBorrowData.borrowable, 0, "borrowable off");

        uint256 userBorrowStorage = resolver.getUserBorrow(address(mockProtocol), address(USDC));

        uint256 lastBorrowLimit = (userBorrowStorage >> LiquiditySlotsLink.BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT) &
            X64;
        // convert from bigMath
        lastBorrowLimit = BigMathMinified.fromBigNumber(lastBorrowLimit, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        assertGt(userBorrowData.borrow, lastBorrowLimit, "user borrow not > lastBorrowLimit");

        // assert any new borrow would fail
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, 1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, 10);
    }

    function test_operate_RevertIfBorrowLimitReached() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        // borrow more than base borrow limit -> should revert
        _borrow(mockProtocol, address(USDC), alice, BASE_BORROW_LIMIT_AFTER_BIGMATH + 1);
    }

    function test_operate_RevertIfBorrowLimitReachedForSupplyAndBorrow() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );

        // execute operate with supply AND borrow
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(BASE_BORROW_LIMIT_AFTER_BIGMATH + 1),
            address(0),
            alice,
            abi.encode(alice)
        );
    }

    function test_operate_RevertIfBorrowLimitReachedForWithdrawAndBorrow() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );

        // execute operate with withdraw AND borrow
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            -int256(0.1 ether),
            int256(BASE_BORROW_LIMIT_AFTER_BIGMATH + 1),
            alice,
            alice,
            abi.encode(alice)
        );
    }

    function test_operate_RevertIfBorrowLimitMaxUtilizationReached() public {
        AdminModuleStructs.TokenConfig[] memory tokenConfigs = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 0,
            threshold: 100, // 1%
            maxUtilization: 1 // 1%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__MaxUtilizationReached)
        );
        // borrow less than base borrow limit but more than max utilization -> should revert
        _borrow(mockProtocol, address(USDC), alice, BASE_BORROW_LIMIT_AFTER_BIGMATH - 1000);
    }

    function test_operate_RevertIfBorrowLimitDefaultMaxUtilizationReached() public {
        // default max utilization 100% should be active

        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: 3 ether,
            maxDebtCeiling: MAX_BORROW_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__MaxUtilizationReached)
        );
        // more than 100% supplied
        _borrow(mockProtocol, address(USDC), alice, 2 ether);
    }

    function test_operate_RevertIfMaxUtilization0() public {
        // set max utilization to 0, no borrow should be possible at all
        AdminModuleStructs.TokenConfig[] memory tokenConfigs = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 0,
            threshold: 100, // 1%
            maxUtilization: 0
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__MaxUtilizationReached)
        );
        _borrow(mockProtocol, address(USDC), alice, 1e14); // utilization will be 0.01%
    }

    function test_operate_BorrowLimitSequence() public {
        uint256 baseLimit = 5 ether;
        uint256 baseLimitAfterBigMath = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                baseLimit,
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
        uint256 maxLimit = 7 ether;
        uint256 maxLimitAfterBigMath = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                maxLimit,
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        {
            // Set borrow config with actual limits
            AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](
                1
            );
            userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
                user: address(mockProtocol),
                token: address(USDC),
                mode: _getInterestMode(),
                expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT, // 20%
                expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION, // 2 days;
                baseDebtCeiling: baseLimit,
                maxDebtCeiling: maxLimit
            });
            vm.prank(admin);
            FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

            // set rate to essentially 0 so we can ignore yield for this test
            AdminModuleStructs.RateDataV1Params[] memory rateData = new AdminModuleStructs.RateDataV1Params[](1);
            rateData[0] = AdminModuleStructs.RateDataV1Params(address(USDC), 9999, 0, 1, 2);
            vm.prank(admin);
            AuthModule(address(liquidity)).updateRateDataV1s(rateData);
        }

        // withdraw supplied from setUp()
        _withdraw(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // seed deposit & borrow
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);
        _borrow(mockProtocolInterestFree, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // supply
        _supply(mockProtocol, address(USDC), alice, 20 ether);

        _assertBorrowLimits(
            0, // user borrow
            baseLimitAfterBigMath, // borrow limit
            baseLimitAfterBigMath, // borrowable until limit
            baseLimitAfterBigMath, // borrowable
            0 // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log("\n--------- 1. action: borrow of 4.18 ether, expands to 5.01 (above base limit) ---------");

        _borrow(mockProtocol, address(USDC), alice, 4.18 ether);

        // user borrow after BigMath
        uint256 userBorrow = _userBorrowAfterBigMath(4.18 ether);

        _assertBorrowLimits(
            userBorrow, // user borrow
            baseLimitAfterBigMath, // borrow limit
            baseLimitAfterBigMath - userBorrow, // borrowable until limit
            baseLimitAfterBigMath - userBorrow, // borrowable
            4.18 ether // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log("--------- TIME WARP to full expansion ---------");
        vm.warp(block.timestamp + 2 days);

        _assertBorrowLimits(
            userBorrow, // user borrow
            5.016 ether, // borrow limit. fully expanded from 4.18 ether
            5.016 ether - userBorrow, // borrowable until limit
            5.016 ether - userBorrow, // borrowable
            4.18 ether // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log("\n--------- 2. action: borrow of 0.82 ether to 5 ether total ---------");

        _borrow(mockProtocol, address(USDC), alice, 0.82 ether);

        userBorrow = _userBorrowAfterBigMath(userBorrow + 0.82 ether);
        _assertBorrowLimits(
            userBorrow, // user borrow
            5.016 ether, // borrow limit. fully expanded from 4.18 ether
            5.016 ether - userBorrow, // borrowable until limit
            5.016 ether - userBorrow, // borrowable
            5 ether // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        // warp tiny bit less than half to get closest to 5.5 & make up for 0.016 already as last limit. makes test easier
        vm.warp(block.timestamp + 2 days / 2 - 2764);
        console2.log("--------- TIME WARP (half expanded) ---------");

        _assertBorrowLimits(
            userBorrow, // user borrow
            5.5 ether, // borrow limit. half expanded from 5 ether
            5.5 ether - userBorrow, // borrowable until limit
            5.5 ether - userBorrow, // borrowable
            5 ether // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log("\n--------- 3. action: borrow of 0.5 ether to 5.5 ether total ---------");

        _borrow(mockProtocol, address(USDC), alice, 0.5 ether);

        userBorrow = _userBorrowAfterBigMath(userBorrow + 0.5 ether);
        _assertBorrowLimits(
            userBorrow, // user borrow
            5.5 ether, // borrow limit. half expanded from 5 ether
            5500004629629629568 - userBorrow, // borrowable until limit
            5500004629629629568 - userBorrow, // borrowable
            5.5 ether // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log("\n--------- 4. action: payback 0.01 ether to total 5.49 ---------");

        _payback(mockProtocol, address(USDC), alice, 0.01 ether);

        userBorrow = _userBorrowAfterBigMath(userBorrow - 0.01 ether);
        _assertBorrowLimits(
            userBorrow, // user borrow
            5.5 ether, // borrow limit. half expanded from 5 ether
            5500004629629629568 - userBorrow, // borrowable until limit
            5500004629629629568 - userBorrow, // borrowable
            5.49 ether // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log("--------- TIME WARP to full expansion ---------");
        vm.warp(block.timestamp + 2 days);

        _assertBorrowLimits(
            userBorrow, // user borrow
            6.588 ether, // borrow limit.
            6.588 ether - userBorrow, // borrowable until limit
            6.588 ether - userBorrow, // borrowable
            5.49 ether // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log("\n--------- 5. action: borrow of 1.01 ether to 6.5 ether total ---------");

        _borrow(mockProtocol, address(USDC), alice, 1.01 ether);

        userBorrow = _userBorrowAfterBigMath(userBorrow + 1.01 ether);
        _assertBorrowLimits(
            userBorrow, // user borrow
            6.588 ether, // borrow limit.
            6.588 ether - userBorrow, // borrowable until limit
            6.588 ether - userBorrow, // borrowable
            6.5 ether // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log("--------- TIME WARP to full expansion ---------");
        vm.warp(block.timestamp + 2 days);

        // max expansion to 7.8 ether but max limit of 7 ether gets active
        _assertBorrowLimits(
            userBorrow, // user borrow
            maxLimitAfterBigMath, // borrow limit.
            maxLimitAfterBigMath - userBorrow, // borrowable until limit
            maxLimitAfterBigMath - userBorrow, // borrowable
            6.5 ether // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log("\n--------- 6. action: borrow ~0.49 ether up to max limit of ~7 total ---------");

        // borrow exactly to max limit
        _borrow(mockProtocol, address(USDC), alice, maxLimitAfterBigMath - userBorrow);

        userBorrow = maxLimitAfterBigMath;
        _assertBorrowLimits(
            userBorrow, // user borrow
            maxLimitAfterBigMath, // borrow limit.
            0, // borrowable until limit
            0, // borrowable
            maxLimitAfterBigMath // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log("--------- TIME WARP to full expansion ---------");
        vm.warp(block.timestamp + 2 days);

        _assertBorrowLimits(
            userBorrow, // user borrow
            maxLimitAfterBigMath, // borrow limit.
            0, // borrowable until limit
            0, // borrowable
            maxLimitAfterBigMath // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log(
            "\n--------- 7. action: borrow 0.01 ether would fail even after expansion (above max limit) ---------"
        );
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, 1e3);

        console2.log("\n--------- 8. action: payback down to 5.5 total ---------");

        _payback(mockProtocol, address(USDC), alice, userBorrow - 5.5 ether);

        userBorrow = _userBorrowAfterBigMath(userBorrow - (userBorrow - 5.5 ether));

        _assertBorrowLimits(
            userBorrow, // user borrow
            6.6 ether, // borrow limit. shrinking is instant. max expansion of 5.5 ether
            1.1 ether, // borrowable until limit
            1.1 ether, // borrowable
            5.5 ether // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );

        console2.log("\n--------- 9. action: payback 5.5 ether down to 0 total ---------");

        _payback(mockProtocol, address(USDC), alice, 5.5 ether);

        _assertBorrowLimits(
            0, // user borrow
            baseLimitAfterBigMath, // borrow limit
            baseLimitAfterBigMath, // borrowable until limit
            baseLimitAfterBigMath, // borrowable
            0 // reset to borrow amount (to have exact amount to continue with test as without the asserts)
        );
    }

    function _userBorrowAfterBigMath(uint256 borrow) internal pure returns (uint256) {
        return
            BigMathMinified.fromBigNumber(
                BigMathMinified.toBigNumber(
                    borrow,
                    DEFAULT_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_UP
                ),
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );
    }

    function test_operate_WhenBorrowLimitExpandPercentIncreased() public {
        // set borrow rate to very low so tolerance will be ok between interest free and with interest for this test
        AdminModuleStructs.RateDataV1Params[] memory rateData = new AdminModuleStructs.RateDataV1Params[](1);
        rateData[0] = AdminModuleStructs.RateDataV1Params(address(USDC), 8000, 50, 80, 100);
        vm.prank(admin);
        AuthModule(address(liquidity)).updateRateDataV1s(rateData);

        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 10);

        // assert limits from no borrow start
        _assertBorrowLimits(
            0,
            BASE_BORROW_LIMIT_AFTER_BIGMATH,
            BASE_BORROW_LIMIT_AFTER_BIGMATH,
            BASE_BORROW_LIMIT_AFTER_BIGMATH,
            0
        );

        // borrow to 0.95 ether (5% below base borrow limit)
        _borrow(mockProtocol, address(USDC), alice, 0.95 ether);
        _assertBorrowLimits(
            0.95 ether,
            BASE_BORROW_LIMIT_AFTER_BIGMATH,
            49799117276250096,
            49799117276250096,
            0.95 ether
        );

        // expand for 10% (half duration)
        vm.warp(block.timestamp + DEFAULT_EXPAND_DEBT_CEILING_DURATION / 2);
        _assertBorrowLimits(
            950013794519650016, // increased a tiny bit from borrow rate
            1094815014358288081, // started at base borrow limit ~1 ether, increased 10% ~0.095 ether
            144817524615992952, // 0.095 + 0.05 ether
            144817524615992952, // 0.095 + 0.05 ether
            950013794519650016
        );

        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: 30 * 1e2, // increase to 30%
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: BASE_BORROW_LIMIT,
            maxDebtCeiling: MAX_BORROW_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        _assertBorrowLimits(
            950013794519650032, // increased a tiny bit from rounding
            1094815014358288081, // started at last borrow of ~0.95 ether, increased 10% ~0.095 ether
            144817524615992952, // 0.095 + 0.05 ether
            144817524615992952, // 0.095 + 0.05 ether
            950013794519650032
        );

        // warp for 1/4 of duration
        vm.warp(block.timestamp + DEFAULT_EXPAND_DEBT_CEILING_DURATION / 4);

        _assertBorrowLimits(
            950013794519650048, // increased a tiny bit from rounding
            1166073480309300722, // started at last borrow of ~0.95 ether, was already expanded to 1.095 ether
            // increased 1/4 of 30% so 7.5% from user borrow so 0,07125 ether. -> ~1,16625 ether
            216053823026085826, // 0.095 + 0.05 + 0.07125 ether
            216053823026085826, // 0.095 + 0.05 + 0.07125  ether
            950013794519650048
        );

        // borrow exactly to borrow limit.
        (ResolverStructs.UserBorrowData memory userBorrowData, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );
        _borrow(mockProtocol, address(USDC), alice, userBorrowData.borrowable);

        _assertBorrowLimits(1166074514905785903, 1166074514905785903, 0, 0, 1166074514905785903);

        // warp for full expansion
        vm.warp(block.timestamp + DEFAULT_EXPAND_DEBT_CEILING_DURATION + 1);
        // assert without interacting to not trigger an update to timestamp
        (userBorrowData, ) = resolver.getUserBorrowData(address(mockProtocol), address(USDC));
        assertApproxEqAbs(userBorrowData.borrow, 1166074514905785903, 1e14); // same user borrow
        assertApproxEqAbs(userBorrowData.borrowLimit, 1515896869377521673, 1e14); // 30% expanded from user borrow
        assertApproxEqAbs(userBorrowData.borrowableUntilLimit, 349815045559567162, 1e14);
        assertApproxEqAbs(userBorrowData.borrowable, 349815045559567162, 1e14);

        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: 50 * 1e2, // increase to 50%
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: BASE_BORROW_LIMIT,
            maxDebtCeiling: MAX_BORROW_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        _assertBorrowLimits(
            1166074514905785903, // same user borrow
            1749111772358678854, // 50% expanded from user borrow
            583054189591490366,
            583054189591490366,
            1166074514905785903
        );

        // case increase and it goes above max hard cap limit
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: 80 * 1e2, // increase to 80%
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: BASE_BORROW_LIMIT,
            maxDebtCeiling: 1.8 ether // set max at 1.8 ether
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        // warp for full expansion
        vm.warp(block.timestamp + DEFAULT_EXPAND_DEBT_CEILING_DURATION + 1);

        _assertBorrowLimits(
            1166074514905785903, // same user borrow
            1799231744297561506, // ~1.8 ether after rounding
            633183365115062748,
            633183365115062748,
            1166074514905785903
        );
    }

    function test_operate_WhenBorrowLimitExpandPercentDecreased() public {
        // set borrow rate to very low so tolerance will be ok between interest free and with interest for this test
        AdminModuleStructs.RateDataV1Params[] memory rateData = new AdminModuleStructs.RateDataV1Params[](1);
        rateData[0] = AdminModuleStructs.RateDataV1Params(address(USDC), 8000, 50, 80, 100);
        vm.prank(admin);
        AuthModule(address(liquidity)).updateRateDataV1s(rateData);

        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 10);

        // assert limits from no borrow start
        _assertBorrowLimits(
            0,
            BASE_BORROW_LIMIT_AFTER_BIGMATH,
            BASE_BORROW_LIMIT_AFTER_BIGMATH,
            BASE_BORROW_LIMIT_AFTER_BIGMATH,
            0
        );

        // borrow to 0.95 ether (5% below base borrow limit)
        _borrow(mockProtocol, address(USDC), alice, 0.95 ether);
        _assertBorrowLimits(
            0.95 ether,
            BASE_BORROW_LIMIT_AFTER_BIGMATH,
            49799117276250096,
            49799117276250096,
            0.95 ether
        );

        // expand for 10% (half duration)
        vm.warp(block.timestamp + DEFAULT_EXPAND_DEBT_CEILING_DURATION / 2);

        // assert without interacting to not trigger an update to timestamp
        (ResolverStructs.UserBorrowData memory userBorrowData, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );
        assertApproxEqAbs(userBorrowData.borrow, 0.95 ether, 1e14); // same user borrow
        assertApproxEqAbs(userBorrowData.borrowLimit, 1094815014358288081, 1e14); // 10% expanded, started at base borrow ~1 ether
        assertApproxEqAbs(userBorrowData.borrowableUntilLimit, 144817524615992952, 1e14); // 0.095 + 0.05 ether
        assertApproxEqAbs(userBorrowData.borrowable, 144817524615992952, 1e14);

        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: 15 * 1e2, // decrease to 15%
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: BASE_BORROW_LIMIT,
            maxDebtCeiling: MAX_BORROW_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        _assertBorrowLimits(
            0.95 ether,
            1071049117276250113, // increased half of 15% so 7.5% of ~0.095 ether, started at base borrow ~1 ether. ~1+ 0,07125
            121049117276250097, // 0.07125 + 0.05 ether
            121049117276250097, // 0.07125 + 0.05 ether
            0.95 ether
        );

        // warp for 1/10 of duration
        vm.warp(block.timestamp + DEFAULT_EXPAND_DEBT_CEILING_DURATION / 10);

        _assertBorrowLimits(
            950013794519650048, // increased a tiny bit from rounding
            1085299117276250113, // increased 1/4 of 15% so 1,5% from user borrow so 0,01425 ether. 1071049117276250113 + 0,01425 ether
            135315062463823432, // 0.07125 + 0.05 + 0.01425 ether
            135315062463823432, // 0.07125 + 0.05 + 0.01425  ether
            950013794519650048
        );

        // borrow exactly to borrow limit.
        (userBorrowData, ) = resolver.getUserBorrowData(address(mockProtocol), address(USDC));
        _borrow(mockProtocol, address(USDC), alice, userBorrowData.borrowable);

        _assertBorrowLimits(1085299117276250113, 1085299117276250113, 0, 0, 1085299117276250113);

        // warp for full expansion
        vm.warp(block.timestamp + DEFAULT_EXPAND_DEBT_CEILING_DURATION + 1);
        // assert without interacting to not trigger an update to timestamp
        (userBorrowData, ) = resolver.getUserBorrowData(address(mockProtocol), address(USDC));
        assertApproxEqAbs(userBorrowData.borrow, 1085299117276250113, 1e14); // same user borrow
        assertApproxEqAbs(userBorrowData.borrowLimit, 1248093984867687629, 1e14); // 15% expanded from user borrow
        assertApproxEqAbs(userBorrowData.borrowableUntilLimit, 162794867591437516, 1e14);
        assertApproxEqAbs(userBorrowData.borrowable, 162794867591437516, 1e14);

        userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: 10 * 1e2, // decrease to 10%
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: BASE_BORROW_LIMIT,
            maxDebtCeiling: MAX_BORROW_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        _assertBorrowLimits(
            1085299117276250113,
            1193829029003875124,
            108529911727625011,
            108529911727625011,
            1085299117276250113
        );

        // set max hard limit to below
        userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: 10 * 1e2, // decrease to 10%
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: BASE_BORROW_LIMIT,
            maxDebtCeiling: 1153829029003875124
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        _assertBorrowLimits(
            1085299117276250113,
            1152975076795894380,
            67675959519644255,
            67675959519644255,
            1085299117276250113
        );
    }

    function _assertBorrowLimits(
        uint256 borrow,
        uint256 borrowLimit,
        uint256 borrowableUntilLimit,
        uint256 borrowable,
        uint256 resetToBorrowAmount
    ) internal {
        (ResolverStructs.UserBorrowData memory userBorrowData, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );
        assertApproxEqAbs(userBorrowData.borrow, borrow, 1e14);
        assertApproxEqAbs(userBorrowData.borrowLimit, borrowLimit, 1e14);
        assertApproxEqAbs(userBorrowData.borrowableUntilLimit, borrowableUntilLimit, 1e14);
        assertApproxEqAbs(userBorrowData.borrowable, borrowable, 1e14);

        // assert reverts if borrowing more
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, userBorrowData.borrowable + 1);

        if (userBorrowData.borrowable > 1e3) {
            // assert borrowing exactly works
            try
                mockProtocol.operate(
                    address(USDC),
                    0,
                    int256(userBorrowData.borrowable),
                    address(0),
                    alice,
                    new bytes(0)
                )
            {} catch {
                console2.log("BORROWING EXACTLY FAILED, reducing borrowable by -1 and try again");
                _borrow(mockProtocol, address(USDC), alice, userBorrowData.borrowable - 1);
            }

            // payback
            (userBorrowData, ) = resolver.getUserBorrowData(address(mockProtocol), address(USDC));
            _payback(mockProtocol, address(USDC), alice, userBorrowData.borrow - resetToBorrowAmount);
        }
    }
}

contract LiquidityUserModuleBorrowLimitTestsWithInterest is LiquidityUserModuleBorrowLimitTests {
    function _getInterestMode() internal pure virtual override returns (uint8) {
        return 1;
    }
}

contract LiquidityUserModuleBorrowLimitTestsInterestFree is LiquidityUserModuleBorrowLimitTests {
    function _getInterestMode() internal pure virtual override returns (uint8) {
        return 0;
    }
}
