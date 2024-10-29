// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { CoreHelpers } from "../helpers/coreHelpers.sol";
import { SafeTransfer } from "../../../../../libraries/safeTransfer.sol";
import { DexSlotsLink } from "../../../../../libraries/dexSlotsLink.sol";
import { DexCalcs } from "../../../../../libraries/dexCalcs.sol";
import { BigMathMinified } from "../../../../../libraries/bigMathMinified.sol";
import { ErrorTypes } from "../../../errorTypes.sol";
import { IFluidDexT1 } from "../../../interfaces/iDexT1.sol";

interface IDexCallback {
    function dexCallback(address token_, uint256 amount_) external;
}

/// @title FluidDexT1
/// @notice Implements core logics for Fluid Dex protocol.
/// Note Token transfers happen directly from user to Liquidity contract and vice-versa.
contract FluidDexT1 is CoreHelpers {
    using BigMathMinified for uint256;

    constructor(ConstantViews memory constantViews_) CoreHelpers(constantViews_) {
        // any implementations should not be zero
        if (
            constantViews_.implementations.shift == address(0) ||
            constantViews_.implementations.admin == address(0) ||
            constantViews_.implementations.colOperations == address(0) ||
            constantViews_.implementations.debtOperations == address(0) ||
            constantViews_.implementations.perfectOperationsAndSwapOut == address(0)
        ) {
            revert FluidDexError(ErrorTypes.DexT1__InvalidImplementation);
        }
    }

    struct SwapInExtras {
        address to;
        uint amountOutMin;
        bool isCallback;
    }

    /// @dev This function allows users to swap a specific amount of input tokens for output tokens
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountIn_ The exact amount of input tokens to swap
    /// @param extras_ Additional parameters for the swap:
    ///   - to: Recipient of swapped tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with amountOut_
    ///   - amountOutMin: The minimum amount of output tokens the user expects to receive
    ///   - isCallback: If true, indicates that the input tokens should be transferred via a callback
    /// @return amountOut_ The amount of output tokens received from the swap
    function _swapIn(
        bool swap0to1_,
        uint256 amountIn_,
        SwapInExtras memory extras_
    ) internal returns (uint256 amountOut_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        if ((dexVariables2_ >> 255) == 1) revert FluidDexError(ErrorTypes.DexT1__SwapAndArbitragePaused);

        _check(dexVariables_, dexVariables2_);

        if (extras_.to == address(0)) extras_.to = msg.sender;

        SwapInMemory memory s_;

        if (swap0to1_) {
            (s_.tokenIn, s_.tokenOut) = (TOKEN_0, TOKEN_1);
            unchecked {
                s_.amtInAdjusted = (amountIn_ * TOKEN_0_NUMERATOR_PRECISION) / TOKEN_0_DENOMINATOR_PRECISION;
            }
        } else {
            (s_.tokenIn, s_.tokenOut) = (TOKEN_1, TOKEN_0);
            unchecked {
                s_.amtInAdjusted = (amountIn_ * TOKEN_1_NUMERATOR_PRECISION) / TOKEN_1_DENOMINATOR_PRECISION;
            }
        }

        _verifySwapAndNonPerfectActions(s_.amtInAdjusted, amountIn_);

        PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices(dexVariables_, dexVariables2_);

        if (msg.value > 0) {
            if (msg.value != amountIn_) revert FluidDexError(ErrorTypes.DexT1__EthAndAmountInMisMatch);
            if (s_.tokenIn != NATIVE_TOKEN) revert FluidDexError(ErrorTypes.DexT1__EthSentForNonNativeSwap);
        }

        // is smart collateral pool enabled
        uint temp_ = dexVariables2_ & 1;
        // is smart debt pool enabled
        uint temp2_ = (dexVariables2_ >> 1) & 1;

        uint temp3_;
        uint temp4_;

        // extracting fee
        temp3_ = ((dexVariables2_ >> 2) & X17);
        unchecked {
            // revenueCut in 6 decimals, to have proper precision
            // if fee = 1% and revenue cut = 10% then revenueCut = 1e8 - (10000 * 10) = 99900000
            s_.revenueCut = EIGHT_DECIMALS - ((((dexVariables2_ >> 19) & X7) * temp3_));
            // fee in 4 decimals
            // 1 - fee. If fee is 1% then withoutFee will be 1e6 - 1e4
            // s_.fee => 1 - withdraw fee
            s_.fee = SIX_DECIMALS - temp3_;
        }

        CollateralReservesSwap memory cs_;
        DebtReservesSwap memory ds_;
        if (temp_ == 1) {
            // smart collateral is enabled
            {
                CollateralReserves memory c_ = _getCollateralReserves(
                    pex_.geometricMean,
                    pex_.upperRange,
                    pex_.lowerRange,
                    pex_.supplyToken0ExchangePrice,
                    pex_.supplyToken1ExchangePrice
                );
                if (swap0to1_) {
                    (
                        cs_.tokenInRealReserves,
                        cs_.tokenOutRealReserves,
                        cs_.tokenInImaginaryReserves,
                        cs_.tokenOutImaginaryReserves
                    ) = (
                        c_.token0RealReserves,
                        c_.token1RealReserves,
                        c_.token0ImaginaryReserves,
                        c_.token1ImaginaryReserves
                    );
                } else {
                    (
                        cs_.tokenInRealReserves,
                        cs_.tokenOutRealReserves,
                        cs_.tokenInImaginaryReserves,
                        cs_.tokenOutImaginaryReserves
                    ) = (
                        c_.token1RealReserves,
                        c_.token0RealReserves,
                        c_.token1ImaginaryReserves,
                        c_.token0ImaginaryReserves
                    );
                }
            }
        }

        if (temp2_ == 1) {
            // smart debt is enabled
            {
                DebtReserves memory d_ = _getDebtReserves(
                    pex_.geometricMean,
                    pex_.upperRange,
                    pex_.lowerRange,
                    pex_.borrowToken0ExchangePrice,
                    pex_.borrowToken1ExchangePrice
                );
                if (swap0to1_) {
                    (
                        ds_.tokenInDebt,
                        ds_.tokenOutDebt,
                        ds_.tokenInRealReserves,
                        ds_.tokenOutRealReserves,
                        ds_.tokenInImaginaryReserves,
                        ds_.tokenOutImaginaryReserves
                    ) = (
                        d_.token0Debt,
                        d_.token1Debt,
                        d_.token0RealReserves,
                        d_.token1RealReserves,
                        d_.token0ImaginaryReserves,
                        d_.token1ImaginaryReserves
                    );
                } else {
                    (
                        ds_.tokenInDebt,
                        ds_.tokenOutDebt,
                        ds_.tokenInRealReserves,
                        ds_.tokenOutRealReserves,
                        ds_.tokenInImaginaryReserves,
                        ds_.tokenOutImaginaryReserves
                    ) = (
                        d_.token1Debt,
                        d_.token0Debt,
                        d_.token1RealReserves,
                        d_.token0RealReserves,
                        d_.token1ImaginaryReserves,
                        d_.token0ImaginaryReserves
                    );
                }
            }
        }

        // limiting amtInAdjusted to be not more than 50% of both (collateral & debt) imaginary tokenIn reserves combined
        // basically, if this throws that means user is trying to swap 0.5x tokenIn if current tokenIn imaginary reserves is x
        // let's take x as token0 here, that means, initially the pool pricing might be:
        // token1Reserve / x and new pool pricing will become token1Reserve / 1.5x (token1Reserve will decrease after swap but for simplicity ignoring that)
        // So pool price is decreased by ~33.33% (oracle will throw error in this case as it only allows 5% price difference but better to limit it before hand)
        unchecked {
            if (s_.amtInAdjusted > ((cs_.tokenInImaginaryReserves + ds_.tokenInImaginaryReserves) / 2))
                revert FluidDexError(ErrorTypes.DexT1__SwapInLimitingAmounts);
        }

        if (temp_ == 1 && temp2_ == 1) {
            // unless both pools are enabled s_.swapRoutingAmt will be 0
            s_.swapRoutingAmt = _swapRoutingIn(
                s_.amtInAdjusted,
                cs_.tokenOutImaginaryReserves,
                cs_.tokenInImaginaryReserves,
                ds_.tokenOutImaginaryReserves,
                ds_.tokenInImaginaryReserves
            );
        }

        // In below if else statement temps are:
        // temp_ => deposit amt
        // temp2_ => withdraw amt
        // temp3_ => payback amt
        // temp4_ => borrow amt
        if (int(s_.amtInAdjusted) > s_.swapRoutingAmt && s_.swapRoutingAmt > 0) {
            // swap will route from the both pools
            // temp_ = amountInCol_
            temp_ = uint(s_.swapRoutingAmt);
            unchecked {
                // temp3_ = amountInDebt_
                temp3_ = s_.amtInAdjusted - temp_;
            }

            (temp2_, temp4_) = (0, 0);

            // debt pool price will be the same as collateral pool after the swap
            s_.withdrawTo = extras_.to;
            s_.borrowTo = extras_.to;
        } else if ((temp_ == 1 && temp2_ == 0) || (s_.swapRoutingAmt >= int(s_.amtInAdjusted))) {
            // entire swap will route through collateral pool
            (temp_, temp2_, temp3_, temp4_) = (s_.amtInAdjusted, 0, 0, 0);
            // price can slightly differ from debt pool but difference will be very small. Probably <0.01% for active DEX pools.
            s_.withdrawTo = extras_.to;
        } else if ((temp_ == 0 && temp2_ == 1) || (s_.swapRoutingAmt <= 0)) {
            // entire swap will route through debt pool
            (temp_, temp2_, temp3_, temp4_) = (0, 0, s_.amtInAdjusted, 0);
            // price can slightly differ from collateral pool but difference will be very small. Probably <0.01% for active DEX pools.
            s_.borrowTo = extras_.to;
        } else {
            // swap should never reach this point but if it does then reverting
            revert FluidDexError(ErrorTypes.DexT1__NoSwapRoute);
        }

        if (temp_ > 0) {
            // temp2_ = amountOutCol_
            temp2_ = _getAmountOut(
                ((temp_ * s_.fee) / SIX_DECIMALS),
                cs_.tokenInImaginaryReserves,
                cs_.tokenOutImaginaryReserves
            );
            swap0to1_
                ? _verifyToken1Reserves(
                    (cs_.tokenInRealReserves + temp_),
                    (cs_.tokenOutRealReserves - temp2_),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_SWAP
                )
                : _verifyToken0Reserves(
                    (cs_.tokenOutRealReserves - temp2_),
                    (cs_.tokenInRealReserves + temp_),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_SWAP
                );
        }
        if (temp3_ > 0) {
            // temp4_ = amountOutDebt_
            temp4_ = _getAmountOut(
                ((temp3_ * s_.fee) / SIX_DECIMALS),
                ds_.tokenInImaginaryReserves,
                ds_.tokenOutImaginaryReserves
            );
            swap0to1_
                ? _verifyToken1Reserves(
                    (ds_.tokenInRealReserves + temp3_),
                    (ds_.tokenOutRealReserves - temp4_),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_SWAP
                )
                : _verifyToken0Reserves(
                    (ds_.tokenOutRealReserves - temp4_),
                    (ds_.tokenInRealReserves + temp3_),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_SWAP
                );
        }

        // (temp_ + temp3_) == amountIn_ == msg.value (for native token), if there is revenue cut then this statement is not true
        temp_ = (temp_ * s_.revenueCut) / EIGHT_DECIMALS;
        temp3_ = (temp3_ * s_.revenueCut) / EIGHT_DECIMALS;

        // from whatever pool higher amount of swap is routing we are taking that as final price, does not matter much because both pools final price should be same
        if (temp_ > temp3_) {
            // new pool price from col pool
            s_.price = swap0to1_
                ? ((cs_.tokenOutImaginaryReserves - temp2_) * 1e27) / (cs_.tokenInImaginaryReserves + temp_)
                : ((cs_.tokenInImaginaryReserves + temp_) * 1e27) / (cs_.tokenOutImaginaryReserves - temp2_);
        } else {
            // new pool price from debt pool
            s_.price = swap0to1_
                ? ((ds_.tokenOutImaginaryReserves - temp4_) * 1e27) / (ds_.tokenInImaginaryReserves + temp3_)
                : ((ds_.tokenInImaginaryReserves + temp3_) * 1e27) / (ds_.tokenOutImaginaryReserves - temp4_);
        }

        // converting into normal token amounts
        if (swap0to1_) {
            temp_ = ((temp_ * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION);
            temp3_ = ((temp3_ * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION);
            // only adding uncheck in out amount
            unchecked {
                temp2_ = ((temp2_ * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION);
                temp4_ = ((temp4_ * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION);
            }
        } else {
            temp_ = ((temp_ * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION);
            temp3_ = ((temp3_ * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION);
            // only adding uncheck in out amount
            unchecked {
                temp2_ = ((temp2_ * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION);
                temp4_ = ((temp4_ * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION);
            }
        }

        unchecked {
            amountOut_ = temp2_ + temp4_;
        }

        // if address dead then reverting with amountOut
        if (extras_.to == ADDRESS_DEAD) revert FluidDexSwapResult(amountOut_);

        if (amountOut_ < extras_.amountOutMin) revert FluidDexError(ErrorTypes.DexT1__NotEnoughAmountOut);

        // allocating to avoid stack-too-deep error
        // not setting in the callbackData as last 2nd to avoid SKIP_TRANSFERS clashing
        s_.data = abi.encode(amountIn_, extras_.isCallback, msg.sender); // true/false is to decide if dex should do callback or directly transfer from user
        // deposit & payback token in at liquidity
        LIQUIDITY.operate{ value: msg.value }(s_.tokenIn, int(temp_), -int(temp3_), address(0), address(0), s_.data);
        // withdraw & borrow token out at liquidity
        LIQUIDITY.operate(s_.tokenOut, -int(temp2_), int(temp4_), s_.withdrawTo, s_.borrowTo, new bytes(0));

        // if hook exists then calling hook
        temp_ = (dexVariables2_ >> 142) & X30;
        if (temp_ > 0) {
            s_.swap0to1 = swap0to1_;
            _hookVerify(temp_, 1, s_.swap0to1, s_.price);
        }

        swap0to1_
            ? _utilizationVerify(((dexVariables2_ >> 238) & X10), EXCHANGE_PRICE_TOKEN_1_SLOT)
            : _utilizationVerify(((dexVariables2_ >> 228) & X10), EXCHANGE_PRICE_TOKEN_0_SLOT);

        dexVariables = _updateOracle(s_.price, pex_.centerPrice, dexVariables_);

        emit Swap(swap0to1_, amountIn_, amountOut_, extras_.to);
    }

    /// @dev Swap tokens with perfect amount in
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountIn_ The exact amount of tokens to swap in
    /// @param amountOutMin_ The minimum amount of tokens to receive after swap
    /// @param to_ Recipient of swapped tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with amountOut_
    /// @return amountOut_ The amount of output tokens received from the swap
    function swapIn(
        bool swap0to1_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        address to_
    ) public payable returns (uint256 amountOut_) {
        return _swapIn(swap0to1_, amountIn_, SwapInExtras(to_, amountOutMin_, false));
    }

    /// @dev Swap tokens with perfect amount in and callback functionality
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountIn_ The exact amount of tokens to swap in
    /// @param amountOutMin_ The minimum amount of tokens to receive after swap
    /// @param to_ Recipient of swapped tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with amountOut_
    /// @return amountOut_ The amount of output tokens received from the swap
    function swapInWithCallback(
        bool swap0to1_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        address to_
    ) public payable returns (uint256 amountOut_) {
        return _swapIn(swap0to1_, amountIn_, SwapInExtras(to_, amountOutMin_, true));
    }

    /// @dev Swap tokens with perfect amount out
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountOut_ The exact amount of tokens to receive after swap
    /// @param amountInMax_ Maximum amount of tokens to swap in
    /// @param to_ Recipient of swapped tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with amountIn_
    /// @return amountIn_ The amount of input tokens used for the swap
    function swapOut(
        bool swap0to1_,
        uint256 amountOut_,
        uint256 amountInMax_,
        address to_
    ) public payable returns (uint256 amountIn_) {
        return abi.decode(_spell(PERFECT_OPERATIONS_AND_SWAP_OUT_IMPLEMENTATION, msg.data), (uint256));
    }

    /// @dev Swap tokens with perfect amount out and callback functionality
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountOut_ The exact amount of tokens to receive after swap
    /// @param amountInMax_ Maximum amount of tokens to swap in
    /// @param to_ Recipient of swapped tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with amountIn_
    /// @return amountIn_ The amount of input tokens used for the swap
    function swapOutWithCallback(
        bool swap0to1_,
        uint256 amountOut_,
        uint256 amountInMax_,
        address to_
    ) public payable returns (uint256 amountIn_) {
        return abi.decode(_spell(PERFECT_OPERATIONS_AND_SWAP_OUT_IMPLEMENTATION, msg.data), (uint256));
    }

    /// @dev Deposit tokens in equal proportion to the current pool ratio
    /// @param shares_ The number of shares to mint
    /// @param maxToken0Deposit_ Maximum amount of token0 to deposit
    /// @param maxToken1Deposit_ Maximum amount of token1 to deposit
    /// @param estimate_ If true, function will revert with estimated deposit amounts without executing the deposit
    /// @return token0Amt_ Amount of token0 deposited
    /// @return token1Amt_ Amount of token1 deposited
    function depositPerfect(
        uint shares_,
        uint maxToken0Deposit_,
        uint maxToken1Deposit_,
        bool estimate_
    ) public payable returns (uint token0Amt_, uint token1Amt_) {
        return abi.decode(_spell(PERFECT_OPERATIONS_AND_SWAP_OUT_IMPLEMENTATION, msg.data), (uint256, uint256));
    }

    /// @dev This function allows users to withdraw a perfect amount of collateral liquidity
    /// @param shares_ The number of shares to withdraw
    /// @param minToken0Withdraw_ The minimum amount of token0 the user is willing to accept
    /// @param minToken1Withdraw_ The minimum amount of token1 the user is willing to accept
    /// @param to_ Recipient of withdrawn tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with token0Amt_ & token1Amt_
    /// @return token0Amt_ The amount of token0 withdrawn
    /// @return token1Amt_ The amount of token1 withdrawn
    function withdrawPerfect(
        uint shares_,
        uint minToken0Withdraw_,
        uint minToken1Withdraw_,
        address to_
    ) public returns (uint token0Amt_, uint token1Amt_) {
        return abi.decode(_spell(PERFECT_OPERATIONS_AND_SWAP_OUT_IMPLEMENTATION, msg.data), (uint256, uint256));
    }

    /// @dev This function allows users to borrow tokens in equal proportion to the current debt pool ratio
    /// @param shares_ The number of shares to borrow
    /// @param minToken0Borrow_ Minimum amount of token0 to borrow
    /// @param minToken1Borrow_ Minimum amount of token1 to borrow
    /// @param to_ Recipient of borrowed tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with token0Amt_ & token1Amt_
    /// @return token0Amt_ Amount of token0 borrowed
    /// @return token1Amt_ Amount of token1 borrowed
    function borrowPerfect(
        uint shares_,
        uint minToken0Borrow_,
        uint minToken1Borrow_,
        address to_
    ) public returns (uint token0Amt_, uint token1Amt_) {
        return abi.decode(_spell(PERFECT_OPERATIONS_AND_SWAP_OUT_IMPLEMENTATION, msg.data), (uint256, uint256));
    }

    /// @dev This function allows users to pay back borrowed tokens in equal proportion to the current debt pool ratio
    /// @param shares_ The number of shares to pay back
    /// @param maxToken0Payback_ Maximum amount of token0 to pay back
    /// @param maxToken1Payback_ Maximum amount of token1 to pay back
    /// @param estimate_ If true, function will revert with estimated payback amounts without executing the payback
    /// @return token0Amt_ Amount of token0 paid back
    /// @return token1Amt_ Amount of token1 paid back
    function paybackPerfect(
        uint shares_,
        uint maxToken0Payback_,
        uint maxToken1Payback_,
        bool estimate_
    ) public payable returns (uint token0Amt_, uint token1Amt_) {
        return abi.decode(_spell(PERFECT_OPERATIONS_AND_SWAP_OUT_IMPLEMENTATION, msg.data), (uint256, uint256));
    }

    /// @dev This function allows users to deposit tokens in any proportion into the col pool
    /// @param token0Amt_ The amount of token0 to deposit
    /// @param token1Amt_ The amount of token1 to deposit
    /// @param minSharesAmt_ The minimum amount of shares the user expects to receive
    /// @param estimate_ If true, function will revert with estimated shares without executing the deposit
    /// @return shares_ The amount of shares minted for the deposit
    function deposit(
        uint token0Amt_,
        uint token1Amt_,
        uint minSharesAmt_,
        bool estimate_
    ) public payable returns (uint shares_) {
        return abi.decode(_spell(COL_OPERATIONS_IMPLEMENTATION, msg.data), (uint256));
    }

    /// @dev This function allows users to withdraw tokens in any proportion from the col pool
    /// @param token0Amt_ The amount of token0 to withdraw
    /// @param token1Amt_ The amount of token1 to withdraw
    /// @param maxSharesAmt_ The maximum number of shares the user is willing to burn
    /// @param to_ Recipient of withdrawn tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with shares_
    /// @return shares_ The number of shares burned for the withdrawal
    function withdraw(
        uint token0Amt_,
        uint token1Amt_,
        uint maxSharesAmt_,
        address to_
    ) public returns (uint shares_) {
        return abi.decode(_spell(COL_OPERATIONS_IMPLEMENTATION, msg.data), (uint256));
    }

    /// @dev This function allows users to borrow tokens in any proportion from the debt pool
    /// @param token0Amt_ The amount of token0 to borrow
    /// @param token1Amt_ The amount of token1 to borrow
    /// @param maxSharesAmt_ The maximum amount of shares the user is willing to receive
    /// @param to_ Recipient of borrowed tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with shares_
    /// @return shares_ The amount of borrow shares minted to represent the borrowed amount
    function borrow(
        uint token0Amt_,
        uint token1Amt_,
        uint maxSharesAmt_,
        address to_
    ) public returns (uint shares_) {
        return abi.decode(_spell(DEBT_OPERATIONS_IMPLEMENTATION, msg.data), (uint256));
    }

    /// @dev This function allows users to payback tokens in any proportion to the debt pool
    /// @param token0Amt_ The amount of token0 to payback
    /// @param token1Amt_ The amount of token1 to payback
    /// @param minSharesAmt_ The minimum amount of shares the user expects to burn
    /// @param estimate_ If true, function will revert with estimated shares without executing the payback
    /// @return shares_ The amount of borrow shares burned for the payback
    function payback(
        uint token0Amt_,
        uint token1Amt_,
        uint minSharesAmt_,
        bool estimate_
    ) public payable returns (uint shares_) {
        return abi.decode(_spell(DEBT_OPERATIONS_IMPLEMENTATION, msg.data), (uint256));
    }

    /// @dev This function allows users to withdraw their collateral with perfect shares in one token
    /// @param shares_ The number of shares to burn for withdrawal
    /// @param minToken0_ The minimum amount of token0 the user expects to receive (set to 0 if withdrawing in token1)
    /// @param minToken1_ The minimum amount of token1 the user expects to receive (set to 0 if withdrawing in token0)
    /// @param to_ Recipient of withdrawn tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with withdrawAmt_
    /// @return withdrawAmt_ The amount of tokens withdrawn in the chosen token
    function withdrawPerfectInOneToken(
        uint shares_,
        uint minToken0_,
        uint minToken1_,
        address to_
    ) public returns (uint withdrawAmt_) {
        return abi.decode(_spell(COL_OPERATIONS_IMPLEMENTATION, msg.data), (uint256));
    }

    /// @dev This function allows users to payback their debt with perfect shares in one token
    /// @param shares_ The number of shares to burn for payback
    /// @param maxToken0_ The maximum amount of token0 the user is willing to pay (set to 0 if paying back in token1)
    /// @param maxToken1_ The maximum amount of token1 the user is willing to pay (set to 0 if paying back in token0)
    /// @param estimate_ If true, the function will revert with the estimated payback amount without executing the payback
    /// @return paybackAmt_ The amount of tokens paid back in the chosen token
    function paybackPerfectInOneToken(
        uint shares_,
        uint maxToken0_,
        uint maxToken1_,
        bool estimate_
    ) public payable returns (uint paybackAmt_) {
        return abi.decode(_spell(DEBT_OPERATIONS_IMPLEMENTATION, msg.data), (uint256));
    }

    /// @dev liquidity callback for cheaper token transfers in case of deposit or payback.
    /// only callable by Liquidity during an operation.
    function liquidityCallback(address token_, uint amount_, bytes calldata data_) external {
        if (msg.sender != address(LIQUIDITY)) revert FluidDexError(ErrorTypes.DexT1__MsgSenderNotLiquidity);
        if (dexVariables & 1 == 0) revert FluidDexError(ErrorTypes.DexT1__ReentrancyBitShouldBeOn);
        if (data_.length != 96) revert FluidDexError(ErrorTypes.DexT1__IncorrectDataLength);

        (uint amountToSend_, bool isCallback_, address from_) = abi.decode(data_, (uint, bool, address));

        if (amountToSend_ < amount_) revert FluidDexError(ErrorTypes.DexT1__AmountToSendLessThanAmount);

        if (isCallback_) {
            IDexCallback(from_).dexCallback(token_, amountToSend_);
        } else {
            SafeTransfer.safeTransferFrom(token_, from_, address(LIQUIDITY), amountToSend_);
        }
    }

    /// @dev the oracle assumes last set price of pool till the next swap happens.
    /// There's a possibility that during that time some interest is generated hence the last stored price is not the 100% correct price for the whole duration
    /// but the difference due to interest will be super low so this difference is ignored
    /// For example 2 swaps happened 10min (600 seconds) apart and 1 token has 10% higher interest than other.
    /// then that token will accrue about 10% * 600 / secondsInAYear = ~0.0002%
    /// @param secondsAgos_ array of seconds ago for which TWAP is needed. If user sends [10, 30, 60] then twaps_ will return [10-0, 30-10, 60-30]
    /// @return twaps_ twap price, lowest price (aka minima) & highest price (aka maxima) between secondsAgo checkpoints
    /// @return currentPrice_ price of pool after the most recent swap
    function oraclePrice(
        uint[] memory secondsAgos_
    ) external view returns (Oracle[] memory twaps_, uint currentPrice_) {
        OraclePriceMemory memory o_;

        uint dexVariables_ = dexVariables;

        if ((dexVariables_ >> 195) & 1 == 0) {
            revert FluidDexError(ErrorTypes.DexT1__OracleNotActive);
        }

        twaps_ = new Oracle[](secondsAgos_.length);

        uint totalTime_;
        uint time_;

        uint i;
        uint secondsAgo_ = secondsAgos_[0];

        currentPrice_ = (dexVariables_ >> 41) & X40;
        currentPrice_ = (currentPrice_ >> DEFAULT_EXPONENT_SIZE) << (currentPrice_ & DEFAULT_EXPONENT_MASK);
        uint price_ = currentPrice_;
        o_.lowestPrice1by0 = currentPrice_;
        o_.highestPrice1by0 = currentPrice_;

        uint twap1by0_;
        uint twap0by1_;

        uint j;

        o_.oracleSlot = (dexVariables_ >> 176) & X3;
        o_.oracleMap = (dexVariables_ >> 179) & X16;
        // if o_.oracleSlot == 7 then it'll enter the if statement in the below while loop
        o_.oracle = o_.oracleSlot < 7 ? _oracle[o_.oracleMap] : 0;

        uint slotData_;
        uint percentDiff_;

        if (((dexVariables_ >> 121) & X33) < block.timestamp) {
            // last swap didn't occured in this block.
            // hence last price is current price of pool & also the last price
            time_ = block.timestamp - ((dexVariables_ >> 121) & X33);
        } else {
            // last swap occured in this block, that means current price is active for 0 secs. Hence TWAP for it will be 0.
            ++j;
        }

        while (true) {
            if (j == 2) {
                if (++o_.oracleSlot == 8) {
                    o_.oracleSlot = 0;
                    if (o_.oracleMap == 0) {
                        o_.oracleMap = TOTAL_ORACLE_MAPPING;
                    }
                    o_.oracle = _oracle[--o_.oracleMap];
                }

                slotData_ = (o_.oracle >> (o_.oracleSlot * 32)) & X32;
                if (slotData_ > 0) {
                    time_ = slotData_ & X9;
                    if (time_ == 0) {
                        // time is in precision & sign bits
                        time_ = slotData_ >> 9;
                        // if o_.oracleSlot is 7 then precision & bits and stored in 1 less map
                        if (o_.oracleSlot == 7) {
                            o_.oracleSlot = 0;
                            if (o_.oracleMap == 0) {
                                o_.oracleMap = TOTAL_ORACLE_MAPPING;
                            }
                            o_.oracle = _oracle[--o_.oracleMap];
                            slotData_ = o_.oracle & X32;
                        } else {
                            ++o_.oracleSlot;
                            slotData_ = (o_.oracle >> (o_.oracleSlot * 32)) & X32;
                        }
                    }
                    percentDiff_ = slotData_ >> 10;
                    percentDiff_ = (ORACLE_LIMIT * percentDiff_) / X22;
                    if (((slotData_ >> 9) & 1 == 1)) {
                        // if positive then old price was lower than current hence subtracting
                        price_ = price_ - (price_ * percentDiff_) / ORACLE_PRECISION;
                    } else {
                        // if negative then old price was higher than current hence adding
                        price_ = price_ + (price_ * percentDiff_) / ORACLE_PRECISION;
                    }
                } else {
                    // oracle data does not exist. Probably due to pool recently got initialized and not have much swaps.
                    revert FluidDexError(ErrorTypes.DexT1__InsufficientOracleData);
                }
            } else if (j == 1) {
                // last & last to last price
                price_ = (dexVariables_ >> 1) & X40;
                price_ = (price_ >> DEFAULT_EXPONENT_SIZE) << (price_ & DEFAULT_EXPONENT_MASK);
                time_ = (dexVariables_ >> 154) & X22;
                ++j;
            } else if (j == 0) {
                ++j;
            }

            totalTime_ += time_;
            if (o_.lowestPrice1by0 > price_) o_.lowestPrice1by0 = price_;
            if (o_.highestPrice1by0 < price_) o_.highestPrice1by0 = price_;
            if (totalTime_ < secondsAgo_) {
                twap1by0_ += price_ * time_;
                twap0by1_ += (1e54 / price_) * time_;
            } else {
                time_ = time_ + secondsAgo_ - totalTime_;
                twap1by0_ += price_ * time_;
                twap0by1_ += (1e54 / price_) * time_;
                // also auto checks that secondsAgos_ should not be == 0
                twap1by0_ = twap1by0_ / secondsAgo_;
                twap0by1_ = twap0by1_ / secondsAgo_;

                twaps_[i] = Oracle(
                    twap1by0_,
                    o_.lowestPrice1by0,
                    o_.highestPrice1by0,
                    twap0by1_,
                    (1e54 / o_.highestPrice1by0),
                    (1e54 / o_.lowestPrice1by0)
                );

                // TWAP for next secondsAgo will start with price_
                o_.lowestPrice1by0 = price_;
                o_.highestPrice1by0 = price_;

                while (++i < secondsAgos_.length) {
                    // secondsAgo_ = [60, 15, 0]
                    time_ = totalTime_ - secondsAgo_;
                    // updating total time as new seconds ago started
                    totalTime_ = time_;
                    // also auto checks that secondsAgos_[i + 1] > secondsAgos_[i]
                    secondsAgo_ = secondsAgos_[i] - secondsAgos_[i - 1];
                    if (totalTime_ < secondsAgo_) {
                        twap1by0_ = price_ * time_;
                        twap0by1_ = (1e54 / price_) * time_;
                        // if time_ comes out as 0 here then lowestPrice & highestPrice should not be price_, it should be next price_ that we will calculate
                        if (time_ == 0) {
                            o_.lowestPrice1by0 = type(uint).max;
                            o_.highestPrice1by0 = 0;
                        }
                        break;
                    } else {
                        time_ = time_ + secondsAgo_ - totalTime_;
                        // twap1by0_ = price_ here
                        twap1by0_ = price_ * time_;
                        // twap0by1_ = (1e54 / price_) * time_;
                        twap0by1_ = (1e54 / price_) * time_;
                        twap1by0_ = twap1by0_ / secondsAgo_;
                        twap0by1_ = twap0by1_ / secondsAgo_;
                        twaps_[i] = Oracle(
                            twap1by0_,
                            o_.lowestPrice1by0,
                            o_.highestPrice1by0,
                            twap0by1_,
                            (1e54 / o_.highestPrice1by0),
                            (1e54 / o_.lowestPrice1by0)
                        );
                    }
                }
                if (i == secondsAgos_.length) return (twaps_, currentPrice_); // oracle fetch over
            }
        }
    }

    function getPricesAndExchangePrices() public {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        _check(dexVariables_, dexVariables2_);

        PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices(dexVariables, dexVariables2);

        revert FluidDexPricesAndExchangeRates(pex_);
    }

    /// @dev Internal fallback function to handle calls to non-existent functions
    /// @notice This function is called when a transaction is sent to the contract without matching any other function
    /// @notice It checks if the caller is authorized, enables re-entrancy protection, delegates the call to the admin implementation, and then disables re-entrancy protection
    /// @notice Only authorized callers (global or dex auth) can trigger this function
    /// @notice This function uses assembly to perform a delegatecall to the admin implementation to update configs related to DEX
    function _fallback() private {
        if (!(DEX_FACTORY.isGlobalAuth(msg.sender) || DEX_FACTORY.isDexAuth(address(this), msg.sender))) {
            revert FluidDexError(ErrorTypes.DexT1__NotAnAuth);
        }

        uint dexVariables_ = dexVariables;
        if (dexVariables_ & 1 == 1) revert FluidDexError(ErrorTypes.DexT1__AlreadyEntered);
        // enabling re-entrancy
        dexVariables = dexVariables_ | 1;

        // Delegate the current call to `ADMIN_IMPLEMENTATION`.
        _spell(ADMIN_IMPLEMENTATION, msg.data);

        // disabling re-entrancy
        // directly fetching from storage so updates from Admin module will get auto covered
        dexVariables = dexVariables & ~uint(1);
    }

    fallback() external payable {
        _fallback();
    }

    receive() external payable {
        if (msg.sig != 0x00000000) {
            _fallback();
        }
    }

    /// @notice returns all Vault constants
    function constantsView() external view returns (ConstantViews memory constantsView_) {
        constantsView_.dexId = DEX_ID;
        constantsView_.liquidity = address(LIQUIDITY);
        constantsView_.factory = address(DEX_FACTORY);
        constantsView_.token0 = TOKEN_0;
        constantsView_.token1 = TOKEN_1;
        constantsView_.implementations.shift = SHIFT_IMPLEMENTATION;
        constantsView_.implementations.admin = ADMIN_IMPLEMENTATION;
        constantsView_.implementations.colOperations = COL_OPERATIONS_IMPLEMENTATION;
        constantsView_.implementations.debtOperations = DEBT_OPERATIONS_IMPLEMENTATION;
        constantsView_.implementations.perfectOperationsAndSwapOut = PERFECT_OPERATIONS_AND_SWAP_OUT_IMPLEMENTATION;
        constantsView_.deployerContract = DEPLOYER_CONTRACT;
        constantsView_.supplyToken0Slot = SUPPLY_TOKEN_0_SLOT;
        constantsView_.borrowToken0Slot = BORROW_TOKEN_0_SLOT;
        constantsView_.supplyToken1Slot = SUPPLY_TOKEN_1_SLOT;
        constantsView_.borrowToken1Slot = BORROW_TOKEN_1_SLOT;
        constantsView_.exchangePriceToken0Slot = EXCHANGE_PRICE_TOKEN_0_SLOT;
        constantsView_.exchangePriceToken1Slot = EXCHANGE_PRICE_TOKEN_1_SLOT;
        constantsView_.oracleMapping = TOTAL_ORACLE_MAPPING;
    }

    /// @notice returns all Vault constants
    function constantsView2() external view returns (ConstantViews2 memory constantsView2_) {
        constantsView2_.token0NumeratorPrecision = TOKEN_0_NUMERATOR_PRECISION;
        constantsView2_.token0DenominatorPrecision = TOKEN_0_DENOMINATOR_PRECISION;
        constantsView2_.token1NumeratorPrecision = TOKEN_1_NUMERATOR_PRECISION;
        constantsView2_.token1DenominatorPrecision = TOKEN_1_DENOMINATOR_PRECISION;
    }

    /// @notice Calculates the real and imaginary reserves for collateral tokens
    /// @dev This function retrieves the supply of both tokens from the liquidity layer,
    ///      adjusts them based on exchange prices, and calculates imaginary reserves
    ///      based on the geometric mean and price range
    /// @param geometricMean_ The geometric mean of the token prices
    /// @param upperRange_ The upper price range
    /// @param lowerRange_ The lower price range
    /// @param token0SupplyExchangePrice_ The exchange price for token0 from liquidity layer
    /// @param token1SupplyExchangePrice_ The exchange price for token1 from liquidity layer
    /// @return c_ A struct containing the calculated real and imaginary reserves for both tokens:
    ///         - token0RealReserves: The real reserves of token0
    ///         - token1RealReserves: The real reserves of token1
    ///         - token0ImaginaryReserves: The imaginary reserves of token0
    ///         - token1ImaginaryReserves: The imaginary reserves of token1
    function getCollateralReserves(
        uint geometricMean_,
        uint upperRange_,
        uint lowerRange_,
        uint token0SupplyExchangePrice_,
        uint token1SupplyExchangePrice_
    ) public view returns (CollateralReserves memory c_) {
        return
            _getCollateralReserves(
                geometricMean_,
                upperRange_,
                lowerRange_,
                token0SupplyExchangePrice_,
                token1SupplyExchangePrice_
            );
    }

    /// @notice Calculates the debt reserves for both tokens
    /// @param geometricMean_ The geometric mean of the upper and lower price ranges
    /// @param upperRange_ The upper price range
    /// @param lowerRange_ The lower price range
    /// @param token0BorrowExchangePrice_ The exchange price of token0 from liquidity layer
    /// @param token1BorrowExchangePrice_ The exchange price of token1 from liquidity layer
    /// @return d_ The calculated debt reserves for both tokens, containing:
    ///         - token0Debt: The debt amount of token0
    ///         - token1Debt: The debt amount of token1
    ///         - token0RealReserves: The real reserves of token0 derived from token1 debt
    ///         - token1RealReserves: The real reserves of token1 derived from token0 debt
    ///         - token0ImaginaryReserves: The imaginary debt reserves of token0
    ///         - token1ImaginaryReserves: The imaginary debt reserves of token1
    function getDebtReserves(
        uint geometricMean_,
        uint upperRange_,
        uint lowerRange_,
        uint token0BorrowExchangePrice_,
        uint token1BorrowExchangePrice_
    ) public view returns (DebtReserves memory d_) {
        return
            _getDebtReserves(
                geometricMean_,
                upperRange_,
                lowerRange_,
                token0BorrowExchangePrice_,
                token1BorrowExchangePrice_
            );
    }
}
