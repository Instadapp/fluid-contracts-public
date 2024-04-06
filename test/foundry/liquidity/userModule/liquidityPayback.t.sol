//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";
import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { LiquidityUserModuleOperateTestSuite } from "./liquidityOperate.t.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";
import { stdError } from "forge-std/Test.sol";

contract LiquidityUserModulePaybackTestSuite is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows USDC liquidity
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // to get borrow rate used for exchange prices update, this is the rate active for utilization BEFORE payback:
        // utilization = DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS / DEFAULT_SUPPLY_AMOUNT; -> 50%
        // annual borrow rate for default test data with default values see {TestHelpers}, at utilization 50%:
        // 4% base rate at 0% utilization, rate grows 6% from 0% to kink at 80%
        // -> so for every 8% in utilization incrase, rate grows 0.6%.
        // at utilization 50% it's 4% + 3.75% (50 / 8 * 0.6%) = 7.75%
        // uint256 borrowRateBeforePayback = 775; // 7.75% in 1e2 precision
        uint256 supplyExchangePrice = 1038750000000; // increased half of 7.75% -> 3.875% (because half of supply is borrowed out)
        uint256 borrowExchangePrice = 1077500000000; // increased 7.75%

        uint256 totalAmounts;
        uint256 userBorrowData;
        uint256 exchangePricesAndConfig;
        {
            uint256 totalSupplyRawInterest = DEFAULT_SUPPLY_AMOUNT;

            uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference

            // to get totalBorrowRawInterest -> borrow amount of 0.5 ETH increases 7.75% -> to 0.53875 ETH
            // after paybacking the default amount 0.3 ETH, there is still 0.23875 ETH being borrowed
            // in raw that would be 0.23875 ETH / borrowExchangePrice
            uint256 totalBorrow = (((defaultBorrowAmountAfterRounding * borrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION) - DEFAULT_PAYBACK_AMOUNT);
            assertEq(totalBorrow, 238750000000000008);
            uint256 totalBorrowRawInterest = ((totalBorrow * EXCHANGE_PRICES_PRECISION) / borrowExchangePrice) + 1; // should be 0.221577726218097455 +1 for round up
            assertEq(totalBorrowRawInterest, 221577726218097456);

            totalAmounts = _simulateTotalAmounts(totalSupplyRawInterest, 0, totalBorrowRawInterest, 0);

            uint256 totalSupply = (DEFAULT_SUPPLY_AMOUNT * supplyExchangePrice) / EXCHANGE_PRICES_PRECISION;
            assertEq(totalSupply, 1038750000000000000);

            userBorrowData = _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                address(USDC),
                totalBorrowRawInterest, // taking interest on borrow amount until payback into account
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            );

            // utilization AFTER payback
            uint256 utilization = (totalBorrow * FOUR_DECIMALS) / totalSupply; // results in 2298,4356
            assertEq(utilization, 2298);
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(address(USDC)),
                utilization
            );
            assertEq(borrowRate, 572); // expected borrow rate at ~23% utilization
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                0,
                0
            );
        }

        _setTestOperateParams(
            address(USDC),
            int256(0),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            address(0),
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                1 // user supply data is not updated as the tx does payback only. So timestamp is still from before
            ),
            userBorrowData,
            true
        );
    }
}

contract LiquidityUserModulePaybackTestSuiteInterestFree is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows USDC liquidity
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // exchange prices are not changing because of interest free mode
        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference

        uint256 utilization;
        uint256 totalAmounts;
        {
            totalAmounts = _simulateTotalAmounts(
                0,
                DEFAULT_SUPPLY_AMOUNT,
                0,
                defaultBorrowAmountAfterRounding - DEFAULT_PAYBACK_AMOUNT
            );

            // utilization AFTER payback
            utilization =
                ((defaultBorrowAmountAfterRounding - DEFAULT_PAYBACK_AMOUNT) * FOUR_DECIMALS) /
                DEFAULT_SUPPLY_AMOUNT; // results in 20%
            assertEq(utilization, 2000);
        }
        uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
            resolver.getRateConfig(address(USDC)),
            utilization
        );
        assertEq(borrowRate, 550); // expected borrow rate at 20% utilization

        uint256 exchangePricesAndConfig;
        {
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                1, // supplyRatio = 1 for mode set to total supply with interest < interest free
                1 // borrowRatio = 1 for mode set to total supply with interest < interest free
            );
        }

        _setTestOperateParams(
            address(USDC),
            int256(0),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            address(0),
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                1 // user supply data is not updated as the tx does payback only. So timestamp is still from before
            ),
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH - DEFAULT_PAYBACK_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

contract LiquidityUserModulePaybackTestSuiteNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies liquidity
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows liquidity
        _borrowNative(mockProtocol, alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // to get borrow rate used for exchange prices update, this is the rate active for utilization BEFORE payback:
        // utilization = DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS / DEFAULT_SUPPLY_AMOUNT; -> 50%
        // annual borrow rate for default test data with default values see {TestHelpers}, at utilization 50%:
        // 4% base rate at 0% utilization, rate grows 6% from 0% to kink at 80%
        // -> so for every 8% in utilization incrase, rate grows 0.6%.
        // at utilization 50% it's 4% + 3.75% (50 / 8 * 0.6%) = 7.75%
        // uint256 borrowRateBeforePayback = 775; // 7.75% in 1e2 precision
        uint256 supplyExchangePrice = 1038750000000; // increased half of 7.75% -> 3.875% (because half of supply is borrowed out)
        uint256 borrowExchangePrice = 1077500000000; // increased 7.75%

        uint256 totalAmounts;
        uint256 userBorrowData;
        uint256 exchangePricesAndConfig;
        {
            uint256 totalSupplyRawInterest = DEFAULT_SUPPLY_AMOUNT;

            uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference

            // to get totalBorrowRawInterest -> borrow amount of 0.5 ETH increases 7.75% -> to 0.53875 ETH
            // after paybacking the default amount 0.3 ETH, there is still 0.23875 ETH being borrowed
            // in raw that would be 0.23875 ETH / borrowExchangePrice
            uint256 totalBorrow = (((defaultBorrowAmountAfterRounding * borrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION) - DEFAULT_PAYBACK_AMOUNT);
            assertEq(totalBorrow, 238750000000000008);
            uint256 totalBorrowRawInterest = ((totalBorrow * EXCHANGE_PRICES_PRECISION) / borrowExchangePrice) + 1; // should be 0.221577726218097455 +1 for round up
            assertEq(totalBorrowRawInterest, 221577726218097456);

            totalAmounts = _simulateTotalAmounts(totalSupplyRawInterest, 0, totalBorrowRawInterest, 0);

            uint256 totalSupply = (DEFAULT_SUPPLY_AMOUNT * supplyExchangePrice) / EXCHANGE_PRICES_PRECISION;
            assertEq(totalSupply, 1038750000000000000);

            userBorrowData = _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                totalBorrowRawInterest, // taking interest on borrow amount until payback into account
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            );

            // utilization AFTER payback
            uint256 utilization = (totalBorrow * FOUR_DECIMALS) / totalSupply; // results in 2298,4356
            assertEq(utilization, 2298);
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(NATIVE_TOKEN_ADDRESS),
                utilization
            );
            assertEq(borrowRate, 572); // expected borrow rate at ~23% utilization
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                0,
                0
            );
        }

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            int256(0),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            address(0),
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                1 // user supply data is not updated as the tx does payback only. So timestamp is still from before
            ),
            userBorrowData,
            true
        );
    }
}

contract LiquidityUserModulePaybackTestSuiteInterestFreeNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));

        // alice supplies liquidity
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows liquidity
        _borrowNative(mockProtocol, alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // exchange prices are not changing because of interest free mode
        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference

        uint256 utilization;
        uint256 totalAmounts;
        {
            totalAmounts = _simulateTotalAmounts(
                0,
                DEFAULT_SUPPLY_AMOUNT,
                0,
                defaultBorrowAmountAfterRounding - DEFAULT_PAYBACK_AMOUNT
            );

            // utilization AFTER payback
            utilization =
                ((defaultBorrowAmountAfterRounding - DEFAULT_PAYBACK_AMOUNT) * FOUR_DECIMALS) /
                DEFAULT_SUPPLY_AMOUNT; // results in 20%
            assertEq(utilization, 2000);
        }
        uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
            resolver.getRateConfig(NATIVE_TOKEN_ADDRESS),
            utilization
        );
        assertEq(borrowRate, 550);

        uint256 exchangePricesAndConfig;
        {
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                1, // supplyRatio = 1 for mode set to total supply with interest < interest free
                1 // borrowRatio = 1 for mode set to total supply with interest < interest free
            );
        }

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            int256(0),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            address(0),
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                1 // user supply data is not updated as the tx does payback only. So timestamp is still from before
            ),
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH - DEFAULT_PAYBACK_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

contract LiquidityUserModulePaybackTests is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows USDC liquidity
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);
    }

    function test_operate_RevertPaybackOperateAmountOutOfBounds() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountOutOfBounds)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(0),
            int256(type(int128).min) - 1,
            address(0),
            alice,
            abi.encode(alice)
        );
    }

    function test_operate_RevertPaybackNoApprovalForTransfer() public {
        uint256 balanceBefore = USDC.balanceOf(alice);

        vm.prank(alice);
        USDC.approve(address(mockProtocol), 0);

        vm.expectRevert("ERC20: insufficient allowance");

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(0),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            address(0),
            address(0),
            abi.encode(alice)
        );

        uint256 balanceAfter = USDC.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore);
    }

    function test_operate_RevertPaybackNotEnoughTransferIn() public {
        uint256 balanceBefore = USDC.balanceOf(alice);

        mockProtocol.setTransferInsufficientMode(true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TransferAmountOutOfBounds)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(0),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            address(0),
            address(0),
            abi.encode(alice)
        );

        uint256 balanceAfter = USDC.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore);
    }

    function test_operate_RevertPaybackNotEnoughTransferInNative() public {
        uint256 balanceBefore = alice.balance;

        mockProtocol.setTransferInsufficientMode(true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TransferAmountOutOfBounds)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate{ value: DEFAULT_PAYBACK_AMOUNT }(
            NATIVE_TOKEN_ADDRESS,
            int256(0),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            address(0),
            address(0),
            abi.encode(alice)
        );

        uint256 balanceAfter = alice.balance;
        assertEq(balanceAfter, balanceBefore);
    }

    function test_operate_RevertPaybackTransferTooMuchNative() public {
        uint256 balanceBefore = alice.balance;

        vm.deal(address(mockProtocol), 100 ether);

        mockProtocol.setTransferExcessMode(true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TransferAmountOutOfBounds)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate{ value: DEFAULT_PAYBACK_AMOUNT }(
            NATIVE_TOKEN_ADDRESS,
            int256(0),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            address(0),
            address(0),
            abi.encode(alice)
        );

        uint256 balanceAfter = alice.balance;
        assertEq(balanceAfter, balanceBefore);
    }

    function test_operate_RevertIfPaybackMoreThanBorrowed() public {
        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        vm.expectRevert(stdError.arithmeticError);
        _payback(mockProtocol, address(USDC), alice, userSupplyData_.supply + 1);
    }

    function test_operate_RevertIfPaybackMoreThanBorrowedNative() public {
        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            NATIVE_TOKEN_ADDRESS
        );

        vm.expectRevert(stdError.arithmeticError);
        _paybackNative(mockProtocol, alice, userSupplyData_.supply + 1);
    }
}

contract LiquidityUserModulePaybackTestsInterestFree is LiquidityUserModulePaybackTests {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));
        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));
    }

    function test_operate_PaybackMoreThanTotalBorrow() public {
        // payback more than total borrow but <= user borrow. should reset total borrow to 0 and reduce user borrow amount

        uint256 simulatedTotalAmounts = _simulateTotalAmounts(0, DEFAULT_SUPPLY_AMOUNT, 0, DEFAULT_BORROW_AMOUNT / 2);

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
        (ResolverStructs.UserBorrowData memory userBorrowData_, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT);
        assertEq(overallTokenData_.supplyRawInterest, 0);
        assertEq(overallTokenData_.supplyInterestFree, DEFAULT_SUPPLY_AMOUNT);
        assertEq(overallTokenData_.borrowRawInterest, 0);
        assertEq(overallTokenData_.borrowInterestFree, DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH / 2);

        uint256 expectedUserBorrow = 500000000000000016; // rounding up happens twice because of interest mode change in setUp()
        assertEq(userBorrowData_.borrow, expectedUserBorrow);

        // payback more than total amount
        uint256 paybackAmount = expectedUserBorrow / 2 + 10;

        uint256 newExpectedUserBorrowAfterBigMath = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                expectedUserBorrow - paybackAmount,
                DEFAULT_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_UP
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
        assertEq(newExpectedUserBorrowAfterBigMath, 250000000000000000);

        _payback(mockProtocol, address(USDC), alice, paybackAmount);

        // assert new user & total amounts
        (userBorrowData_, overallTokenData_) = resolver.getUserBorrowData(address(mockProtocol), address(USDC));

        assertEq(overallTokenData_.supplyRawInterest, 0);
        assertEq(overallTokenData_.supplyInterestFree, DEFAULT_SUPPLY_AMOUNT);
        assertEq(overallTokenData_.borrowRawInterest, 0);
        assertEq(overallTokenData_.borrowInterestFree, 0);

        assertEq(userBorrowData_.borrow, newExpectedUserBorrowAfterBigMath);
    }

    function test_operate_PaybackExactToZero() public {
        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // payback full borrowed amount
        // read borrowed amount via resolver
        (ResolverStructs.UserBorrowData memory userBorrowData, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userBorrowData.borrow, 500000000000000016); // default borrow amount bigMath rounded up twice

        _payback(mockProtocol, address(USDC), alice, userBorrowData.borrow);

        // read borrowed amount via resolver, should be 0 now
        (userBorrowData, ) = resolver.getUserBorrowData(address(mockProtocol), address(USDC));
        assertEq(userBorrowData.borrow, 0);
    }
}

contract LiquidityUserModulePaybackTestsWithInterest is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows USDC liquidity
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);
    }

    function test_operate_PaybackMoreThanTotalBorrow() public {
        // payback more than total borrow but <= user borrow. should reset total borrow to 0 and reduce user borrow amount

        uint256 simulatedTotalAmounts = _simulateTotalAmounts(DEFAULT_SUPPLY_AMOUNT, 0, DEFAULT_BORROW_AMOUNT / 2, 0);

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
        (ResolverStructs.UserBorrowData memory userBorrowData_, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT);
        assertEq(
            (overallTokenData_.supplyRawInterest * overallTokenData_.supplyExchangePrice) / EXCHANGE_PRICES_PRECISION,
            DEFAULT_SUPPLY_AMOUNT
        );
        assertEq(overallTokenData_.supplyInterestFree, 0);
        assertEq(
            (overallTokenData_.borrowRawInterest * overallTokenData_.borrowExchangePrice) / EXCHANGE_PRICES_PRECISION,
            DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH / 2
        );
        assertEq(overallTokenData_.borrowInterestFree, 0);

        assertEq(userBorrowData_.borrow, DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH);

        // payback more than total amount
        uint256 paybackAmount = DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH / 2 + 10;
        _payback(mockProtocol, address(USDC), alice, paybackAmount);

        // assert new user & total amounts
        (userBorrowData_, overallTokenData_) = resolver.getUserBorrowData(address(mockProtocol), address(USDC));

        uint256 newExpectedUserBorrowAfterBigMath = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH - paybackAmount,
                DEFAULT_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_UP
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        assertEq(
            (overallTokenData_.supplyRawInterest * overallTokenData_.supplyExchangePrice) / EXCHANGE_PRICES_PRECISION,
            DEFAULT_SUPPLY_AMOUNT
        );
        assertEq(overallTokenData_.supplyInterestFree, 0);
        assertEq(overallTokenData_.borrowRawInterest, 0);
        assertEq(overallTokenData_.borrowInterestFree, 0);
        assertEq(userBorrowData_.borrow, newExpectedUserBorrowAfterBigMath);
    }

    function test_operate_PaybackExactToZero() public {
        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // payback full borrowed amount
        // read borrowed amount via resolver
        (ResolverStructs.UserBorrowData memory userBorrowData, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );
        // uint256 supplyExchangePrice = 1038750000000; // increased half of 7.75% -> 3.875% (because half of supply is borrowed out)
        // uint256 borrowExchangePrice = 1077500000000; // increased 7.75%
        // so borrowed should be ~ 0.5 ether * 1077500000000 / 1e12 = 0.53875×10^18
        // but actually default borrow amount is not exactly 0.5 ether, but rather 500000000000000008 because of BigMath round up
        // 500000000000000008 * 1077500000000 / 1e12 = 538750000000000008
        assertEq(userBorrowData.borrow, 538750000000000008);

        // payback amount must be +1 to make up for rounding loss:
        // 538750000000000008 * 1e12 / 1077500000000 = 500000000000000007,xyz -> rounded down
        // so must do +1 to get to exactly zero
        _payback(mockProtocol, address(USDC), alice, userBorrowData.borrow + 1);

        // read borrowed amount via resolver, should be 0 now
        (userBorrowData, ) = resolver.getUserBorrowData(address(mockProtocol), address(USDC));
        assertEq(userBorrowData.borrow, 0);
    }
}
