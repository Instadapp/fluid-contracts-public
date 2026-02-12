//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LibraryLiquidityCalcsBaseTest } from "./liquidityCalcsBaseTest.t.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";

import "forge-std/console2.sol";

contract LibraryLiquidityCalcsGetTotalSupplyTests is LibraryLiquidityCalcsBaseTest {
    function assertExpectedTotalSupply(
        uint256 totalSupplyRaw,
        uint256 totalSupplyInterestFree,
        uint256 supplyExchangePrice
    ) internal {
        uint256 simulatedTotalAmounts = _simulateTotalAmounts(totalSupplyRaw, totalSupplyInterestFree, 0, 0);

        uint256 expectedTotalSupply = (totalSupplyRaw * supplyExchangePrice) / 1e12 + totalSupplyInterestFree;

        assertEq(testHelper.getTotalSupply(simulatedTotalAmounts, supplyExchangePrice), expectedTotalSupply);
    }

    function test_getTotalSupply_WhenOnlySupplyWithInterest() public {
        uint256 totalSupplyRaw = 123457984546456;
        uint256 totalSupplyInterestFree = 0;
        uint256 supplyExchangePrice = 1234500000;

        assertExpectedTotalSupply(totalSupplyRaw, totalSupplyInterestFree, supplyExchangePrice);
    }

    function test_getTotalSupply_WhenOnlySupplyInterestFree() public {
        uint256 totalSupplyRaw = 0;
        uint256 totalSupplyInterestFree = 123457984546456;
        uint256 supplyExchangePrice = 1234500000;

        assertExpectedTotalSupply(totalSupplyRaw, totalSupplyInterestFree, supplyExchangePrice);
    }

    function test_getTotalSupply_WhenBoth() public {
        uint256 totalSupplyRaw = 123457984546456;
        uint256 totalSupplyInterestFree = 123457984546456;
        uint256 supplyExchangePrice = 1234500000;

        assertExpectedTotalSupply(totalSupplyRaw, totalSupplyInterestFree, supplyExchangePrice);
    }

    function test_getTotalSupply_When0() public {
        uint256 totalSupplyRaw = 0;
        uint256 totalSupplyInterestFree = 0;
        uint256 supplyExchangePrice = 1234500000;

        assertExpectedTotalSupply(totalSupplyRaw, totalSupplyInterestFree, supplyExchangePrice);
    }
}

contract LibraryLiquidityCalcsGetTotalBorrowTests is LibraryLiquidityCalcsBaseTest {
    function assertExpectedTotalBorrow(
        uint256 totalBorrowRaw,
        uint256 totalBorrowInterestFree,
        uint256 borrowExchangePrice
    ) internal {
        uint256 simulatedTotalAmounts = _simulateTotalAmounts(0, 0, totalBorrowRaw, totalBorrowInterestFree);

        uint256 expectedTotalBorrow = (totalBorrowRaw * borrowExchangePrice) / 1e12 + totalBorrowInterestFree;

        assertEq(testHelper.getTotalBorrow(simulatedTotalAmounts, borrowExchangePrice), expectedTotalBorrow);
    }

    function test_getTotalBorrow_WhenOnlyBorrowWithInterest() public {
        uint256 totalBorrowRaw = 123457984546456;
        uint256 totalBorrowInterestFree = 0;
        uint256 borrowExchangePrice = 1234500000;

        assertExpectedTotalBorrow(totalBorrowRaw, totalBorrowInterestFree, borrowExchangePrice);
    }

    function test_getTotalBorrow_WhenOnlyBorrowInterestFree() public {
        uint256 totalBorrowRaw = 0;
        uint256 totalBorrowInterestFree = 123457984546456;
        uint256 borrowExchangePrice = 1234500000;

        assertExpectedTotalBorrow(totalBorrowRaw, totalBorrowInterestFree, borrowExchangePrice);
    }

    function test_getTotalBorrow_WhenBoth() public {
        uint256 totalBorrowRaw = 123457984546456;
        uint256 totalBorrowInterestFree = 123457984546456;
        uint256 borrowExchangePrice = 1234500000;

        assertExpectedTotalBorrow(totalBorrowRaw, totalBorrowInterestFree, borrowExchangePrice);
    }

    function test_getTotalBorrow_When0() public {
        uint256 totalBorrowRaw = 0;
        uint256 totalBorrowInterestFree = 0;
        uint256 borrowExchangePrice = 1234500000;

        assertExpectedTotalBorrow(totalBorrowRaw, totalBorrowInterestFree, borrowExchangePrice);
    }
}
