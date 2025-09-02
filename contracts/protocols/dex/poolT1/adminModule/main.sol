// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Variables } from "../common/variables.sol";
import { Events } from "./events.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { Error } from "../../error.sol";
import { BigMathMinified } from "../../../../libraries/bigMathMinified.sol";
import { ConstantVariables } from "../common/constantVariables.sol";
import { Structs } from "./structs.sol";
import { IFluidDexT1 } from "../../interfaces/iDexT1.sol";
import { IFluidLiquidity } from "../../../../liquidity/interfaces/iLiquidity.sol";
import { SafeTransfer } from "../../../../libraries/safeTransfer.sol";
import { AddressCalcs } from "../../../../libraries/addressCalcs.sol";
import { DexSlotsLink } from "../../../../libraries/dexSlotsLink.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Fluid Dex protocol Admin Module contract.
///         Implements admin related methods to set pool configs
///         Methods are limited to be called via delegateCall only. Dex CoreModule ("DexT1" contract)
///         is expected to call the methods implemented here after checking the msg.sender is authorized.
contract FluidDexT1Admin is ConstantVariables, Variables, Structs, Events, Error {
    using BigMathMinified for uint256;

    address private immutable ADDRESS_THIS;

    constructor() {
        ADDRESS_THIS = address(this);
    }

    modifier _onlyDelegateCall() {
        // also indirectly checked by `_check` because pool can never be initialized as long as the initialize method
        // is delegate call only, but just to be sure on Admin logic we add the modifier everywhere nonetheless.
        if (address(this) == ADDRESS_THIS) {
            revert FluidDexError(ErrorTypes.DexT1Admin__OnlyDelegateCallAllowed);
        }
        _;
    }

    modifier _check() {
        if ((dexVariables2 & 3) == 0) {
            revert FluidDexError(ErrorTypes.DexT1Admin__PoolNotInitialized);
        }
        _;
    }

    /// @dev checks that `value_` address is a contract (which includes address zero check) or native address
    function _checkIsContractOrNativeAddress(address value_) internal view {
        if (value_.code.length == 0 && value_ != NATIVE_TOKEN) {
            revert FluidDexError(ErrorTypes.DexT1Admin__AddressNotAContract);
        }
    }

    /// @dev checks that `value_` address is a contract (which includes address zero check)
    function _checkIsContract(address value_) internal view {
        if (value_.code.length == 0) {
            revert FluidDexError(ErrorTypes.DexT1Admin__AddressNotAContract);
        }
    }

    function turnOnSmartCol(uint token0Amt_) public payable _check _onlyDelegateCall {
        if (dexVariables2 & 1 == 1) {
            revert FluidDexError(ErrorTypes.DexT1Admin__SmartColIsAlreadyOn);
        }
        uint centerPrice_ = (dexVariables >> 81) & X40;
        centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);
        _turnOnSmartCol(token0Amt_, centerPrice_);

        dexVariables2 = dexVariables2 | 1;

        emit LogTurnOnSmartCol(token0Amt_);
    }

    function _turnOnSmartCol(uint token0Amt_, uint centerPrice_) internal {
        IFluidDexT1.ConstantViews memory c_ = IFluidDexT1(address(this)).constantsView();
        IFluidDexT1.ConstantViews2 memory c2_ = IFluidDexT1(address(this)).constantsView2();

        uint token0AmtAdjusted_ = (token0Amt_ * c2_.token0NumeratorPrecision) / c2_.token0DenominatorPrecision;

        uint token1AmtAdjusted_ = (centerPrice_ * token0AmtAdjusted_) / 1e27;

        uint token1Amt_ = (token1AmtAdjusted_ * c2_.token1DenominatorPrecision) / c2_.token1NumeratorPrecision;

        IFluidLiquidity liquidity_ = IFluidLiquidity(c_.liquidity);

        // if both tokens are not native token and msg.value is sent, revert
        if (msg.value > 0 && c_.token0 != NATIVE_TOKEN && c_.token1 != NATIVE_TOKEN) {
            revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }

        address token_;
        uint amt_;
        for (uint i = 0; i < 2; i++) {
            if (i == 0) {
                token_ = c_.token0;
                amt_ = token0Amt_;
            } else {
                token_ = c_.token1;
                amt_ = token1Amt_;
            }
            if (token_ == NATIVE_TOKEN) {
                if (msg.value > amt_) {
                    SafeTransfer.safeTransferNative(msg.sender, msg.value - amt_);
                } else if (msg.value < amt_) {
                    revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
                }
                // deposit
                liquidity_.operate{ value: amt_ }(
                    token_,
                    int(amt_),
                    0,
                    address(0),
                    address(0),
                    abi.encode(amt_, false, msg.sender)
                );
            } else {
                // deposit
                liquidity_.operate(token_, int(amt_), 0, address(0), address(0), abi.encode(amt_, false, msg.sender));
            }
        }

        // minting shares according to whatever tokenAmt is bigger
        // adding shares on storage but not adding shares for any user, hence locking these shares forever
        // adjusted amounts are in 12 decimals, making shares in 18 decimals
        uint totalSupplyShares_ = (token0AmtAdjusted_ > token1AmtAdjusted_)
            ? token0AmtAdjusted_ * 10 ** (18 - TOKENS_DECIMALS_PRECISION)
            : token1AmtAdjusted_ * 10 ** (18 - TOKENS_DECIMALS_PRECISION);

        if (totalSupplyShares_ < NINE_DECIMALS) {
            revert FluidDexError(ErrorTypes.DexT1Admin__UnexpectedPoolState);
        }

        // setting initial max shares as X128
        totalSupplyShares_ = (totalSupplyShares_ & X128) | (X128 << 128);
        // storing in storage
        _totalSupplyShares = totalSupplyShares_;
    }

    function turnOnSmartDebt(uint token0Amt_) public _check _onlyDelegateCall {
        if (dexVariables2 & 2 == 2) {
            revert FluidDexError(ErrorTypes.DexT1Admin__SmartDebtIsAlreadyOn);
        }
        uint centerPrice_ = (dexVariables >> 81) & X40;
        centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);
        _turnOnSmartDebt(token0Amt_, centerPrice_);

        dexVariables2 = dexVariables2 | 2;

        emit LogTurnOnSmartDebt(token0Amt_);
    }

    /// @dev Can only borrow if DEX pool address borrow config is added in Liquidity Layer for both the tokens else Liquidity Layer will revert
    /// governance will have access to _turnOnSmartDebt, technically governance here can borrow as much as limits are set
    /// so it's governance responsibility that it borrows small amount between $100 - $10,000
    /// Borrowing in 50:50 ratio (doesn't matter if pool configuration is set to 20:80, 30:70, etc, external swap will arbitrage & balance the pool)
    function _turnOnSmartDebt(uint token0Amt_, uint centerPrice_) internal {
        IFluidDexT1.ConstantViews memory c_ = IFluidDexT1(address(this)).constantsView();
        IFluidDexT1.ConstantViews2 memory c2_ = IFluidDexT1(address(this)).constantsView2();

        uint token0AmtAdjusted_ = (token0Amt_ * c2_.token0NumeratorPrecision) / c2_.token0DenominatorPrecision;

        uint token1AmtAdjusted_ = (centerPrice_ * token0AmtAdjusted_) / 1e27;

        uint token1Amt_ = (token1AmtAdjusted_ * c2_.token1DenominatorPrecision) / c2_.token1NumeratorPrecision;

        IFluidLiquidity liquidity_ = IFluidLiquidity(c_.liquidity);

        liquidity_.operate(c_.token0, 0, int(token0Amt_), address(0), TEAM_MULTISIG, new bytes(0));
        liquidity_.operate(c_.token1, 0, int(token1Amt_), address(0), TEAM_MULTISIG, new bytes(0));

        // minting shares as whatever tokenAmt is bigger
        // adding shares on storage but not adding shares for any user, hence locking these shares forever
        // adjusted amounts are in 12 decimals, making shares in 18 decimals
        uint totalBorrowShares_ = (token0AmtAdjusted_ > token1AmtAdjusted_)
            ? token0AmtAdjusted_ * 10 ** (18 - TOKENS_DECIMALS_PRECISION)
            : token1AmtAdjusted_ * 10 ** (18 - TOKENS_DECIMALS_PRECISION);

        if (totalBorrowShares_ < NINE_DECIMALS) {
            revert FluidDexError(ErrorTypes.DexT1Admin__UnexpectedPoolState);
        }

        // setting initial max shares as X128
        totalBorrowShares_ = (totalBorrowShares_ & X128) | (X128 << 128);
        // storing in storage
        _totalBorrowShares = totalBorrowShares_;
    }

    /// @param fee_ in 4 decimals, 10000 = 1%
    /// @param revenueCut_ in 4 decimals, 100000 = 10%, 10% cut on fee_, so if fee is 1% and cut is 10% then cut in swap amount will be 10% of 1% = 0.1%
    function updateFeeAndRevenueCut(uint fee_, uint revenueCut_) public _check _onlyDelegateCall {
        // cut is an integer in storage slot which is more than enough
        // but from UI we are allowing to send in 4 decimals to maintain consistency & avoid human error in future
        if (revenueCut_ != 0 && revenueCut_ < FOUR_DECIMALS) {
            // human input error. should send 0 for wanting 0, not 0 because of precision reduction.
            revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }

        revenueCut_ = revenueCut_ / FOUR_DECIMALS;

        if (fee_ > FIVE_DECIMALS || revenueCut_ > TWO_DECIMALS) {
            revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        dexVariables2 =
            (dexVariables2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC000003) |
            (fee_ << 2) |
            (revenueCut_ << 19);

        emit LogUpdateFeeAndRevenueCut(fee_, revenueCut_ * FOUR_DECIMALS);
    }

    /// @param upperPercent_ in 4 decimals, 10000 = 1%
    /// @param lowerPercent_ in 4 decimals, 10000 = 1%
    /// @param shiftTime_ in secs, in how much time the upper percent configs change should be fully done
    function updateRangePercents(
        uint upperPercent_,
        uint lowerPercent_,
        uint shiftTime_
    ) public _check _onlyDelegateCall {
        uint dexVariables2_ = dexVariables2;
        if (
            (upperPercent_ > (SIX_DECIMALS - FOUR_DECIMALS)) || // capping range to 99%.
            (lowerPercent_ > (SIX_DECIMALS - FOUR_DECIMALS)) || // capping range to 99%.
            (upperPercent_ == 0) ||
            (lowerPercent_ == 0) ||
            (shiftTime_ > X20) ||
            (((dexVariables2_ >> 26) & 1) == 1) // if last shift is still active then don't allow a newer shift
        ) {
            revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        dexVariables2 =
            (dexVariables2_ & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF80000000003FFFFFF) |
            (uint((shiftTime_ > 0) ? 1 : 0) << 26) |
            (upperPercent_ << 27) |
            (lowerPercent_ << 47);

        uint oldUpperPercent_ = (dexVariables2_ >> 27) & X20;
        uint oldLowerPercent_ = (dexVariables2_ >> 47) & X20;

        if (shiftTime_ > 0) {
            _rangeShift = uint128(
                oldUpperPercent_ | (oldLowerPercent_ << 20) | (shiftTime_ << 40) | (block.timestamp << 60)
            );
        }
        // Note _rangeShift is reset when the previous shift is fully completed, which is forced to have happened through if check above

        emit LogUpdateRangePercents(upperPercent_, lowerPercent_, shiftTime_);
    }

    /// @param upperThresholdPercent_ in 4 decimals, 10000 = 1%
    /// @param lowerThresholdPercent_ in 4 decimals, 10000 = 1%
    /// @param thresholdShiftTime_ in secs, in how much time the threshold percent should take to shift the ranges
    /// @param shiftTime_ in secs, in how much time the upper config changes should be fully done.
    function updateThresholdPercent(
        uint upperThresholdPercent_,
        uint lowerThresholdPercent_,
        uint thresholdShiftTime_,
        uint shiftTime_
    ) public _check _onlyDelegateCall {
        uint dexVariables2_ = dexVariables2;

        // thresholds are with 0.1% precision, hence removing last 3 decimals.
        // we are allowing to send in 4 decimals to maintain consistency with other params
        upperThresholdPercent_ = upperThresholdPercent_ / THREE_DECIMALS;
        lowerThresholdPercent_ = lowerThresholdPercent_ / THREE_DECIMALS;
        if (
            (upperThresholdPercent_ > THREE_DECIMALS) ||
            (lowerThresholdPercent_ > THREE_DECIMALS) ||
            (thresholdShiftTime_ == 0) ||
            (thresholdShiftTime_ > X24) ||
            ((upperThresholdPercent_ == 0) && (lowerThresholdPercent_ > 0)) ||
            ((upperThresholdPercent_ > 0) && (lowerThresholdPercent_ == 0)) ||
            (shiftTime_ > X20) ||
            (((dexVariables2_ >> 67) & 1) == 1) // if last shift is still active then don't allow a newer shift
        ) {
            revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        dexVariables2 =
            (dexVariables2_ & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000007FFFFFFFFFFFFFFFF) |
            (uint((shiftTime_ > 0) ? 1 : 0) << 67) |
            (upperThresholdPercent_ << 68) |
            (lowerThresholdPercent_ << 78) |
            (thresholdShiftTime_ << 88);

        uint oldUpperThresholdPercent_ = (dexVariables2_ >> 68) & X10;
        uint oldLowerThresholdPercent_ = (dexVariables2_ >> 78) & X10;
        uint oldThresholdTime_ = (dexVariables2_ >> 88) & X24;

        if (shiftTime_ > 0) {
            _thresholdShift = uint128(
                oldUpperThresholdPercent_ |
                    (oldLowerThresholdPercent_ << 20) |
                    (shiftTime_ << 40) |
                    (block.timestamp << 60) |
                    (oldThresholdTime_ << 93)
            );
        }
        // Note _thresholdShift is reset when the previous shift is fully completed, which is forced to have happened through if check above

        emit LogUpdateThresholdPercent(
            upperThresholdPercent_ * THREE_DECIMALS,
            lowerThresholdPercent_ * THREE_DECIMALS,
            thresholdShiftTime_,
            shiftTime_
        );
    }

    /// @dev we are storing uint nonce from which we will calculate the contract address, to store an address we need 160 bits
    /// which is quite a lot of storage slot
    /// @param centerPriceAddress_ nonce < X30, this nonce will be used to calculate contract address
    function updateCenterPriceAddress(
        uint centerPriceAddress_,
        uint percent_,
        uint time_
    ) public _check _onlyDelegateCall {
        if ((centerPriceAddress_ > X30) || (percent_ == 0) || (percent_ > X20) || (time_ == 0) || (time_ > X20)) {
            revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        if (centerPriceAddress_ > 0) {
            IFluidDexT1.ConstantViews memory c_ = IFluidDexT1(address(this)).constantsView();
            address centerPrice_ = AddressCalcs.addressCalc(c_.deployerContract, centerPriceAddress_);
            _checkIsContract(centerPrice_);
            // note: if address is made 0 then as well in the last swap currentPrice is updated on storage, so code will start using that automatically
            dexVariables2 =
                (dexVariables2 & 0xFeFFFFFFFFFFFFFFFFFFFFFFFFFFC0000000FFFFFFFFFFFFFFFFFFFFFFFFFFFF) |
                (centerPriceAddress_ << 112) |
                (uint(1) << 248);

            _centerPriceShift = block.timestamp | (percent_ << 33) | (time_ << 53);
        } else {
            dexVariables2 = (dexVariables2 & 0xFeFFFFFFFFFFFFFFFFFFFFFFFFFFC0000000FFFFFFFFFFFFFFFFFFFFFFFFFFFF);

            _centerPriceShift = 0;
        }

        emit LogUpdateCenterPriceAddress(centerPriceAddress_, percent_, time_);
    }

    /// @dev we are storing uint nonce from which we will calculate the contract address, to store an address we need 160 bits
    /// which is quite a lot of storage slot
    /// @param hookAddress_ nonce < X30, this nonce will be used to calculate contract address
    function updateHookAddress(uint hookAddress_) public _check _onlyDelegateCall {
        if (hookAddress_ > X30) {
            revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        if (hookAddress_ > 0) {
            IFluidDexT1.ConstantViews memory c_ = IFluidDexT1(address(this)).constantsView();
            address hook_ = AddressCalcs.addressCalc(c_.deployerContract, hookAddress_);
            _checkIsContract(hook_);
        }

        dexVariables2 =
            (dexVariables2 & 0xFFFFFFFFFFFFFFFFFFFFF00000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) |
            (hookAddress_ << 142);

        emit LogUpdateHookAddress(hookAddress_);
    }

    function updateCenterPriceLimits(uint maxCenterPrice_, uint minCenterPrice_) public _check _onlyDelegateCall {
        uint centerPrice_ = (dexVariables >> 81) & X40;
        centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);

        if (
            (maxCenterPrice_ <= minCenterPrice_) ||
            (centerPrice_ <= minCenterPrice_) ||
            (centerPrice_ >= maxCenterPrice_) ||
            (minCenterPrice_ == 0)
        ) {
            revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }

        dexVariables2 =
            (dexVariables2 & 0xFFFFFFF00000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) |
            (maxCenterPrice_.toBigNumber(20, 8, BigMathMinified.ROUND_UP) << 172) |
            (minCenterPrice_.toBigNumber(20, 8, BigMathMinified.ROUND_DOWN) << 200);

        emit LogUpdateCenterPriceLimits(maxCenterPrice_, minCenterPrice_);
    }

    function updateUtilizationLimit(
        uint token0UtilizationLimit_,
        uint token1UtilizationLimit_
    ) public _check _onlyDelegateCall {
        if (
            (token0UtilizationLimit_ != 0 && token0UtilizationLimit_ < THREE_DECIMALS) ||
            (token1UtilizationLimit_ != 0 && token1UtilizationLimit_ < THREE_DECIMALS)
        ) {
            // human input error. should send 0 for wanting 0, not 0 because of precision reduction.
            revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }

        token0UtilizationLimit_ = token0UtilizationLimit_ / THREE_DECIMALS;
        token1UtilizationLimit_ = token1UtilizationLimit_ / THREE_DECIMALS;

        if (token0UtilizationLimit_ > THREE_DECIMALS || token1UtilizationLimit_ > THREE_DECIMALS) {
            revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        dexVariables2 =
            (dexVariables2 & 0xFF00000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) |
            (token0UtilizationLimit_ << 228) |
            (token1UtilizationLimit_ << 238);

        emit LogUpdateUtilizationLimit(
            token0UtilizationLimit_ * THREE_DECIMALS,
            token1UtilizationLimit_ * THREE_DECIMALS
        );
    }

    function updateUserSupplyConfigs(UserSupplyConfig[] memory userSupplyConfigs_) external _check _onlyDelegateCall {
        uint256 userSupplyData_;

        for (uint256 i; i < userSupplyConfigs_.length; ) {
            _checkIsContract(userSupplyConfigs_[i].user);
            if (userSupplyConfigs_[i].expandDuration == 0) {
                // can not set expand duration to 0 as that could cause a division by 0 in LiquidityCalcs.
                // having expand duration as 0 is anyway not an expected config so removing the possibility for that.
                // if no expansion is wanted, simply set expandDuration to 1 and expandPercent to 0.
                revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
            }
            if (userSupplyConfigs_[i].expandPercent > FOUR_DECIMALS) {
                revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
            }
            if (userSupplyConfigs_[i].expandDuration > X24) {
                // duration is max 24 bits
                revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
            }
            if (userSupplyConfigs_[i].baseWithdrawalLimit == 0) {
                // base withdrawal limit can not be 0. As a side effect, this ensures that there is no supply config
                // where all values would be 0, so configured users can be differentiated in the mapping.
                revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
            }
            // @dev baseWithdrawalLimit has no max bits amount as it is in normal token amount & converted to BigNumber

            // get current user config data from storage
            userSupplyData_ = _userSupplyData[userSupplyConfigs_[i].user];

            // Updating user data on storage
            _userSupplyData[userSupplyConfigs_[i].user] =
                // mask to update first bit + bits 162-217 (expand percentage, expand duration, base limit)
                (userSupplyData_ & 0xfffffffffc00000000000003ffffffffffffffffffffffffffffffffffffffff) |
                (1) |
                (userSupplyConfigs_[i].expandPercent << DexSlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) |
                (userSupplyConfigs_[i].expandDuration << DexSlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) |
                // convert base withdrawal limit to BigNumber for storage (10 | 8). (below this, 100% can be withdrawn)
                (userSupplyConfigs_[i].baseWithdrawalLimit.toBigNumber(
                    SMALL_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_DOWN
                ) << DexSlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT);

            unchecked {
                ++i;
            }
        }

        emit LogUpdateUserSupplyConfigs(userSupplyConfigs_);
    }

    /// @notice sets a new withdrawal limit as the current limit for a certain user
    /// @param user_ user address for which to update the withdrawal limit
    /// @param newLimit_ new limit until which user supply can decrease to.
    ///                  Important: input in raw. Must account for exchange price in input param calculation.
    ///                  Note any limit that is < max expansion or > current user supply will set max expansion limit or
    ///                  current user supply as limit respectively.
    ///                  - set 0 to make maximum possible withdrawable: instant full expansion, and if that goes
    ///                  below base limit then fully down to 0.
    ///                  - set type(uint256).max to make current withdrawable 0 (sets current user supply as limit).
    function updateUserWithdrawalLimit(address user_, uint256 newLimit_) external _check _onlyDelegateCall {
        _checkIsContract(user_);

        // get current user config data from storage
        uint256 userSupplyData_ = _userSupplyData[user_];
        if (userSupplyData_ == 0) {
            revert FluidDexError(ErrorTypes.DexT1Admin__UserNotDefined);
        }

        // get current user supply amount
        uint256 userSupply_ = (userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        userSupply_ = (userSupply_ >> DEFAULT_EXPONENT_SIZE) << (userSupply_ & DEFAULT_EXPONENT_MASK);

        // maxExpansionLimit_ => withdrawal limit expandPercent (is in 1e2 decimals)
        uint256 maxExpansionLimit_ = (userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) & X14;
        maxExpansionLimit_ = userSupply_ - ((userSupply_ * maxExpansionLimit_) / FOUR_DECIMALS);

        if (newLimit_ == 0 || newLimit_ < maxExpansionLimit_) {
            // instant full expansion, and if that goes below base limit then fully down to 0.
            // if we were to set a limit that goes below max expansion limit, then after 1 deposit or 1 withdrawal it would
            // become based on the max expansion limit again (unless it goes below base limit), which can be confusing.
            // Also updating base limit here to avoid the change after 1 interaction might have undesired effects.
            // So limiting update to max. full expansion. If more is desired, this must be called again after some withdraws.
            newLimit_ = maxExpansionLimit_;
        } else if (newLimit_ == type(uint256).max || newLimit_ > userSupply_) {
            // current withdrawable 0 (sets current user supply as limit).
            newLimit_ = userSupply_;
        }
        // else => new limit is between > max expansion and < user supply.

        // set input limit as new current limit. instant withdrawable will be userSupply_ - newLimit_

        uint256 baseLimit_ = (userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT) & X18;
        baseLimit_ = (baseLimit_ >> DEFAULT_EXPONENT_SIZE) << (baseLimit_ & DEFAULT_EXPONENT_MASK);
        if (userSupply_ < baseLimit_) {
            newLimit_ = 0;
            // Note if new limit goes below base limit, it follows default behavior: first there must be a withdrawal
            // that brings user supply below base limit, then the limit will be set to 0.
            // otherwise we would have the same problem as described above after 1 interaction.
        }

        // Update on storage
        _userSupplyData[user_] =
            // mask to update bits 65-161 (withdrawal limit, timestamp)
            (userSupplyData_ & 0xFFFFFFFFFFFFFFFFFFFFFFFC000000000000000000000001FFFFFFFFFFFFFFFF) |
            (newLimit_.toBigNumber(DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN) <<
                DexSlotsLink.BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT) | // converted to BigNumber can not overflow
            (block.timestamp << DexSlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP);

        emit LogUpdateUserWithdrawalLimit(user_, newLimit_);
    }

    function updateUserBorrowConfigs(UserBorrowConfig[] memory userBorrowConfigs_) external _check _onlyDelegateCall {
        uint256 userBorrowData_;

        for (uint256 i; i < userBorrowConfigs_.length; ) {
            _checkIsContract(userBorrowConfigs_[i].user);
            if (
                // max debt ceiling must not be smaller than base debt ceiling. Also covers case where max = 0 but base > 0
                userBorrowConfigs_[i].baseDebtCeiling > userBorrowConfigs_[i].maxDebtCeiling ||
                // can not set expand duration to 0 as that could cause a division by 0 in LiquidityCalcs.
                // having expand duration as 0 is anyway not an expected config so removing the possibility for that.
                // if no expansion is wanted, simply set expandDuration to 1 and expandPercent to 0.
                userBorrowConfigs_[i].expandDuration == 0
            ) {
                revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
            }
            if (userBorrowConfigs_[i].expandPercent > X14) {
                // expandPercent is max 14 bits
                revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
            }
            if (userBorrowConfigs_[i].expandDuration > X24) {
                // duration is max 24 bits
                revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
            }
            if (userBorrowConfigs_[i].baseDebtCeiling == 0 || userBorrowConfigs_[i].maxDebtCeiling == 0) {
                // limits can not be 0. As a side effect, this ensures that there is no borrow config
                // where all values would be 0, so configured users can be differentiated in the mapping.
                revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
            }
            // @dev baseDebtCeiling & maxDebtCeiling have no max bits amount as they are in normal token amount
            // and then converted to BigNumber

            // get current user config data from storage
            userBorrowData_ = _userBorrowData[userBorrowConfigs_[i].user];

            // Updating user data on storage

            _userBorrowData[userBorrowConfigs_[i].user] =
                // mask to update first bit (mode) + bits 162-235 (debt limit values)
                (userBorrowData_ & 0xfffff0000000000000000003ffffffffffffffffffffffffffffffffffffffff) |
                (1) |
                (userBorrowConfigs_[i].expandPercent << DexSlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) |
                (userBorrowConfigs_[i].expandDuration << DexSlotsLink.BITS_USER_BORROW_EXPAND_DURATION) |
                // convert base debt limit to BigNumber for storage (10 | 8). (borrow is always possible below this)
                (userBorrowConfigs_[i].baseDebtCeiling.toBigNumber(
                    SMALL_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_DOWN
                ) << DexSlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) |
                // convert max debt limit to BigNumber for storage (10 | 8). (no borrowing ever possible above this)
                (userBorrowConfigs_[i].maxDebtCeiling.toBigNumber(
                    SMALL_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_DOWN
                ) << DexSlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT);

            unchecked {
                ++i;
            }
        }

        emit LogUpdateUserBorrowConfigs(userBorrowConfigs_);
    }

    function pauseUser(address user_, bool pauseSupply_, bool pauseBorrow_) public _onlyDelegateCall {
        _checkIsContract(user_);

        uint256 userData_;

        if (pauseSupply_) {
            // userData_ => userSupplyData_
            userData_ = _userSupplyData[user_];
            if (userData_ == 0) {
                revert FluidDexError(ErrorTypes.DexT1Admin__UserNotDefined);
            }
            if (userData_ & 1 == 0) {
                revert FluidDexError(ErrorTypes.DexT1Admin__InvalidPauseToggle);
            }
            // set first bit as 0, meaning all user's supply operations are paused
            _userSupplyData[user_] = userData_ & (~uint(1));
        }

        if (pauseBorrow_) {
            // userData_ => userBorrowData_
            userData_ = _userBorrowData[user_];
            if (userData_ == 0) {
                revert FluidDexError(ErrorTypes.DexT1Admin__UserNotDefined);
            }
            if (userData_ & 1 == 0) {
                revert FluidDexError(ErrorTypes.DexT1Admin__InvalidPauseToggle);
            }
            // set first bit as 0, meaning all user's borrow operations are paused
            _userBorrowData[user_] = userData_ & (~uint(1));
        }

        emit LogPauseUser(user_, pauseSupply_, pauseBorrow_);
    }

    function unpauseUser(address user_, bool unpauseSupply_, bool unpauseBorrow_) public _onlyDelegateCall {
        _checkIsContract(user_);

        uint256 userData_;

        if (unpauseSupply_) {
            // userData_ => userSupplyData_
            userData_ = _userSupplyData[user_];
            if (userData_ == 0) {
                revert FluidDexError(ErrorTypes.DexT1Admin__UserNotDefined);
            }
            if (userData_ & 1 == 1) {
                revert FluidDexError(ErrorTypes.DexT1Admin__InvalidPauseToggle);
            }

            // set first bit as 1, meaning unpause
            _userSupplyData[user_] = userData_ | 1;
        }

        if (unpauseBorrow_) {
            // userData_ => userBorrowData_
            userData_ = _userBorrowData[user_];
            if (userData_ == 0) {
                revert FluidDexError(ErrorTypes.DexT1Admin__UserNotDefined);
            }
            if (userData_ & 1 == 1) {
                revert FluidDexError(ErrorTypes.DexT1Admin__InvalidPauseToggle);
            }

            // set first bit as 1, meaning unpause
            _userBorrowData[user_] = userData_ | 1;
        }

        emit LogUnpauseUser(user_, unpauseSupply_, unpauseBorrow_);
    }

    /// note we have not added updateUtilizationLimit in the params here because struct of InitializeVariables already has 16 variables
    /// we might skip adding it and let it update through the indepdent function to keep initialize struct simple
    function initialize(InitializeVariables memory i_) public payable _onlyDelegateCall {
        _checkIsContract(TEAM_MULTISIG);

        if (!(i_.smartCol || i_.smartDebt)) {
            // either 1 should be on upon pool initialization
            revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }
        // cut is an integer in storage slot which is more than enough
        // but from UI we are allowing to send in 4 decimals to maintain consistency & avoid human error in future
        if (i_.revenueCut != 0 && i_.revenueCut < FOUR_DECIMALS) {
            // human input error. should send 0 for wanting 0, not 0 because of precision reduction.
            revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }

        // revenue cut has no decimals
        i_.revenueCut = i_.revenueCut / FOUR_DECIMALS;
        i_.upperShiftThreshold = i_.upperShiftThreshold / THREE_DECIMALS;
        i_.lowerShiftThreshold = i_.lowerShiftThreshold / THREE_DECIMALS;

        if (
            (i_.fee > FIVE_DECIMALS) || // fee cannot be more than 10%
            (i_.revenueCut > TWO_DECIMALS) ||
            (i_.upperPercent > (SIX_DECIMALS - FOUR_DECIMALS)) || // capping range to 99%.
            (i_.lowerPercent > (SIX_DECIMALS - FOUR_DECIMALS)) || // capping range to 99%.
            (i_.upperPercent == 0) ||
            (i_.lowerPercent == 0) ||
            (i_.upperShiftThreshold > THREE_DECIMALS) ||
            (i_.lowerShiftThreshold > THREE_DECIMALS) ||
            ((i_.upperShiftThreshold == 0) && (i_.lowerShiftThreshold > 0)) ||
            ((i_.upperShiftThreshold > 0) && (i_.lowerShiftThreshold == 0)) ||
            (i_.thresholdShiftTime == 0) ||
            (i_.thresholdShiftTime > X24) ||
            (i_.centerPriceAddress > X30) ||
            (i_.hookAddress > X30) ||
            (i_.centerPrice <= i_.minCenterPrice) ||
            (i_.centerPrice >= i_.maxCenterPrice) ||
            (i_.minCenterPrice == 0)
        ) {
            revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }

        uint dexVariables2_;

        if (i_.smartCol) {
            _turnOnSmartCol(i_.token0ColAmt, i_.centerPrice);
            dexVariables2_ = dexVariables2_ | 1;
        }

        if (i_.smartDebt) {
            _turnOnSmartDebt(i_.token0DebtAmt, i_.centerPrice);
            dexVariables2_ = dexVariables2_ | 2;
        }

        i_.centerPrice = i_.centerPrice.toBigNumber(32, 8, BigMathMinified.ROUND_DOWN);
        // setting up initial dexVariables
        dexVariables =
            (i_.centerPrice << 1) |
            (i_.centerPrice << 41) |
            (i_.centerPrice << 81) |
            (block.timestamp << 121) |
            (60 << 154) | // just setting 60 seconds, no particular reason for it why "60"
            (7 << 176);

        dexVariables2 =
            dexVariables2_ |
            (i_.fee << 2) |
            (i_.revenueCut << 19) |
            (i_.upperPercent << 27) |
            (i_.lowerPercent << 47) |
            (i_.upperShiftThreshold << 68) |
            (i_.lowerShiftThreshold << 78) |
            (i_.thresholdShiftTime << 88) |
            (i_.centerPriceAddress << 112) |
            (i_.hookAddress << 142) |
            (i_.maxCenterPrice.toBigNumber(20, 8, BigMathMinified.ROUND_UP) << 172) |
            (i_.minCenterPrice.toBigNumber(20, 8, BigMathMinified.ROUND_DOWN) << 200) |
            (THREE_DECIMALS << 228) | // setting initial token0 max utilization to 100%
            (THREE_DECIMALS << 238); // setting initial token1 max utilization to 100%

        emit LogInitializePoolConfig(
            i_.smartCol,
            i_.smartDebt,
            i_.token0ColAmt,
            i_.token0DebtAmt,
            i_.fee,
            i_.revenueCut * FOUR_DECIMALS,
            i_.centerPriceAddress,
            i_.hookAddress
        );

        emit LogInitializePriceParams(
            i_.upperPercent,
            i_.lowerPercent,
            i_.upperShiftThreshold * THREE_DECIMALS,
            i_.lowerShiftThreshold * THREE_DECIMALS,
            i_.thresholdShiftTime,
            i_.maxCenterPrice,
            i_.minCenterPrice
        );
    }

    function pauseSwapAndArbitrage() public _onlyDelegateCall {
        uint dexVariables2_ = dexVariables2;
        if ((dexVariables2_ >> 255) == 1) {
            // already paused
            revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }
        dexVariables2 = dexVariables2_ | (uint(1) << 255);

        emit LogPauseSwapAndArbitrage();
    }

    function unpauseSwapAndArbitrage() public _onlyDelegateCall {
        uint dexVariables2_ = dexVariables2;
        if ((dexVariables2_ >> 255) == 0) {
            // already unpaused
            revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }
        dexVariables2 = (dexVariables2_ << 1) >> 1;

        emit LogUnpauseSwapAndArbitrage();
    }

    /// @notice sends any potentially stuck funds to Liquidity contract.
    /// @dev this contract never holds any funds as all operations send / receive funds from user <-> Liquidity.
    function rescueFunds(address token_) external _onlyDelegateCall {
        address liquidity_ = IFluidDexT1(address(this)).constantsView().liquidity;
        if (token_ == NATIVE_TOKEN) {
            SafeTransfer.safeTransferNative(liquidity_, address(this).balance);
        } else {
            SafeTransfer.safeTransfer(token_, liquidity_, IERC20(token_).balanceOf(address(this)));
        }

        emit LogRescueFunds(token_);
    }

    function updateMaxSupplyShares(uint maxSupplyShares_) external _onlyDelegateCall {
        uint totalSupplyShares_ = _totalSupplyShares;

        // totalSupplyShares_ can only be 0 when smart col pool is not initialized
        if ((maxSupplyShares_ > X128) || (totalSupplyShares_ == 0)) {
            revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }
        _totalSupplyShares = (totalSupplyShares_ & X128) | (maxSupplyShares_ << 128);

        emit LogUpdateMaxSupplyShares(maxSupplyShares_);
    }

    function updateMaxBorrowShares(uint maxBorrowShares_) external _onlyDelegateCall {
        uint totalBorrowShares_ = _totalBorrowShares;

        // totalBorrowShares_ can only be 0 when smart debt pool is not initialized
        if ((maxBorrowShares_ > X128) || (totalBorrowShares_ == 0)) {
            revert FluidDexError(ErrorTypes.DexT1Admin__ConfigOverflow);
        }
        _totalBorrowShares = (totalBorrowShares_ & X128) | (maxBorrowShares_ << 128);

        emit LogUpdateMaxBorrowShares(maxBorrowShares_);
    }

    /// @notice Toggles the oracle activation
    /// @param turnOn_ Whether to turn on or off the oracle
    function toggleOracleActivation(bool turnOn_) external _onlyDelegateCall {
        uint dexVariables_ = dexVariables;
        if ((((dexVariables_ >> 195) & 1 == 1) && turnOn_) || (((dexVariables_ >> 195) & 1 == 0) && !turnOn_)) {
            // already active
            revert FluidDexError(ErrorTypes.DexT1Admin__InvalidParams);
        }
        if (turnOn_) {
            dexVariables = dexVariables_ | (uint(1) << 195);
        } else {
            dexVariables = dexVariables_ & (~(uint(1) << 195));
        }

        emit LogToggleOracleActivation(turnOn_);
    }
}
