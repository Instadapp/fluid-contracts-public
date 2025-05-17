// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";

import { CoreHelpers } from "./coreHelpers.sol";
import { ErrorTypes } from "../../../errorTypes.sol";
import { DexSlotsLink } from "../../../../../libraries/dexSlotsLink.sol";
import { DexCalcs } from "../../../../../libraries/dexCalcs.sol";
import { BigMathMinified } from "../../../../../libraries/bigMathMinified.sol";
import { SafeTransfer } from "../../../../../libraries/safeTransfer.sol";
import { LiquidityCalcs } from "../../../../../libraries/liquidityCalcs.sol";

abstract contract UserHelpers is CoreHelpers {
    using BigMathMinified for uint256;

    constructor(ConstantViews memory constantViews_) CoreHelpers(constantViews_) {}

    function _verifyMint(uint amt_, uint totalAmt_) internal pure {
        // not minting too less shares or too more
        // If totalAmt_ is worth $1 then user can at max mint $1B of new amt_ at once.
        // If totalAmt_ is worth $1B then user have to mint min of $1 of amt_.
        if (amt_ < (totalAmt_ / NINE_DECIMALS) || amt_ > (totalAmt_ * NINE_DECIMALS)) {
            revert FluidDexError(ErrorTypes.DexT1__MintAmtOverflow);
        }
    }

    function _verifyRedeem(uint amt_, uint totalAmt_) internal pure {
        // If burning of amt_ is > 99.99% of totalAmt_ or if amt_ is less than totalAmt_ / 1e9 then revert.
        if (amt_ > ((totalAmt_ * 9999) / FOUR_DECIMALS) || (amt_ < (totalAmt_ / NINE_DECIMALS))) {
            revert FluidDexError(ErrorTypes.DexT1__BurnAmtOverflow);
        }
    }

    function _getExchangePrices() internal view returns (ExchangePrices memory ex_) {
        // Exchange price will remain same as Liquidity Layer
        (ex_.supplyToken0ExchangePrice, ex_.borrowToken0ExchangePrice) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY.readFromStorage(EXCHANGE_PRICE_TOKEN_0_SLOT)
        );

        (ex_.supplyToken1ExchangePrice, ex_.borrowToken1ExchangePrice) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY.readFromStorage(EXCHANGE_PRICE_TOKEN_1_SLOT)
        );
    }

    function _updatingUserSupplyDataOnStorage(
        uint userSupplyData_,
        uint userSupply_,
        uint newWithdrawalLimit_
    ) internal {
        // calculate withdrawal limit to store as previous withdrawal limit in storage
        newWithdrawalLimit_ = DexCalcs.calcWithdrawalLimitAfterOperate(
            userSupplyData_,
            userSupply_,
            newWithdrawalLimit_
        );

        userSupply_ = userSupply_.toBigNumber(
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );

        newWithdrawalLimit_ = newWithdrawalLimit_.toBigNumber(
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );

        if (((userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64) == userSupply_) {
            // make sure that shares amount is not so small that it wouldn't affect storage update. if a difference
            // is present then rounding will be in the right direction to avoid any potential manipulation.
            revert FluidDexError(ErrorTypes.DexT1__SharesAmountInsufficient);
        }

        // Updating on storage, copied exactly the same from Liquidity Layer
        _userSupplyData[msg.sender] =
            // mask to update bits 1-161 (supply amount, withdrawal limit, timestamp)
            (userSupplyData_ & 0xfffffffffffffffffffffffc0000000000000000000000000000000000000001) |
            (userSupply_ << DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) | // converted to BigNumber can not overflow
            (newWithdrawalLimit_ << DexSlotsLink.BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT) | // converted to BigNumber can not overflow
            (block.timestamp << DexSlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP);
    }

    function _updatingUserBorrowDataOnStorage(uint userBorrowData_, uint userBorrow_, uint newBorrowLimit_) internal {
        // calculate borrow limit to store as previous borrow limit in storage
        newBorrowLimit_ = DexCalcs.calcBorrowLimitAfterOperate(userBorrowData_, userBorrow_, newBorrowLimit_);

        // Converting user's borrowings into bignumber
        userBorrow_ = userBorrow_.toBigNumber(
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_UP
        );

        // Converting borrow limit into bignumber
        newBorrowLimit_ = newBorrowLimit_.toBigNumber(
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );

        if (((userBorrowData_ >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64) == userBorrow_) {
            // make sure that shares amount is not so small that it wouldn't affect storage update. if a difference
            // is present then rounding will be in the right direction to avoid any potential manipulation.
            revert FluidDexError(ErrorTypes.DexT1__SharesAmountInsufficient);
        }

        // Updating on storage, copied exactly the same from Liquidity Layer
        _userBorrowData[msg.sender] =
            // mask to update bits 1-161 (borrow amount, borrow limit, timestamp)
            (userBorrowData_ & 0xfffffffffffffffffffffffc0000000000000000000000000000000000000001) |
            (userBorrow_ << DexSlotsLink.BITS_USER_BORROW_AMOUNT) | // converted to BigNumber can not overflow
            (newBorrowLimit_ << DexSlotsLink.BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT) | // converted to BigNumber can not overflow
            (block.timestamp << DexSlotsLink.BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP);
    }

    /// @notice Deposits or pays back in liquidity
    /// @param token_ The token to deposit or pay back
    /// @param depositAmt_ The amount to deposit
    /// @param paybackAmt_ The amount to pay back
    function _depositOrPaybackInLiquidity(address token_, uint depositAmt_, uint paybackAmt_) internal {
        // both cannot be greater than 0
        // if both are 0 then liquidity layer will revert
        // only 1 should be greater than 0
        if (depositAmt_ > 0 && paybackAmt_ > 0) revert();
        if (token_ == NATIVE_TOKEN) {
            uint amt_ = depositAmt_ > 0 ? depositAmt_ : paybackAmt_;
            if (msg.value > amt_) {
                SafeTransfer.safeTransferNative(msg.sender, msg.value - amt_);
            } else if (msg.value < amt_) {
                revert FluidDexError(ErrorTypes.DexT1__MsgValueLowOnDepositOrPayback);
            }
            LIQUIDITY.operate{ value: amt_ }(
                token_,
                int(depositAmt_),
                -int(paybackAmt_),
                address(0),
                address(0),
                new bytes(0)
            );
        } else {
            LIQUIDITY.operate(
                token_,
                int(depositAmt_),
                -int(paybackAmt_),
                address(0),
                address(0),
                abi.encode((depositAmt_ + paybackAmt_), true, msg.sender)
            );
        }
    }
}
