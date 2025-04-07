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
contract FluidDexT1OperationsCol is SecondaryHelpers {
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
    ) public payable _onlyDelegateCall returns (uint shares_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        _check(dexVariables_, dexVariables2_);

        uint userSupplyData_ = _userSupplyData[msg.sender];

        if (userSupplyData_ & 1 == 0 && !estimate_) revert FluidDexError(ErrorTypes.DexT1__UserSupplyInNotOn);

        // is smart collateral pool enabled
        if ((dexVariables2_ & 1) == 1) {
            PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices(dexVariables_, dexVariables2_);

            DepositColMemory memory d_;

            CollateralReserves memory c_ = _getCollateralReserves(
                pex_.geometricMean,
                pex_.upperRange,
                pex_.lowerRange,
                pex_.supplyToken0ExchangePrice,
                pex_.supplyToken1ExchangePrice
            );
            CollateralReserves memory c2_ = c_;

            if (token0Amt_ > 0) {
                d_.token0AmtAdjusted =
                    (((token0Amt_ - 1) * TOKEN_0_NUMERATOR_PRECISION) / TOKEN_0_DENOMINATOR_PRECISION) -
                    1;
                _verifySwapAndNonPerfectActions(d_.token0AmtAdjusted, token0Amt_);
                _verifyMint(d_.token0AmtAdjusted, c_.token0RealReserves);
            }

            if (token1Amt_ > 0) {
                d_.token1AmtAdjusted =
                    (((token1Amt_ - 1) * TOKEN_1_NUMERATOR_PRECISION) / TOKEN_1_DENOMINATOR_PRECISION) -
                    1;
                _verifySwapAndNonPerfectActions(d_.token1AmtAdjusted, token1Amt_);
                _verifyMint(d_.token1AmtAdjusted, c_.token1RealReserves);
            }

            uint temp_;
            uint temp2_;

            uint totalSupplyShares_ = _totalSupplyShares & X128;
            if ((c_.token0RealReserves > 0) && (c_.token1RealReserves > 0)) {
                if (d_.token0AmtAdjusted > 0 && d_.token1AmtAdjusted > 0) {
                    // mint shares in equal proportion
                    // temp_ => expected shares from token0 deposit
                    temp_ = (d_.token0AmtAdjusted * 1e18) / c_.token0RealReserves;
                    // temp2_ => expected shares from token1 deposit
                    temp2_ = (d_.token1AmtAdjusted * 1e18) / c_.token1RealReserves;
                    if (temp_ > temp2_) {
                        // use temp2_ shares
                        shares_ = (temp2_ * totalSupplyShares_) / 1e18;
                        // temp_ => token0 to swap
                        temp_ = ((temp_ - temp2_) * c_.token0RealReserves) / 1e18;
                        temp2_ = 0;
                    } else if (temp2_ > temp_) {
                        // use temp_ shares
                        shares_ = (temp_ * totalSupplyShares_) / 1e18;
                        // temp2_ => token1 to swap
                        temp2_ = ((temp2_ - temp_) * c_.token1RealReserves) / 1e18;
                        temp_ = 0;
                    } else {
                        // if equal then revert as swap will not be needed anymore which can create some issue, better to use depositPerfect in this case
                        revert FluidDexError(ErrorTypes.DexT1__InvalidDepositAmts);
                    }

                    // User deposited in equal proportion here. Hence updating col reserves and the swap will happen on updated col reserves
                    c2_ = _getUpdatedColReserves(shares_, totalSupplyShares_, c_, true);

                    totalSupplyShares_ += shares_;
                } else if (d_.token0AmtAdjusted > 0) {
                    temp_ = d_.token0AmtAdjusted;
                    temp2_ = 0;
                } else if (d_.token1AmtAdjusted > 0) {
                    temp_ = 0;
                    temp2_ = d_.token1AmtAdjusted;
                } else {
                    // user sent both amounts as 0
                    revert FluidDexError(ErrorTypes.DexT1__InvalidDepositAmts);
                }

                if (temp_ > 0) {
                    // swap token0
                    temp_ = _getSwapAndDeposit(
                        temp_, // token0 to divide and swap
                        c2_.token1ImaginaryReserves, // token1 imaginary reserves
                        c2_.token0ImaginaryReserves, // token0 imaginary reserves
                        c2_.token0RealReserves, // token0 real reserves
                        c2_.token1RealReserves // token1 real reserves
                    );
                } else if (temp2_ > 0) {
                    // swap token1
                    temp_ = _getSwapAndDeposit(
                        temp2_, // token1 to divide and swap
                        c2_.token0ImaginaryReserves, // token0 imaginary reserves
                        c2_.token1ImaginaryReserves, // token1 imaginary reserves
                        c2_.token1RealReserves, // token1 real reserves
                        c2_.token0RealReserves // token0 real reserves
                    );
                } else {
                    // maybe possible to happen due to some precision issue that both are 0
                    revert FluidDexError(ErrorTypes.DexT1__DepositAmtsZero);
                }

                // new shares minted from swap & deposit
                temp_ = (temp_ * totalSupplyShares_) / 1e18;
                // adding fee in case of swap & deposit
                // 1 - fee. If fee is 1% then without fee will be 1e6 - 1e4
                // temp_ => withdraw fee
                temp_ = (temp_ * (SIX_DECIMALS - ((dexVariables2_ >> 2) & X17))) / SIX_DECIMALS;
                // final new shares to mint for user
                shares_ += temp_;
                // final new collateral shares
                totalSupplyShares_ += temp_;
            } else {
                revert FluidDexError(ErrorTypes.DexT1__InvalidCollateralReserves);
            }

            if (estimate_) revert FluidDexLiquidityOutput(shares_);

            if (shares_ < minSharesAmt_) revert FluidDexError(ErrorTypes.DexT1__SharesMintedLess);

            if (token0Amt_ > 0) {
                _verifyToken1Reserves(
                    (c_.token0RealReserves + d_.token0AmtAdjusted),
                    (c_.token1RealReserves + d_.token1AmtAdjusted),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );
                temp_ = token0Amt_;
                _depositOrPaybackInLiquidity(TOKEN_0, temp_, 0);
            }

            if (token1Amt_ > 0) {
                _verifyToken0Reserves(
                    (c_.token0RealReserves + d_.token0AmtAdjusted),
                    (c_.token1RealReserves + d_.token1AmtAdjusted),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );
                temp_ = token1Amt_;
                _depositOrPaybackInLiquidity(TOKEN_1, temp_, 0);
            }

            // userSupply_ => temp_
            temp_ = (userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
            // extracting exisiting shares and then adding new shares in it
            temp_ = ((temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK));

            // calculate current, updated (expanded etc.) withdrawal limit
            // newWithdrawalLimit_ => temp2_
            temp2_ = DexCalcs.calcWithdrawalLimitBeforeOperate(userSupplyData_, temp_);

            temp_ += shares_;

            _updatingUserSupplyDataOnStorage(userSupplyData_, temp_, temp2_);

            // updating total col shares in storage
            _updateSupplyShares(totalSupplyShares_);

            emit LogDepositColLiquidity(token0Amt_, token1Amt_, shares_);

            _arbitrage(dexVariables_, dexVariables2_, pex_);
        } else {
            revert FluidDexError(ErrorTypes.DexT1__SmartColNotEnabled);
        }
    }

    /// @dev This function allows users to withdraw tokens in any proportion from the col pool
    /// @param token0Amt_ The amount of token0 to withdraw
    /// @param token1Amt_ The amount of token1 to withdraw
    /// @param maxSharesAmt_ The maximum number of shares the user is willing to burn
    /// @param to_ Recipient of swapped tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with shares_
    /// @return shares_ The number of shares burned for the withdrawal
    function withdraw(
        uint token0Amt_,
        uint token1Amt_,
        uint maxSharesAmt_,
        address to_
    ) public _onlyDelegateCall returns (uint shares_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        _check(dexVariables_, dexVariables2_);

        uint userSupplyData_ = _userSupplyData[msg.sender];

        if (userSupplyData_ & 1 == 0 && to_ != ADDRESS_DEAD) revert FluidDexError(ErrorTypes.DexT1__UserSupplyInNotOn);

        WithdrawColMemory memory w_;

        w_.to = (to_ == address(0)) ? msg.sender : to_;

        // is smart collateral pool enabled
        if ((dexVariables2_ & 1) == 1) {
            PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices(dexVariables_, dexVariables2_);

            uint token0Reserves_ = _getLiquidityCollateral(SUPPLY_TOKEN_0_SLOT, pex_.supplyToken0ExchangePrice, true);
            uint token1Reserves_ = _getLiquidityCollateral(SUPPLY_TOKEN_1_SLOT, pex_.supplyToken1ExchangePrice, false);
            w_.token0ReservesInitial = token0Reserves_;
            w_.token1ReservesInitial = token1Reserves_;

            if (token0Amt_ > 0) {
                unchecked {
                    w_.token0AmtAdjusted =
                        (((token0Amt_ + 1) * TOKEN_0_NUMERATOR_PRECISION) / TOKEN_0_DENOMINATOR_PRECISION) +
                        1;
                }
                _verifySwapAndNonPerfectActions(w_.token0AmtAdjusted, token0Amt_);
                _verifyRedeem(w_.token0AmtAdjusted, token0Reserves_);
            }

            if (token1Amt_ > 0) {
                unchecked {
                    w_.token1AmtAdjusted =
                        (((token1Amt_ + 1) * TOKEN_1_NUMERATOR_PRECISION) / TOKEN_1_DENOMINATOR_PRECISION) +
                        1;
                }
                _verifySwapAndNonPerfectActions(w_.token1AmtAdjusted, token1Amt_);
                _verifyRedeem(w_.token1AmtAdjusted, token1Reserves_);
            }

            uint temp_;
            uint temp2_;

            uint totalSupplyShares_ = _totalSupplyShares & X128;
            if ((token0Reserves_ > 0) && (token1Reserves_ > 0)) {
                if (w_.token0AmtAdjusted > 0 && w_.token1AmtAdjusted > 0) {
                    // mint shares in equal proportion
                    // temp_ => expected shares from token0 withdraw
                    temp_ = (w_.token0AmtAdjusted * 1e18) / token0Reserves_;
                    // temp2_ => expected shares from token1 withdraw
                    temp2_ = (w_.token1AmtAdjusted * 1e18) / token1Reserves_;
                    if (temp_ > temp2_) {
                        // use temp2_ shares
                        shares_ = ((temp2_ * totalSupplyShares_) / 1e18);
                        // temp_ => token0 to swap
                        temp_ = ((temp_ - temp2_) * token0Reserves_) / 1e18;
                        temp2_ = 0;
                    } else if (temp2_ > temp_) {
                        // use temp1_ shares
                        shares_ = ((temp_ * totalSupplyShares_) / 1e18);
                        // temp2_ => token1 to swap
                        temp2_ = ((temp2_ - temp_) * token1Reserves_) / 1e18;
                        temp_ = 0;
                    } else {
                        // if equal then revert as swap will not be needed anymore which can create some issue, better to use withdraw in perfect proportion for this
                        revert FluidDexError(ErrorTypes.DexT1__InvalidWithdrawAmts);
                    }

                    // User withdrew in equal proportion here. Hence updating col reserves and the swap will happen on updated col reserves
                    token0Reserves_ = token0Reserves_ - ((token0Reserves_ * shares_) / totalSupplyShares_);
                    token1Reserves_ = token1Reserves_ - ((token1Reserves_ * shares_) / totalSupplyShares_);
                    totalSupplyShares_ -= shares_;
                } else if (w_.token0AmtAdjusted > 0) {
                    temp_ = w_.token0AmtAdjusted;
                    temp2_ = 0;
                } else if (w_.token1AmtAdjusted > 0) {
                    temp_ = 0;
                    temp2_ = w_.token1AmtAdjusted;
                } else {
                    // user sent both amounts as 0
                    revert FluidDexError(ErrorTypes.DexT1__WithdrawAmtsZero);
                }

                uint token0ImaginaryReservesOutsideRangpex_;
                uint token1ImaginaryReservesOutsideRangpex_;

                if (pex_.geometricMean < 1e27) {
                    (
                        token0ImaginaryReservesOutsideRangpex_,
                        token1ImaginaryReservesOutsideRangpex_
                    ) = _calculateReservesOutsideRange(
                        pex_.geometricMean,
                        pex_.upperRange,
                        (token0Reserves_ - temp_),
                        (token1Reserves_ - temp2_)
                    );
                } else {
                    // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
                    // 1 / geometricMean for new geometricMean
                    // 1 / lowerRange will become upper range
                    // 1 / upperRange will become lower range
                    (
                        token1ImaginaryReservesOutsideRangpex_,
                        token0ImaginaryReservesOutsideRangpex_
                    ) = _calculateReservesOutsideRange(
                        (1e54 / pex_.geometricMean),
                        (1e54 / pex_.lowerRange),
                        (token1Reserves_ - temp2_),
                        (token0Reserves_ - temp_)
                    );
                }

                if (temp_ > 0) {
                    // swap into token0
                    temp_ = _getWithdrawAndSwap(
                        token0Reserves_, // token0 real reserves
                        token1Reserves_, // token1 real reserves
                        token0ImaginaryReservesOutsideRangpex_, // token0 imaginary reserves
                        token1ImaginaryReservesOutsideRangpex_, // token1 imaginary reserves
                        temp_ // token0 to divide and swap into
                    );
                } else if (temp2_ > 0) {
                    // swap into token1
                    temp_ = _getWithdrawAndSwap(
                        token1Reserves_, // token1 real reserves
                        token0Reserves_, // token0 real reserves
                        token1ImaginaryReservesOutsideRangpex_, // token1 imaginary reserves
                        token0ImaginaryReservesOutsideRangpex_, // token0 imaginary reserves
                        temp2_ // token0 to divide and swap into
                    );
                } else {
                    // maybe possible to happen due to some precision issue that both are 0
                    revert FluidDexError(ErrorTypes.DexT1__WithdrawAmtsZero);
                }

                // shares to burn from withdraw & swap
                temp_ = ((temp_ * totalSupplyShares_) / 1e18);
                // adding fee in case of withdraw & swap
                // 1 + fee. If fee is 1% then withdrawing withFepex_ will be 1e6 + 1e4
                temp_ = (temp_ * (SIX_DECIMALS + ((dexVariables2_ >> 2) & X17))) / SIX_DECIMALS;
                // updating shares to burn for user
                shares_ += temp_;
                // final new collateral shares
                totalSupplyShares_ -= temp_;
            } else {
                revert FluidDexError(ErrorTypes.DexT1__InvalidCollateralReserves);
            }

            if (to_ == ADDRESS_DEAD) revert FluidDexLiquidityOutput(shares_);

            if (shares_ > maxSharesAmt_) revert FluidDexError(ErrorTypes.DexT1__WithdrawExcessSharesBurn);

            // userSupply_ => temp_
            temp_ = (userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
            temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

            // calculate current, updated (expanded etc.) withdrawal limit
            // newWithdrawalLimit_ => temp2_
            temp2_ = DexCalcs.calcWithdrawalLimitBeforeOperate(userSupplyData_, temp_);

            temp_ -= shares_;

            // withdrawal limit reached
            if (temp_ < temp2_) revert FluidDexError(ErrorTypes.DexT1__WithdrawLimitReached);

            _updatingUserSupplyDataOnStorage(userSupplyData_, temp_, temp2_);

            // updating total col shares in storage
            _updateSupplyShares(totalSupplyShares_);

            if (w_.token0AmtAdjusted > 0) {
                _verifyToken0Reserves(
                    (w_.token0ReservesInitial - w_.token0AmtAdjusted),
                    (w_.token1ReservesInitial - w_.token1AmtAdjusted),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );
                // withdraw
                temp_ = token0Amt_;
                LIQUIDITY.operate(TOKEN_0, -int(temp_), 0, w_.to, address(0), new bytes(0));
            }

            if (w_.token1AmtAdjusted > 0) {
                _verifyToken1Reserves(
                    (w_.token0ReservesInitial - w_.token0AmtAdjusted),
                    (w_.token1ReservesInitial - w_.token1AmtAdjusted),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );
                // withdraw
                temp_ = token1Amt_;
                LIQUIDITY.operate(TOKEN_1, -int(temp_), 0, w_.to, address(0), new bytes(0));
            }

            emit LogWithdrawColLiquidity(token0Amt_, token1Amt_, shares_);

            _arbitrage(dexVariables_, dexVariables2_, pex_);
        } else {
            revert FluidDexError(ErrorTypes.DexT1__SmartColNotEnabled);
        }
    }

    /// @dev This function allows users to withdraw their collateral with perfect shares in one token
    /// @param shares_ The number of shares to burn for withdrawal
    /// @param minToken0_ The minimum amount of token0 the user expects to receive (set to 0 if withdrawing in token1)
    /// @param minToken1_ The minimum amount of token1 the user expects to receive (set to 0 if withdrawing in token0)
    /// @param to_ Recipient of swapped tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with shares_
    /// @return withdrawAmt_ The amount of tokens withdrawn in the chosen token
    function withdrawPerfectInOneToken(
        uint shares_,
        uint minToken0_,
        uint minToken1_,
        address to_
    ) public _onlyDelegateCall returns (uint withdrawAmt_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        _check(dexVariables_, dexVariables2_);

        uint userSupplyData_ = _userSupplyData[msg.sender];

        if (userSupplyData_ & 1 == 0 && to_ != ADDRESS_DEAD) {
            revert FluidDexError(ErrorTypes.DexT1__UserSupplyInNotOn);
        }

        to_ = (to_ == address(0)) ? msg.sender : to_;

        if ((minToken0_ > 0 && minToken1_ > 0) || (minToken0_ == 0 && minToken1_ == 0)) {
            // only 1 token should be > 0
            revert FluidDexError(ErrorTypes.DexT1__InvalidWithdrawAmts);
        }

        // is smart collateral pool enabled
        if ((dexVariables2_ & 1) == 1) {
            PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices(dexVariables_, dexVariables2_);

            uint totalSupplyShares_ = _totalSupplyShares & X128;

            _verifyRedeem(shares_, totalSupplyShares_);

            uint token0Amt_;
            uint token1Amt_;

            CollateralReserves memory c_ = _getCollateralReserves(
                pex_.geometricMean,
                pex_.upperRange,
                pex_.lowerRange,
                pex_.supplyToken0ExchangePrice,
                pex_.supplyToken1ExchangePrice
            );

            if ((c_.token0RealReserves == 0) || (c_.token1RealReserves == 0)) {
                revert FluidDexError(ErrorTypes.DexT1__InvalidCollateralReserves);
            }

            CollateralReserves memory c2_ = _getUpdatedColReserves(shares_, totalSupplyShares_, c_, false);
            // Storing exact token0 & token1 raw/adjusted withdrawal amount after burning shares
            token0Amt_ = c_.token0RealReserves - c2_.token0RealReserves - 1;
            token1Amt_ = c_.token1RealReserves - c2_.token1RealReserves - 1;

            if (minToken0_ > 0) {
                // user wants to withdraw entirely in token0, hence swapping token1 into token0
                token0Amt_ += _getAmountOut(token1Amt_, c2_.token1ImaginaryReserves, c2_.token0ImaginaryReserves);
                token1Amt_ = 0;
                _verifyToken0Reserves(
                    (c_.token0RealReserves - token0Amt_),
                    c_.token1RealReserves,
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );

                // converting token0Amt_ from raw/adjusted to normal token amount
                token0Amt_ = (((token0Amt_ - 1) * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION) - 1;

                // deducting fee on withdrawing in 1 token
                token0Amt_ = (token0Amt_ * (SIX_DECIMALS - ((dexVariables2_ >> 2) & X17))) / SIX_DECIMALS;

                withdrawAmt_ = token0Amt_;
                if (to_ == ADDRESS_DEAD) revert FluidDexLiquidityOutput(withdrawAmt_);
                if (withdrawAmt_ < minToken0_) revert FluidDexError(ErrorTypes.DexT1__WithdrawalNotEnough);
            } else {
                // user wants to withdraw entirely in token1, hence swapping token0 into token1
                token1Amt_ += _getAmountOut(token0Amt_, c2_.token0ImaginaryReserves, c2_.token1ImaginaryReserves);
                token0Amt_ = 0;
                _verifyToken1Reserves(
                    c_.token0RealReserves,
                    (c_.token1RealReserves - token1Amt_),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_USER_OPERATIONS
                );

                // converting token1Amt_ from raw/adjusted to normal token amount
                token1Amt_ = (((token1Amt_ - 1) * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION) - 1;

                // deducting fee on withdrawing in 1 token
                token1Amt_ = (token1Amt_ * (SIX_DECIMALS - ((dexVariables2_ >> 2) & X17))) / SIX_DECIMALS;

                withdrawAmt_ = token1Amt_;
                if (to_ == ADDRESS_DEAD) revert FluidDexLiquidityOutput(withdrawAmt_);
                if (withdrawAmt_ < minToken1_) revert FluidDexError(ErrorTypes.DexT1__WithdrawalNotEnough);
            }

            uint256 userSupply_ = (userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
            userSupply_ = (userSupply_ >> DEFAULT_EXPONENT_SIZE) << (userSupply_ & DEFAULT_EXPONENT_MASK);

            // calculate current, updated (expanded etc.) withdrawal limit
            // temp_ => newWithdrawalLimit_
            uint256 temp_ = DexCalcs.calcWithdrawalLimitBeforeOperate(userSupplyData_, userSupply_);

            userSupply_ -= shares_;

            // withdraws below limit
            if (userSupply_ < temp_) revert FluidDexError(ErrorTypes.DexT1__WithdrawLimitReached);

            _updatingUserSupplyDataOnStorage(userSupplyData_, userSupply_, temp_);

            totalSupplyShares_ = totalSupplyShares_ - shares_;
            _updateSupplyShares(totalSupplyShares_);

            // to avoid stack-too-deep error
            temp_ = uint160(to_);
            if (minToken0_ > 0) {
                // withdraw
                LIQUIDITY.operate(TOKEN_0, -int(token0Amt_), 0, address(uint160(temp_)), address(0), new bytes(0));
            } else {
                // withdraw
                LIQUIDITY.operate(TOKEN_1, -int(token1Amt_), 0, address(uint160(temp_)), address(0), new bytes(0));
            }

            // to avoid stack-too-deep error
            temp_ = shares_;
            emit LogWithdrawColInOneToken(temp_, token0Amt_, token1Amt_);

            _arbitrage(dexVariables_, dexVariables2_, pex_);
        } else {
            revert FluidDexError(ErrorTypes.DexT1__SmartColNotEnabled);
        }
    }
}
