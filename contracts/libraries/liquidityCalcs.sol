// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { LibsErrorTypes as ErrorTypes } from "./errorTypes.sol";
import { LiquiditySlotsLink } from "./liquiditySlotsLink.sol";
import { BigMathMinified } from "./bigMathMinified.sol";

/// @notice implements calculation methods used for Fluid liquidity such as updated exchange prices,
/// borrow rate, withdrawal / borrow limits, revenue amount.
library LiquidityCalcs {
    error FluidLiquidityCalcsError(uint256 errorId_);

    /// @notice emitted if the calculated borrow rate surpassed max borrow rate (16 bits) and was capped at maximum value 65535
    event BorrowRateMaxCap();

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
    /// @return supplyExchangePrice_ updated supplyExchangePrice
    /// @return borrowExchangePrice_ updated borrowExchangePrice
    function calcExchangePrices(
        uint256 exchangePricesAndConfig_
    ) internal view returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) {
        // Extracting exchange prices
        supplyExchangePrice_ =
            (exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) &
            X64;
        borrowExchangePrice_ =
            (exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) &
            X64;

        if (supplyExchangePrice_ == 0 || borrowExchangePrice_ == 0) {
            revert FluidLiquidityCalcsError(ErrorTypes.LiquidityCalcs__ExchangePriceZero);
        }

        uint256 temp_ = exchangePricesAndConfig_ & X16; // temp_ = borrowRate

        unchecked {
            // last timestamp can not be > current timestamp
            uint256 secondsSinceLastUpdate_ = block.timestamp -
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
            // ratioSupplyYield = 60% * 83,33333% * (100% + 25%) = 62,5%
            // supplyRate = (40% * (100% - 10%)) * 62,5% = 36% * 62,5% = 22.5%
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
    /// @return revenueAmount_ collectable revenue amount
    function calcRevenue(
        uint256 totalAmounts_,
        uint256 exchangePricesAndConfig_,
        uint256 liquidityTokenBalance_
    ) internal view returns (uint256 revenueAmount_) {
        // @dev no need to super-optimize this method as it is only used by admin

        // calculate the new exchange prices based on earned interest
        (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) = calcExchangePrices(exchangePricesAndConfig_);

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

    ///////////////////////////////////////////////////////////////////////////
    //////////                      CALC LIMITS                       /////////
    ///////////////////////////////////////////////////////////////////////////

    /// @dev calculates withdrawal limit before an operate execution:
    /// amount of user supply that must stay supplied (not amount that can be withdrawn).
    /// i.e. if user has supplied 100m and can withdraw 5M, this method returns the 95M, not the withdrawable amount 5M
    /// @param userSupplyData_ user supply data packed uint256 from storage
    /// @param userSupply_ current user supply amount already extracted from `userSupplyData_` and converted from BigMath
    /// @return currentWithdrawalLimit_ current withdrawal limit updated for expansion since last interaction.
    ///         returned value is in raw for with interest mode, normal amount for interest free mode!
    function calcWithdrawalLimitBeforeOperate(
        uint256 userSupplyData_,
        uint256 userSupply_
    ) internal view returns (uint256 currentWithdrawalLimit_) {
        // @dev must support handling the case where timestamp is 0 (config is set but no interactions yet).
        // first tx where timestamp is 0 will enter `if (lastWithdrawalLimit_ == 0)` because lastWithdrawalLimit_ is not set yet.
        // returning max withdrawal allowed, which is not exactly right but doesn't matter because the first interaction must be
        // a deposit anyway. Important is that it would not revert.

        // Note the first time a deposit brings the user supply amount to above the base withdrawal limit, the active limit
        // is the fully expanded limit immediately.

        // extract last set withdrawal limit
        uint256 lastWithdrawalLimit_ = (userSupplyData_ >>
            LiquiditySlotsLink.BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT) & X64;
        lastWithdrawalLimit_ =
            (lastWithdrawalLimit_ >> DEFAULT_EXPONENT_SIZE) <<
            (lastWithdrawalLimit_ & DEFAULT_EXPONENT_MASK);
        if (lastWithdrawalLimit_ == 0) {
            // withdrawal limit is not activated. Max withdrawal allowed
            return 0;
        }

        uint256 maxWithdrawableLimit_;
        uint256 temp_;
        unchecked {
            // extract max withdrawable percent of user supply and
            // calculate maximum withdrawable amount expandPercentage of user supply at full expansion duration elapsed
            // e.g.: if 10% expandPercentage, meaning 10% is withdrawable after full expandDuration has elapsed.

            // userSupply_ needs to be atleast 1e73 to overflow max limit of ~1e77 in uint256 (no token in existence where this is possible).
            maxWithdrawableLimit_ =
                (((userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) & X14) * userSupply_) /
                FOUR_DECIMALS;

            // time elapsed since last withdrawal limit was set (in seconds)
            // @dev last process timestamp is guaranteed to exist for withdrawal, as a supply must have happened before.
            // last timestamp can not be > current timestamp
            temp_ =
                block.timestamp -
                ((userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP) & X33);
        }
        // calculate withdrawable amount of expandPercent that is elapsed of expandDuration.
        // e.g. if 60% of expandDuration has elapsed, then user should be able to withdraw 6% of user supply, down to 94%.
        // Note: no explicit check for this needed, it is covered by setting minWithdrawalLimit_ if needed.
        temp_ =
            (maxWithdrawableLimit_ * temp_) /
            // extract expand duration: After this, decrement won't happen (user can withdraw 100% of withdraw limit)
            ((userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) & X24); // expand duration can never be 0
        // calculate expanded withdrawal limit: last withdrawal limit - withdrawable amount.
        // Note: withdrawable amount here can grow bigger than userSupply if timeElapsed is a lot bigger than expandDuration,
        // which would cause the subtraction `lastWithdrawalLimit_ - withdrawableAmount_` to revert. In that case, set 0
        // which will cause minimum (fully expanded) withdrawal limit to be set in lines below.
        unchecked {
            // underflow explicitly checked & handled
            currentWithdrawalLimit_ = lastWithdrawalLimit_ > temp_ ? lastWithdrawalLimit_ - temp_ : 0;
            // calculate minimum withdrawal limit: minimum amount of user supply that must stay supplied at full expansion.
            // subtraction can not underflow as maxWithdrawableLimit_ is a percentage amount (<=100%) of userSupply_
            temp_ = userSupply_ - maxWithdrawableLimit_;
        }
        // if withdrawal limit is decreased below minimum then set minimum
        // (e.g. when more than expandDuration time has elapsed)
        if (temp_ > currentWithdrawalLimit_) {
            currentWithdrawalLimit_ = temp_;
        }
    }

    /// @dev calculates withdrawal limit after an operate execution:
    /// amount of user supply that must stay supplied (not amount that can be withdrawn).
    /// i.e. if user has supplied 100m and can withdraw 5M, this method returns the 95M, not the withdrawable amount 5M
    /// @param userSupplyData_ user supply data packed uint256 from storage
    /// @param userSupply_ current user supply amount already extracted from `userSupplyData_` and added / subtracted with the executed operate amount
    /// @param newWithdrawalLimit_ current withdrawal limit updated for expansion since last interaction, result from `calcWithdrawalLimitBeforeOperate`
    /// @return withdrawalLimit_ updated withdrawal limit that should be written to storage. returned value is in
    ///                          raw for with interest mode, normal amount for interest free mode!
    function calcWithdrawalLimitAfterOperate(
        uint256 userSupplyData_,
        uint256 userSupply_,
        uint256 newWithdrawalLimit_
    ) internal pure returns (uint256) {
        // temp_ => base withdrawal limit. below this, maximum withdrawals are allowed
        uint256 temp_ = (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT) & X18;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

        // if user supply is below base limit then max withdrawals are allowed
        if (userSupply_ < temp_) {
            return 0;
        }
        // temp_ => withdrawal limit expandPercent (is in 1e2 decimals)
        temp_ = (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) & X14;
        unchecked {
            // temp_ => minimum withdrawal limit: userSupply - max withdrawable limit (userSupply * expandPercent))
            // userSupply_ needs to be atleast 1e73 to overflow max limit of ~1e77 in uint256 (no token in existence where this is possible).
            // subtraction can not underflow as maxWithdrawableLimit_ is a percentage amount (<=100%) of userSupply_
            temp_ = userSupply_ - ((userSupply_ * temp_) / FOUR_DECIMALS);
        }
        // if new (before operation) withdrawal limit is less than minimum limit then set minimum limit.
        // e.g. can happen on new deposits. withdrawal limit is instantly fully expanded in a scenario where
        // increased deposit amount outpaces withrawals.
        if (temp_ > newWithdrawalLimit_) {
            return temp_;
        }
        return newWithdrawalLimit_;
    }

    /// @dev calculates borrow limit before an operate execution:
    /// total amount user borrow can reach (not borrowable amount in current operation).
    /// i.e. if user has borrowed 50M and can still borrow 5M, this method returns the total 55M, not the borrowable amount 5M
    /// @param userBorrowData_ user borrow data packed uint256 from storage
    /// @param userBorrow_ current user borrow amount already extracted from `userBorrowData_`
    /// @return currentBorrowLimit_ current borrow limit updated for expansion since last interaction. returned value is in
    ///                             raw for with interest mode, normal amount for interest free mode!
    function calcBorrowLimitBeforeOperate(
        uint256 userBorrowData_,
        uint256 userBorrow_
    ) internal view returns (uint256 currentBorrowLimit_) {
        // @dev must support handling the case where timestamp is 0 (config is set but no interactions yet) -> base limit.
        // first tx where timestamp is 0 will enter `if (maxExpandedBorrowLimit_ < baseBorrowLimit_)` because `userBorrow_` and thus
        // `maxExpansionLimit_` and thus `maxExpandedBorrowLimit_` is 0 and `baseBorrowLimit_` can not be 0.

        // temp_ = extract borrow expand percent (is in 1e2 decimals)
        uint256 temp_ = (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & X14;

        uint256 maxExpansionLimit_;
        uint256 maxExpandedBorrowLimit_;
        unchecked {
            // calculate max expansion limit: Max amount limit can expand to since last interaction
            // userBorrow_ needs to be atleast 1e73 to overflow max limit of ~1e77 in uint256 (no token in existence where this is possible).
            maxExpansionLimit_ = ((userBorrow_ * temp_) / FOUR_DECIMALS);

            // calculate max borrow limit: Max point limit can increase to since last interaction
            maxExpandedBorrowLimit_ = userBorrow_ + maxExpansionLimit_;
        }

        // currentBorrowLimit_ = extract base borrow limit
        currentBorrowLimit_ = (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & X18;
        currentBorrowLimit_ =
            (currentBorrowLimit_ >> DEFAULT_EXPONENT_SIZE) <<
            (currentBorrowLimit_ & DEFAULT_EXPONENT_MASK);

        if (maxExpandedBorrowLimit_ < currentBorrowLimit_) {
            return currentBorrowLimit_;
        }
        // time elapsed since last borrow limit was set (in seconds)
        unchecked {
            // temp_ = timeElapsed_ (last timestamp can not be > current timestamp)
            temp_ =
                block.timestamp -
                ((userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP) & X33); // extract last update timestamp
        }

        // currentBorrowLimit_ = expandedBorrowableAmount + extract last set borrow limit
        currentBorrowLimit_ =
            // calculate borrow limit expansion since last interaction for `expandPercent` that is elapsed of `expandDuration`.
            // divisor is extract expand duration (after this, full expansion to expandPercentage happened).
            ((maxExpansionLimit_ * temp_) /
                ((userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_DURATION) & X24)) + // expand duration can never be 0
            //  extract last set borrow limit
            BigMathMinified.fromBigNumber(
                (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT) & X64,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );

        // if timeElapsed is bigger than expandDuration, new borrow limit would be > max expansion,
        // so set to `maxExpandedBorrowLimit_` in that case.
        // also covers the case where last process timestamp = 0 (timeElapsed would simply be very big)
        if (currentBorrowLimit_ > maxExpandedBorrowLimit_) {
            currentBorrowLimit_ = maxExpandedBorrowLimit_;
        }
        // temp_ = extract hard max borrow limit. Above this user can never borrow (not expandable above)
        temp_ = (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

        if (currentBorrowLimit_ > temp_) {
            currentBorrowLimit_ = temp_;
        }
    }

    /// @dev calculates borrow limit after an operate execution:
    /// total amount user borrow can reach (not borrowable amount in current operation).
    /// i.e. if user has borrowed 50M and can still borrow 5M, this method returns the total 55M, not the borrowable amount 5M
    /// @param userBorrowData_ user borrow data packed uint256 from storage
    /// @param userBorrow_ current user borrow amount already extracted from `userBorrowData_` and added / subtracted with the executed operate amount
    /// @param newBorrowLimit_ current borrow limit updated for expansion since last interaction, result from `calcBorrowLimitBeforeOperate`
    /// @return borrowLimit_ updated borrow limit that should be written to storage.
    ///                      returned value is in raw for with interest mode, normal amount for interest free mode!
    function calcBorrowLimitAfterOperate(
        uint256 userBorrowData_,
        uint256 userBorrow_,
        uint256 newBorrowLimit_
    ) internal pure returns (uint256 borrowLimit_) {
        // temp_ = extract borrow expand percent
        uint256 temp_ = (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & X14; // (is in 1e2 decimals)

        unchecked {
            // borrowLimit_ = calculate maximum borrow limit at full expansion.
            // userBorrow_ needs to be at least 1e73 to overflow max limit of ~1e77 in uint256 (no token in existence where this is possible).
            borrowLimit_ = userBorrow_ + ((userBorrow_ * temp_) / FOUR_DECIMALS);
        }

        // temp_ = extract base borrow limit
        temp_ = (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & X18;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

        if (borrowLimit_ < temp_) {
            // below base limit, borrow limit is always base limit
            return temp_;
        }
        // temp_ = extract hard max borrow limit. Above this user can never borrow (not expandable above)
        temp_ = (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

        // make sure fully expanded borrow limit is not above hard max borrow limit
        if (borrowLimit_ > temp_) {
            borrowLimit_ = temp_;
        }
        // if new borrow limit (from before operate) is > max borrow limit, set max borrow limit.
        // (e.g. on a repay shrinking instantly to fully expanded borrow limit from new borrow amount. shrinking is instant)
        if (newBorrowLimit_ > borrowLimit_) {
            return borrowLimit_;
        }
        return newBorrowLimit_;
    }

    ///////////////////////////////////////////////////////////////////////////
    //////////                      CALC RATES                        /////////
    ///////////////////////////////////////////////////////////////////////////

    /// @dev Calculates new borrow rate from utilization for a token
    /// @param rateData_ rate data packed uint256 from storage for the token
    /// @param utilization_ totalBorrow / totalSupply. 1e4 = 100% utilization
    /// @return rate_ rate for that particular token in 1e2 precision (e.g. 5% rate = 500)
    function calcBorrowRateFromUtilization(uint256 rateData_, uint256 utilization_) internal returns (uint256 rate_) {
        // extract rate version: 4 bits (0xF) starting from bit 0
        uint256 rateVersion_ = (rateData_ & 0xF);

        if (rateVersion_ == 1) {
            rate_ = calcRateV1(rateData_, utilization_);
        } else if (rateVersion_ == 2) {
            rate_ = calcRateV2(rateData_, utilization_);
        } else {
            revert FluidLiquidityCalcsError(ErrorTypes.LiquidityCalcs__UnsupportedRateVersion);
        }

        if (rate_ > X16) {
            // hard cap for borrow rate at maximum value 16 bits (65535) to make sure it does not overflow storage space.
            // this is unlikely to ever happen if configs stay within expected levels.
            rate_ = X16;
            // emit event to more easily become aware
            emit BorrowRateMaxCap();
        }
    }

    /// @dev calculates the borrow rate based on utilization for rate data version 1 (with one kink) in 1e2 precision
    /// @param rateData_ rate data packed uint256 from storage for the token
    /// @param utilization_  in 1e2 (100% = 1e4)
    /// @return rate_ rate in 1e2 precision
    function calcRateV1(uint256 rateData_, uint256 utilization_) internal pure returns (uint256 rate_) {
        /// For rate v1 (one kink) ------------------------------------------------------
        /// Next 16  bits =>  4 - 19 => Rate at utilization 0% (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
        /// Next 16  bits =>  20- 35 => Utilization at kink1 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
        /// Next 16  bits =>  36- 51 => Rate at utilization kink1 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
        /// Next 16  bits =>  52- 67 => Rate at utilization 100% (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
        /// Last 188 bits =>  68-255 => blank, might come in use in future

        // y = mx + c.
        // y is borrow rate
        // x is utilization
        // m = slope (m can also be negative for declining rates)
        // c is constant (c can be negative)

        uint256 y1_;
        uint256 y2_;
        uint256 x1_;
        uint256 x2_;

        // extract kink1: 16 bits (0xFFFF) starting from bit 20
        // kink is in 1e2, same as utilization, so no conversion needed for direct comparison of the two
        uint256 kink1_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_UTILIZATION_AT_KINK) & X16;
        if (utilization_ < kink1_) {
            // if utilization is less than kink
            y1_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO) & X16;
            y2_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) & X16;
            x1_ = 0; // 0%
            x2_ = kink1_;
        } else {
            // else utilization is greater than kink
            y1_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) & X16;
            y2_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX) & X16;
            x1_ = kink1_;
            x2_ = FOUR_DECIMALS; // 100%
        }

        int256 constant_;
        int256 slope_;
        unchecked {
            // calculating slope with twelve decimal precision. m = (y2 - y1) / (x2 - x1).
            // utilization of x2 can not be <= utilization of x1 (so no underflow or 0 divisor)
            // y is in 1e2 so can not overflow when multiplied with TWELVE_DECIMALS
            slope_ = (int256(y2_ - y1_) * int256(TWELVE_DECIMALS)) / int256((x2_ - x1_));

            // calculating constant at 12 decimal precision. slope is already in 12 decimal hence only multiple with y1. c = y - mx.
            // maximum y1_ value is 65535. 65535 * 1e12 can not overflow int256
            // maximum slope is 65535 - 0 * TWELVE_DECIMALS / 1 = 65535 * 1e12;
            // maximum x1_ is 100% (9_999 actually) => slope_ * x1_ can not overflow int256
            // subtraction most extreme case would be  0 - max value slope_ * x1_ => can not underflow int256
            constant_ = int256(y1_ * TWELVE_DECIMALS) - (slope_ * int256(x1_));

            // calculating new borrow rate
            // - slope_ max value is 65535 * 1e12,
            // - utilization max value is let's say 500% (extreme case where borrow rate increases borrow amount without new supply)
            // - constant max value is 65535 * 1e12
            // so max values are 65535 * 1e12 * 50_000 + 65535 * 1e12 -> 3.2768*10^21, which easily fits int256
            // divisor TWELVE_DECIMALS can not be 0
            slope_ = (slope_ * int256(utilization_)) + constant_; // reusing `slope_` as variable for gas savings
            if (slope_ < 0) {
                revert FluidLiquidityCalcsError(ErrorTypes.LiquidityCalcs__BorrowRateNegative);
            }
            rate_ = uint256(slope_) / TWELVE_DECIMALS;
        }
    }

    /// @dev calculates the borrow rate based on utilization for rate data version 2 (with two kinks) in 1e4 precision
    /// @param rateData_ rate data packed uint256 from storage for the token
    /// @param utilization_  in 1e2 (100% = 1e4)
    /// @return rate_ rate in 1e4 precision
    function calcRateV2(uint256 rateData_, uint256 utilization_) internal pure returns (uint256 rate_) {
        /// For rate v2 (two kinks) -----------------------------------------------------
        /// Next 16  bits =>  4 - 19 => Rate at utilization 0% (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
        /// Next 16  bits =>  20- 35 => Utilization at kink1 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
        /// Next 16  bits =>  36- 51 => Rate at utilization kink1 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
        /// Next 16  bits =>  52- 67 => Utilization at kink2 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
        /// Next 16  bits =>  68- 83 => Rate at utilization kink2 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
        /// Next 16  bits =>  84- 99 => Rate at utilization 100% (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
        /// Last 156 bits => 100-255 => blank, might come in use in future

        // y = mx + c.
        // y is borrow rate
        // x is utilization
        // m = slope (m can also be negative for declining rates)
        // c is constant (c can be negative)

        uint256 y1_;
        uint256 y2_;
        uint256 x1_;
        uint256 x2_;

        // extract kink1: 16 bits (0xFFFF) starting from bit 20
        // kink is in 1e2, same as utilization, so no conversion needed for direct comparison of the two
        uint256 kink1_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK1) & X16;
        if (utilization_ < kink1_) {
            // if utilization is less than kink1
            y1_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_ZERO) & X16;
            y2_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK1) & X16;
            x1_ = 0; // 0%
            x2_ = kink1_;
        } else {
            // extract kink2: 16 bits (0xFFFF) starting from bit 52
            uint256 kink2_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK2) & X16;
            if (utilization_ < kink2_) {
                // if utilization is less than kink2
                y1_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK1) & X16;
                y2_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK2) & X16;
                x1_ = kink1_;
                x2_ = kink2_;
            } else {
                // else utilization is greater than kink2
                y1_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK2) & X16;
                y2_ = (rateData_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_MAX) & X16;
                x1_ = kink2_;
                x2_ = FOUR_DECIMALS;
            }
        }

        int256 constant_;
        int256 slope_;
        unchecked {
            // calculating slope with twelve decimal precision. m = (y2 - y1) / (x2 - x1).
            // utilization of x2 can not be <= utilization of x1 (so no underflow or 0 divisor)
            // y is in 1e2 so can not overflow when multiplied with TWELVE_DECIMALS
            slope_ = (int256(y2_ - y1_) * int256(TWELVE_DECIMALS)) / int256((x2_ - x1_));

            // calculating constant at 12 decimal precision. slope is already in 12 decimal hence only multiple with y1. c = y - mx.
            // maximum y1_ value is 65535. 65535 * 1e12 can not overflow int256
            // maximum slope is 65535 - 0 * TWELVE_DECIMALS / 1 = 65535 * 1e12;
            // maximum x1_ is 100% (9_999 actually) => slope_ * x1_ can not overflow int256
            // subtraction most extreme case would be  0 - max value slope_ * x1_ => can not underflow int256
            constant_ = int256(y1_ * TWELVE_DECIMALS) - (slope_ * int256(x1_));

            // calculating new borrow rate
            // - slope_ max value is 65535 * 1e12,
            // - utilization max value is let's say 500% (extreme case where borrow rate increases borrow amount without new supply)
            // - constant max value is 65535 * 1e12
            // so max values are 65535 * 1e12 * 50_000 + 65535 * 1e12 -> 3.2768*10^21, which easily fits int256
            // divisor TWELVE_DECIMALS can not be 0
            slope_ = (slope_ * int256(utilization_)) + constant_; // reusing `slope_` as variable for gas savings
            if (slope_ < 0) {
                revert FluidLiquidityCalcsError(ErrorTypes.LiquidityCalcs__BorrowRateNegative);
            }
            rate_ = uint256(slope_) / TWELVE_DECIMALS;
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
