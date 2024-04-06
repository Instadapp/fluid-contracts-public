//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { LiquidityUserModuleOperateTestSuite } from "./liquidityOperate.t.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";
import { stdError } from "forge-std/Test.sol";

contract LiquidityUserModuleWithdrawTestSuite is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        _setTestOperateParams(
            address(USDC),
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            int256(0),
            alice,
            alice,
            address(0),
            _simulateTotalAmounts(DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT, 0, 0, 0),
            _simulateExchangePrices(resolver, address(USDC), supplyExchangePrice, borrowExchangePrice),
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(resolver, address(mockProtocol), address(USDC), 0, 0, 0),
            true
        );
    }
}

contract LiquidityUserModuleWithdrawTestSuiteInterestFree is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        _setTestOperateParams(
            address(USDC),
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            int256(0),
            alice,
            alice,
            address(0),
            _simulateTotalAmounts(0, DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT, 0, 0),
            _simulateExchangePricesWithRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                1, // supplyRatio = 1 for mode set to total supply with interest < interest free
                0 // borrowRatio
            ),
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(resolver, address(mockProtocol), address(USDC), 0, 0, 0),
            true
        );
    }
}

contract LiquidityUserModuleWithdrawTestSuiteNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies liquidity
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            int256(0),
            alice,
            alice,
            address(0),
            _simulateTotalAmounts(DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT, 0, 0, 0),
            _simulateExchangePrices(resolver, NATIVE_TOKEN_ADDRESS, supplyExchangePrice, borrowExchangePrice),
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(resolver, address(mockProtocol), NATIVE_TOKEN_ADDRESS, 0, 0, 0),
            true
        );
    }
}

contract LiquidityUserModuleWithdrawTestSuiteInterestFreeNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));

        // alice supplies liquidity
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            int256(0),
            alice,
            alice,
            address(0),
            _simulateTotalAmounts(0, DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT, 0, 0),
            _simulateExchangePricesWithRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                1, // supplyRatio = 1 for mode set to total supply with interest < interest free
                0 // borrowRatio
            ),
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(resolver, address(mockProtocol), NATIVE_TOKEN_ADDRESS, 0, 0, 0),
            true
        );
    }
}

contract LiquidityUserModuleWithdrawTests is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);
    }

    function test_operate_RevertWithdrawOperateAmountOutOfBounds() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountOutOfBounds)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(type(int128).min) - 1,
            int256(0),
            alice,
            address(0),
            abi.encode(alice)
        );
    }

    function test_operate_RevertIfWithdrawToNotSet() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__ReceiverNotDefined)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            int256(0),
            address(0),
            address(0),
            new bytes(0)
        );
    }

    function test_operate_RevertIfWithdrawToNotSetNative() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__ReceiverNotDefined)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            NATIVE_TOKEN_ADDRESS,
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            int256(0),
            address(0),
            address(0),
            new bytes(0)
        );
    }

    function test_operate_RevertIfWithdrawMoreThanSupplied() public {
        vm.expectRevert(stdError.arithmeticError);
        _withdraw(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT + 1);
    }

    function test_operate_RevertIfWithdrawMoreThanSuppliedNative() public {
        vm.expectRevert(stdError.arithmeticError);
        _withdrawNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT + 1);
    }
}

contract LiquidityUserModuleWithdrawTestsInterestFree is LiquidityUserModuleWithdrawTests {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));
        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));
    }

    function test_operate_WithdrawMoreThanTotalSupply() public {
        // withdraw more than total supply but <= user supply. should reset total supply to 0 and reduce user supply amount

        uint256 simulatedTotalAmounts = _simulateTotalAmounts(0, DEFAULT_SUPPLY_AMOUNT / 2, 0, 0);

        bytes32 slot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
            address(USDC)
        );

        // simulate lower total amount in storage
        vm.store(address(liquidity), slot, bytes32(simulatedTotalAmounts));

        (
            ResolverStructs.UserSupplyData memory userSupplyData_,
            ResolverStructs.OverallTokenData memory overallTokenData_
        ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT);
        assertEq(overallTokenData_.supplyRawInterest, 0);
        assertEq(overallTokenData_.supplyInterestFree, DEFAULT_SUPPLY_AMOUNT / 2);
        assertEq(overallTokenData_.borrowRawInterest, 0);
        assertEq(overallTokenData_.borrowInterestFree, 0);

        // withdraw more than total amount
        uint256 withdrawAmount = DEFAULT_SUPPLY_AMOUNT / 2 + 10;

        uint256 newExpectedUserSupplyAfterBigMath = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                userSupplyData_.supply - withdrawAmount,
                DEFAULT_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
        assertEq(newExpectedUserSupplyAfterBigMath, 499999999999999984);

        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount);

        // assert new user & total amounts
        (userSupplyData_, overallTokenData_) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));

        assertEq(userSupplyData_.supply, newExpectedUserSupplyAfterBigMath);

        assertEq(overallTokenData_.supplyRawInterest, 0);
        assertEq(overallTokenData_.supplyInterestFree, 0);
        assertEq(overallTokenData_.borrowRawInterest, 0);
        assertEq(overallTokenData_.borrowInterestFree, 0);
    }

    function test_operate_WithdrawExactToZero() public {
        // borrow to create some yield for better test setup
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);
        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // create more supply so there is actually liquidity for withdrawal, but from other user (other mockProtocol)
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // withdraw full available supply amount
        // read supplied amount via resolver
        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData.supply, DEFAULT_SUPPLY_AMOUNT);

        _withdraw(mockProtocol, address(USDC), alice, userSupplyData.supply);

        // read supplied amount via resolver, should be 0 now
        (userSupplyData, ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertEq(userSupplyData.supply, 0);
    }
}

contract LiquidityUserModuleWithdrawTestsWithInterest is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);
    }

    function test_operate_WithdrawMoreThanTotalSupply() public {
        // withdraw more than total supply but <= user supply. should reset total supply to 0 and reduce user supply amount

        // borrow to create some yield for better test setup
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        uint256 simulatedTotalAmounts = _simulateTotalAmounts(DEFAULT_SUPPLY_AMOUNT / 2, 0, DEFAULT_BORROW_AMOUNT, 0);

        bytes32 slot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
            address(USDC)
        );

        // simulate lower total amount in storage. affects supplyExchangePrice
        vm.store(address(liquidity), slot, bytes32(simulatedTotalAmounts));

        // simulate correct utilization of 100%, ratios etc.
        uint256 simulatedExchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
            resolver,
            address(USDC),
            1e12, // supplyExchangePrice
            1e12, // borrowExchangePrice
            DEFAULT_100_PERCENT, // utilization
            775, // borrow rate = 7,75%
            block.timestamp,
            0, // supplyRatio there is only supply with interest. first bit 0
            0 // borrowRatio there is only borrow with interest. first bit 0
        );
        slot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            address(USDC)
        );
        vm.store(address(liquidity), slot, bytes32(simulatedExchangePricesAndConfig));

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        (
            ResolverStructs.UserSupplyData memory userSupplyData_,
            ResolverStructs.OverallTokenData memory overallTokenData_
        ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));

        // uint256 supplyExchangePrice = 1077500000000; // increased 7.75% (because ALL of supply is borrowed out)
        // uint256 borrowExchangePrice = 1077500000000; // increased 7.75%
        assertEq(userSupplyData_.supply, 1.0775 ether);

        assertEq(overallTokenData_.supplyRawInterest, DEFAULT_SUPPLY_AMOUNT / 2);
        assertEq(overallTokenData_.totalSupply, 0.53875 ether); // 0.5 ether adjusted for supplyExchangePrice
        assertEq(overallTokenData_.supplyInterestFree, 0);
        assertEq(overallTokenData_.borrowRawInterest, DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH);
        assertEq(overallTokenData_.borrowInterestFree, 0);

        // withdraw more than total amount
        uint256 withdrawAmount = overallTokenData_.totalSupply + 1;

        uint256 newExpectedUserSupplyAfterBigMath = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                userSupplyData_.supply - withdrawAmount, // 1.0775 ether - 0.53875 ether + 1 = 538750000000000001
                DEFAULT_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
        assertEq(newExpectedUserSupplyAfterBigMath, 538749999999999992);

        // payback borrowed amount to create funds at liquidity
        _payback(mockProtocol, address(USDC), alice, (DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH * 1077500000000) / 1e12);

        _withdraw(mockProtocol, address(USDC), alice, withdrawAmount);

        // assert new user & total amounts
        (userSupplyData_, overallTokenData_) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));

        assertApproxEqAbs(userSupplyData_.supply, newExpectedUserSupplyAfterBigMath, 1); // tolerance for rounding

        assertEq(overallTokenData_.supplyRawInterest, 0);
        assertEq(overallTokenData_.supplyInterestFree, 0);
        assertApproxEqAbs(overallTokenData_.borrowRawInterest, 0, 1); // tolerance for rounding
        assertEq(overallTokenData_.borrowInterestFree, 0);
    }

    function test_operate_WithdrawExactToZero() public {
        // borrow to create some yield for better test setup
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);
        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // create more supply so there is actually liquidity for withdrawal, but from other user (other mockProtocol)
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // withdraw full available supply amount
        // read supplied amount via resolver
        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        // uint256 supplyExchangePrice = 1038750000000; // increased half of 7.75% -> 3.875% (because half of supply is borrowed out)
        // uint256 borrowExchangePrice = 1077500000000; // increased 7.75%
        // so withdrawable should be ~ 1 ether * 1038750000000 / 1e12 = 1.03875×10^18
        assertEq(userSupplyData.supply, 1.03875 ether);

        _withdraw(mockProtocol, address(USDC), alice, userSupplyData.supply);

        // read supplied amount via resolver, should be 0 now
        (userSupplyData, ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertEq(userSupplyData.supply, 0);
    }
}
