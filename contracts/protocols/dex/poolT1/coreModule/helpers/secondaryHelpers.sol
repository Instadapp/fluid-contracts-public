// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";

import { UserHelpers } from "./userHelpers.sol";
import { ErrorTypes } from "../../../errorTypes.sol";
import { SafeTransfer } from "../../../../../libraries/safeTransfer.sol";
import { BigMathMinified } from "../../../../../libraries/bigMathMinified.sol";
import { AddressCalcs } from "../../../../../libraries/addressCalcs.sol";

abstract contract SecondaryHelpers is UserHelpers {
    using BigMathMinified for uint256;

    constructor(ConstantViews memory constantViews_) UserHelpers(constantViews_) {}

    /// @param c_ tokenA amount to swap and deposit
    /// @param d_ tokenB imaginary reserves
    /// @param e_ tokenA imaginary reserves
    /// @param f_ tokenA real reserves
    /// @param i_ tokenB real reserves
    function _getSwapAndDeposit(uint c_, uint d_, uint e_, uint f_, uint i_) internal pure returns (uint shares_) {
        // swap and deposit in equal proportion

        // tokenAx = c
        // imaginaryTokenBReserves = d
        // imaginaryTokenAReserves = e
        // tokenAReserves = f
        // tokenBReserves = i

        // Quadratic equations, A, B & C are:
        // A = i
        // B = (ie - ic + dc + fd)
        // C = -iec

        // final equation:
        // token to swap = (−(c⋅d−c⋅i+d⋅f+e⋅i) + (4⋅c⋅e⋅i^2 + (c⋅d−c⋅i+d⋅f+e⋅i)^2)^0.5) / 2⋅i
        // B = (c⋅d−c⋅i+d⋅f+e⋅i)
        // token to swap = (−B + (4⋅c⋅e⋅i^2 + (B)^2)^0.5) / 2⋅i
        // simplifying above equation by dividing the entire equation by i:
        // token to swap = (−B/i + (4⋅c⋅e + (B/i)^2)^0.5) / 2
        // note: d > i always, so dividing won't be an issue

        // temp_ => B/i
        uint temp_ = (c_ * d_ + d_ * f_ + e_ * i_ - c_ * i_) / i_;
        uint temp2_ = 4 * c_ * e_;
        uint amtToSwap_ = (FixedPointMathLib.sqrt((temp2_ + (temp_ * temp_))) - temp_) / 2;

        // Ensure the amount to swap is within reasonable bounds:
        // - Not greater than 99.9999% of the input amount (c_)
        // - Not less than 0.0001% of the input amount (c_)
        // This prevents extreme scenarios and maybe potential precision issues
        if ((amtToSwap_ > ((c_ * (SIX_DECIMALS - 1)) / SIX_DECIMALS)) || (amtToSwap_ < (c_ / SIX_DECIMALS)))
            revert FluidDexError(ErrorTypes.DexT1__SwapAndDepositTooLowOrTooHigh);

        // temp_ => amt0ToDeposit
        temp_ = c_ - amtToSwap_;
        // (imaginaryTokenBReserves * amtToSwap_) / (imaginaryTokenAReserves + amtToSwap_)
        // temp2_ => amt1ToDeposit_
        temp2_ = (d_ * amtToSwap_) / (e_ + amtToSwap_);

        // temp_ => shares1
        temp_ = (temp_ * 1e18) / (f_ + amtToSwap_);
        // temp2_ => shares1
        temp2_ = (temp2_ * 1e18) / (i_ - temp2_);
        // temp_ & temp2 should be same. Although, due to some possible precision loss taking the lower one
        shares_ = temp_ > temp2_ ? temp2_ : temp_;
    }

    /// @notice Updates collateral reserves based on minting or burning of shares
    /// @param newShares_ The number of new shares being minted or burned
    /// @param totalOldShares_ The total number of shares before the operation
    /// @param c_ The current collateral reserves
    /// @param mintOrBurn_ True if minting shares, false if burning shares
    /// @return c2_ The updated collateral reserves after the operation
    function _getUpdatedColReserves(
        uint newShares_,
        uint totalOldShares_,
        CollateralReserves memory c_,
        bool mintOrBurn_ // true if mint, false if burn
    ) internal pure returns (CollateralReserves memory c2_) {
        if (mintOrBurn_) {
            // If minting, increase reserves proportionally to new shares
            c2_.token0RealReserves = c_.token0RealReserves + (c_.token0RealReserves * newShares_) / totalOldShares_;
            c2_.token1RealReserves = c_.token1RealReserves + (c_.token1RealReserves * newShares_) / totalOldShares_;
            c2_.token0ImaginaryReserves =
                c_.token0ImaginaryReserves +
                (c_.token0ImaginaryReserves * newShares_) /
                totalOldShares_;
            c2_.token1ImaginaryReserves =
                c_.token1ImaginaryReserves +
                (c_.token1ImaginaryReserves * newShares_) /
                totalOldShares_;
        } else {
            // If burning, decrease reserves proportionally to burned shares
            c2_.token0RealReserves = c_.token0RealReserves - ((c_.token0RealReserves * newShares_) / totalOldShares_);
            c2_.token1RealReserves = c_.token1RealReserves - ((c_.token1RealReserves * newShares_) / totalOldShares_);
            c2_.token0ImaginaryReserves =
                c_.token0ImaginaryReserves -
                ((c_.token0ImaginaryReserves * newShares_) / totalOldShares_);
            c2_.token1ImaginaryReserves =
                c_.token1ImaginaryReserves -
                ((c_.token1ImaginaryReserves * newShares_) / totalOldShares_);
        }
        return c2_;
    }

    /// @param c_ tokenA current real reserves (aka reserves before withdraw & swap)
    /// @param d_ tokenB current real reserves (aka reserves before withdraw & swap)
    /// @param e_ tokenA: final imaginary reserves - real reserves (aka reserves outside range after withdraw & swap)
    /// @param f_ tokenB: final imaginary reserves - real reserves (aka reserves outside range after withdraw & swap)
    /// @param g_ tokenA perfect amount to withdraw
    function _getWithdrawAndSwap(uint c_, uint d_, uint e_, uint f_, uint g_) internal pure returns (uint shares_) {
        // Equations we have:
        // 1. tokenAxa / tokenBxb = tokenAReserves / tokenBReserves (Withdraw in equal proportion)
        // 2. newTokenAReserves = tokenAReserves - tokenAxa
        // 3. newTokenBReserves = tokenBReserves - tokenBxb
        // 4 (known). finalTokenAReserves = tokenAReserves - tokenAx
        // 5 (known). finalTokenBReserves = tokenBReserves

        // Note: Xnew * Ynew = k = Xfinal * Yfinal (Xfinal & Yfinal is final imaginary reserve of token A & B).
        // Now as we know finalTokenAReserves & finalTokenAReserves, hence we can also calculate
        // imaginaryReserveMinusRealReservesA = finalImaginaryAReserves - finalTokenAReserves
        // imaginaryReserveMinusRealReservesB = finalImaginaryBReserves - finalTokenBReserves
        // Swaps only happen on real reserves hence before and after swap imaginaryReserveMinusRealReservesA &
        // imaginaryReserveMinusRealReservesB should have exactly the same value.

        // 6. newImaginaryTokenAReserves = imaginaryReserveMinusRealReservesA + newTokenAReserves
        // newImaginaryTokenAReserves = imaginaryReserveMinusRealReservesA + tokenAReserves - tokenAxa
        // 7. newImaginaryTokenBReserves = imaginaryReserveMinusRealReservesB + newTokenBReserves
        // newImaginaryTokenBReserves = imaginaryReserveMinusRealReservesB + tokenBReserves - tokenBxb
        // 8. tokenAxb = (newImaginaryTokenAReserves * tokenBxb) / (newImaginaryTokenBReserves + tokenBxb)
        // 9. tokenAxa + tokenAxb = tokenAx

        // simplifying knowns in 1 letter to make things clear:
        // c = tokenAReserves
        // d = tokenBReserves
        // e = imaginaryReserveMinusRealReservesA
        // f = imaginaryReserveMinusRealReservesB
        // g = tokenAx

        // A, B, C of quadratic are:
        // A = d
        // B = -(de + 2cd + cf)
        // C = cfg + cdg

        // tokenAxa = ((d⋅e + 2⋅c⋅d + c⋅f) - ((d⋅e + 2⋅c⋅d + c⋅f)^2 - 4⋅d⋅(c⋅f⋅g + c⋅d⋅g))^0.5) / 2d
        // dividing 2d first to avoid overflowing
        // B = (d⋅e + 2⋅c⋅d + c⋅f) / 2d
        // (B - ((B)^2 - (4⋅d⋅(c⋅f⋅g + c⋅d⋅g) / 4⋅d^2))^0.5)
        // (B - ((B)^2 - ((c⋅f⋅g + c⋅d⋅g) / d))^0.5)

        // temp_ = B/2A
        uint temp_ = (d_ * e_ + 2 * c_ * d_ + c_ * f_) / (2 * d_);
        // temp2_ = 4AC / 4A^2 = C / A
        // to avoid overflowing in any case multiplying with g_ later
        uint temp2_ = (((c_ * f_) / d_) + c_) * g_;

        // tokenAxa = (-B - (B^2 - 4AC)^0.5) / 2A
        uint tokenAxa_ = temp_ - FixedPointMathLib.sqrt((temp_ * temp_) - temp2_);

        // Ensure the amount to withdraw is within reasonable bounds:
        // - Not greater than 99.9999% of the input amount (g_)
        // - Not less than 0.0001% of the input amount (g_)
        // This prevents extreme scenarios and maybe potential precision issues
        if (tokenAxa_ > ((g_ * (SIX_DECIMALS - 1)) / SIX_DECIMALS) || tokenAxa_ < (g_ / SIX_DECIMALS))
            revert FluidDexError(ErrorTypes.DexT1__WithdrawAndSwapTooLowOrTooHigh);

        shares_ = (tokenAxa_ * 1e18) / c_;
    }

    /// @param c_ tokenA current debt before swap (aka debt before borrow & swap)
    /// @param d_ tokenB current debt before swap (aka debt before borrow & swap)
    /// @param e_ tokenA final imaginary reserves (reserves after borrow & swap)
    /// @param f_ tokenB final imaginary reserves (reserves after borrow & swap)
    /// @param g_ tokenA perfect amount to borrow
    function _getBorrowAndSwap(uint c_, uint d_, uint e_, uint f_, uint g_) internal pure returns (uint shares_) {
        // 1. tokenAxa / tokenADebt = tokenBxb / tokenBDebt (borrowing in equal proportion)
        // 2. newImaginaryTokenAReserves = tokenAFinalImaginaryReserves + tokenAxb
        // 3. newImaginaryTokenBReserves = tokenBFinalImaginaryReserves - tokenBxb
        // // Note: I assumed reserve of tokenA and debt of token A while solving which is fine.
        // // But in other places I use debtA to find reserveB
        // 4. tokenAxb = (newImaginaryTokenAReserves * tokenBxb) / (newImaginaryTokenBReserves + tokenBxb)
        // 5. tokenAxa + tokenAxb = tokenAx

        // Inserting 2 & 3 into 4:
        // 6. tokenAxb = ((tokenAFinalImaginaryReserves + tokenAxb) * tokenBxb) / ((tokenBFinalImaginaryReserves - tokenBxb) + tokenBxb)
        // 6. tokenAxb = ((tokenAFinalImaginaryReserves + tokenAxb) * tokenBxb) / (tokenBFinalImaginaryReserves)

        // Making 1 in terms of tokenBxb:
        // 1. tokenBxb = tokenAxa * tokenBDebt / tokenADebt

        // Inserting 5 into 6:
        // 7. (tokenAx - tokenAxa) = ((tokenAFinalImaginaryReserves + (tokenAx - tokenAxa)) * tokenBxb) / (tokenBFinalImaginaryReserves)

        // Inserting 1 into 7:
        // 8. (tokenAx - tokenAxa) * tokenBFinalImaginaryReserves = ((tokenAFinalImaginaryReserves + (tokenAx - tokenAxa)) * (tokenAxa * tokenBDebt / tokenADebt))

        // Replacing knowns with:
        // c = tokenADebt
        // d = tokenBDebt
        // e = tokenAFinalImaginaryReserves
        // f = tokenBFinalImaginaryReserves
        // g = tokenAx

        // 8. (g - tokenAxa) * f * c = ((e + (g - tokenAxa)) * (tokenAxa * d))
        // 8. cfg - cf*tokenAxa = de*tokenAxa + dg*tokenAxa - d*tokenAxa^2
        // 8. d*tokenAxa^2 - cf*tokenAxa - de*tokenAxa - dg*tokenAxa + cfg = 0
        // 8. d*tokenAxa^2 - (cf + de + dg)*tokenAxa + cfg = 0

        // A, B, C of quadratic are:
        // A = d
        // B = -(cf + de + dg)
        // C = cfg

        // temp_ = B/2A
        uint temp_ = (c_ * f_ + d_ * e_ + d_ * g_) / (2 * d_);

        // temp2_ = 4AC / 4A^2 = C / A
        // to avoid overflowing in any case multiplying with g_ later
        uint temp2_ = (c_ * f_ * g_) / d_;

        // tokenAxa = (-B - (B^2 - 4AC)^0.5) / 2A
        uint tokenAxa_ = temp_ - FixedPointMathLib.sqrt((temp_ * temp_) - temp2_);

        // Ensure the amount to borrow is within reasonable bounds:
        // - Not greater than 99.9999% of the input amount (g_)
        // - Not less than 0.0001% of the input amount (g_)
        // This prevents extreme scenarios and maybe potential precision issues
        if (tokenAxa_ > ((g_ * (SIX_DECIMALS - 1)) / SIX_DECIMALS) || tokenAxa_ < (g_ / SIX_DECIMALS))
            revert FluidDexError(ErrorTypes.DexT1__BorrowAndSwapTooLowOrTooHigh);

        // rounding up borrow shares to mint for user
        shares_ = ((tokenAxa_ + 1) * 1e18) / c_;
    }

    /// @notice Updates debt and reserves based on minting or burning shares
    /// @param shares_ The number of shares to mint or burn
    /// @param totalShares_ The total number of shares before the operation
    /// @param d_ The current debt and reserves
    /// @param mintOrBurn_ True if minting, false if burning
    /// @return d2_ The updated debt and reserves
    /// @dev This function calculates the new debt and reserves when minting or burning shares.
    /// @dev It updates the following for both tokens:
    /// @dev - Debt
    /// @dev - Real Reserves
    /// @dev - Imaginary Reserves
    /// @dev The calculation is done proportionally based on the ratio of shares to total shares.
    /// @dev For minting, it adds the proportional amount.
    /// @dev For burning, it subtracts the proportional amount.
    function _getUpdateDebtReserves(
        uint shares_,
        uint totalShares_,
        DebtReserves memory d_,
        bool mintOrBurn_ // true if mint, false if burn
    ) internal pure returns (DebtReserves memory d2_) {
        if (mintOrBurn_) {
            d2_.token0Debt = d_.token0Debt + (d_.token0Debt * shares_) / totalShares_;
            d2_.token1Debt = d_.token1Debt + (d_.token1Debt * shares_) / totalShares_;
            d2_.token0RealReserves = d_.token0RealReserves + (d_.token0RealReserves * shares_) / totalShares_;
            d2_.token1RealReserves = d_.token1RealReserves + (d_.token1RealReserves * shares_) / totalShares_;
            d2_.token0ImaginaryReserves =
                d_.token0ImaginaryReserves +
                (d_.token0ImaginaryReserves * shares_) /
                totalShares_;
            d2_.token1ImaginaryReserves =
                d_.token1ImaginaryReserves +
                (d_.token1ImaginaryReserves * shares_) /
                totalShares_;
        } else {
            d2_.token0Debt = d_.token0Debt - (d_.token0Debt * shares_) / totalShares_;
            d2_.token1Debt = d_.token1Debt - (d_.token1Debt * shares_) / totalShares_;
            d2_.token0RealReserves = d_.token0RealReserves - (d_.token0RealReserves * shares_) / totalShares_;
            d2_.token1RealReserves = d_.token1RealReserves - (d_.token1RealReserves * shares_) / totalShares_;
            d2_.token0ImaginaryReserves =
                d_.token0ImaginaryReserves -
                (d_.token0ImaginaryReserves * shares_) /
                totalShares_;
            d2_.token1ImaginaryReserves =
                d_.token1ImaginaryReserves -
                (d_.token1ImaginaryReserves * shares_) /
                totalShares_;
        }

        return d2_;
    }

    /// @param a_ tokenA new imaginary reserves (imaginary reserves after perfect payback but not swap yet)
    /// @param b_ tokenB new imaginary reserves (imaginary reserves after perfect payback but not swap yet)
    /// @param c_ tokenA current debt
    /// @param d_ tokenB current debt & final debt (tokenB current & final debt remains same)
    /// @param i_ tokenA new reserves (reserves after perfect payback but not swap yet)
    /// @param j_ tokenB new reserves (reserves after perfect payback but not swap yet)
    function _getSwapAndPaybackOneTokenPerfectShares(
        uint a_,
        uint b_,
        uint c_,
        uint d_,
        uint i_,
        uint j_
    ) internal pure returns (uint tokenAmt_) {
        // l_ => tokenA reserves outside range
        uint l_ = a_ - i_;
        // m_ => tokenB reserves outside range
        uint m_ = b_ - j_;
        // w_ => new K or final K will be same, xy = k
        uint w_ = a_ * b_;
        // z_ => final reserveB full, when entire debt is in tokenA
        uint z_ = w_ / l_;
        // y_ => final reserveA full, when entire debt is in tokenB
        uint y_ = w_ / m_;
        // v_ = final reserveB
        uint v_ = z_ - m_ - d_;
        // x_ = final tokenA debt
        uint x_ = (v_ * y_) / (m_ + v_);

        // amountA to payback, this amount will get swapped into tokenB to payback in perfect proportion
        tokenAmt_ = c_ - x_;

        // Ensure the amount to swap and payback is within reasonable bounds:
        // - Not greater than 99.9999% of the current debt (c_)
        // This prevents extreme scenarios where almost all debt is getting paid after swap,
        // which could maybe lead to precision issues & edge cases
        if ((tokenAmt_ > (c_ * (SIX_DECIMALS - 1)) / SIX_DECIMALS))
            revert FluidDexError(ErrorTypes.DexT1__SwapAndPaybackTooLowOrTooHigh);
    }

    /// @param c_ tokenA debt before swap & payback
    /// @param d_ tokenB debt before swap & payback
    /// @param e_ tokenA imaginary reserves before swap & payback
    /// @param f_ tokenB imaginary reserves before swap & payback
    /// @param g_ tokenA perfect amount to payback
    function _getSwapAndPayback(uint c_, uint d_, uint e_, uint f_, uint g_) internal pure returns (uint shares_) {
        // 1. tokenAxa / newTokenADebt = tokenBxb / newTokenBDebt (borrowing in equal proportion)
        // 2. newTokenADebt = tokenADebt - tokenAxb
        // 3. newTokenBDebt = tokenBDebt + tokenBxb
        // 4. imaginaryTokenAReserves = Calculated above from debtA
        // 5. imaginaryTokenBReserves = Calculated above from debtA
        // // Note: I assumed reserveA and debtA for same tokenA
        // // But in other places I used debtA to find reserveB
        // 6. tokenBxb = (imaginaryTokenBReserves * tokenAxb) / (imaginaryTokenAReserves + tokenAxb)
        // 7. tokenAxa + tokenAxb = tokenAx

        // Unknowns in the above equations are:
        // tokenAxa, tokenAxb, tokenBxb

        // simplifying knowns in 1 letter to make things clear:
        // c = tokenADebt
        // d = tokenBDebt
        // e = imaginaryTokenAReserves
        // f = imaginaryTokenBReserves
        // g = tokenAx

        // Restructuring 1:
        // 1. newTokenBDebt = (tokenBxb * newTokenADebt) / tokenAxa

        // Inserting 1 in 3:
        // 8. (tokenBxb * newTokenADebt) / tokenAxa = tokenBDebt + tokenBxb

        // Refactoring 8 w.r.t tokenBxb:
        // 8. (tokenBxb * newTokenADebt) - tokenAxa * tokenBxb = tokenBDebt * tokenAxa
        // 8. tokenBxb * (newTokenADebt - tokenAxa) = tokenBDebt * tokenAxa
        // 8. tokenBxb = (tokenBDebt * tokenAxa) / (newTokenADebt - tokenAxa)

        // Inserting 2 in 8:
        // 9. tokenBxb = (tokenBDebt * tokenAxa) / (tokenADebt - tokenAxb - tokenAxa)
        // 9. tokenBxb = (tokenBDebt * tokenAxa) / (tokenADebt - tokenAx)

        // Inserting 9 in 6:
        // 10. (tokenBDebt * tokenAxa) / (tokenADebt - tokenAx) = (imaginaryTokenBReserves * tokenAxb) / (imaginaryTokenAReserves + tokenAxb)
        // 10. (tokenBDebt * (tokenAx - tokenAxb)) / (tokenADebt - tokenAx) = (imaginaryTokenBReserves * tokenAxb) / (imaginaryTokenAReserves + tokenAxb)

        // Replacing with single digits:
        // 10. (d * (g - tokenAxb)) / (c - g) = (f * tokenAxb) / (e + tokenAxb)
        // 10. d * (g - tokenAxb) * (e + tokenAxb) = (f * tokenAxb) * (c - g)
        // 10. deg + dg*tokenAxb - de*tokenAxb - d*tokenAxb^2 = cf*tokenAxb - fg*tokenAxb
        // 10. d*tokenAxb^2 + cf*tokenAxb - fg*tokenAxb + de*tokenAxb - dg*tokenAxb - deg = 0
        // 10. d*tokenAxb^2 + (cf - fg + de - dg)*tokenAxb - deg = 0

        // A = d
        // B = (cf + de - fg - dg)
        // C = -deg

        // Solving Quadratic will give the value for tokenAxb, now that "tokenAxb" is known we can also know:
        // tokenAxa & tokenBxb

        // temp_ => B/A
        uint temp_ = (c_ * f_ + d_ * e_ - f_ * g_ - d_ * g_) / d_;

        // temp2_ = -AC / A^2
        uint temp2_ = 4 * e_ * g_;

        uint amtToSwap_ = (FixedPointMathLib.sqrt((temp2_ + (temp_ * temp_))) - temp_) / 2;

        // Ensure the amount to swap is within reasonable bounds:
        // - Not greater than 99.9999% of the input amount (g_)
        // - Not less than 0.0001% of the input amount (g_)
        // This prevents extreme scenarios and maybe potential precision issues
        if ((amtToSwap_ > (g_ * (SIX_DECIMALS - 1)) / SIX_DECIMALS) || (amtToSwap_ < (g_ / SIX_DECIMALS)))
            revert FluidDexError(ErrorTypes.DexT1__SwapAndPaybackTooLowOrTooHigh);

        // temp_ => amt0ToPayback
        temp_ = g_ - amtToSwap_;
        // (imaginaryTokenBReserves * amtToSwap_) / (imaginaryTokenAReserves + amtToSwap_)
        // temp2_ => amt1ToPayback
        temp2_ = (f_ * amtToSwap_) / (e_ + amtToSwap_);

        // temp_ => shares0
        temp_ = (temp_ * 1e18) / (c_ - amtToSwap_);
        // temp_ => shares1
        temp2_ = (temp2_ * 1e18) / (d_ + temp2_);
        // temp_ & temp2 should be same. Although, due to some possible precision loss taking the lower one
        shares_ = temp_ > temp2_ ? temp2_ : temp_;
    }

    /// @dev This function performs arbitrage between the collateral and debt pools
    /// @param dexVariables_ The current state of dex variables
    /// @param dexVariables2_ Additional dex variables
    /// @param pex_ Struct containing prices and exchange rates
    /// @notice This function is called after user operations to balance the pools
    /// @notice It swaps tokens between the collateral and debt pools to align their prices
    /// @notice The function updates the oracle price based on the arbitrage results
    function _arbitrage(uint dexVariables_, uint dexVariables2_, PricesAndExchangePrice memory pex_) internal {
        if ((dexVariables2_ >> 255) == 1) revert FluidDexError(ErrorTypes.DexT1__SwapAndArbitragePaused);

        CollateralReserves memory c_;
        DebtReserves memory d_;
        uint price_;
        if ((dexVariables2_ & 1) == 1) {
            c_ = _getCollateralReserves(
                pex_.geometricMean,
                pex_.upperRange,
                pex_.lowerRange,
                pex_.supplyToken0ExchangePrice,
                pex_.supplyToken1ExchangePrice
            );
        }
        if ((dexVariables2_ & 2) == 2) {
            d_ = _getDebtReserves(
                pex_.geometricMean,
                pex_.upperRange,
                pex_.lowerRange,
                pex_.borrowToken0ExchangePrice,
                pex_.borrowToken1ExchangePrice
            );
        }
        if ((dexVariables2_ & 3) < 3) {
            price_ = ((dexVariables2_ & 1) == 1)
                ? ((c_.token1ImaginaryReserves) * 1e27) / (c_.token0ImaginaryReserves)
                : ((d_.token1ImaginaryReserves) * 1e27) / (d_.token0ImaginaryReserves);
            // arbitrage should only happen if both smart debt & smart collateral are enabled
            // Storing in storage, it will also uninitialize re-entrancy
            dexVariables = _updateOracle(price_, pex_.centerPrice, dexVariables_);
            return;
        }

        uint temp_;
        uint amtOut_;
        uint amtIn_;

        // both smart debt & smart collateral enabled

        // always swapping token0 into token1
        int a_ = _swapRoutingIn(
            0,
            c_.token1ImaginaryReserves,
            c_.token0ImaginaryReserves,
            d_.token1ImaginaryReserves,
            d_.token0ImaginaryReserves
        );
        if (a_ > 0) {
            // swap will route through col pool
            temp_ = uint(a_);
            amtOut_ = _getAmountOut(temp_, c_.token0ImaginaryReserves, c_.token1ImaginaryReserves);
            amtIn_ = _getAmountIn(temp_, d_.token1ImaginaryReserves, d_.token0ImaginaryReserves);

            // new pool price
            // debt pool price will be the same as collateral pool after the swap
            // note: updating price here as in next line amtOut_ will get updated to normal amounts
            price_ = ((c_.token1ImaginaryReserves - amtOut_) * 1e27) / (c_.token0ImaginaryReserves + temp_);

            // converting into normal token form from DEX precisions
            a_ = (((a_) * int(TOKEN_0_DENOMINATOR_PRECISION)) / int(TOKEN_0_NUMERATOR_PRECISION));
            amtOut_ = (((amtOut_) * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION);
            amtIn_ = (((amtIn_) * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION);

            // deposit token0 and borrow token0
            // withdraw token1 and payback token1
            LIQUIDITY.operate(TOKEN_0, a_, a_, address(0), address(this), abi.encode(SKIP_TRANSFERS, address(this)));
            LIQUIDITY.operate(
                TOKEN_1,
                -int(amtOut_),
                -int(amtIn_),
                address(this),
                address(0),
                abi.encode(SKIP_TRANSFERS, address(this))
            );
        } else if (a_ < 0) {
            // swap will route through debt pool
            temp_ = uint(-a_);
            amtOut_ = _getAmountOut(temp_, d_.token0ImaginaryReserves, d_.token1ImaginaryReserves);
            amtIn_ = _getAmountIn(temp_, c_.token1ImaginaryReserves, c_.token0ImaginaryReserves);

            // new pool price
            // debt pool price will be the same as collateral pool after the swap
            // note: updating price here as in next line amtOut_ will get updated to normal amounts
            price_ = ((d_.token1ImaginaryReserves - amtOut_) * 1e27) / (d_.token0ImaginaryReserves + temp_);

            // converting into normal token form from DEX precisions
            a_ = ((a_ * int(TOKEN_0_DENOMINATOR_PRECISION)) / int(TOKEN_0_NUMERATOR_PRECISION));
            amtOut_ = ((amtOut_ * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION);
            amtIn_ = (((amtIn_) * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION);

            // payback token0 and withdraw token0
            // deposit token1 and borrow token1
            LIQUIDITY.operate(TOKEN_0, a_, a_, address(this), address(0), abi.encode(SKIP_TRANSFERS, address(this)));
            LIQUIDITY.operate(
                TOKEN_1,
                int(amtIn_),
                int(amtOut_),
                address(0),
                address(this),
                abi.encode(SKIP_TRANSFERS, address(this))
            );
        } else {
            // reverting if nothing to arbitrage. Naturally to get here will have very low probability
            revert FluidDexError(ErrorTypes.DexT1__NothingToArbitrage);
        }

        // if hook exists then calling hook
        temp_ = (dexVariables2_ >> 142) & X30;
        if (temp_ > 0) {
            uint lastPrice_ = (dexVariables_ >> 41) & X40;
            lastPrice_ = (lastPrice_ >> DEFAULT_EXPONENT_SIZE) << (lastPrice_ & DEFAULT_EXPONENT_MASK);
            _hookVerify(temp_, 2, lastPrice_ > price_, price_);
        }

        // Storing in storage, it will also uninitialize re-entrancy
        dexVariables = _updateOracle(price_, pex_.centerPrice, dexVariables_);

        emit LogArbitrage(a_, amtOut_);
    }
}
