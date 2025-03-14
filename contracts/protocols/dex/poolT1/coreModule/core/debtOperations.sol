// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SecondaryHelpers } from "../helpers/secondaryHelpers.sol";
import { SafeTransfer } from "../../../../../libraries/safeTransfer.sol";
import { DexSlotsLink } from "../../../../../libraries/dexSlotsLink.sol";
import { DexCalcs } from "../../../../../libraries/dexCalcs.sol";
import { BigMathMinified } from "../../../../../libraries/bigMathMinified.sol";
import { ErrorTypes } from "../../../errorTypes.sol";

/// @title FluidDexT1
/// @notice Implements core logics for Fluid Dex protocol.
/// Note Token transfers happen directly from user to Liquidity contract and vice-versa.
contract FluidDexT1OperationsDebt is SecondaryHelpers {
    using BigMathMinified for uint256;

    constructor(ConstantViews memory constantViews_) SecondaryHelpers(constantViews_) {
        // all implementations should be zero other than shift
        if (
            constantViews_.implementations.shift == address(0) ||
            constantViews_.implementations.admin != address(0) ||
            constantViews_.implementations.colOperations != address(0) ||
            constantViews_.implementations.debtOperations != address(0) ||
            constantViews_.implementations.perfectOperationsAndSwapOut != address(0)
        ) {
            revert FluidDexError(ErrorTypes.DexT1__InvalidImplementation);
        }
    }

    modifier _onlyDelegateCall() {
        // also indirectly checked by `_check` because pool can never be initialized as long as the initialize method
        // is delegate call only, but just to be sure on Admin logic we add the modifier everywhere nonetheless.
        if (address(this) == THIS_CONTRACT) {
            revert FluidDexError(ErrorTypes.DexT1__OnlyDelegateCallAllowed);
        }
        _;
    }

    /// @dev This function allows users to borrow tokens in any proportion from the debt pool
    /// @param token0Amt_ The amount of token0 to borrow
    /// @param token1Amt_ The amount of token1 to borrow
    /// @param maxSharesAmt_ The maximum amount of shares the user is willing to receive
    /// @param to_ Recipient of swapped tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with shares_ 
    /// @return shares_ The amount of borrow shares minted to represent the borrowed amount
    function borrow(
        uint token0Amt_,
        uint token1Amt_,
        uint maxSharesAmt_,
        address to_
    ) public _onlyDelegateCall returns (uint shares_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        _check(dexVariables_, dexVariables2_);

        uint userBorrowData_ = _userBorrowData[msg.sender];

        if (userBorrowData_ & 1 == 0 && to_ != ADDRESS_DEAD) revert FluidDexError(ErrorTypes.DexT1__UserDebtInNotOn);

        BorrowDebtMemory memory b_;

        b_.to = (to_ == address(0)) ? msg.sender : to_;

        // is smart debt pool enabled
        if (((dexVariables2_ >> 1) & 1) == 1) {
            PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices(dexVariables_, dexVariables2_);

            uint token0Debt_ = _getLiquidityDebt(BORROW_TOKEN_0_SLOT, pex_.borrowToken0ExchangePrice, true);
            uint token1Debt_ = _getLiquidityDebt(BORROW_TOKEN_1_SLOT, pex_.borrowToken1ExchangePrice, false);
            b_.token0DebtInitial = token0Debt_;
            b_.token1DebtInitial = token1Debt_;

            if (token0Amt_ > 0) {
                b_.token0AmtAdjusted =
                    (((token0Amt_ + 1) * TOKEN_0_NUMERATOR_PRECISION) / TOKEN_0_DENOMINATOR_PRECISION) +
                    1;
                _verifySwapAndNonPerfectActions(b_.token0AmtAdjusted, token0Amt_);
                _verifyMint(b_.token0AmtAdjusted, token0Debt_);
            }

            if (token1Amt_ > 0) {
                b_.token1AmtAdjusted =
                    (((token1Amt_ + 1) * TOKEN_1_NUMERATOR_PRECISION) / TOKEN_1_DENOMINATOR_PRECISION) +
                    1;
                _verifySwapAndNonPerfectActions(b_.token1AmtAdjusted, token1Amt_);
                _verifyMint(b_.token1AmtAdjusted, token1Debt_);
            }

            uint temp_;
            uint temp2_;

            uint totalBorrowShares_ = _totalBorrowShares & X128;
            if ((token0Debt_ > 0) && (token1Debt_ > 0)) {
                if (b_.token0AmtAdjusted > 0 && b_.token1AmtAdjusted > 0) {
                    // mint shares in equal proportion
                    // temp_ => expected shares from token0 payback
                    temp_ = (b_.token0AmtAdjusted * 1e18) / token0Debt_;
                    // temp2_ => expected shares from token1 payback
                    temp2_ = (b_.token1AmtAdjusted * 1e18) / token1Debt_;
                    if (temp_ > temp2_) {
                        // use temp2_ shares
                        shares_ = (temp2_ * totalBorrowShares_) / 1e18;
                        // temp_ => token0 to swap
                        temp_ = ((temp_ - temp2_) * token0Debt_) / 1e18;
                        temp2_ = 0;
                    } else if (temp2_ > temp_) {
                        // use temp1_ shares
                        shares_ = (temp_ * totalBorrowShares_) / 1e18;
                        // temp2_ => token1 to swap
                        temp2_ = ((temp2_ - temp_) * token1Debt_) / 1e18;
                        temp_ = 0;
                    } else {
                        // if equal then revert as swap will not be needed anymore which can create some issue, better to use perfect borrow in this case
                        revert FluidDexError(ErrorTypes.DexT1__InvalidBorrowAmts);
                    }

                    // User borrowed in equal proportion here. Hence updating col reserves and the swap will happen on updated col reserves
                    token0Debt_ = token0Debt_ + (token0Debt_ * shares_) / totalBorrowShares_;
                    token1Debt_ = token1Debt_ + (token1Debt_ * shares_) / totalBorrowShares_;
                    totalBorrowShares_ += shares_;
                } else if (b_.token0AmtAdjusted > 0) {
                    temp_ = b_.token0AmtAdjusted;
                    temp2_ = 0;
                } else if (b_.token1AmtAdjusted > 0) {
                    temp_ = 0;
                    temp2_ = b_.token1AmtAdjusted;
                } else {
                    // user sent both amounts as 0
                    revert FluidDexError(ErrorTypes.DexT1__InvalidBorrowAmts);
                }

                uint token0FinalImaginaryReserves_;
                uint token1FinalImaginaryReserves_;

                if (pex_.geometricMean < 1e27) {
                    (, , token0FinalImaginaryReserves_, token1FinalImaginaryReserves_) = _calculateDebtReserves(
                        pex_.geometricMean,
                        pex_.lowerRange,
                        (token0Debt_ + temp_),
                        (token1Debt_ + temp2_)
                    );
                } else {
                    // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
                    // 1 / geometricMean for new geometricMean
                    // 1 / lowerRange will become upper range
                    // 1 / upperRange will become lower range
                    (, , token1FinalImaginaryReserves_, token0FinalImaginaryReserves_) = _calculateDebtReserves(
                        (1e54 / pex_.geometricMean),
                        (1e54 / pex_.upperRange),
                        (token1Debt_ + temp2_),
                        (token0Debt_ + temp_)
                    );
                }

                if (temp_ > 0) {
                    // swap into token0
                    temp_ = _getBorrowAndSwap(
                        token0Debt_, // token0 debt
                        token1Debt_, // token1 debt
                        token0FinalImaginaryReserves_, // token0 imaginary reserves
                        token1FinalImaginaryReserves_, // token1 imaginary reserves
                        temp_ // token0 to divide and swap into
                    );
                } else if (temp2_ > 0) {
                    // swap into token1
                    temp_ = _getBorrowAndSwap(
                        token1Debt_, // token1 debt
                        token0Debt_, // token0 debt
                        token1FinalImaginaryReserves_, // token1 imaginary reserves
                        token0FinalImaginaryReserves_, // token0 imaginary reserves
                        temp2_ // token1 to divide and swap into
                    );
                } else {
                    // maybe possible to happen due to some precision issue that both are 0
                    revert FluidDexError(ErrorTypes.DexT1__BorrowAmtsZero);
                }

                // new shares to mint from borrow & swap
                temp_ = (temp_ * totalBorrowShares_) / 1e18;
                // adding fee in case of borrow & swap
                // 1 + fee. If fee is 1% then withdrawing withFepex_ will be 1e6 + 1e4
                temp_ = (temp_ * (SIX_DECIMALS + ((dexVariables2_ >> 2) & X17))) / SIX_DECIMALS;
                // final new shares to mint for user
                shares_ += temp_;
                // final new debt shares
                totalBorrowShares_ += temp_;
            } else {
                revert FluidDexError(ErrorTypes.DexT1__InvalidDebtReserves);
            }

            if (to_ == ADDRESS_DEAD) revert FluidDexLiquidityOutput(shares_);

            if (shares_ > maxSharesAmt_) revert FluidDexError(ErrorTypes.DexT1__BorrowExcessSharesMinted);

            // extract user borrow amount
            // userBorrow_ => temp_
            temp_ = (userBorrowData_ >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
            temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

            // calculate current, updated (expanded etc.) borrow limit
            // newBorrowLimit_ => temp2_
            temp2_ = DexCalcs.calcBorrowLimitBeforeOperate(userBorrowData_, temp_);

            temp_ += shares_;

            // user above debt limit
            if (temp_ > temp2_) revert FluidDexError(ErrorTypes.DexT1__DebtLimitReached);

            _updatingUserBorrowDataOnStorage(userBorrowData_, temp_, temp2_);

            if (b_.token0AmtAdjusted > 0) {
                // comparing debt here rather than reserves to simply code, impact won't be much overall
                _verifyToken1Reserves(
                    (b_.token0DebtInitial + b_.token0AmtAdjusted),
                    (b_.token1DebtInitial + b_.token1AmtAdjusted),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );
                // assigning token0Amt_ to temp_ to avoid compilation error (I don't know why it's throwing when using token0Amt_ directly)
                temp_ = token0Amt_;
                // borrow
                LIQUIDITY.operate(TOKEN_0, 0, int(temp_), address(0), b_.to, new bytes(0));
            }

            if (b_.token1AmtAdjusted > 0) {
                // comparing debt here rather than reserves to simply code, impact won't be much overall
                _verifyToken0Reserves(
                    (b_.token0DebtInitial + b_.token0AmtAdjusted),
                    (b_.token1DebtInitial + b_.token1AmtAdjusted),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );
                // assigning token1Amt_ to temp_ to avoid compilation error (I don't know why it's throwing when using token0Amt_ directly)
                temp_ = token1Amt_;
                // borrow
                LIQUIDITY.operate(TOKEN_1, 0, int(temp_), address(0), b_.to, new bytes(0));
            }

            // updating total debt shares in storage
            _updateBorrowShares(totalBorrowShares_);

            emit LogBorrowDebtLiquidity(token0Amt_, token1Amt_, shares_);

            _arbitrage(dexVariables_, dexVariables2_, pex_);
        } else {
            revert FluidDexError(ErrorTypes.DexT1__SmartDebtNotEnabled);
        }
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
    ) public payable _onlyDelegateCall returns (uint shares_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        _check(dexVariables_, dexVariables2_);

        uint userBorrowData_ = _userBorrowData[msg.sender];

        if (userBorrowData_ & 1 == 0 && !estimate_) revert FluidDexError(ErrorTypes.DexT1__UserDebtInNotOn);

        // is smart debt pool enabled
        if (((dexVariables2_ >> 1) & 1) == 1) {
            PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices(dexVariables_, dexVariables2_);

            PaybackDebtMemory memory p_;

            DebtReserves memory d_ = _getDebtReserves(
                pex_.geometricMean,
                pex_.upperRange,
                pex_.lowerRange,
                pex_.borrowToken0ExchangePrice,
                pex_.borrowToken1ExchangePrice
            );
            DebtReserves memory d2_ = d_;

            if (token0Amt_ > 0) {
                p_.token0AmtAdjusted =
                    (((token0Amt_ - 1) * TOKEN_0_NUMERATOR_PRECISION) / TOKEN_0_DENOMINATOR_PRECISION) -
                    1;
                _verifySwapAndNonPerfectActions(p_.token0AmtAdjusted, token0Amt_);
                _verifyRedeem(p_.token0AmtAdjusted, d_.token0Debt);
            }

            if (token1Amt_ > 0) {
                p_.token1AmtAdjusted =
                    (((token1Amt_ - 1) * TOKEN_1_NUMERATOR_PRECISION) / TOKEN_1_DENOMINATOR_PRECISION) -
                    1;
                _verifySwapAndNonPerfectActions(p_.token1AmtAdjusted, token1Amt_);
                _verifyRedeem(p_.token1AmtAdjusted, d_.token1Debt);
            }

            uint temp_;
            uint temp2_;

            uint totalBorrowShares_ = _totalBorrowShares & X128;
            if ((d_.token0Debt > 0) && (d_.token1Debt > 0)) {
                if (p_.token0AmtAdjusted > 0 && p_.token1AmtAdjusted > 0) {
                    // burn shares in equal proportion
                    // temp_ => expected shares from token0 payback
                    temp_ = (p_.token0AmtAdjusted * 1e18) / d_.token0Debt;
                    // temp2_ => expected shares from token1 payback
                    temp2_ = (p_.token1AmtAdjusted * 1e18) / d_.token1Debt;
                    if (temp_ > temp2_) {
                        // use temp2_ shares
                        shares_ = ((temp2_ * totalBorrowShares_) / 1e18);
                        // temp_ => token0 to swap
                        temp_ = p_.token0AmtAdjusted - (temp2_ * p_.token0AmtAdjusted) / temp_;
                        temp2_ = 0;
                    } else if (temp2_ > temp_) {
                        // use temp_ shares
                        shares_ = ((temp_ * totalBorrowShares_) / 1e18);
                        // temp2_ => token1 to swap
                        temp2_ = p_.token1AmtAdjusted - ((temp_ * p_.token1AmtAdjusted) / temp2_); // to this
                        temp_ = 0;
                    } else {
                        // if equal then revert as swap will not be needed anymore which can create some issue, better to use perfect payback in this case
                        revert FluidDexError(ErrorTypes.DexT1__InvalidPaybackAmts);
                    }

                    // User paid back in equal proportion here. Hence updating debt reserves and the swap will happen on updated debt reserves
                    d2_ = _getUpdateDebtReserves(
                        shares_,
                        totalBorrowShares_,
                        d_,
                        false // true if mint, false if burn
                    );
                    totalBorrowShares_ -= shares_;
                } else if (p_.token0AmtAdjusted > 0) {
                    temp_ = p_.token0AmtAdjusted;
                    temp2_ = 0;
                } else if (p_.token1AmtAdjusted > 0) {
                    temp_ = 0;
                    temp2_ = p_.token1AmtAdjusted;
                } else {
                    // user sent both amounts as 0
                    revert FluidDexError(ErrorTypes.DexT1__InvalidPaybackAmts);
                }

                if (temp_ > 0) {
                    // swap token0 into token1 and payback equally
                    temp_ = _getSwapAndPayback(
                        d2_.token0Debt,
                        d2_.token1Debt,
                        d2_.token0ImaginaryReserves,
                        d2_.token1ImaginaryReserves,
                        temp_
                    );
                } else if (temp2_ > 0) {
                    // swap token1 into token0 and payback equally
                    temp_ = _getSwapAndPayback(
                        d2_.token1Debt,
                        d2_.token0Debt,
                        d2_.token1ImaginaryReserves,
                        d2_.token0ImaginaryReserves,
                        temp2_
                    );
                } else {
                    // maybe possible to happen due to some precision issue that both are 0
                    revert FluidDexError(ErrorTypes.DexT1__PaybackAmtsZero);
                }

                // new shares to burn from payback & swap
                temp_ = ((temp_ * totalBorrowShares_) / 1e18);

                // adding fee in case of payback & swap
                // 1 - fee. If fee is 1% then withdrawing withFepex_ will be 1e6 - 1e4
                temp_ = (temp_ * (SIX_DECIMALS - ((dexVariables2_ >> 2) & X17))) / SIX_DECIMALS;
                // final shares to burn for user
                shares_ += temp_;
                // final new debt shares
                totalBorrowShares_ -= temp_;
            } else {
                revert FluidDexError(ErrorTypes.DexT1__InvalidDebtReserves);
            }

            if (estimate_) revert FluidDexLiquidityOutput(shares_);

            if (shares_ < minSharesAmt_) revert FluidDexError(ErrorTypes.DexT1__PaybackSharedBurnedLess);

            if (token0Amt_ > 0) {
                // comparing debt here rather than reserves to simply code, impact won't be much overall
                _verifyToken0Reserves(
                    (d_.token0Debt - p_.token0AmtAdjusted),
                    (d_.token1Debt - p_.token1AmtAdjusted),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );
                // payback
                temp_ = token0Amt_;
                _depositOrPaybackInLiquidity(TOKEN_0, 0, temp_);
            }

            if (token1Amt_ > 0) {
                // comparing debt here rather than reserves to simply code, impact won't be much overall
                _verifyToken1Reserves(
                    (d_.token0Debt - p_.token0AmtAdjusted),
                    (d_.token1Debt - p_.token1AmtAdjusted),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );
                // payback
                temp_ = token1Amt_;
                _depositOrPaybackInLiquidity(TOKEN_1, 0, temp_);
            }

            // extract user borrow amount
            // userBorrow_ => temp_
            temp_ = (userBorrowData_ >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
            temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

            // calculate current, updated (expanded etc.) borrow limit
            // newBorrowLimit_ => temp2_
            temp2_ = DexCalcs.calcBorrowLimitBeforeOperate(userBorrowData_, temp_);

            temp_ -= shares_;

            _updatingUserBorrowDataOnStorage(userBorrowData_, temp_, temp2_);
            // updating total debt shares in storage
            _updateBorrowShares(totalBorrowShares_);

            emit LogPaybackDebtLiquidity(token0Amt_, token1Amt_, shares_);

            _arbitrage(dexVariables_, dexVariables2_, pex_);
        } else {
            revert FluidDexError(ErrorTypes.DexT1__SmartDebtNotEnabled);
        }
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
    ) public payable _onlyDelegateCall returns (uint paybackAmt_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        _check(dexVariables_, dexVariables2_);

        uint userBorrowData_ = _userBorrowData[msg.sender];

        if (userBorrowData_ & 1 == 0 && !estimate_) revert FluidDexError(ErrorTypes.DexT1__UserDebtInNotOn);

        if ((maxToken0_ > 0 && maxToken1_ > 0) || (maxToken0_ == 0 && maxToken1_ == 0)) {
            // only 1 token should be > 0
            revert FluidDexError(ErrorTypes.DexT1__InvalidWithdrawAmts);
        }

        // is smart debt pool enabled
        if (((dexVariables2_ >> 1) & 1) == 1) {
            PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices(dexVariables_, dexVariables2_);

            uint totalBorrowShares_ = _totalBorrowShares & X128;

            _verifyRedeem(shares_, totalBorrowShares_);

            uint token0Amt_;
            uint token1Amt_;

            // smart debt in enabled
            DebtReserves memory d_ = _getDebtReserves(
                pex_.geometricMean,
                pex_.upperRange,
                pex_.lowerRange,
                pex_.borrowToken0ExchangePrice,
                pex_.borrowToken1ExchangePrice
            );

            if ((d_.token0Debt == 0) || (d_.token1Debt == 0)) {
                revert FluidDexError(ErrorTypes.DexT1__InvalidDebtReserves);
            }

            // Removing debt liquidity in equal proportion
            DebtReserves memory d2_ = _getUpdateDebtReserves(shares_, totalBorrowShares_, d_, false);

            if (maxToken0_ > 0) {
                // entire payback is in token0_
                token0Amt_ = _getSwapAndPaybackOneTokenPerfectShares(
                    d2_.token0ImaginaryReserves,
                    d2_.token1ImaginaryReserves,
                    d_.token0Debt,
                    d_.token1Debt,
                    d2_.token0RealReserves,
                    d2_.token1RealReserves
                );
                _verifyToken0Reserves(
                    (d_.token0Debt - token0Amt_),
                    d_.token1Debt,
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );

                // converting from raw/adjusted to normal token amounts
                token0Amt_ = (((token0Amt_ + 1) * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION) + 1;

                // adding fee on paying back in 1 token
                token0Amt_ = (token0Amt_ * (SIX_DECIMALS + ((dexVariables2_ >> 2) & X17))) / SIX_DECIMALS;

                paybackAmt_ = token0Amt_;
                if (estimate_) revert FluidDexSingleTokenOutput(paybackAmt_);
                if (paybackAmt_ > maxToken0_) revert FluidDexError(ErrorTypes.DexT1__PaybackAmtTooHigh);
                _depositOrPaybackInLiquidity(TOKEN_0, 0, paybackAmt_);
            } else {
                // entire payback is in token1_
                token1Amt_ = _getSwapAndPaybackOneTokenPerfectShares(
                    d2_.token1ImaginaryReserves,
                    d2_.token0ImaginaryReserves,
                    d_.token1Debt,
                    d_.token0Debt,
                    d2_.token1RealReserves,
                    d2_.token0RealReserves
                );
                _verifyToken1Reserves(
                    d_.token0Debt,
                    (d_.token1Debt - token1Amt_),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );

                // converting from raw/adjusted to normal token amounts
                token1Amt_ = (((token1Amt_ + 1) * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION) + 1;

                // adding fee on paying back in 1 token
                token1Amt_ = (token1Amt_ * (SIX_DECIMALS + ((dexVariables2_ >> 2) & X17))) / SIX_DECIMALS;

                paybackAmt_ = token1Amt_;
                if (estimate_) revert FluidDexSingleTokenOutput(paybackAmt_);
                if (paybackAmt_ > maxToken1_) revert FluidDexError(ErrorTypes.DexT1__PaybackAmtTooHigh);
                _depositOrPaybackInLiquidity(TOKEN_1, 0, paybackAmt_);
            }

            // extract user borrow amount
            uint256 userBorrow_ = (userBorrowData_ >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
            userBorrow_ = (userBorrow_ >> DEFAULT_EXPONENT_SIZE) << (userBorrow_ & DEFAULT_EXPONENT_MASK);

            // calculate current, updated (expanded etc.) borrow limit
            // temp_ => newBorrowLimit_
            uint256 temp_ = DexCalcs.calcBorrowLimitBeforeOperate(userBorrowData_, userBorrow_);
            userBorrow_ -= shares_;

            _updatingUserBorrowDataOnStorage(userBorrowData_, userBorrow_, temp_);

            totalBorrowShares_ = totalBorrowShares_ - shares_;
            _updateBorrowShares(totalBorrowShares_);

            // to avoid stack-too-deep error
            temp_ = shares_;
            emit LogPaybackDebtInOneToken(temp_, token0Amt_, token1Amt_);

            _arbitrage(dexVariables_, dexVariables2_, pex_);
        } else {
            revert FluidDexError(ErrorTypes.DexT1__SmartDebtNotEnabled);
        }
    }
}
