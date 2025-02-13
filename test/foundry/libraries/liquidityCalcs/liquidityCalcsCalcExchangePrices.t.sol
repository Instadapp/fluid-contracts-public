//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LibraryLiquidityCalcsBaseTest } from "./liquidityCalcsBaseTest.t.sol";
import { LibsErrorTypes } from "../../../../contracts/libraries/errorTypes.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";

import "forge-std/console2.sol";

contract LibraryLiquidityCalcsCalcExchangePricesTests is LibraryLiquidityCalcsBaseTest {
    uint256 constant DEFAULT_PERCENT_PRECISION = 1e2;
    uint256 constant HUNDRED_PERCENT = 100 * DEFAULT_PERCENT_PRECISION;
    uint256 constant DEFAULT_FEE = 50 * DEFAULT_PERCENT_PRECISION; // 50%
    uint256 constant EXCHANGE_PRICES_PRECISION = 1e12;

    uint256 constant supplyInterestFree = 2 ether;
    uint256 constant borrowInterestFree = 1 ether;

    // Note: lots of additional tests are in liquidityYield.t.sol that indirectly fully test calcExchangePrices()

    function testLiquidityCalcs_calcExchangePrices_RevertSupplyExchangePrice0() public {
        uint256 exchangePricesAndConfig = _simulateExchangePricesAndConfig(
            0, // borrow rate
            0, // fee
            0, // utilization
            0, // updateOnStorageThreshold
            0, // last update timestamp -> half a year ago
            0, // supplyExchangePrice
            EXCHANGE_PRICES_PRECISION, // borrowExchangePrice
            0,
            0,
            0,
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityCalcs.FluidLiquidityCalcsError.selector,
                LibsErrorTypes.LiquidityCalcs__ExchangePriceZero
            )
        );

        testHelper.calcExchangePrices(exchangePricesAndConfig);
    }

    function testLiquidityCalcs_calcExchangePrices_RevertBorrowExchangePrice0() public {
        uint256 exchangePricesAndConfig = _simulateExchangePricesAndConfig(
            0, // borrow rate
            0, // fee
            0, // utilization
            0, // updateOnStorageThreshold
            0, // last update timestamp -> half a year ago
            EXCHANGE_PRICES_PRECISION, // supplyExchangePrice
            0, // borrowExchangePrice
            0,
            0,
            0,
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityCalcs.FluidLiquidityCalcsError.selector,
                LibsErrorTypes.LiquidityCalcs__ExchangePriceZero
            )
        );

        testHelper.calcExchangePrices(exchangePricesAndConfig);
    }

    function testLiquidityCalcs_calcExchangePrices_WhenBorrowRate0() public {
        vm.warp(block.timestamp + 2000 days); // skip ahead to not cause an underflow for last update timestamp

        uint256 supplyWithInterestRaw = 10 ether;
        uint256 borrowWithInterestRaw = 8 ether;

        uint256 exchangePricesAndConfig = _simulateExchangePricesAndConfig(
            0, // borrow rate
            DEFAULT_FEE, // fee
            (HUNDRED_PERCENT * (borrowWithInterestRaw + borrowInterestFree)) /
                (supplyWithInterestRaw + supplyInterestFree), // utilization
            1 * DEFAULT_PERCENT_PRECISION, // updateOnStorageThreshold
            block.timestamp - 182.5 days, // last update timestamp -> half a year ago
            EXCHANGE_PRICES_PRECISION, // supplyExchangePrice
            EXCHANGE_PRICES_PRECISION, // borrowExchangePrice
            // supply ratio mode: if 0 then supplyInterestFree / supplyWithInterestRaw else supplyWithInterestRaw / supplyInterestFree
            // ratio always divides by bigger amount, ratio can never be > 100%
            supplyWithInterestRaw > supplyInterestFree ? 0 : 1,
            supplyWithInterestRaw > supplyInterestFree
                ? (supplyInterestFree * HUNDRED_PERCENT) / supplyWithInterestRaw
                : (supplyWithInterestRaw * HUNDRED_PERCENT) / supplyInterestFree,
            borrowWithInterestRaw > borrowInterestFree ? 0 : 1,
            borrowWithInterestRaw > borrowInterestFree
                ? (borrowInterestFree * HUNDRED_PERCENT) / borrowWithInterestRaw
                : (borrowWithInterestRaw * HUNDRED_PERCENT) / borrowInterestFree
        );

        (uint256 supplyExchangePrice, uint256 borrowExchangePrice) = testHelper.calcExchangePrices(
            exchangePricesAndConfig
        );

        assertEq(supplyExchangePrice, EXCHANGE_PRICES_PRECISION);
        assertEq(borrowExchangePrice, EXCHANGE_PRICES_PRECISION);
    }

    function testLiquidityCalcs_calcExchangePrices_WhenTimePassed0() public {
        vm.warp(block.timestamp + 2000 days); // skip ahead to not cause an underflow for last update timestamp

        uint256 supplyWithInterestRaw = 10 ether;
        uint256 borrowWithInterestRaw = 8 ether;

        uint256 exchangePricesAndConfig = _simulateExchangePricesAndConfig(
            10 * DEFAULT_PERCENT_PRECISION, // borrow rate
            DEFAULT_FEE, // fee
            (HUNDRED_PERCENT * (borrowWithInterestRaw + borrowInterestFree)) /
                (supplyWithInterestRaw + supplyInterestFree), // utilization
            1 * DEFAULT_PERCENT_PRECISION, // updateOnStorageThreshold
            block.timestamp, // last update timestamp
            EXCHANGE_PRICES_PRECISION, // supplyExchangePrice
            EXCHANGE_PRICES_PRECISION, // borrowExchangePrice
            // supply ratio mode: if 0 then supplyInterestFree / supplyWithInterestRaw else supplyWithInterestRaw / supplyInterestFree
            // ratio always divides by bigger amount, ratio can never be > 100%
            supplyWithInterestRaw > supplyInterestFree ? 0 : 1,
            supplyWithInterestRaw > supplyInterestFree
                ? (supplyInterestFree * HUNDRED_PERCENT) / supplyWithInterestRaw
                : (supplyWithInterestRaw * HUNDRED_PERCENT) / supplyInterestFree,
            borrowWithInterestRaw > borrowInterestFree ? 0 : 1,
            borrowWithInterestRaw > borrowInterestFree
                ? (borrowInterestFree * HUNDRED_PERCENT) / borrowWithInterestRaw
                : (borrowWithInterestRaw * HUNDRED_PERCENT) / borrowInterestFree
        );

        (uint256 supplyExchangePrice, uint256 borrowExchangePrice) = testHelper.calcExchangePrices(
            exchangePricesAndConfig
        );

        assertEq(supplyExchangePrice, EXCHANGE_PRICES_PRECISION);
        assertEq(borrowExchangePrice, EXCHANGE_PRICES_PRECISION);
    }

    function testLiquidityCalcs_calcExchangePrices() public {
        vm.warp(block.timestamp + 2000 days); // skip ahead to not cause an underflow for last update timestamp

        uint256 exchangePricesAndConfig;

        uint256 supplyWithInterestRaw = 10 ether;
        uint256 borrowWithInterestRaw = 8 ether;

        exchangePricesAndConfig = _simulateExchangePricesAndConfig(
            10 * DEFAULT_PERCENT_PRECISION, // borrow rate
            DEFAULT_FEE, // fee
            (HUNDRED_PERCENT * (borrowWithInterestRaw + borrowInterestFree)) /
                (supplyWithInterestRaw + supplyInterestFree), // utilization
            1 * DEFAULT_PERCENT_PRECISION, // updateOnStorageThreshold
            block.timestamp - 182.5 days, // last update timestamp -> half a year ago
            EXCHANGE_PRICES_PRECISION, // supplyExchangePrice
            EXCHANGE_PRICES_PRECISION, // borrowExchangePrice
            // supply ratio mode: if 0 then supplyInterestFree / supplyWithInterestRaw else supplyWithInterestRaw / supplyInterestFree
            // ratio always divides by bigger amount, ratio can never be > 100%
            supplyWithInterestRaw > supplyInterestFree ? 0 : 1,
            supplyWithInterestRaw > supplyInterestFree
                ? (supplyInterestFree * HUNDRED_PERCENT) / supplyWithInterestRaw
                : (supplyWithInterestRaw * HUNDRED_PERCENT) / supplyInterestFree,
            borrowWithInterestRaw > borrowInterestFree ? 0 : 1,
            borrowWithInterestRaw > borrowInterestFree
                ? (borrowInterestFree * HUNDRED_PERCENT) / borrowWithInterestRaw
                : (borrowWithInterestRaw * HUNDRED_PERCENT) / borrowInterestFree
        );

        (uint256 supplyExchangePrice, uint256 borrowExchangePrice) = testHelper.calcExchangePrices(
            exchangePricesAndConfig
        );

        console2.log("borrowExchangePrice", borrowExchangePrice);
        // borrow exchange price should be:
        // 8 ether paying 10% borrow rate in 1 year so 0.4 in half a year
        // so 8 raw * borrowExchangePrice = 8.4 -> borrowExchange price must be 1.05
        assertEq(borrowExchangePrice, 1.05e12);

        console2.log("supplyExchangePrice", supplyExchangePrice);
        // supply exchange price should be:
        // supply rate should be 10% - fee 50% = 5%. and only 75% is lent out with yield so 3,75%.
        // and only 8 out of 9 borrow are paying yield so 3,75*8/9 = 3,3333%
        // but 1/6 of supply is not getting the yield so 3,33%*6/5 = 4%
        // and for half the year only that would be 2%. so supplyExchangePrice must be 1.02.
        // or as cross-check:
        // 0.4 ether borrowing interest, but 50% of that are kept as fee -> so 0.2 yield.
        // total supply should end up 12.2 ether. With supplyInterestFree still 2 ether,
        // supplyWithInterest 10.2 ether.
        // so 10 raw * supplyExchangePrice = 10.2 -> supplyExchangePrice price must be 1.02
        assertEq(supplyExchangePrice, 1.02e12);

        // raw amounts to normal for updated exchange prices ->
        supplyWithInterestRaw = (supplyWithInterestRaw * supplyExchangePrice) / 1e12;
        borrowWithInterestRaw = (borrowWithInterestRaw * borrowExchangePrice) / 1e12;

        // assuming another half year has passed, starting exchange prices are not 1
        exchangePricesAndConfig = _simulateExchangePricesAndConfig(
            10 * DEFAULT_PERCENT_PRECISION, // borrow rate
            DEFAULT_FEE, // fee
            (HUNDRED_PERCENT * (borrowWithInterestRaw + borrowInterestFree)) /
                (supplyWithInterestRaw + supplyInterestFree), // utilization
            1 * DEFAULT_PERCENT_PRECISION, // updateOnStorageThreshold
            block.timestamp - 182.5 days, // last update timestamp -> half a year ago
            supplyExchangePrice, // supplyExchangePrice
            borrowExchangePrice, // borrowExchangePrice
            // supply ratio mode: if 0 then supplyInterestFree / supplyWithInterestRaw else supplyWithInterestRaw / supplyInterestFree
            // ratio always divides by bigger amount, ratio can never be > 100%
            supplyWithInterestRaw > supplyInterestFree ? 0 : 1,
            supplyWithInterestRaw > supplyInterestFree
                ? (supplyInterestFree * HUNDRED_PERCENT) / supplyWithInterestRaw
                : (supplyWithInterestRaw * HUNDRED_PERCENT) / supplyInterestFree,
            borrowWithInterestRaw > borrowInterestFree ? 0 : 1,
            borrowWithInterestRaw > borrowInterestFree
                ? (borrowInterestFree * HUNDRED_PERCENT) / borrowWithInterestRaw
                : (borrowWithInterestRaw * HUNDRED_PERCENT) / borrowInterestFree
        );

        (supplyExchangePrice, borrowExchangePrice) = testHelper.calcExchangePrices(exchangePricesAndConfig);

        console2.log("borrowExchangePrice", borrowExchangePrice);
        // borrow exchange price should be:
        // 8.4 ether paying 10% borrow rate in 1 year so 0.42 in half a year
        // so 8 raw * borrowExchangePrice = 8.82 -> borrowExchange price must be 1.1025
        assertEq(borrowExchangePrice, 1.1025e12);

        console2.log("supplyExchangePrice", supplyExchangePrice);
        // supply exchange price should be:
        // 0.42 ether new borrowings, but 50% of that are kept as fee -> so 0.21 yield
        // so 10 raw * supplyExchangePrice = 10.41 -> supplyExchangePrice price must be 1.041
        assertApproxEqAbs(supplyExchangePrice, 1.041e12, 1e7);
    }
}
