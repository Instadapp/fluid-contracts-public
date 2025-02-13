// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { LibsErrorTypes as ErrorTypes } from "../../../libraries/errorTypes.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";

/// @dev this is the exact same code as `LiquidityCalcs` library, just that it supports a simulated
/// block.timestamp to expose historical calculations.
library CalcsSimulatedTime {
    error FluidCalcsSimulatedTimeError(uint256 errorId_);
    error FluidCalcsSimulatedTimeInvalidTimestamp();

    /// @dev constants as from Liquidity variables.sol
    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    /// @dev Ignoring leap years
    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    // constants used for BigMath conversion from and to storage
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    uint256 internal constant FOUR_DECIMALS = 1e4;
    uint256 internal constant TWELVE_DECIMALS = 1e12;
    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X15 = 0x7fff;
    uint256 internal constant X16 = 0xffff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X24 = 0xffffff;
    uint256 internal constant X33 = 0x1ffffffff;
    uint256 internal constant X64 = 0xffffffffffffffff;

    ///////////////////////////////////////////////////////////////////////////
    //////////                  CALC EXCHANGE PRICES                  /////////
    ///////////////////////////////////////////////////////////////////////////

    /// @dev calculates interest (exchange prices) for a token given its' exchangePricesAndConfig from storage.
    /// @param exchangePricesAndConfig_ exchange prices and config packed uint256 read from storage
    /// @param blockTimestamp_ simulated block.timestamp
    /// @return supplyExchangePrice_ updated supplyExchangePrice
    /// @return borrowExchangePrice_ updated borrowExchangePrice
    function calcExchangePrices(
        uint256 exchangePricesAndConfig_,
        uint256 blockTimestamp_
    ) internal pure returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) {
        // Extracting exchange prices
        supplyExchangePrice_ =
            (exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) &
            X64;
        borrowExchangePrice_ =
            (exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) &
            X64;

        if (supplyExchangePrice_ == 0 || borrowExchangePrice_ == 0) {
            revert FluidCalcsSimulatedTimeError(ErrorTypes.LiquidityCalcs__ExchangePriceZero);
        }

        uint256 temp_ = exchangePricesAndConfig_ & X16; // temp_ = borrowRate

        // @dev HERE CUSTOM: added check for simulated timestamp
        if (
            blockTimestamp_ <
            ((exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) & X33)
        ) {
            revert FluidCalcsSimulatedTimeInvalidTimestamp();
        }

        unchecked {
            // last timestamp can not be > current timestamp
            uint256 secondsSinceLastUpdate_ = blockTimestamp_ -
                ((exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) & X33);

            uint256 borrowRatio_ = (exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_RATIO) &
                X15;
            if (secondsSinceLastUpdate_ == 0 || temp_ == 0 || borrowRatio_ == 1) {
                // if no time passed, borrow rate is 0, or no raw borrowings: no exchange price update needed
                // (if borrowRatio_ == 1 means there is only borrowInterestFree, as first bit is 1 and rest is 0)
                return (supplyExchangePrice_, borrowExchangePrice_);
            }

            // calculate new borrow exchange price.
            // formula borrowExchangePriceIncrease: previous price * borrow rate * secondsSinceLastUpdate_.
            // nominator is max uint112 (uint64 * uint16 * uint32). Divisor can not be 0.
            borrowExchangePrice_ +=
                (borrowExchangePrice_ * temp_ * secondsSinceLastUpdate_) /
                (SECONDS_PER_YEAR * FOUR_DECIMALS);

            // FOR SUPPLY EXCHANGE PRICE:
            // all yield paid by borrowers (in mode with interest) goes to suppliers in mode with interest.
            // formula: previous price * supply rate * secondsSinceLastUpdate_.
            // where supply rate = (borrow rate  - revenueFee%) * ratioSupplyYield. And
            // ratioSupplyYield = utilization * supplyRatio * borrowRatio
            //
            // Example:
            // supplyRawInterest is 80, supplyInterestFree is 20. totalSupply is 100. BorrowedRawInterest is 50.
            // BorrowInterestFree is 10. TotalBorrow is 60. borrow rate 40%, revenueFee 10%.
            // yield is 10 (so half a year must have passed).
            // supplyRawInterest must become worth 89. totalSupply must become 109. BorrowedRawInterest must become 60.
            // borrowInterestFree must still be 10. supplyInterestFree still 20. totalBorrow 70.
            // supplyExchangePrice would have to go from 1 to 1,125 (+ 0.125). borrowExchangePrice from 1 to 1,2 (+0.2).
            // utilization is 60%. supplyRatio = 20 / 80 = 25% (only 80% of lenders receiving yield).
            // borrowRatio = 10 / 50 = 20% (only 83,333% of borrowers paying yield):
            // x of borrowers paying yield = 100% - (20 / (100 + 20)) = 100% - 16.6666666% = 83,333%.
            // ratioSupplyYield = 60% * 83,33333% * (100% + 20%) = 62,5%
            // supplyRate = (40% * (100% - 10%)) * = 36% * 62,5% = 22.5%
            // increase in supplyExchangePrice, assuming 100 as previous price.
            // 100 * 22,5% * 1/2 (half a year) = 0,1125.
            // cross-check supplyRawInterest worth = 80 * 1.1125 = 89. totalSupply worth = 89 + 20.

            // -------------- 1. calculate ratioSupplyYield --------------------------------
            // step1: utilization * supplyRatio (or actually part of lenders receiving yield)

            // temp_ => supplyRatio (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
            // if first bit 0 then ratio is supplyInterestFree / supplyWithInterest (supplyWithInterest is bigger)
            // else ratio is supplyWithInterest / supplyInterestFree (supplyInterestFree is bigger)
            temp_ = (exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_RATIO) & X15;

            if (temp_ == 1) {
                // if no raw supply: no exchange price update needed
                // (if supplyRatio_ == 1 means there is only supplyInterestFree, as first bit is 1 and rest is 0)
                return (supplyExchangePrice_, borrowExchangePrice_);
            }

            // ratioSupplyYield precision is 1e27 as 100% for increased precision when supplyInterestFree > supplyWithInterest
            if (temp_ & 1 == 1) {
                // ratio is supplyWithInterest / supplyInterestFree (supplyInterestFree is bigger)
                temp_ = temp_ >> 1;

                // Note: case where temp_ == 0 (only supplyInterestFree, no yield) already covered by early return
                // in the if statement a little above.

                // based on above example but supplyRawInterest is 20, supplyInterestFree is 80. no fee.
                // supplyRawInterest must become worth 30. totalSupply must become 110.
                // supplyExchangePrice would have to go from 1 to 1,5. borrowExchangePrice from 1 to 1,2.
                // so ratioSupplyYield must come out as 2.5 (250%).
                // supplyRatio would be (20 * 10_000 / 80) = 2500. but must be inverted.
                temp_ = (1e27 * FOUR_DECIMALS) / temp_; // e.g. 1e31 / 2500 = 4e27. (* 1e27 for precision)
                // e.g. 5_000 * (1e27 + 4e27) / 1e27 = 25_000 (=250%).
                temp_ =
                    // utilization * (100% + 100% / supplyRatio)
                    (((exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) & X14) *
                        (1e27 + temp_)) / // extract utilization (max 16_383 so there is no way this can overflow).
                    (FOUR_DECIMALS);
                // max possible value of temp_ here is 16383 * (1e27 + 1e31) / 1e4 = ~1.64e31
            } else {
                // ratio is supplyInterestFree / supplyWithInterest (supplyWithInterest is bigger)
                temp_ = temp_ >> 1;
                // if temp_ == 0 then only supplyWithInterest => full yield. temp_ is already 0

                // e.g. 5_000 * 10_000 + (20 * 10_000 / 80) / 10_000 = 5000 * 12500 / 10000 = 6250 (=62.5%).
                temp_ =
                    // 1e27 * utilization * (100% + supplyRatio) / 100%
                    (1e27 *
                        ((exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) & X14) * // extract utilization (max 16_383 so there is no way this can overflow).
                        (FOUR_DECIMALS + temp_)) /
                    (FOUR_DECIMALS * FOUR_DECIMALS);
                // max possible temp_ value: 1e27 * 16383 * 2e4 / 1e8 = 3.2766e27
            }
            // from here temp_ => ratioSupplyYield (utilization * supplyRatio part) scaled by 1e27. max possible value ~1.64e31

            // step2 of ratioSupplyYield: add borrowRatio (only x% of borrowers paying yield)
            if (borrowRatio_ & 1 == 1) {
                // ratio is borrowWithInterest / borrowInterestFree (borrowInterestFree is bigger)
                borrowRatio_ = borrowRatio_ >> 1;
                // borrowRatio_ => x of total bororwers paying yield. scale to 1e27.

                // Note: case where borrowRatio_ == 0 (only borrowInterestFree, no yield) already covered
                // at the beginning of the method by early return if `borrowRatio_ == 1`.

                // based on above example but borrowRawInterest is 10, borrowInterestFree is 50. no fee. borrowRatio = 20%.
                // so only 16.66% of borrowers are paying yield. so the 100% - part of the formula is not needed.
                // x of borrowers paying yield = (borrowRatio / (100 + borrowRatio)) = 16.6666666%
                // borrowRatio_ => x of total bororwers paying yield. scale to 1e27.
                borrowRatio_ = (borrowRatio_ * 1e27) / (FOUR_DECIMALS + borrowRatio_);
                // max value here for borrowRatio_ is (1e31 / (1e4 + 1e4))= 5e26 (= 50% of borrowers paying yield).
            } else {
                // ratio is borrowInterestFree / borrowWithInterest (borrowWithInterest is bigger)
                borrowRatio_ = borrowRatio_ >> 1;

                // borrowRatio_ => x of total bororwers paying yield. scale to 1e27.
                // x of borrowers paying yield = 100% - (borrowRatio / (100 + borrowRatio)) = 100% - 16.6666666% = 83,333%.
                borrowRatio_ = (1e27 - ((borrowRatio_ * 1e27) / (FOUR_DECIMALS + borrowRatio_)));
                // borrowRatio can never be > 100%. so max subtraction can be 100% - 100% / 200%.
                // or if borrowRatio_ is 0 -> 100% - 0. or if borrowRatio_ is 1 -> 100% - 1 / 101.
                // max value here for borrowRatio_ is 1e27 - 0 = 1e27 (= 100% of borrowers paying yield).
            }

            // temp_ => ratioSupplyYield. scaled down from 1e25 = 1% each to normal percent precision 1e2 = 1%.
            // max nominator value is ~1.64e31 * 1e27 = 1.64e58. max result = 1.64e8
            temp_ = (FOUR_DECIMALS * temp_ * borrowRatio_) / 1e54;

            // 2. calculate supply rate
            // temp_ => supply rate (borrow rate  - revenueFee%) * ratioSupplyYield.
            // division part is done in next step to increase precision. (divided by 2x FOUR_DECIMALS, fee + borrowRate)
            // Note that all calculation divisions for supplyExchangePrice are rounded down.
            // Note supply rate can be bigger than the borrowRate, e.g. if there are only few lenders with interest
            // but more suppliers not earning interest.
            temp_ = ((exchangePricesAndConfig_ & X16) * // borrow rate
                temp_ * // ratioSupplyYield
                (FOUR_DECIMALS - ((exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_FEE) & X14))); // revenueFee
            // fee can not be > 100%. max possible = 65535 * ~1.64e8 * 1e4 =~1.074774e17.

            // 3. calculate increase in supply exchange price
            supplyExchangePrice_ += ((supplyExchangePrice_ * temp_ * secondsSinceLastUpdate_) /
                (SECONDS_PER_YEAR * FOUR_DECIMALS * FOUR_DECIMALS * FOUR_DECIMALS));
            // max possible nominator = max uint 64 * 1.074774e17 * max uint32 = ~8.52e45. Denominator can not be 0.
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    //////////                     CALC REVENUE                       /////////
    ///////////////////////////////////////////////////////////////////////////

    /// @dev gets the `revenueAmount_` for a token given its' totalAmounts and exchangePricesAndConfig from storage
    /// and the current balance of the Fluid liquidity contract for the token.
    /// @param totalAmounts_ total amounts packed uint256 read from storage
    /// @param exchangePricesAndConfig_ exchange prices and config packed uint256 read from storage
    /// @param liquidityTokenBalance_   current balance of Liquidity contract (IERC20(token_).balanceOf(address(this)))
    /// @param blockTimestamp_ simulated block.timestamp
    /// @return revenueAmount_ collectable revenue amount
    function calcRevenue(
        uint256 totalAmounts_,
        uint256 exchangePricesAndConfig_,
        uint256 liquidityTokenBalance_,
        uint256 blockTimestamp_
    ) internal pure returns (uint256 revenueAmount_) {
        // @dev no need to super-optimize this method as it is only used by admin

        // calculate the new exchange prices based on earned interest
        (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) = calcExchangePrices(
            exchangePricesAndConfig_,
            blockTimestamp_
        );

        // total supply = interest free + with interest converted from raw
        uint256 totalSupply_ = getTotalSupply(totalAmounts_, supplyExchangePrice_);

        if (totalSupply_ > 0) {
            // available revenue: balanceOf(token) + totalBorrowings - totalLendings.
            revenueAmount_ = liquidityTokenBalance_ + getTotalBorrow(totalAmounts_, borrowExchangePrice_);
            // ensure there is no possible case because of rounding etc. where this would revert,
            // explicitly check if >
            revenueAmount_ = revenueAmount_ > totalSupply_ ? revenueAmount_ - totalSupply_ : 0;
            // Note: if utilization > 100% (totalSupply < totalBorrow), then all the amount above 100% utilization
            // can only be revenue.
        } else {
            // if supply is 0, then rest of balance can be withdrawn as revenue so that no amounts get stuck
            revenueAmount_ = liquidityTokenBalance_;
        }
    }

    /// @dev reads the total supply out of Liquidity packed storage `totalAmounts_` for `supplyExchangePrice_`
    function getTotalSupply(
        uint256 totalAmounts_,
        uint256 supplyExchangePrice_
    ) internal pure returns (uint256 totalSupply_) {
        // totalSupply_ => supplyInterestFree
        totalSupply_ = (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_SUPPLY_INTEREST_FREE) & X64;
        totalSupply_ = (totalSupply_ >> DEFAULT_EXPONENT_SIZE) << (totalSupply_ & DEFAULT_EXPONENT_MASK);

        uint256 totalSupplyRaw_ = totalAmounts_ & X64; // no shifting as supplyRaw is first 64 bits
        totalSupplyRaw_ = (totalSupplyRaw_ >> DEFAULT_EXPONENT_SIZE) << (totalSupplyRaw_ & DEFAULT_EXPONENT_MASK);

        // totalSupply = supplyInterestFree + supplyRawInterest normalized from raw
        totalSupply_ += ((totalSupplyRaw_ * supplyExchangePrice_) / EXCHANGE_PRICES_PRECISION);
    }

    /// @dev reads the total borrow out of Liquidity packed storage `totalAmounts_` for `borrowExchangePrice_`
    function getTotalBorrow(
        uint256 totalAmounts_,
        uint256 borrowExchangePrice_
    ) internal pure returns (uint256 totalBorrow_) {
        // totalBorrow_ => borrowInterestFree
        // no & mask needed for borrow interest free as it occupies the last bits in the storage slot
        totalBorrow_ = (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_INTEREST_FREE);
        totalBorrow_ = (totalBorrow_ >> DEFAULT_EXPONENT_SIZE) << (totalBorrow_ & DEFAULT_EXPONENT_MASK);

        uint256 totalBorrowRaw_ = (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST) & X64;
        totalBorrowRaw_ = (totalBorrowRaw_ >> DEFAULT_EXPONENT_SIZE) << (totalBorrowRaw_ & DEFAULT_EXPONENT_MASK);

        // totalBorrow = borrowInterestFree + borrowRawInterest normalized from raw
        totalBorrow_ += ((totalBorrowRaw_ * borrowExchangePrice_) / EXCHANGE_PRICES_PRECISION);
    }
}
