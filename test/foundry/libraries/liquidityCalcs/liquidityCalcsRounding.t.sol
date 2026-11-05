//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LibraryLiquidityCalcsBaseTest } from "./liquidityCalcsBaseTest.t.sol";

import "forge-std/console2.sol";

/// @notice Borrow exchange price accrual rounds up, and calcRevenue never overestimates revenue.
contract LibraryLiquidityCalcsRoundingTests is LibraryLiquidityCalcsBaseTest {
    uint256 constant EXCHANGE_PRICES_PRECISION = 1e12;
    uint256 constant SECONDS_PER_YEAR = 365 days;
    uint256 constant FOUR_DECIMALS = 1e4;

    function _config(
        uint256 borrowRate_,
        uint256 lastUpdateTimestamp_,
        uint256 supplyExchangePrice_,
        uint256 borrowExchangePrice_
    ) internal pure returns (uint256) {
        return
            _simulateExchangePricesAndConfig(
                borrowRate_,
                0, // fee
                5000, // utilization 50%
                0, // updateOnStorageThreshold
                lastUpdateTimestamp_,
                supplyExchangePrice_,
                borrowExchangePrice_,
                0, // supplyRatioMode
                5000, // supplyRatio
                0, // borrowRatioMode
                5000 // borrowRatio
            );
    }

    // ############### borrow exchange price accrual rounds up ###############

    /// @dev the exact increment the contract must apply: ceil(price * rate * elapsed / (year * 1e4))
    function _expectedCeilIncrease(uint256 price_, uint256 rate_, uint256 elapsed_) internal pure returns (uint256) {
        uint256 numerator_ = price_ * rate_ * elapsed_;
        uint256 divisor_ = SECONDS_PER_YEAR * FOUR_DECIMALS;
        return (numerator_ + divisor_ - 1) / divisor_;
    }

    function test_borrowExchangePrice_roundsUp_whenDivisionInexact() public {
        uint256 borrowPrice_ = EXCHANGE_PRICES_PRECISION;
        uint256 rate_ = 1; // 0.01%
        uint256 elapsed_ = 1;
        uint256 divisor_ = SECONDS_PER_YEAR * FOUR_DECIMALS;

        uint256 floorIncrease_ = (borrowPrice_ * rate_ * elapsed_) / divisor_;
        assertGt((borrowPrice_ * rate_ * elapsed_) % divisor_, 0, "precondition: division is inexact");

        vm.warp(1000000);
        uint256 config_ = _config(rate_, block.timestamp - elapsed_, EXCHANGE_PRICES_PRECISION, borrowPrice_);

        (, uint256 newBorrowPrice_) = testHelper.calcExchangePrices(config_);

        // the pre-fix code applied floorIncrease_; the fix must apply exactly one wei more
        assertEq(
            newBorrowPrice_,
            borrowPrice_ + floorIncrease_ + 1,
            "borrow price must round up when the accrual division leaves a remainder"
        );
    }

    function test_borrowExchangePrice_doesNotOverchargeOnExactDivision() public {
        // pick elapsed so that price * rate * elapsed is an exact multiple of (year * 1e4):
        // divisor = 365 days * 1e4 = 315_360_000_000. With price 1e12 and rate 10_000, numerator = 1e16 * elapsed.
        // 1e16 * elapsed % 315_360_000_000 == 0 for elapsed = 3_942 (verified below by assertion).
        uint256 borrowPrice_ = EXCHANGE_PRICES_PRECISION;
        uint256 rate_ = 10000;
        uint256 divisor_ = SECONDS_PER_YEAR * FOUR_DECIMALS;

        // find the smallest elapsed making the division exact
        uint256 elapsed_;
        for (uint256 i = 1; i < 100000; i++) {
            if ((borrowPrice_ * rate_ * i) % divisor_ == 0) {
                elapsed_ = i;
                break;
            }
        }
        assertGt(elapsed_, 0, "precondition: found an exact-division elapsed");

        vm.warp(block.timestamp + 1000000);
        uint256 config_ = _config(rate_, block.timestamp - elapsed_, EXCHANGE_PRICES_PRECISION, borrowPrice_);

        (, uint256 newBorrowPrice_) = testHelper.calcExchangePrices(config_);

        uint256 exactIncrease_ = (borrowPrice_ * rate_ * elapsed_) / divisor_;
        // ceil must NOT add a wei when the division is exact (this is what `x / y + 1` would get wrong)
        assertEq(newBorrowPrice_, borrowPrice_ + exactIncrease_, "must not overcharge on exact division");
    }

    function testFuzz_borrowExchangePrice_matchesCeilAndNeverFloors(
        uint16 rate_,
        uint32 elapsed_,
        uint64 borrowPrice_
    ) public {
        vm.assume(rate_ > 0);
        vm.assume(elapsed_ > 0);
        vm.assume(borrowPrice_ >= EXCHANGE_PRICES_PRECISION);

        vm.warp(uint256(elapsed_) + 1000000);
        uint256 config_ = _config(rate_, block.timestamp - elapsed_, EXCHANGE_PRICES_PRECISION, borrowPrice_);

        (, uint256 newBorrowPrice_) = testHelper.calcExchangePrices(config_);

        uint256 expected_ = uint256(borrowPrice_) + _expectedCeilIncrease(borrowPrice_, rate_, elapsed_);
        assertEq(newBorrowPrice_, expected_, "borrow price must equal exact ceiling accrual");

        // the security property: ceil is always >= floor, and never more than 1 above it
        uint256 floorPrice_ = uint256(borrowPrice_) +
            (uint256(borrowPrice_) * rate_ * elapsed_) /
            (SECONDS_PER_YEAR * FOUR_DECIMALS);
        assertGe(newBorrowPrice_, floorPrice_, "must never round below floor (would erode solvency)");
        assertLe(newBorrowPrice_ - floorPrice_, 1, "must never exceed floor by more than 1 wei");
    }

    // ############### calcRevenue must not overestimate revenue ###############

    function test_getTotalSupply_roundUpFlag_semantics() public {
        // supplyWithInterest raw chosen so raw * price / 1e12 is inexact
        uint256 rawSupply_ = 3;
        uint256 price_ = EXCHANGE_PRICES_PRECISION + 1; // 3 * (1e12+1) / 1e12 = 3.000000000003 -> floor 3, ceil 4
        uint256 totalAmounts_ = _simulateTotalAmounts(rawSupply_, 0, 0, 0);

        uint256 floorSupply_ = testHelper.getTotalSupply(totalAmounts_, price_, false);
        uint256 ceilSupply_ = testHelper.getTotalSupply(totalAmounts_, price_, true);

        assertEq(ceilSupply_, floorSupply_ + 1, "ceil must be exactly one above floor when division is inexact");

        // backwards-compatible 2-arg overload must behave exactly like roundUp_ = false
        assertEq(
            testHelper.getTotalSupply(totalAmounts_, price_),
            floorSupply_,
            "2-arg overload must keep floor semantics"
        );
    }

    function test_getTotalSupply_roundUp_noChangeOnExactDivision() public {
        uint256 totalAmounts_ = _simulateTotalAmounts(5 ether, 1 ether, 0, 0);
        // exact price -> raw * 1e12 / 1e12 is exact, ceil must not add anything
        assertEq(
            testHelper.getTotalSupply(totalAmounts_, EXCHANGE_PRICES_PRECISION, true),
            testHelper.getTotalSupply(totalAmounts_, EXCHANGE_PRICES_PRECISION, false),
            "ceil must equal floor when division is exact"
        );
    }

    function testFuzz_getTotalSupply_ceilIsNeverBelowFloor(uint64 rawSupply_, uint64 price_) public {
        vm.assume(price_ >= EXCHANGE_PRICES_PRECISION);
        uint256 totalAmounts_ = _simulateTotalAmounts(rawSupply_, 0, 0, 0);

        uint256 floorSupply_ = testHelper.getTotalSupply(totalAmounts_, price_, false);
        uint256 ceilSupply_ = testHelper.getTotalSupply(totalAmounts_, price_, true);

        assertGe(ceilSupply_, floorSupply_, "ceil must never be below floor");
        assertLe(ceilSupply_ - floorSupply_, 1, "ceil must never exceed floor by more than 1");
    }

    function testFuzz_calcRevenue_neverExceedsFloorBasedRevenue(
        uint64 rawSupply_,
        uint64 supplyInterestFree_,
        uint128 balance_
    ) public {
        vm.assume(rawSupply_ > 0);

        uint256 supplyExchangePrice_ = EXCHANGE_PRICES_PRECISION + 12345678;
        uint256 totalAmounts_ = _simulateTotalAmounts(rawSupply_, supplyInterestFree_, 0, 0);
        uint256 config_ = _config(0, block.timestamp, supplyExchangePrice_, EXCHANGE_PRICES_PRECISION);

        uint256 revenue_ = testHelper.calcRevenue(totalAmounts_, config_, balance_);

        // revenue computed against the (larger) ceil-rounded total supply must never exceed
        // what a floor-rounded total supply would have yielded: the protocol can only ever claim less.
        uint256 floorTotalSupply_ = testHelper.getTotalSupply(totalAmounts_, supplyExchangePrice_, false);
        uint256 revenueWithFloorSupply_ = balance_ > floorTotalSupply_ ? balance_ - floorTotalSupply_ : 0;

        assertLe(revenue_, revenueWithFloorSupply_, "revenue must never be overestimated vs floor-rounded supply");
    }

    function test_calcRevenue_doesNotDipIntoSupplierFunds() public {
        // balance exactly equals what depositors are owed (ceil-rounded) -> revenue must be 0
        uint256 rawSupply_ = 7;
        uint256 supplyExchangePrice_ = EXCHANGE_PRICES_PRECISION + 1;
        uint256 totalAmounts_ = _simulateTotalAmounts(rawSupply_, 0, 0, 0);
        uint256 config_ = _config(0, block.timestamp, supplyExchangePrice_, EXCHANGE_PRICES_PRECISION);

        uint256 owedToDepositors_ = testHelper.getTotalSupply(totalAmounts_, supplyExchangePrice_, true);

        assertEq(
            testHelper.calcRevenue(totalAmounts_, config_, owedToDepositors_),
            0,
            "no revenue when balance only covers what depositors are owed"
        );
    }
}
