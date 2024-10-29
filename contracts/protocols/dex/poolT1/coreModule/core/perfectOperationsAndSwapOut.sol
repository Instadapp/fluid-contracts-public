// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { UserHelpers } from "../helpers/userHelpers.sol";
import { SafeTransfer } from "../../../../../libraries/safeTransfer.sol";
import { DexSlotsLink } from "../../../../../libraries/dexSlotsLink.sol";
import { DexCalcs } from "../../../../../libraries/dexCalcs.sol";
import { BigMathMinified } from "../../../../../libraries/bigMathMinified.sol";
import { ErrorTypes } from "../../../errorTypes.sol";

/// @title FluidDexT1
/// @notice Implements core logics for Fluid Dex protocol.
/// Note Token transfers happen directly from user to Liquidity contract and vice-versa.
contract FluidDexT1PerfectOperationsAndSwapOut is UserHelpers {
    using BigMathMinified for uint256;

    constructor(ConstantViews memory constantViews_) UserHelpers(constantViews_) {
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

    struct SwapOutExtras {
        address to;
        uint amountInMax;
        bool isCallback;
    }

    /// @dev Swap tokens with perfect amount out. If NATIVE_TOKEN is sent then msg.value should be passed as amountInMax, amountInMax - amountIn of ETH are sent back to msg.sender
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountOut_ The exact amount of tokens to receive after swap
    /// @param extras_ Additional parameters for the swap:
    ///   - to_: Recipient of swapped tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with amountIn_
    ///   - amountInMax: The maximum amount of input tokens the user is willing to swap
    ///   - isCallback: If true, indicates that the output tokens should be transferred via a callback
    /// @return amountIn_ The amount of input tokens used for the swap
    function _swapOut(
        bool swap0to1_,
        uint256 amountOut_,
        SwapOutExtras memory extras_
    ) internal _onlyDelegateCall returns (uint256 amountIn_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        if ((dexVariables2_ >> 255) == 1) revert FluidDexError(ErrorTypes.DexT1__SwapAndArbitragePaused);

        _check(dexVariables_, dexVariables2_);

        if (extras_.to == address(0)) extras_.to = msg.sender;

        SwapOutMemory memory s_;

        if (swap0to1_) {
            (s_.tokenIn, s_.tokenOut) = (TOKEN_0, TOKEN_1);
            unchecked {
                s_.amtOutAdjusted = (amountOut_ * TOKEN_1_NUMERATOR_PRECISION) / TOKEN_1_DENOMINATOR_PRECISION;
            }
        } else {
            (s_.tokenIn, s_.tokenOut) = (TOKEN_1, TOKEN_0);
            unchecked {
                s_.amtOutAdjusted = (amountOut_ * TOKEN_0_NUMERATOR_PRECISION) / TOKEN_0_DENOMINATOR_PRECISION;
            }
        }

        _verifySwapAndNonPerfectActions(s_.amtOutAdjusted, amountOut_);

        PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices(dexVariables_, dexVariables2_);

        if ((msg.value > 0) || ((s_.tokenIn == NATIVE_TOKEN) && (msg.value == 0))) {
            if (msg.value != extras_.amountInMax) revert FluidDexError(ErrorTypes.DexT1__EthAndAmountInMisMatch);
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

        // limiting amtOutAdjusted to be not more than 50% of both (collateral & debt) imaginary tokenOut reserves combined
        // basically, if this throws that means user is trying to swap 0.5x tokenOut if current tokenOut imaginary reserves is x
        // let's take x as token0 here, that means, initially the pool pricing might be:
        // token1Reserve / x and new pool pricing will become token1Reserve / 0.5x (token1Reserve will decrease after swap but for simplicity ignoring that)
        // So pool price is increased by ~50% (oracle will throw error in this case as it only allows 5% price difference but better to limit it before hand)
        unchecked {
            if (s_.amtOutAdjusted > ((cs_.tokenOutImaginaryReserves + ds_.tokenOutImaginaryReserves) / 2))
                revert FluidDexError(ErrorTypes.DexT1__SwapOutLimitingAmounts);
        }

        if (temp_ == 1 && temp2_ == 1) {
            // if both pools are not enabled then s_.swapRoutingAmt will be 0
            s_.swapRoutingAmt = _swapRoutingOut(
                s_.amtOutAdjusted,
                cs_.tokenInImaginaryReserves,
                cs_.tokenOutImaginaryReserves,
                ds_.tokenInImaginaryReserves,
                ds_.tokenOutImaginaryReserves
            );
        }

        // In below if else statement temps are:
        // temp_ => withdraw amt
        // temp2_ => deposit amt
        // temp3_ => borrow amt
        // temp4_ => payback amt
        if (int(s_.amtOutAdjusted) > s_.swapRoutingAmt && s_.swapRoutingAmt > 0) {
            // swap will route from both pools
            // temp_ = amountOutCol_
            temp_ = uint(s_.swapRoutingAmt);
            unchecked {
                // temp3_ = amountOutDebt_
                temp3_ = s_.amtOutAdjusted - temp_;
            }

            (temp2_, temp4_) = (0, 0);

            // debt pool price will be the same as collateral pool after the swap
            s_.withdrawTo = extras_.to;
            s_.borrowTo = extras_.to;
        } else if ((temp_ == 1 && temp2_ == 0) || (s_.swapRoutingAmt >= int(s_.amtOutAdjusted))) {
            // entire swap will route through collateral pool
            (temp_, temp2_, temp3_, temp4_) = (s_.amtOutAdjusted, 0, 0, 0);
            // price can slightly differ from debt pool but difference will be very small. Probably <0.01% for active DEX pools.
            s_.withdrawTo = extras_.to;
        } else if ((temp_ == 0 && temp2_ == 1) || (s_.swapRoutingAmt <= 0)) {
            // entire swap will route through debt pool
            (temp_, temp2_, temp3_, temp4_) = (0, 0, s_.amtOutAdjusted, 0);
            // price can slightly differ from collateral pool but difference will be very small. Probably <0.01% for active DEX pools.
            s_.borrowTo = extras_.to;
        } else {
            // swap should never reach this point but if it does then reverting
            revert FluidDexError(ErrorTypes.DexT1__NoSwapRoute);
        }

        if (temp_ > 0) {
            // temp2_ = amountInCol_
            temp2_ = _getAmountIn(temp_, cs_.tokenInImaginaryReserves, cs_.tokenOutImaginaryReserves);
            temp2_ = (temp2_ * SIX_DECIMALS) / s_.fee;
            swap0to1_
                ? _verifyToken1Reserves(
                    (cs_.tokenInRealReserves + temp2_),
                    (cs_.tokenOutRealReserves - temp_),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_SWAP
                )
                : _verifyToken0Reserves(
                    (cs_.tokenOutRealReserves - temp_),
                    (cs_.tokenInRealReserves + temp2_),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_SWAP
                );
        }
        if (temp3_ > 0) {
            // temp4_ = amountInDebt_
            temp4_ = _getAmountIn(temp3_, ds_.tokenInImaginaryReserves, ds_.tokenOutImaginaryReserves);
            temp4_ = (temp4_ * SIX_DECIMALS) / s_.fee;
            swap0to1_
                ? _verifyToken1Reserves(
                    (ds_.tokenInRealReserves + temp4_),
                    (ds_.tokenOutRealReserves - temp3_),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_SWAP
                )
                : _verifyToken0Reserves(
                    (ds_.tokenOutRealReserves - temp3_),
                    (ds_.tokenInRealReserves + temp4_),
                    pex_.centerPrice,
                    MINIMUM_LIQUIDITY_SWAP
                );
        }

        amountIn_ = temp2_ + temp4_;

        // cutting revenue off of amount in.
        temp2_ = (temp2_ * s_.revenueCut) / EIGHT_DECIMALS;
        temp4_ = (temp4_ * s_.revenueCut) / EIGHT_DECIMALS;

        // from whatever pool higher amount of swap is routing we are taking that as final price, does not matter much because both pools final price should be same
        if (temp_ > temp3_) {
            // new pool price from col pool
            s_.price = swap0to1_
                ? ((cs_.tokenOutImaginaryReserves - temp_) * 1e27) / (cs_.tokenInImaginaryReserves + temp2_)
                : ((cs_.tokenInImaginaryReserves + temp2_) * 1e27) / (cs_.tokenOutImaginaryReserves - temp_);
        } else {
            // new pool price from debt pool
            s_.price = swap0to1_
                ? ((ds_.tokenOutImaginaryReserves - temp3_) * 1e27) / (ds_.tokenInImaginaryReserves + temp4_)
                : ((ds_.tokenInImaginaryReserves + temp4_) * 1e27) / (ds_.tokenOutImaginaryReserves - temp3_);
        }

        // Converting into normal token amounts
        if (swap0to1_) {
            // only adding uncheck in out amount
            unchecked {
                temp_ = (temp_ * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION;
                temp3_ = (temp3_ * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION;
            }
            temp2_ = (temp2_ * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION;
            temp4_ = (temp4_ * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION;
            amountIn_ = (amountIn_ * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION;
        } else {
            // only adding uncheck in out amount
            unchecked {
                temp_ = (temp_ * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION;
                temp3_ = (temp3_ * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION;
            }
            temp2_ = (temp2_ * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION;
            temp4_ = (temp4_ * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION;
            amountIn_ = (amountIn_ * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION;
        }

        // If address dead then reverting with amountIn
        if (extras_.to == ADDRESS_DEAD) revert FluidDexSwapResult(amountIn_);

        if (amountIn_ > extras_.amountInMax) revert FluidDexError(ErrorTypes.DexT1__ExceedsAmountInMax);

        // allocating to avoid stack-too-deep error
        // not setting in the callbackData as last 2nd to avoid SKIP_TRANSFERS clashing
        s_.data = abi.encode(amountIn_, extras_.isCallback, msg.sender); // true/false is to decide if dex should do callback or directly transfer from user
        // if native token then pass msg.value as amountIn_ else 0
        s_.msgValue = (s_.tokenIn == NATIVE_TOKEN) ? amountIn_ : 0;
        // Deposit & payback token in at liquidity
        LIQUIDITY.operate{ value: s_.msgValue }(s_.tokenIn, int(temp2_), -int(temp4_), address(0), address(0), s_.data);
        // Withdraw & borrow token out at liquidity
        LIQUIDITY.operate(s_.tokenOut, -int(temp_), int(temp3_), s_.withdrawTo, s_.borrowTo, new bytes(0));

        // If hook exists then calling hook
        temp_ = (dexVariables2_ >> 142) & X30;
        if (temp_ > 0) {
            s_.swap0to1 = swap0to1_;
            _hookVerify(temp_, 1, s_.swap0to1, s_.price);
        }

        swap0to1_
            ? _utilizationVerify(((dexVariables2_ >> 238) & X10), EXCHANGE_PRICE_TOKEN_1_SLOT)
            : _utilizationVerify(((dexVariables2_ >> 228) & X10), EXCHANGE_PRICE_TOKEN_0_SLOT);

        dexVariables = _updateOracle(s_.price, pex_.centerPrice, dexVariables_);

        if (s_.tokenIn == NATIVE_TOKEN && amountIn_ < extras_.amountInMax) {
            unchecked {
                SafeTransfer.safeTransferNative(msg.sender, extras_.amountInMax - amountIn_);
            }
        }

        // to avoid stack too deep error
        temp_ = amountOut_;
        emit Swap(swap0to1_, amountIn_, temp_, extras_.to);
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
        uint amountInMax_,
        address to_
    ) public payable _onlyDelegateCall returns (uint amountIn_) {
        return _swapOut(swap0to1_, amountOut_, SwapOutExtras(to_, amountInMax_, false));
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
        return _swapOut(swap0to1_, amountOut_, SwapOutExtras(to_, amountInMax_, true));
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
    ) public payable _onlyDelegateCall returns (uint token0Amt_, uint token1Amt_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        _check(dexVariables_, dexVariables2_);

        uint userSupplyData_ = _userSupplyData[msg.sender];

        // user collateral configs are not set yet
        if (userSupplyData_ & 1 == 0 && !estimate_) revert FluidDexError(ErrorTypes.DexT1__UserSupplyInNotOn);

        // is smart collateral pool enabled
        if ((dexVariables2_ & 1) == 1) {
            ExchangePrices memory ex_ = _getExchangePrices();

            // smart col in enabled
            uint totalSupplyShares_ = _totalSupplyShares & X128;

            _verifyMint(shares_, totalSupplyShares_);

            // Adding col liquidity in equal proportion
            // Adding + 1, to keep protocol on the winning side
            token0Amt_ =
                (_getLiquidityCollateral(SUPPLY_TOKEN_0_SLOT, ex_.supplyToken0ExchangePrice, true) * shares_) /
                totalSupplyShares_;
            token1Amt_ =
                (_getLiquidityCollateral(SUPPLY_TOKEN_1_SLOT, ex_.supplyToken1ExchangePrice, false) * shares_) /
                totalSupplyShares_;

            // converting back into normal token amounts
            // Adding + 1, to keep protocol on the winning side
            token0Amt_ = (((token0Amt_ + 1) * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION) + 1;
            token1Amt_ = (((token1Amt_ + 1) * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION) + 1;

            if (estimate_) revert FluidDexPerfectLiquidityOutput(token0Amt_, token1Amt_);

            if (token0Amt_ > maxToken0Deposit_ || token1Amt_ > maxToken1Deposit_) {
                revert FluidDexError(ErrorTypes.DexT1__AboveDepositMax);
            }

            _depositOrPaybackInLiquidity(TOKEN_0, token0Amt_, 0);

            _depositOrPaybackInLiquidity(TOKEN_1, token1Amt_, 0);

            uint userSupply_ = (userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
            // extracting exisiting shares and then adding new shares in it
            userSupply_ = ((userSupply_ >> DEFAULT_EXPONENT_SIZE) << (userSupply_ & DEFAULT_EXPONENT_MASK));

            // calculate current, updated (expanded etc.) withdrawal limit
            uint256 newWithdrawalLimit_ = DexCalcs.calcWithdrawalLimitBeforeOperate(userSupplyData_, userSupply_);

            userSupply_ += shares_;

            // bigNumber the shares are not same as before
            _updatingUserSupplyDataOnStorage(userSupplyData_, userSupply_, newWithdrawalLimit_);

            _updateSupplyShares(totalSupplyShares_ + shares_);
        } else {
            revert FluidDexError(ErrorTypes.DexT1__SmartColNotEnabled);
        }

        // uninitializing re-entrancy
        dexVariables = dexVariables_;

        emit LogDepositPerfectColLiquidity(shares_, token0Amt_, token1Amt_);
    }

    /// @dev This function allows users to withdraw a perfect amount of collateral liquidity
    /// @param shares_ The number of shares to withdraw
    /// @param minToken0Withdraw_ The minimum amount of token0 the user is willing to accept
    /// @param minToken1Withdraw_ The minimum amount of token1 the user is willing to accept
    /// @param to_ Recipient of swapped tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with token0Amt_ & token1Amt_
    /// @return token0Amt_ The amount of token0 withdrawn
    /// @return token1Amt_ The amount of token1 withdrawn
    function withdrawPerfect(
        uint shares_,
        uint minToken0Withdraw_,
        uint minToken1Withdraw_,
        address to_
    ) public _onlyDelegateCall returns (uint token0Amt_, uint token1Amt_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        _check(dexVariables_, dexVariables2_);

        uint userSupplyData_ = _userSupplyData[msg.sender];

        if (userSupplyData_ & 1 == 0 && to_ != ADDRESS_DEAD) {
            revert FluidDexError(ErrorTypes.DexT1__UserSupplyInNotOn);
        }

        to_ = (to_ == address(0)) ? msg.sender : to_;

        // is smart collateral pool enabled
        if ((dexVariables2_ & 1) == 1) {
            ExchangePrices memory ex_ = _getExchangePrices();

            uint totalSupplyShares_ = _totalSupplyShares & X128;

            _verifyRedeem(shares_, totalSupplyShares_);

            // smart col in enabled
            // Withdrawing col liquidity in equal proportion
            token0Amt_ =
                (_getLiquidityCollateral(SUPPLY_TOKEN_0_SLOT, ex_.supplyToken0ExchangePrice, true) * shares_) /
                totalSupplyShares_;
            token1Amt_ =
                (_getLiquidityCollateral(SUPPLY_TOKEN_1_SLOT, ex_.supplyToken1ExchangePrice, false) * shares_) /
                totalSupplyShares_;

            // converting back into normal token amounts
            token0Amt_ = (((token0Amt_ - 1) * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION) - 1;
            token1Amt_ = (((token1Amt_ - 1) * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION) - 1;

            if (to_ == ADDRESS_DEAD) revert FluidDexPerfectLiquidityOutput(token0Amt_, token1Amt_);

            if (token0Amt_ < minToken0Withdraw_ || token1Amt_ < minToken1Withdraw_) {
                revert FluidDexError(ErrorTypes.DexT1__BelowWithdrawMin);
            }

            uint256 userSupply_ = (userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
            userSupply_ = (userSupply_ >> DEFAULT_EXPONENT_SIZE) << (userSupply_ & DEFAULT_EXPONENT_MASK);

            // calculate current, updated (expanded etc.) withdrawal limit
            uint256 newWithdrawalLimit_ = DexCalcs.calcWithdrawalLimitBeforeOperate(userSupplyData_, userSupply_);
            userSupply_ -= shares_;

            // withdraws below limit
            if (userSupply_ < newWithdrawalLimit_) revert FluidDexError(ErrorTypes.DexT1__WithdrawLimitReached);

            _updatingUserSupplyDataOnStorage(userSupplyData_, userSupply_, newWithdrawalLimit_);

            totalSupplyShares_ = totalSupplyShares_ - shares_;
            _updateSupplyShares(totalSupplyShares_);

            // withdraw
            // if token0Amt_ == 0 then Liqudity Layer will revert
            LIQUIDITY.operate(TOKEN_0, -int(token0Amt_), 0, to_, address(0), new bytes(0));

            // withdraw
            // if token1Amt_ == 0 then Liqudity Layer will revert
            LIQUIDITY.operate(TOKEN_1, -int(token1Amt_), 0, to_, address(0), new bytes(0));
        } else {
            revert FluidDexError(ErrorTypes.DexT1__SmartColNotEnabled);
        }

        // uninitializing re-entrancy
        dexVariables = dexVariables_;

        emit LogWithdrawPerfectColLiquidity(shares_, token0Amt_, token1Amt_);
    }

    /// @dev This function allows users to borrow tokens in equal proportion to the current debt pool ratio
    /// @param shares_ The number of shares to borrow
    /// @param minToken0Borrow_ Minimum amount of token0 to borrow
    /// @param minToken1Borrow_ Minimum amount of token1 to borrow
    /// @param to_ Recipient of swapped tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with token0Amt_ & token1Amt_
    /// @return token0Amt_ Amount of token0 borrowed
    /// @return token1Amt_ Amount of token1 borrowed
    function borrowPerfect(
        uint shares_,
        uint minToken0Borrow_,
        uint minToken1Borrow_,
        address to_
    ) public _onlyDelegateCall returns (uint token0Amt_, uint token1Amt_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        _check(dexVariables_, dexVariables2_);

        uint userBorrowData_ = _userBorrowData[msg.sender];

        // user debt configs are not set yet
        if (userBorrowData_ & 1 == 0 && to_ != ADDRESS_DEAD) revert FluidDexError(ErrorTypes.DexT1__UserDebtInNotOn);

        to_ = (to_ == address(0)) ? msg.sender : to_;

        // is smart debt pool enabled
        if (((dexVariables2_ >> 1) & 1) == 1) {
            ExchangePrices memory ex_ = _getExchangePrices();

            uint totalBorrowShares_ = _totalBorrowShares & X128;

            _verifyMint(shares_, totalBorrowShares_);

            // Adding debt liquidity in equal proportion
            token0Amt_ =
                (_getLiquidityDebt(BORROW_TOKEN_0_SLOT, ex_.borrowToken0ExchangePrice, true) * shares_) /
                totalBorrowShares_;
            token1Amt_ =
                (_getLiquidityDebt(BORROW_TOKEN_1_SLOT, ex_.borrowToken1ExchangePrice, false) * shares_) /
                totalBorrowShares_;
            // converting back into normal token amounts
            token0Amt_ = (((token0Amt_ - 1) * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION) - 1;
            token1Amt_ = (((token1Amt_ - 1) * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION) - 1;

            if (to_ == ADDRESS_DEAD) revert FluidDexPerfectLiquidityOutput(token0Amt_, token1Amt_);

            if (token0Amt_ < minToken0Borrow_ || token1Amt_ < minToken1Borrow_) {
                revert FluidDexError(ErrorTypes.DexT1__BelowBorrowMin);
            }

            // extract user borrow amount
            uint256 userBorrow_ = (userBorrowData_ >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
            userBorrow_ = (userBorrow_ >> DEFAULT_EXPONENT_SIZE) << (userBorrow_ & DEFAULT_EXPONENT_MASK);

            // calculate current, updated (expanded etc.) borrow limit
            uint256 newBorrowLimit_ = DexCalcs.calcBorrowLimitBeforeOperate(userBorrowData_, userBorrow_);

            userBorrow_ += shares_;

            // user above debt limit
            if (userBorrow_ > newBorrowLimit_) revert FluidDexError(ErrorTypes.DexT1__DebtLimitReached);

            // borrow
            // if token0Amt_ == 0 then Liqudity Layer will revert
            LIQUIDITY.operate(TOKEN_0, 0, int(token0Amt_), address(0), to_, new bytes(0));

            // borrow
            // if token1Amt_ == 1 then Liqudity Layer will revert
            LIQUIDITY.operate(TOKEN_1, 0, int(token1Amt_), address(0), to_, new bytes(0));

            _updatingUserBorrowDataOnStorage(userBorrowData_, userBorrow_, newBorrowLimit_);

            _updateBorrowShares(totalBorrowShares_ + shares_);
        } else {
            revert FluidDexError(ErrorTypes.DexT1__SmartDebtNotEnabled);
        }

        // uninitializing re-entrancy
        dexVariables = dexVariables_;

        emit LogBorrowPerfectDebtLiquidity(shares_, token0Amt_, token1Amt_);
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
    ) public payable _onlyDelegateCall returns (uint token0Amt_, uint token1Amt_) {
        uint dexVariables_ = dexVariables;
        uint dexVariables2_ = dexVariables2;

        _check(dexVariables_, dexVariables2_);

        uint userBorrowData_ = _userBorrowData[msg.sender];

        if (userBorrowData_ & 1 == 0 && !estimate_) revert FluidDexError(ErrorTypes.DexT1__UserDebtInNotOn);

        // is smart debt pool enabled
        if (((dexVariables2_ >> 1) & 1) == 1) {
            uint totalBorrowShares_ = _totalBorrowShares & X128;

            ExchangePrices memory ex_ = _getExchangePrices();

            _verifyRedeem(shares_, totalBorrowShares_);

            // Removing debt liquidity in equal proportion
            token0Amt_ =
                (_getLiquidityDebt(BORROW_TOKEN_0_SLOT, ex_.borrowToken0ExchangePrice, true) * shares_) /
                totalBorrowShares_;
            token1Amt_ =
                (_getLiquidityDebt(BORROW_TOKEN_1_SLOT, ex_.borrowToken1ExchangePrice, false) * shares_) /
                totalBorrowShares_;
            // converting back into normal token amounts
            token0Amt_ = (((token0Amt_ + 1) * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION) + 1;
            token1Amt_ = (((token1Amt_ + 1) * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION) + 1;

            if (estimate_) revert FluidDexPerfectLiquidityOutput(token0Amt_, token1Amt_);

            if (token0Amt_ > maxToken0Payback_ || token1Amt_ > maxToken1Payback_) {
                revert FluidDexError(ErrorTypes.DexT1__AbovePaybackMax);
            }

            _depositOrPaybackInLiquidity(TOKEN_0, 0, token0Amt_);

            _depositOrPaybackInLiquidity(TOKEN_1, 0, token1Amt_);

            // extract user borrow amount
            uint256 userBorrow_ = (userBorrowData_ >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
            userBorrow_ = (userBorrow_ >> DEFAULT_EXPONENT_SIZE) << (userBorrow_ & DEFAULT_EXPONENT_MASK);

            // calculate current, updated (expanded etc.) borrow limit
            uint256 newBorrowLimit_ = DexCalcs.calcBorrowLimitBeforeOperate(userBorrowData_, userBorrow_);

            userBorrow_ -= shares_;

            _updatingUserBorrowDataOnStorage(userBorrowData_, userBorrow_, newBorrowLimit_);

            totalBorrowShares_ = totalBorrowShares_ - shares_;
            _updateBorrowShares(totalBorrowShares_);
        } else {
            revert FluidDexError(ErrorTypes.DexT1__SmartDebtNotEnabled);
        }

        // uninitializing re-entrancy
        dexVariables = dexVariables_;

        emit LogPaybackPerfectDebtLiquidity(shares_, token0Amt_, token1Amt_);
    }
}
