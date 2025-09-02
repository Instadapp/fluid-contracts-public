// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";

import { BigMathMinified } from "../../libraries/bigMathMinified.sol";
import { LiquidityCalcs } from "../../libraries/liquidityCalcs.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { SafeTransfer } from "../../libraries/safeTransfer.sol";
import { CommonHelpers } from "../common/helpers.sol";
import { Events } from "./events.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";

interface IProtocol {
    function liquidityCallback(address token_, uint256 amount_, bytes calldata data_) external;
}

abstract contract CoreInternals is Error, CommonHelpers, Events {
    using BigMathMinified for uint256;

    /// @dev supply or withdraw for both with interest & interest free.
    /// positive `amount_` is deposit, negative `amount_` is withdraw.
    function _supplyOrWithdraw(
        address token_,
        int256 amount_,
        uint256 supplyExchangePrice_
    ) internal returns (int256 newSupplyInterestRaw_, int256 newSupplyInterestFree_) {
        uint256 userSupplyData_ = _userSupplyData[msg.sender][token_];

        if (userSupplyData_ == 0) {
            revert FluidLiquidityError(ErrorTypes.UserModule__UserNotDefined);
        }
        if ((userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_IS_PAUSED) & 1 == 1) {
            revert FluidLiquidityError(ErrorTypes.UserModule__UserPaused);
        }

        // extract user supply amount
        uint256 userSupply_ = (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        userSupply_ = (userSupply_ >> DEFAULT_EXPONENT_SIZE) << (userSupply_ & DEFAULT_EXPONENT_MASK);

        // calculate current, updated (expanded etc.) withdrawal limit
        uint256 newWithdrawalLimit_ = LiquidityCalcs.calcWithdrawalLimitBeforeOperate(userSupplyData_, userSupply_);

        // calculate updated user supply amount
        if (userSupplyData_ & 1 == 1) {
            // mode: with interest
            if (amount_ > 0) {
                // convert amount from normal to raw (divide by exchange price) -> round down for deposit
                newSupplyInterestRaw_ = (amount_ * int256(EXCHANGE_PRICES_PRECISION)) / int256(supplyExchangePrice_);
                userSupply_ = userSupply_ + uint256(newSupplyInterestRaw_);
            } else {
                // convert amount from normal to raw (divide by exchange price) -> round up for withdraw
                newSupplyInterestRaw_ = -int256(
                    FixedPointMathLib.mulDivUp(uint256(-amount_), EXCHANGE_PRICES_PRECISION, supplyExchangePrice_)
                );
                // if withdrawal is more than user's supply then solidity will throw here
                userSupply_ = userSupply_ - uint256(-newSupplyInterestRaw_);
            }
        } else {
            // mode: without interest
            newSupplyInterestFree_ = amount_;
            if (newSupplyInterestFree_ > 0) {
                userSupply_ = userSupply_ + uint256(newSupplyInterestFree_);
            } else {
                // if withdrawal is more than user's supply then solidity will throw here
                userSupply_ = userSupply_ - uint256(-newSupplyInterestFree_);
            }
        }

        if (amount_ < 0 && userSupply_ < newWithdrawalLimit_) {
            // if withdraw, then check the user supply after withdrawal is above withdrawal limit
            revert FluidLiquidityError(ErrorTypes.UserModule__WithdrawalLimitReached);
        }

        // calculate withdrawal limit to store as previous withdrawal limit in storage
        newWithdrawalLimit_ = LiquidityCalcs.calcWithdrawalLimitAfterOperate(
            userSupplyData_,
            userSupply_,
            newWithdrawalLimit_
        );

        // Converting user's supply into BigNumber
        userSupply_ = userSupply_.toBigNumber(
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );
        if (((userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64) == userSupply_) {
            // make sure that operate amount is not so small that it wouldn't affect storage update. if a difference
            // is present then rounding will be in the right direction to avoid any potential manipulation.
            revert FluidLiquidityError(ErrorTypes.UserModule__OperateAmountInsufficient);
        }

        // Converting withdrawal limit into BigNumber
        newWithdrawalLimit_ = newWithdrawalLimit_.toBigNumber(
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );

        // Updating on storage
        _userSupplyData[msg.sender][token_] =
            // mask to update bits 1-161 (supply amount, withdrawal limit, timestamp)
            (userSupplyData_ & 0xfffffffffffffffffffffffc0000000000000000000000000000000000000001) |
            (userSupply_ << LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) | // converted to BigNumber can not overflow
            (newWithdrawalLimit_ << LiquiditySlotsLink.BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT) | // converted to BigNumber can not overflow
            (block.timestamp << LiquiditySlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP);
    }

    /// @dev borrow or payback for both with interest & interest free.
    /// positive `amount_` is borrow, negative `amount_` is payback.
    function _borrowOrPayback(
        address token_,
        int256 amount_,
        uint256 borrowExchangePrice_
    ) internal returns (int256 newBorrowInterestRaw_, int256 newBorrowInterestFree_) {
        uint256 userBorrowData_ = _userBorrowData[msg.sender][token_];

        if (userBorrowData_ == 0) {
            revert FluidLiquidityError(ErrorTypes.UserModule__UserNotDefined);
        }
        if ((userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_IS_PAUSED) & 1 == 1) {
            revert FluidLiquidityError(ErrorTypes.UserModule__UserPaused);
        }

        // extract user borrow amount
        uint256 userBorrow_ = (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
        userBorrow_ = (userBorrow_ >> DEFAULT_EXPONENT_SIZE) << (userBorrow_ & DEFAULT_EXPONENT_MASK);

        // calculate current, updated (expanded etc.) borrow limit
        uint256 newBorrowLimit_ = LiquidityCalcs.calcBorrowLimitBeforeOperate(userBorrowData_, userBorrow_);

        // calculate updated user borrow amount
        if (userBorrowData_ & 1 == 1) {
            // with interest
            if (amount_ > 0) {
                // convert amount normal to raw (divide by exchange price) -> round up for borrow
                newBorrowInterestRaw_ = int256(
                    FixedPointMathLib.mulDivUp(uint256(amount_), EXCHANGE_PRICES_PRECISION, borrowExchangePrice_)
                );
                userBorrow_ = userBorrow_ + uint256(newBorrowInterestRaw_);
            } else {
                // convert amount from normal to raw (divide by exchange price) -> round down for payback
                newBorrowInterestRaw_ = (amount_ * int256(EXCHANGE_PRICES_PRECISION)) / int256(borrowExchangePrice_);
                userBorrow_ = userBorrow_ - uint256(-newBorrowInterestRaw_);
            }
        } else {
            // without interest
            newBorrowInterestFree_ = amount_;
            if (newBorrowInterestFree_ > 0) {
                // borrowing
                userBorrow_ = userBorrow_ + uint256(newBorrowInterestFree_);
            } else {
                // payback
                userBorrow_ = userBorrow_ - uint256(-newBorrowInterestFree_);
            }
        }

        if (amount_ > 0 && userBorrow_ > newBorrowLimit_) {
            // if borrow, then check the user borrow amount after borrowing is below borrow limit
            revert FluidLiquidityError(ErrorTypes.UserModule__BorrowLimitReached);
        }

        // calculate borrow limit to store as previous borrow limit in storage
        newBorrowLimit_ = LiquidityCalcs.calcBorrowLimitAfterOperate(userBorrowData_, userBorrow_, newBorrowLimit_);

        // Converting user's borrowings into bignumber
        userBorrow_ = userBorrow_.toBigNumber(
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_UP
        );

        if (((userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & X64) == userBorrow_) {
            // make sure that operate amount is not so small that it wouldn't affect storage update. if a difference
            // is present then rounding will be in the right direction to avoid any potential manipulation.
            revert FluidLiquidityError(ErrorTypes.UserModule__OperateAmountInsufficient);
        }

        // Converting borrow limit into bignumber
        newBorrowLimit_ = newBorrowLimit_.toBigNumber(
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );

        // Updating on storage
        _userBorrowData[msg.sender][token_] =
            // mask to update bits 1-161 (borrow amount, borrow limit, timestamp)
            (userBorrowData_ & 0xfffffffffffffffffffffffc0000000000000000000000000000000000000001) |
            (userBorrow_ << LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) | // converted to BigNumber can not overflow
            (newBorrowLimit_ << LiquiditySlotsLink.BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT) | // converted to BigNumber can not overflow
            (block.timestamp << LiquiditySlotsLink.BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP);
    }

    /// @dev checks if `supplyAmount_` & `borrowAmount_` amounts transfers can be skipped (DEX-protocol use-case).
    /// -   Requirements:
    /// -  ` callbackData_` MUST be encoded so that "from" address is the last 20 bytes in the last 32 bytes slot,
    ///     also for native token operations where liquidityCallback is not triggered!
    ///     from address must come at last position if there is more data. I.e. encode like:
    ///     abi.encode(otherVar1, otherVar2, FROM_ADDRESS). Note dynamic types used with abi.encode come at the end
    ///     so if dynamic types are needed, you must use abi.encodePacked to ensure the from address is at the end.
    /// -   this "from" address must match withdrawTo_ or borrowTo_ and must be == `msg.sender`
    /// -   `callbackData_` must in addition to the from address as described above include bytes32 SKIP_TRANSFERS
    ///     in the slot before (bytes 32 to 63)
    /// -   `msg.value` must be 0.
    /// -   Amounts must be either:
    ///     -  supply(+) == borrow(+), withdraw(-) == payback(-).
    ///     -  Liquidity must be on the winning side (deposit < borrow OR payback < withdraw).
    function _isInOutBalancedOut(
        int256 supplyAmount_,
        int256 borrowAmount_,
        address withdrawTo_,
        address borrowTo_,
        bytes memory callbackData_
    ) internal view returns (bool) {
        // callbackData_ being at least > 63 in length is already verified before calling this method.

        // 1. SKIP_TRANSFERS must be set in callbackData_ 32 bytes before last 32 bytes
        bytes32 skipTransfers_;
        assembly {
            skipTransfers_ := mload(
                add(
                    // add padding for length as present for dynamic arrays in memory
                    add(callbackData_, 32),
                    // Load from memory offset of 2 slots (64 bytes): 1 slot: bytes32 skipTransfers_ + 2 slot: address inFrom_
                    sub(mload(callbackData_), 64)
                )
            )
        }
        if (skipTransfers_ != SKIP_TRANSFERS) {
            return false;
        }
        // after here, if invalid, protocol intended to skip transfers, but something is invalid. so we don't just
        // NOT skip transfers, we actually revert because there must be something wrong on protocol side.

        // 2. amounts must be
        // a) equal: supply(+) == borrow(+), withdraw(-) == payback(-) OR
        // b) Liquidity must be on the winning side.
        // EITHER:
        // deposit and borrow, both positive. there must be more borrow than deposit.
        // so supply amount must be less, e.g. 80 deposit and 100 borrow.
        // OR:
        // withdraw and payback, both negative. there must be more withdraw than payback.
        // so supplyAmount must be less (e.g. -100 withdraw and -80 payback )
        if (
            msg.value != 0 || // no msg.value should be sent along when trying to skip transfers.
            supplyAmount_ == 0 ||
            borrowAmount_ == 0 || // it must be a 2 actions operation, not just e.g. only deposit or only payback.
            supplyAmount_ > borrowAmount_ // allow case a) and b): supplyAmount must be <=
        ) {
            revert FluidLiquidityError(ErrorTypes.UserModule__SkipTransfersInvalid);
        }

        // 3. inFrom_ must be in last 32 bytes and must match receiver
        address inFrom_;
        assembly {
            inFrom_ := mload(
                add(
                    // add padding for length as present for dynamic arrays in memory
                    add(callbackData_, 32),
                    // assembly expects address with leading zeros / left padded so need to use 32 as length here
                    sub(mload(callbackData_), 32)
                )
            )
        }

        if (supplyAmount_ > 0) {
            // deposit and borrow
            if (!(inFrom_ == borrowTo_ && inFrom_ == msg.sender)) {
                revert FluidLiquidityError(ErrorTypes.UserModule__SkipTransfersInvalid);
            }
        } else {
            // withdraw and payback
            if (!(inFrom_ == withdrawTo_ && inFrom_ == msg.sender)) {
                revert FluidLiquidityError(ErrorTypes.UserModule__SkipTransfersInvalid);
            }
        }

        return true;
    }
}

/// @title  Fluid Liquidity UserModule
/// @notice Fluid Liquidity public facing endpoint logic contract that implements the `operate()` method.
///         operate can be used to deposit, withdraw, borrow & payback funds, given that they have the necessary
///         user config allowance. Interacting users must be allowed via the Fluid Liquidity AdminModule first.
///         Intended users are thus allow-listed protocols, e.g. the Lending protocol (fTokens), Vault protocol etc.
/// @dev For view methods / accessing data, use the "LiquidityResolver" periphery contract.
contract FluidLiquidityUserModule is CoreInternals {
    using BigMathMinified for uint256;

    /// @dev struct for vars used in operate() that would otherwise cause a Stack too deep error
    struct OperateMemoryVars {
        bool skipTransfers;
        uint256 supplyExchangePrice;
        uint256 borrowExchangePrice;
        uint256 supplyRawInterest;
        uint256 supplyInterestFree;
        uint256 borrowRawInterest;
        uint256 borrowInterestFree;
        uint256 totalAmounts;
        uint256 exchangePricesAndConfig;
    }

    /// @notice inheritdoc IFluidLiquidity
    function operate(
        address token_,
        int256 supplyAmount_,
        int256 borrowAmount_,
        address withdrawTo_,
        address borrowTo_,
        bytes calldata callbackData_
    ) external payable reentrancy returns (uint256 memVar3_, uint256 memVar4_) {
        if (supplyAmount_ == 0 && borrowAmount_ == 0) {
            revert FluidLiquidityError(ErrorTypes.UserModule__OperateAmountsZero);
        }
        if (
            supplyAmount_ < type(int128).min ||
            supplyAmount_ > type(int128).max ||
            borrowAmount_ < type(int128).min ||
            borrowAmount_ > type(int128).max
        ) {
            revert FluidLiquidityError(ErrorTypes.UserModule__OperateAmountOutOfBounds);
        }
        if ((supplyAmount_ < 0 && withdrawTo_ == address(0)) || (borrowAmount_ > 0 && borrowTo_ == address(0))) {
            revert FluidLiquidityError(ErrorTypes.UserModule__ReceiverNotDefined);
        }
        if (token_ != NATIVE_TOKEN_ADDRESS && msg.value > 0) {
            // revert: there should not be msg.value if the token is not the native token
            revert FluidLiquidityError(ErrorTypes.UserModule__MsgValueForNonNativeToken);
        }

        OperateMemoryVars memory o_;

        // @dev temporary memory variables used as helper in between to avoid assigning new memory variables
        uint256 memVar_;
        // memVar2_ => operateAmountIn: deposit + payback
        uint256 memVar2_ = uint256((supplyAmount_ > 0 ? supplyAmount_ : int256(0))) +
            uint256((borrowAmount_ < 0 ? -borrowAmount_ : int256(0)));

        // check if token transfers can be skipped. see `_isInOutBalancedOut` for details.
        if (
            callbackData_.length > 63 &&
            _isInOutBalancedOut(supplyAmount_, borrowAmount_, withdrawTo_, borrowTo_, callbackData_)
        ) {
            memVar2_ = 0; // set to 0 to skip transfers IN
            o_.skipTransfers = true; // set flag to true to skip transfers OUT
        }
        if (token_ == NATIVE_TOKEN_ADDRESS) {
            unchecked {
                // check supply and payback amount is covered by available sent msg.value and
                // protection that msg.value is not unintentionally way more than actually used in operate()
                if (
                    memVar2_ > msg.value ||
                    msg.value > (memVar2_ * (FOUR_DECIMALS + MAX_INPUT_AMOUNT_EXCESS)) / FOUR_DECIMALS
                ) {
                    revert FluidLiquidityError(ErrorTypes.UserModule__TransferAmountOutOfBounds);
                }
            }
            memVar2_ = 0; // set to 0 to skip transfers IN more gas efficient. No need for native token.
        }
        // if supply or payback or both -> transfer token amount from sender to here.
        // for native token this is already covered by msg.value checks in operate(). memVar2_ is set to 0
        // for same amounts in same operate(): supply(+) == borrow(+), withdraw(-) == payback(-). memVar2_ is set to 0
        if (memVar2_ > 0) {
            // memVar_ => initial token balance of this contract
            memVar_ = IERC20(token_).balanceOf(address(this));
            // trigger protocol to send token amount and pass callback data
            IProtocol(msg.sender).liquidityCallback(token_, memVar2_, callbackData_);
            // memVar_ => current token balance of this contract - initial balance
            memVar_ = IERC20(token_).balanceOf(address(this)) - memVar_;
            unchecked {
                if (
                    memVar_ < memVar2_ ||
                    memVar_ > (memVar2_ * (FOUR_DECIMALS + MAX_INPUT_AMOUNT_EXCESS)) / FOUR_DECIMALS
                ) {
                    // revert if protocol did not send enough to cover supply / payback
                    // or if protocol sent more than expected, with 1% tolerance for any potential rounding issues (and for DEX revenue cut)
                    revert FluidLiquidityError(ErrorTypes.UserModule__TransferAmountOutOfBounds);
                }
            }
        }

        o_.exchangePricesAndConfig = _exchangePricesAndConfig[token_];

        // calculate updated exchange prices
        (o_.supplyExchangePrice, o_.borrowExchangePrice) = LiquidityCalcs.calcExchangePrices(
            o_.exchangePricesAndConfig
        );

        // Extract total supply / borrow amounts for the token
        o_.totalAmounts = _totalAmounts[token_];
        memVar_ = o_.totalAmounts & X64;
        o_.supplyRawInterest = (memVar_ >> DEFAULT_EXPONENT_SIZE) << (memVar_ & DEFAULT_EXPONENT_MASK);
        memVar_ = (o_.totalAmounts >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_SUPPLY_INTEREST_FREE) & X64;
        o_.supplyInterestFree = (memVar_ >> DEFAULT_EXPONENT_SIZE) << (memVar_ & DEFAULT_EXPONENT_MASK);
        memVar_ = (o_.totalAmounts >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST) & X64;
        o_.borrowRawInterest = (memVar_ >> DEFAULT_EXPONENT_SIZE) << (memVar_ & DEFAULT_EXPONENT_MASK);
        // no & mask needed for borrow interest free as it occupies the last bits in the storage slot
        memVar_ = (o_.totalAmounts >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_INTEREST_FREE);
        o_.borrowInterestFree = (memVar_ >> DEFAULT_EXPONENT_SIZE) << (memVar_ & DEFAULT_EXPONENT_MASK);

        if (supplyAmount_ != 0) {
            // execute supply or withdraw and update total amounts
            {
                uint256 totalAmountsBefore_ = o_.totalAmounts;
                (int256 newSupplyInterestRaw_, int256 newSupplyInterestFree_) = _supplyOrWithdraw(
                    token_,
                    supplyAmount_,
                    o_.supplyExchangePrice
                );
                // update total amounts. this is done here so that values are only written to storage once
                // if a borrow / payback also happens in the same `operate()` call
                if (newSupplyInterestFree_ == 0) {
                    // Note newSupplyInterestFree_ can ONLY be 0 if mode is with interest,
                    // easy to check as that variable is NOT the result of a dvision etc.
                    // supply or withdraw with interest -> raw amount
                    if (newSupplyInterestRaw_ > 0) {
                        o_.supplyRawInterest += uint256(newSupplyInterestRaw_);
                    } else {
                        unchecked {
                            o_.supplyRawInterest = o_.supplyRawInterest > uint256(-newSupplyInterestRaw_)
                                ? o_.supplyRawInterest - uint256(-newSupplyInterestRaw_)
                                : 0; // withdraw amount is > total supply -> withdraw total supply down to 0
                            // Note no risk here as if the user withdraws more than supplied it would revert already
                            // earlier. Total amounts can end up < sum of user amounts because of rounding
                        }
                    }

                    // Note check for revert {UserModule}__ValueOverflow__TOTAL_SUPPLY is further down when we anyway
                    // calculate the normal amount from raw

                    // Converting the updated total amount into big number for storage
                    memVar_ = o_.supplyRawInterest.toBigNumber(
                        DEFAULT_COEFFICIENT_SIZE,
                        DEFAULT_EXPONENT_SIZE,
                        BigMathMinified.ROUND_DOWN
                    );
                    // update total supply with interest at total amounts in storage (only update changed values)
                    o_.totalAmounts =
                        // mask to update bits 0-63
                        (o_.totalAmounts & 0xffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000) |
                        memVar_; // converted to BigNumber can not overflow
                } else {
                    // supply or withdraw interest free -> normal amount
                    if (newSupplyInterestFree_ > 0) {
                        o_.supplyInterestFree += uint256(newSupplyInterestFree_);
                    } else {
                        unchecked {
                            o_.supplyInterestFree = o_.supplyInterestFree > uint256(-newSupplyInterestFree_)
                                ? o_.supplyInterestFree - uint256(-newSupplyInterestFree_)
                                : 0; // withdraw amount is > total supply -> withdraw total supply down to 0
                            // Note no risk here as if the user withdraws more than supplied it would revert already
                            // earlier. Total amounts can end up < sum of user amounts because of rounding
                        }
                    }
                    if (o_.supplyInterestFree > MAX_TOKEN_AMOUNT_CAP) {
                        // only withdrawals allowed if total supply interest free reaches MAX_TOKEN_AMOUNT_CAP
                        revert FluidLiquidityError(ErrorTypes.UserModule__ValueOverflow__TOTAL_SUPPLY);
                    }
                    // Converting the updated total amount into big number for storage
                    memVar_ = o_.supplyInterestFree.toBigNumber(
                        DEFAULT_COEFFICIENT_SIZE,
                        DEFAULT_EXPONENT_SIZE,
                        BigMathMinified.ROUND_DOWN
                    );
                    // update total supply interest free at total amounts in storage (only update changed values)
                    o_.totalAmounts =
                        // mask to update bits 64-127
                        (o_.totalAmounts & 0xffffffffffffffffffffffffffffffff0000000000000000ffffffffffffffff) |
                        (memVar_ << LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_SUPPLY_INTEREST_FREE); // converted to BigNumber can not overflow
                }
                if (totalAmountsBefore_ == o_.totalAmounts) {
                    // make sure that operate amount is not so small that it wouldn't affect storage update. if a difference
                    // is present then rounding will be in the right direction to avoid any potential manipulation.
                    revert FluidLiquidityError(ErrorTypes.UserModule__OperateAmountInsufficient);
                }
            }
        }
        if (borrowAmount_ != 0) {
            // execute borrow or payback and update total amounts
            {
                uint256 totalAmountsBefore_ = o_.totalAmounts;
                (int256 newBorrowInterestRaw_, int256 newBorrowInterestFree_) = _borrowOrPayback(
                    token_,
                    borrowAmount_,
                    o_.borrowExchangePrice
                );
                // update total amounts. this is done here so that values are only written to storage once
                // if a supply / withdraw also happens in the same `operate()` call
                if (newBorrowInterestFree_ == 0) {
                    // Note newBorrowInterestFree_ can ONLY be 0 if mode is with interest,
                    // easy to check as that variable is NOT the result of a dvision etc.
                    // borrow or payback with interest -> raw amount
                    if (newBorrowInterestRaw_ > 0) {
                        o_.borrowRawInterest += uint256(newBorrowInterestRaw_);
                    } else {
                        unchecked {
                            o_.borrowRawInterest = o_.borrowRawInterest > uint256(-newBorrowInterestRaw_)
                                ? o_.borrowRawInterest - uint256(-newBorrowInterestRaw_)
                                : 0; // payback amount is > total borrow -> payback total borrow down to 0
                        }
                    }

                    // Note check for revert UserModule__ValueOverflow__TOTAL_BORROW is further down when we anyway
                    // calculate the normal amount from raw

                    // Converting the updated total amount into big number for storage
                    memVar_ = o_.borrowRawInterest.toBigNumber(
                        DEFAULT_COEFFICIENT_SIZE,
                        DEFAULT_EXPONENT_SIZE,
                        BigMathMinified.ROUND_UP
                    );
                    // update total borrow with interest at total amounts in storage (only update changed values)
                    o_.totalAmounts =
                        // mask to update bits 128-191
                        (o_.totalAmounts & 0xffffffffffffffff0000000000000000ffffffffffffffffffffffffffffffff) |
                        (memVar_ << LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST); // converted to BigNumber can not overflow
                } else {
                    // borrow or payback interest free -> normal amount
                    if (newBorrowInterestFree_ > 0) {
                        o_.borrowInterestFree += uint256(newBorrowInterestFree_);
                    } else {
                        unchecked {
                            o_.borrowInterestFree = o_.borrowInterestFree > uint256(-newBorrowInterestFree_)
                                ? o_.borrowInterestFree - uint256(-newBorrowInterestFree_)
                                : 0; // payback amount is > total borrow -> payback total borrow down to 0
                        }
                    }
                    if (o_.borrowInterestFree > MAX_TOKEN_AMOUNT_CAP) {
                        // only payback allowed if total borrow interest free reaches MAX_TOKEN_AMOUNT_CAP
                        revert FluidLiquidityError(ErrorTypes.UserModule__ValueOverflow__TOTAL_BORROW);
                    }
                    // Converting the updated total amount into big number for storage
                    memVar_ = o_.borrowInterestFree.toBigNumber(
                        DEFAULT_COEFFICIENT_SIZE,
                        DEFAULT_EXPONENT_SIZE,
                        BigMathMinified.ROUND_UP
                    );
                    // update total borrow interest free at total amounts in storage (only update changed values)
                    o_.totalAmounts =
                        // mask to update bits 192-255
                        (o_.totalAmounts & 0x0000000000000000ffffffffffffffffffffffffffffffffffffffffffffffff) |
                        (memVar_ << LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_INTEREST_FREE); // converted to BigNumber can not overflow
                }
                if (totalAmountsBefore_ == o_.totalAmounts) {
                    // make sure that operate amount is not so small that it wouldn't affect storage update. if a difference
                    // is present then rounding will be in the right direction to avoid any potential manipulation.
                    revert FluidLiquidityError(ErrorTypes.UserModule__OperateAmountInsufficient);
                }
            }
        }
        // Updating total amounts on storage
        _totalAmounts[token_] = o_.totalAmounts;
        {
            // update exchange prices / utilization / ratios
            // exchangePricesAndConfig is only written to storage if either utilization, supplyRatio or borrowRatio
            // change is above the required storageUpdateThreshold config value or if the last write was > 1 day ago.

            // 1. calculate new supply ratio, borrow ratio & utilization.
            // 2. check if last storage write was > 1 day ago.
            // 3. If false -> check if utilization is above update threshold
            // 4. If false -> check if supply ratio is above update threshold
            // 5. If false -> check if borrow ratio is above update threshold
            // 6. If any true, then update on storage

            // ########## calculating supply ratio ##########
            // supplyWithInterest in normal amount
            memVar3_ = ((o_.supplyRawInterest * o_.supplyExchangePrice) / EXCHANGE_PRICES_PRECISION);
            if (memVar3_ > MAX_TOKEN_AMOUNT_CAP && supplyAmount_ > 0) {
                // only withdrawals allowed if total supply raw reaches MAX_TOKEN_AMOUNT_CAP
                revert FluidLiquidityError(ErrorTypes.UserModule__ValueOverflow__TOTAL_SUPPLY);
            }
            // memVar_ => total supply. set here so supplyWithInterest (memVar3_) is only calculated once. For utilization
            memVar_ = o_.supplyInterestFree + memVar3_;
            if (memVar3_ > o_.supplyInterestFree) {
                // memVar3_ is ratio with 1 bit as 0 as supply interest raw is bigger
                memVar3_ = ((o_.supplyInterestFree * FOUR_DECIMALS) / memVar3_) << 1;
                // because of checking to divide by bigger amount, ratio can never be > 100%
            } else if (memVar3_ < o_.supplyInterestFree) {
                // memVar3_ is ratio with 1 bit as 1 as supply interest free is bigger
                memVar3_ = (((memVar3_ * FOUR_DECIMALS) / o_.supplyInterestFree) << 1) | 1;
                // because of checking to divide by bigger amount, ratio can never be > 100%
            } else if (memVar_ > 0) {
                // supplies match exactly (memVar3_  == o_.supplyInterestFree) and total supplies are not 0
                // -> set ratio to 1 (with first bit set to 0, doesn't matter)
                memVar3_ = FOUR_DECIMALS << 1;
            } // else if total supply = 0, memVar3_ (supplyRatio) is already 0.

            // ########## calculating borrow ratio ##########
            // borrowWithInterest in normal amount
            memVar4_ = ((o_.borrowRawInterest * o_.borrowExchangePrice) / EXCHANGE_PRICES_PRECISION);
            if (memVar4_ > MAX_TOKEN_AMOUNT_CAP && borrowAmount_ > 0) {
                // only payback allowed if total borrow raw reaches MAX_TOKEN_AMOUNT_CAP
                revert FluidLiquidityError(ErrorTypes.UserModule__ValueOverflow__TOTAL_BORROW);
            }
            // memVar2_ => total borrow. set here so borrowWithInterest (memVar4_) is only calculated once. For utilization
            memVar2_ = o_.borrowInterestFree + memVar4_;
            if (memVar4_ > o_.borrowInterestFree) {
                // memVar4_ is ratio with 1 bit as 0 as borrow interest raw is bigger
                memVar4_ = ((o_.borrowInterestFree * FOUR_DECIMALS) / memVar4_) << 1;
                // because of checking to divide by bigger amount, ratio can never be > 100%
            } else if (memVar4_ < o_.borrowInterestFree) {
                // memVar4_ is ratio with 1 bit as 1 as borrow interest free is bigger
                memVar4_ = (((memVar4_ * FOUR_DECIMALS) / o_.borrowInterestFree) << 1) | 1;
                // because of checking to divide by bigger amount, ratio can never be > 100%
            } else if (memVar2_ > 0) {
                // borrows match exactly (memVar4_  == o_.borrowInterestFree) and total borrows are not 0
                // -> set ratio to 1 (with first bit set to 0, doesn't matter)
                memVar4_ = FOUR_DECIMALS << 1;
            } // else if total borrow = 0, memVar4_ (borrowRatio) is already 0.

            // calculate utilization. If there is no supply, utilization must be 0 (avoid division by 0)
            uint256 utilization_;
            if (memVar_ > 0) {
                utilization_ = ((memVar2_ * FOUR_DECIMALS) / memVar_);

                // for borrow operations, ensure max utilization is not reached
                if (borrowAmount_ > 0) {
                    // memVar_ => max utilization
                    // if any max utilization other than 100% is set, the flag usesConfigs2 in
                    // exchangePricesAndConfig is 1. (optimized to avoid SLOAD if not needed).
                    memVar_ = (o_.exchangePricesAndConfig >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_USES_CONFIGS2) &
                        1 ==
                        1
                        ? (_configs2[token_] & X14) // read configured max utilization
                        : FOUR_DECIMALS; // default max utilization = 100%

                    if (utilization_ > memVar_) {
                        revert FluidLiquidityError(ErrorTypes.UserModule__MaxUtilizationReached);
                    }
                }
            }

            // check if time difference is big enough (> 1 day)
            unchecked {
                if (
                    block.timestamp >
                    // extract last update timestamp + 1 day
                    (((o_.exchangePricesAndConfig >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) & X33) +
                        FORCE_STORAGE_WRITE_AFTER_TIME)
                ) {
                    memVar_ = 1; // set write to storage flag
                } else {
                    memVar_ = 0;
                }
            }

            if (memVar_ == 0) {
                // time difference is not big enough to cause storage write -> check utilization

                // memVar_ => extract last utilization
                memVar_ = (o_.exchangePricesAndConfig >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) & X14;
                // memVar2_ => storage update threshold in percent
                memVar2_ =
                    (o_.exchangePricesAndConfig >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UPDATE_THRESHOLD) &
                    X14;
                unchecked {
                    // set memVar_ to 1 if current utilization to previous utilization difference is > update storage threshold
                    memVar_ = (utilization_ > memVar_ ? utilization_ - memVar_ : memVar_ - utilization_) > memVar2_
                        ? 1
                        : 0;
                    if (memVar_ == 0) {
                        // utilization & time difference is not big enough -> check supplyRatio difference
                        // memVar_ => extract last supplyRatio
                        memVar_ =
                            (o_.exchangePricesAndConfig >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_RATIO) &
                            X15;
                        // set memVar_ to 1 if current supplyRatio to previous supplyRatio difference is > update storage threshold
                        if ((memVar_ & 1) == (memVar3_ & 1)) {
                            memVar_ = memVar_ >> 1;
                            memVar_ = (
                                (memVar3_ >> 1) > memVar_ ? (memVar3_ >> 1) - memVar_ : memVar_ - (memVar3_ >> 1)
                            ) > memVar2_
                                ? 1
                                : 0; // memVar3_ = supplyRatio, memVar_ = previous supplyRatio, memVar2_ = update storage threshold
                        } else {
                            // if inverse bit is changing then always update on storage
                            memVar_ = 1;
                        }
                        if (memVar_ == 0) {
                            // utilization, time, and supplyRatio difference is not big enough -> check borrowRatio difference
                            // memVar_ => extract last borrowRatio
                            memVar_ =
                                (o_.exchangePricesAndConfig >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_RATIO) &
                                X15;
                            // set memVar_ to 1 if current borrowRatio to previous borrowRatio difference is > update storage threshold
                            if ((memVar_ & 1) == (memVar4_ & 1)) {
                                memVar_ = memVar_ >> 1;
                                memVar_ = (
                                    (memVar4_ >> 1) > memVar_ ? (memVar4_ >> 1) - memVar_ : memVar_ - (memVar4_ >> 1)
                                ) > memVar2_
                                    ? 1
                                    : 0; // memVar4_ = borrowRatio, memVar_ = previous borrowRatio, memVar2_ = update storage threshold
                            } else {
                                // if inverse bit is changing then always update on storage
                                memVar_ = 1;
                            }
                        }
                    }
                }
            }

            // memVar_ is 1 if either time diff was enough or if
            // utilization, supplyRatio or borrowRatio difference was > update storage threshold
            if (memVar_ == 1) {
                // memVar_ => calculate new borrow rate for utilization. includes value overflow check.
                memVar_ = LiquidityCalcs.calcBorrowRateFromUtilization(_rateData[token_], utilization_);
                // ensure values written to storage do not exceed the dedicated bit space in packed uint256 slots
                if (o_.supplyExchangePrice > X64 || o_.borrowExchangePrice > X64) {
                    revert FluidLiquidityError(ErrorTypes.UserModule__ValueOverflow__EXCHANGE_PRICES);
                }
                if (utilization_ > X14) {
                    revert FluidLiquidityError(ErrorTypes.UserModule__ValueOverflow__UTILIZATION);
                }
                o_.exchangePricesAndConfig =
                    (o_.exchangePricesAndConfig &
                        // mask to update bits: 0-15 (borrow rate), 30-43 (utilization), 58-248 (timestamp, exchange prices, ratios)
                        0xfe000000000000000000000000000000000000000000000003fff0003fff0000) |
                    memVar_ | // calcBorrowRateFromUtilization already includes an overflow check
                    (utilization_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) |
                    (block.timestamp << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) |
                    (o_.supplyExchangePrice << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) |
                    (o_.borrowExchangePrice << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) |
                    // ratios can never be > 100%, no overflow check needed
                    (memVar3_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_RATIO) | // supplyRatio (memVar3_ holds that value)
                    (memVar4_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_RATIO); // borrowRatio (memVar4_ holds that value)
                // Updating on storage
                _exchangePricesAndConfig[token_] = o_.exchangePricesAndConfig;
            } else {
                // do not update in storage but update o_.exchangePricesAndConfig for updated exchange prices at
                // event emit of LogOperate
                o_.exchangePricesAndConfig =
                    (o_.exchangePricesAndConfig &
                        // mask to update bits: 91-218 (exchange prices)
                        0xfffffffffc00000000000000000000000000000007ffffffffffffffffffffff) |
                    (o_.supplyExchangePrice << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) |
                    (o_.borrowExchangePrice << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE);
            }
        }
        // sending tokens to user at the end after updating everything
        // only transfer to user in case of withdraw or borrow.
        // do not transfer for same amounts in same operate(): supply(+) == borrow(+), withdraw(-) == payback(-). (DEX protocol use-case)
        if ((supplyAmount_ < 0 || borrowAmount_ > 0) && !o_.skipTransfers) {
            // sending tokens to user at the end after updating everything
            // set memVar2_ to borrowAmount (if borrow) or reset memVar2_ var to 0 because
            // it is used with > 0 check below to transfer withdraw / borrow / both
            memVar2_ = borrowAmount_ > 0 ? uint256(borrowAmount_) : 0;
            if (supplyAmount_ < 0) {
                unchecked {
                    memVar_ = uint256(-supplyAmount_);
                }
            } else {
                memVar_ = 0;
            }
            if (memVar_ > 0 && memVar2_ > 0 && withdrawTo_ == borrowTo_) {
                // if user is doing borrow & withdraw together and address for both is the same
                // then transfer tokens of borrow & withdraw together to save on gas
                if (token_ == NATIVE_TOKEN_ADDRESS) {
                    SafeTransfer.safeTransferNative(withdrawTo_, memVar_ + memVar2_);
                } else {
                    SafeTransfer.safeTransfer(token_, withdrawTo_, memVar_ + memVar2_);
                }
            } else {
                if (token_ == NATIVE_TOKEN_ADDRESS) {
                    // if withdraw
                    if (memVar_ > 0) {
                        SafeTransfer.safeTransferNative(withdrawTo_, memVar_);
                    }
                    // if borrow
                    if (memVar2_ > 0) {
                        SafeTransfer.safeTransferNative(borrowTo_, memVar2_);
                    }
                } else {
                    // if withdraw
                    if (memVar_ > 0) {
                        SafeTransfer.safeTransfer(token_, withdrawTo_, memVar_);
                    }
                    // if borrow
                    if (memVar2_ > 0) {
                        SafeTransfer.safeTransfer(token_, borrowTo_, memVar2_);
                    }
                }
            }
        }
        // emit Operate event
        emit LogOperate(
            msg.sender,
            token_,
            supplyAmount_,
            borrowAmount_,
            withdrawTo_,
            borrowTo_,
            o_.totalAmounts,
            o_.exchangePricesAndConfig
        );
        // set return values
        memVar3_ = o_.supplyExchangePrice;
        memVar4_ = o_.borrowExchangePrice;
    }
}
