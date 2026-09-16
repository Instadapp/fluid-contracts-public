// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IAllowanceTransfer } from "../interfaces/permit2/iAllowanceTransfer.sol";
import { IFluidLendingRewardsRateModel } from "../interfaces/iLendingRewardsRateModel.sol";
import { IFluidLendingStaticRateModel } from "../interfaces/iLendingStaticRateModel.sol";
import { IFluidLendingFactory } from "../interfaces/iLendingFactory.sol";
import { IFTokenAdmin } from "../interfaces/iFToken.sol";
import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { SafeTransfer } from "../../../libraries/safeTransfer.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { Variables } from "./variables.sol";
import { Events } from "./events.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";

/// @dev ReentrancyGuard based on OpenZeppelin implementation.
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.8/contracts/security/ReentrancyGuard.sol
abstract contract ReentrancyGuard is Error, Variables {
    uint8 internal constant REENTRANCY_NOT_ENTERED = 1;
    uint8 internal constant REENTRANCY_ENTERED = 2;

    constructor() {
        _status = REENTRANCY_NOT_ENTERED;
    }

    /// @dev checks that no reentrancy occurs, reverts if so. Calling the method in the modifier reduces
    /// bytecode size as modifiers are inlined into bytecode
    function _checkReentrancy() internal {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status != REENTRANCY_NOT_ENTERED) {
            revert FluidLendingError(ErrorTypes.fToken__Reentrancy);
        }

        // Any calls to nonReentrant after this point will fail
        _status = REENTRANCY_ENTERED;
    }

    /// @dev Prevents a contract from calling itself, directly or indirectly.
    /// See OpenZeppelin implementation for more info
    modifier nonReentrant() {
        _checkReentrancy();

        _;

        // storing original value triggers a refund (see https://eips.ethereum.org/EIPS/eip-2200)
        _status = REENTRANCY_NOT_ENTERED;
    }
}

/// @dev internal methods for fToken contracts
abstract contract fTokenCore is Error, Variables, Events, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    /// @dev Gets current (updated) Liquidity supply exchange price for the underyling asset
    function _getLiquidityExchangePrice() internal view virtual returns (uint256 supplyExchangePrice_) {
        (supplyExchangePrice_, ) = LiquidityCalcs.calcExchangePrices(
            _liquidity().readFromStorage(_liquidityExchangePricesSlot())
        );
    }

    /// @dev initializes the fToken exchange-price state; shared by the constructor and beacon-proxy `initialize()`.
    function _initializeFTokenState() internal {
        // set initial values for _liquidityExchangePrice, _tokenExchangePrice and _lastUpdateTimestamp
        _liquidityExchangePrice = uint64(_getLiquidityExchangePrice());
        _tokenExchangePrice = uint64(EXCHANGE_PRICES_PRECISION);
        _lastUpdateTimestamp = uint40(block.timestamp);
    }

    /// @dev Gets current Liquidity supply balance of `address(this)` for the underyling asset
    function _getLiquidityBalance() internal view virtual returns (uint256 balance_) {
        // extract user supply amount
        uint256 userSupplyRaw_ = BigMathMinified.fromBigNumber(
            (_liquidity().readFromStorage(_liquidityUserSupplySlot()) >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) &
                LiquidityCalcs.X64,
            LiquidityCalcs.DEFAULT_EXPONENT_SIZE,
            LiquidityCalcs.DEFAULT_EXPONENT_MASK
        );

        unchecked {
            // can not overflow as userSupplyRaw_ can be maximally type(int128).max, liquidity exchange price type(uint64).max
            return (userSupplyRaw_ * _getLiquidityExchangePrice()) / EXCHANGE_PRICES_PRECISION;
        }
    }

    /// @dev Gets current Liquidity underlying token balance
    function _getLiquidityUnderlyingBalance() internal view virtual returns (uint256) {
        return _asset().balanceOf(address(_liquidity()));
    }

    /// @dev Gets current withdrawable amount at Liquidity `withdrawalLimit_` (withdrawal limit or balance).
    function _getLiquidityWithdrawable() internal view virtual returns (uint256 withdrawalLimit_) {
        uint256 userSupplyData_ = _liquidity().readFromStorage(_liquidityUserSupplySlot());
        uint256 userSupply_ = BigMathMinified.fromBigNumber(
            (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & LiquidityCalcs.X64,
            LiquidityCalcs.DEFAULT_EXPONENT_SIZE,
            LiquidityCalcs.DEFAULT_EXPONENT_MASK
        );
        withdrawalLimit_ = LiquidityCalcs.calcWithdrawalLimitBeforeOperate(userSupplyData_, userSupply_);

        // convert raw amounts to normal amounts
        unchecked {
            // can not overflow as userSupply_ can be maximally type(int128).max
            // and withdrawalLimit is smaller than userSupply_
            uint256 liquidityExchangePrice_ = _getLiquidityExchangePrice();
            withdrawalLimit_ = (withdrawalLimit_ * liquidityExchangePrice_) / EXCHANGE_PRICES_PRECISION;
            userSupply_ = (userSupply_ * liquidityExchangePrice_) / EXCHANGE_PRICES_PRECISION;
        }

        withdrawalLimit_ = userSupply_ > withdrawalLimit_ ? userSupply_ - withdrawalLimit_ : 0;

        uint256 balanceAtLiquidity_ = _getLiquidityUnderlyingBalance();

        return balanceAtLiquidity_ > withdrawalLimit_ ? withdrawalLimit_ : balanceAtLiquidity_;
    }

    /// @dev Calculates new token exchange price based on the current liquidity exchange price `newLiquidityExchangePrice_` and rewards rate.
    /// @param newLiquidityExchangePrice_ new (current) liquidity exchange price
    function _calculateNewTokenExchangePrice(
        uint256 newLiquidityExchangePrice_
    ) internal view returns (uint256 newTokenExchangePrice_, bool rewardsEnded_) {
        uint256 oldTokenExchangePrice_ = _tokenExchangePrice;
        uint256 oldLiquidityExchangePrice_ = _liquidityExchangePrice;

        if (newLiquidityExchangePrice_ < oldLiquidityExchangePrice_) {
            // liquidity exchange price should only ever increase. If not, something went wrong and avoid
            // proceeding with unknown outcome.
            revert FluidLendingError(ErrorTypes.fToken__LiquidityExchangePriceUnexpected);
        }

        // signed: streaming APR is >= 0; static model may return a negative Liquidity offset.
        int256 totalReturnInPercent_; // rewardsRateInPercent + liquidityReturnInPercent
        if (_rewardsActive) {
            {
                // get rewards rate per year
                // only trigger call to rewardsRateModel if rewards are actually active to save gas
                int256 rewardsRate_;
                uint256 rewardsStartTime_;
                uint256 rewardsEndTime_;
                try
                    // both streaming and static rate models implement signed `getRateV2`. the static model ignores
                    // the total assets input, so only calculate it (from old tokenExchangeRate) when needed to save gas.
                    _rewardsRateModel.getRateV2(
                        _staticRateModelActive
                            ? 0
                            : (oldTokenExchangePrice_ * totalSupply()) / EXCHANGE_PRICES_PRECISION
                    )
                returns (int256 rate_, bool ended_, uint256 startTime_, uint256 endTime_) {
                    (rewardsRate_, rewardsEnded_, rewardsStartTime_, rewardsEndTime_) = (
                        rate_,
                        ended_,
                        startTime_,
                        endTime_
                    );
                } catch {
                    // a reverting (broken / miswired) rate model is treated as ended with endTime 0: rewards are
                    // skipped, only liquidity yield applies and governance can always re-wire or unset the model.
                    rewardsEnded_ = true;
                }
                if (rewardsRate_ > int256(MAX_REWARDS_RATE) || rewardsRate_ < -int256(MAX_REWARDS_RATE)) {
                    // capped at ±MAX_REWARDS_RATE; outside that → treat as misconfigured → 0.
                    rewardsRate_ = 0;
                }

                // when rewards have ended, accrue exactly up to the rewards end time instead of losing the tail
                // since the last exchange price update (or overpaying beyond the end time).
                uint256 rewardsAccrueUntil_ = (rewardsEnded_ && rewardsEndTime_ < block.timestamp)
                    ? rewardsEndTime_
                    : block.timestamp;

                uint256 lastUpdateTimestamp_ = _lastUpdateTimestamp;
                if (lastUpdateTimestamp_ < rewardsStartTime_) {
                    // if last update was before the rewards started, make sure rewards actually only accrue
                    // from the actual rewards start time, not from the last update timestamp to avoid overpayment.
                    lastUpdateTimestamp_ = rewardsStartTime_;
                }

                if (rewardsAccrueUntil_ > lastUpdateTimestamp_) {
                    // calculate rewards return in percent: (rewards_rate * time passed) / seconds_in_a_year.
                    unchecked {
                        // rewardsRate * timeElapsed / SECONDS_PER_YEAR.
                        // no overflow: |rewardsRate_| <= MAX_REWARDS_RATE (50e12), timeElapsed bounded;
                        // max |product| ~ 50e12 * 8589934591 / 31536000 ≈ 1.36e16, well within int256.
                        totalReturnInPercent_ =
                            (rewardsRate_ * int256(rewardsAccrueUntil_ - lastUpdateTimestamp_)) /
                            int256(SECONDS_PER_YEAR);
                    }
                }
            }
        }

        // Liquidity yield always compounds (streaming and static). Static adds a signed offset on top;
        // inventory vs EP gap is settled via bidirectional `rebalance()`.
        unchecked {
            // calculate liquidityReturnInPercent: (newLiquidityExchangePrice_ - oldLiquidityExchangePrice_) / oldLiquidityExchangePrice_.
            // and add it to totalReturnInPercent_ that already holds rewardsRateInPercent_.
            // oldLiquidityExchangePrice_ can not be 0, minimal value is 1e12. subtraction can not underflow because
            // new exchange price can only be >= oldLiquidityExchangePrice_.
            totalReturnInPercent_ += int256(
                ((newLiquidityExchangePrice_ - oldLiquidityExchangePrice_) * 1e14) / oldLiquidityExchangePrice_
            );
        }

        // Negative static offset can only cancel Liquidity yield for this window, never decrease the share EP.
        if (totalReturnInPercent_ < 0) {
            totalReturnInPercent_ = 0;
        }

        // newTokenExchangePrice_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_
        newTokenExchangePrice_ =
            oldTokenExchangePrice_ +
            ((oldTokenExchangePrice_ * uint256(totalReturnInPercent_)) / 1e14); // divided by 100% (1e14)
    }

    /// @dev calculates new exchange prices, updates values in storage and returns new tokenExchangePrice (with reward rates)
    function _updateRates(
        uint256 liquidityExchangePrice_,
        bool forceUpdateStorage_
    ) internal returns (uint256 tokenExchangePrice_) {
        bool rewardsEnded_;
        (tokenExchangePrice_, rewardsEnded_) = _calculateNewTokenExchangePrice(liquidityExchangePrice_);
        if (_rewardsActive || forceUpdateStorage_) {
            // Solidity will NOT cause a revert if values are too big to fit max uint type size. Explicitly check before
            // writing to storage. Also see https://github.com/ethereum/solidity/issues/10195.
            if (tokenExchangePrice_ > type(uint64).max) {
                revert FluidLendingError(ErrorTypes.fToken__ExchangePriceOverflow);
            }

            _tokenExchangePrice = uint64(tokenExchangePrice_);
            _liquidityExchangePrice = uint64(liquidityExchangePrice_);
            _lastUpdateTimestamp = uint40(block.timestamp);

            emit LogUpdateRates(tokenExchangePrice_, liquidityExchangePrice_);
        }

        if (rewardsEnded_) {
            // set rewardsActive flag to false to save gas for all future exchange prices calculations,
            // without having to explicitly require setting `updateRewards` to address zero.
            // Note rewardsEnded_ can only be true when _rewardsActive is true (model is only called then),
            // so the exchange prices including the rewards tail accrued exactly until the rewards end time
            // have been written to storage above before _rewardsActive is set to false here.
            _rewardsActive = false;
        }

        return tokenExchangePrice_;
    }

    /// @dev splits a bytes signature `sig` into `v`, `r`, `s`.
    /// Taken from https://docs.soliditylang.org/en/v0.8.17/solidity-by-example.html
    function _splitSignature(bytes memory sig) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65);

        assembly {
            // first 32 bytes, after the length prefix.
            r := mload(add(sig, 32))
            // second 32 bytes.
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes).
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    /// @dev Deposit `assets_` amount of tokens to Liquidity
    /// @param assets_ The amount of tokens to deposit
    /// @param liquidityCallbackData_ callback data passed to Liquidity for `liquidityCallback`
    /// @return exchangePrice_ liquidity exchange price for token
    function _depositToLiquidity(
        uint256 assets_,
        bytes memory liquidityCallbackData_
    ) internal virtual returns (uint256 exchangePrice_) {
        // @dev Note: Although there might be some small difference between the `assets_` amount and the actual amount
        // accredited at Liquidity due to BigMath rounding down, this amount is so small that it can be ignored.
        // because of BigMath precision of 7.2057594e16 for a coefficient size of 56, it would require >72 trillion DAI
        // to "benefit" 1 DAI in additional shares minted. Considering gas cost + APR per second, this ensures such
        // a manipulation attempt becomes extremely unlikely.

        // send funds to Liquidity protocol to generate yield
        (exchangePrice_, ) = _liquidity().operate(
            address(_asset()),
            SafeCast.toInt256(assets_),
            0,
            address(0),
            address(0),
            liquidityCallbackData_ // callback data. -> "from" for transferFrom in `liquidityCallback`
        );
    }

    /// @dev Withdraw `assets_` amount of tokens from Liquidity directly to `receiver_`
    /// @param assets_    The amount of tokens to withdraw
    /// @param receiver_  the receiver address of withdraw amount
    /// @return exchangePrice_   liquidity exchange price for token
    function _withdrawFromLiquidity(
        uint256 assets_,
        address receiver_
    ) internal virtual returns (uint256 exchangePrice_) {
        // @dev See similar comment in `_depositToLiquidity()` regarding burning a tiny bit of additional shares here
        // because of inaccuracies in Liquidity userSupply BigMath being rounded down.

        // get funds back from Liquidity protocol to send to the user
        (exchangePrice_, ) = _liquidity().operate(
            address(_asset()),
            -SafeCast.toInt256(assets_),
            0,
            receiver_,
            address(0),
            new bytes(0) // callback data -> withdraw doesn't trigger a callback
        );
    }

    /// @dev deposits `assets_` into liquidity and mints shares for `receiver_`. Returns amount of `sharesMinted_`.
    function _executeDeposit(
        uint256 assets_,
        address receiver_,
        bytes memory liquidityCallbackData_
    ) internal virtual validAddress(receiver_) returns (uint256 sharesMinted_) {
        // send funds to Liquidity protocol to generate yield -> returns updated liquidityExchangePrice
        uint256 tokenExchangePrice_ = _depositToLiquidity(assets_, liquidityCallbackData_);

        // update the exchange prices
        tokenExchangePrice_ = _updateRates(tokenExchangePrice_, false);

        // calculate the shares to mint
        // not using previewDeposit here because we just got newTokenExchangePrice_
        sharesMinted_ = (assets_ * EXCHANGE_PRICES_PRECISION) / tokenExchangePrice_;

        if (sharesMinted_ == 0) {
            revert FluidLendingError(ErrorTypes.fToken__DepositInsignificant);
        }

        _mint(receiver_, sharesMinted_);

        emit Deposit(msg.sender, receiver_, assets_, sharesMinted_);
    }

    /// @dev withdraws `assets_` from liquidity to `receiver_` and burns shares from `owner_`.
    /// Returns amount of `sharesBurned_`.
    /// requires nonReentrant! modifier on calling method otherwise ERC777s could reenter!
    function _executeWithdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) internal virtual validAddress(receiver_) returns (uint256 sharesBurned_) {
        // burn shares for assets_ amount: assets_ * EXCHANGE_PRICES_PRECISION / updatedTokenTexchangePrice. Rounded up.
        // Note to be extra safe we do the shares burn before the withdrawFromLiquidity, even though that would return the
        // updated liquidityExchangePrice and thus save gas.
        sharesBurned_ = assets_.mulDivUp(EXCHANGE_PRICES_PRECISION, _updateRates(_getLiquidityExchangePrice(), false));

        /*
            The `mulDivUp` function is designed to round up the result of multiplication followed by division. 
            Given non-zero `assets_` and the rounding-up behavior of this function, `sharesBurned_` will always 
            be at least 1 if there's any remainder in the division.
            Thus, if `assets_` is non-zero, `sharesBurned_` can never be 0. The nature of the function ensures 
            that even the smallest fractional result (greater than 0) will be rounded up to 1. Hence, there's no need 
            to check for a rounding error that results in 0.
            Furthermore, if `assets_` was 0, an error 'UserModule__OperateAmountsZero' would already have been thrown 
            during the `operate` function, ensuring the contract never reaches this point with a zero `assets_` value.
            Note: If ever the logic or the function behavior changes in the future, this assertion may need to be reconsidered.
        */

        _burn(owner_, sharesBurned_);

        // withdraw from liquidity directly to _receiver.
        _withdrawFromLiquidity(assets_, receiver_);

        emit Withdraw(msg.sender, receiver_, owner_, assets_, sharesBurned_);
    }
}

/// @notice fToken view methods. Implements view methods for ERC4626 compatibility
abstract contract fTokenViews is fTokenCore {
    using FixedPointMathLib for uint256;

    /// @notice Returns key fToken config and current exchange data.
    function getData()
        public
        view
        returns (
            IFluidLiquidity liquidity_,
            IFluidLendingFactory lendingFactory_,
            IFluidLendingRewardsRateModel lendingRewardsRateModel_,
            IAllowanceTransfer permit2_,
            address rebalancer_,
            bool rewardsActive_,
            uint256 liquidityBalance_,
            uint256 liquidityExchangePrice_,
            uint256 tokenExchangePrice_
        )
    {
        liquidityExchangePrice_ = _getLiquidityExchangePrice();

        bool rewardsEnded_;
        (tokenExchangePrice_, rewardsEnded_) = _calculateNewTokenExchangePrice(liquidityExchangePrice_);

        return (
            _liquidity(),
            _lendingFactory(),
            _rewardsRateModel,
            PERMIT2,
            _rebalancer,
            _rewardsActive && !rewardsEnded_,
            _getLiquidityBalance(),
            liquidityExchangePrice_,
            tokenExchangePrice_
        );
    }

    /// @notice Returns the underlying asset address.
    function asset() public view virtual returns (address) {
        return address(_asset());
    }

    /// @notice Returns total managed underlying assets.
    function totalAssets() public view virtual returns (uint256) {
        (uint256 tokenExchangePrice_, ) = _calculateNewTokenExchangePrice(_getLiquidityExchangePrice());
        return
            // all the underlying tokens are stored in Liquidity contract at all times
            (tokenExchangePrice_ * totalSupply()) / EXCHANGE_PRICES_PRECISION;
    }

    /// @notice Converts assets to shares at the current exchange price.
    function convertToShares(uint256 assets_) public view virtual returns (uint256) {
        (uint256 tokenExchangePrice_, ) = _calculateNewTokenExchangePrice(_getLiquidityExchangePrice());
        return assets_.mulDivDown(EXCHANGE_PRICES_PRECISION, tokenExchangePrice_);
    }

    /// @notice Converts shares to assets at the current exchange price.
    function convertToAssets(uint256 shares_) public view virtual returns (uint256) {
        (uint256 tokenExchangePrice_, ) = _calculateNewTokenExchangePrice(_getLiquidityExchangePrice());
        return shares_.mulDivDown(tokenExchangePrice_, EXCHANGE_PRICES_PRECISION);
    }

    /// @notice Previews shares minted for assets; execution may differ slightly.
    function previewDeposit(uint256 assets_) public view virtual returns (uint256) {
        return convertToShares(assets_);
    }

    /// @notice Previews assets needed to mint shares.
    function previewMint(uint256 shares_) public view virtual returns (uint256) {
        (uint256 tokenExchangePrice_, ) = _calculateNewTokenExchangePrice(_getLiquidityExchangePrice());
        return shares_.mulDivUp(tokenExchangePrice_, EXCHANGE_PRICES_PRECISION);
    }

    /// @notice Previews shares burned for withdrawing assets.
    function previewWithdraw(uint256 assets_) public view virtual returns (uint256) {
        (uint256 tokenExchangePrice_, ) = _calculateNewTokenExchangePrice(_getLiquidityExchangePrice());
        return assets_.mulDivUp(EXCHANGE_PRICES_PRECISION, tokenExchangePrice_);
    }

    /// @notice Previews assets returned for shares; execution may differ slightly.
    function previewRedeem(uint256 shares_) public view virtual returns (uint256) {
        return convertToAssets(shares_);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns max depositable assets.
    function maxDeposit(address) public view virtual returns (uint256) {
        // read total supplyInterest_ for the token at Liquidity and convert from BigMath
        uint256 supplyInterest_ = _liquidity().readFromStorage(_liquidityTotalAmountsSlot()) & LiquidityCalcs.X64;
        supplyInterest_ =
            (supplyInterest_ >> LiquidityCalcs.DEFAULT_EXPONENT_SIZE) <<
            (supplyInterest_ & LiquidityCalcs.DEFAULT_EXPONENT_MASK);

        unchecked {
            // normalize from raw
            supplyInterest_ = (supplyInterest_ * _getLiquidityExchangePrice()) / EXCHANGE_PRICES_PRECISION;
            // compare against hardcoded max possible value for total supply considering BigMath rounding down:
            // type(int128).max) after BigMath rounding (first 56 bits precision, then 71 bits getting set to 0)
            // so 1111111111111111111111111111111111111111111111111111111100000000000000000000000000000000000000000000000000000000000000000000000
            // = 170141183460469229370504062281061498880. using minus 1
            if (supplyInterest_ > 170141183460469229370504062281061498879) {
                return 0;
            }
            // type(int128).max is the maximum interactable amount at Liquidity. But also total token amounts
            // must not overflow type(int128).max, so max depositable is type(int128).max - totalSupply.
            return uint256(uint128(type(int128).max)) - supplyInterest_;
        }
    }

    /// @notice Returns max mintable shares.
    function maxMint(address) public view virtual returns (uint256) {
        return convertToShares(maxDeposit(address(0)));
    }

    /// @notice Returns max withdrawable assets for an owner.
    function maxWithdraw(address owner_) public view virtual returns (uint256) {
        uint256 maxWithdrawableAtLiquidity_ = _getLiquidityWithdrawable();
        uint256 ownerBalance_ = convertToAssets(balanceOf(owner_));
        return maxWithdrawableAtLiquidity_ < ownerBalance_ ? maxWithdrawableAtLiquidity_ : ownerBalance_;
    }

    /// @notice Returns max redeemable shares for an owner.
    function maxRedeem(address owner_) public view virtual returns (uint256) {
        uint256 maxWithdrawableAtLiquidity_ = convertToShares(_getLiquidityWithdrawable());
        uint256 ownerBalance_ = balanceOf(owner_);
        return maxWithdrawableAtLiquidity_ < ownerBalance_ ? maxWithdrawableAtLiquidity_ : ownerBalance_;
    }

    /// @notice Returns the minimum significant deposit amount.
    function minDeposit() public view virtual returns (uint256) {
        uint256 minBigMathRounding_ = 1 <<
            (_liquidity().readFromStorage(_liquidityTotalAmountsSlot()) & LiquidityCalcs.DEFAULT_EXPONENT_MASK); // 1 << total supply exponent
        uint256 previewMint_ = previewMint(1); // rounds up
        return minBigMathRounding_ > previewMint_ ? minBigMathRounding_ : previewMint_;
    }
}

/// @notice fToken admin related methods. fToken admins are Lending Factory auths. Possible actions are
/// updating rewards, funding rewards, and rescuing any stuck funds (fToken contract itself never holds any funds).
abstract contract fTokenAdmin is fTokenCore, fTokenViews, IFTokenAdmin {
    /// @dev checks if `msg.sender` is an allowed auth at LendingFactory. internal method instead of modifier
    ///      to reduce bytecode size.
    function _checkIsLendingFactoryAuth() internal view {
        if (!_lendingFactory().isAuth(msg.sender)) {
            revert FluidLendingError(ErrorTypes.fToken__Unauthorized);
        }
    }

    /// @dev LendingFactory auth, or wired `_rewardsRateModel` setting only itself / address(0).
    function _checkRewardsConfigAuth(address newModel_) internal view {
        if (_lendingFactory().isAuth(msg.sender)) {
            return;
        }
        if (msg.sender == address(_rewardsRateModel) && (newModel_ == msg.sender || newModel_ == address(0))) {
            return;
        }
        revert FluidLendingError(ErrorTypes.fToken__Unauthorized);
    }

    /// @inheritdoc IFTokenAdmin
    function updateRewards(IFluidLendingRewardsRateModel rewardsRateModel_) external {
        _checkRewardsConfigAuth(address(rewardsRateModel_));

        // @dev no check for address zero needed here, as that is actually explicitly checked where _rewardsRateModel
        // is used. In fact it is beneficial to set _rewardsRateModel to address zero when there are no rewards.

        // apply current rewards rate before updating to new one
        updateRates();

        _rewardsRateModel = rewardsRateModel_;

        // set flag _rewardsActive
        _rewardsActive = address(rewardsRateModel_) != address(0);
        _staticRateModelActive = false;

        emit LogUpdateRewards(rewardsRateModel_);
    }

    /// @inheritdoc IFTokenAdmin
    /// @dev Mirrors `updateRewards`: settles the current rate via `updateRates()` before re-wiring the model.
    ///      Re-enables `_rewardsActive` when re-wiring after a prior `rewardsEnded_` shutdown (same as
    ///      streaming `startRewards` calling `updateRewards`). Callable by LendingFactory auths **or** the
    ///      currently wired rate model (so `setStaticRate` does not require permanent factory auth).
    ///      Wired-model callers may only set themselves or `address(0)`.
    function updateStaticRewards(IFluidLendingStaticRateModel staticRateModel_) external {
        _checkRewardsConfigAuth(address(staticRateModel_));

        // apply current rewards rate before updating to new one
        updateRates();

        _rewardsRateModel = IFluidLendingRewardsRateModel(address(staticRateModel_));

        _staticRateModelActive = address(staticRateModel_) != address(0);
        _rewardsActive = address(staticRateModel_) != address(0);

        emit LogUpdateStaticRewards(staticRateModel_);
    }

    /// @notice Returns whether the wired rewards rate model is a static (TVL-independent) rate model.
    function isStaticRateModelActive() public view returns (bool) {
        return _staticRateModelActive;
    }

    /// @inheritdoc IFTokenAdmin
    function rebalance() external payable virtual nonReentrant returns (uint256 assets_) {
        if (msg.sender != _rebalancer) {
            revert FluidLendingError(ErrorTypes.fToken__NotRebalancer);
        }
        if (msg.value > 0) {
            revert FluidLendingError(ErrorTypes.fToken__NotNativeUnderlying);
        }

        uint256 totalAssets_ = totalAssets();
        uint256 liquidityBalance_ = _getLiquidityBalance();
        uint256 liquidityExchangePrice_ = _getLiquidityExchangePrice();

        // matching vault rebalance behavior: funds are pulled from / sent to the stored `_rebalancer`
        // address (same as msg.sender here given the access check above).
        // LogRebalance: +deposit (legacy positive amount), -withdraw (new fees path).
        int256 rebalanceAssets_;
        if (totalAssets_ > liquidityBalance_) {
            // rewards direction: top up Liquidity to match totalAssets(), pulling from the rebalancer
            assets_ = totalAssets_ - liquidityBalance_;
            liquidityExchangePrice_ = _depositToLiquidity(assets_, abi.encode(_rebalancer));
            rebalanceAssets_ = int256(assets_);
        } else if (liquidityBalance_ > totalAssets_) {
            // fees direction: withdraw excess Liquidity supply to the rebalancer
            assets_ = liquidityBalance_ - totalAssets_;
            liquidityExchangePrice_ = _withdrawFromLiquidity(assets_, _rebalancer);
            rebalanceAssets_ = -int256(assets_);
        }

        // update the exchange prices, always updating on storage
        _updateRates(liquidityExchangePrice_, true);

        // no shares are minted when funding fToken contract for rewards

        emit LogRebalance(rebalanceAssets_);
    }

    /// @inheritdoc IFTokenAdmin
    function updateRebalancer(address newRebalancer_) public validAddress(newRebalancer_) {
        _checkIsLendingFactoryAuth();

        _rebalancer = newRebalancer_;

        emit LogUpdateRebalancer(newRebalancer_);
    }

    /// @inheritdoc IFTokenAdmin
    function updateRates() public returns (uint256 tokenExchangePrice_, uint256 liquidityExchangePrice_) {
        liquidityExchangePrice_ = _getLiquidityExchangePrice();
        tokenExchangePrice_ = _updateRates(liquidityExchangePrice_, true);
    }

    /// @inheritdoc IFTokenAdmin
    //
    // @dev this contract never holds any funds:
    // -> deposited funds are directly sent to Liquidity.
    // -> rewards are also stored at Liquidity.
    function rescueFunds(address token_) external virtual nonReentrant {
        _checkIsLendingFactoryAuth();
        SafeTransfer.safeTransfer(address(token_), address(_liquidity()), IERC20(token_).balanceOf(address(this)));
        emit LogRescueFunds(token_);
    }
}

/// @notice fToken base: bundles the shared fToken state-changing/admin/view logic (`fTokenAdmin` -> `fTokenCore` +
/// `fTokenViews`) together with `decimals()` and `liquidityCallback()`.
/// @dev Intentionally excludes public user entrypoints (deposit / mint / withdraw / redeem and signature flows live in
///      `fTokenActions` & co) so beacon-proxy permissioned implementations can inherit audited logic without ungated
///      selectors.
abstract contract fTokenBase is fTokenAdmin {
    /// @inheritdoc IERC20Metadata
    function decimals() public view virtual override(ERC20) returns (uint8) {
        return _decimals();
    }

    /// @notice Handles Liquidity callback token pulls during deposits.
    function liquidityCallback(address token_, uint256 amount_, bytes calldata data_) external virtual {
        if (msg.sender != address(_liquidity()) || token_ != address(_asset()) || _status != REENTRANCY_ENTERED) {
            // caller must be liquidity, token must match, and reentrancy status must be REENTRANCY_ENTERED
            revert FluidLendingError(ErrorTypes.fToken__Unauthorized);
        }

        // callback data can be a) an address only b) an address + transfer via permit2 flag set to true
        // for a) length will be 32, for b) length is 64
        if (data_.length == 32) {
            address from_ = abi.decode(data_, (address));

            // transfer `amount_` from `from_` (original deposit msg.sender) to liquidity contract
            SafeTransfer.safeTransferFrom(address(_asset()), from_, address(_liquidity()), amount_);
        } else {
            (bool isPermit2_, address from_) = abi.decode(data_, (bool, address));
            if (!isPermit2_) {
                // unexepcted liquidity callback data
                revert FluidLendingError(ErrorTypes.fToken__InvalidParams);
            }

            // transfer `amount_` from `from_` (original deposit msg.sender) to liquidity contract via PERMIT2
            PERMIT2.transferFrom(from_, address(_liquidity()), uint160(amount_), address(_asset()));
        }
    }
}

/// @notice fToken shared action internals: deposit, mint, withdraw and redeem.
/// All production public actions and permissioned public actions reuse these helpers.
abstract contract fTokenActionsCore is fTokenBase {
    /// @dev reverts if `amount_` is < `minAmountOut_`. Used to reduce bytecode size.
    function _revertIfBelowMinAmountOut(uint256 amount_, uint256 minAmountOut_) internal pure {
        if (amount_ < minAmountOut_) {
            revert FluidLendingError(ErrorTypes.fToken__MinAmountOut);
        }
    }

    /// @dev reverts if `amount_` is > `maxAmount_`. Used to reduce bytecode size.
    function _revertIfAboveMaxAmount(uint256 amount_, uint256 maxAmount_) internal pure {
        if (amount_ > maxAmount_) {
            revert FluidLendingError(ErrorTypes.fToken__MaxAmount);
        }
    }

    function _deposit(uint256 assets_, address receiver_) internal returns (uint256 shares_) {
        if (assets_ == type(uint256).max) {
            assets_ = _asset().balanceOf(msg.sender);
        }

        // @dev transfer of tokens from `msg.sender` to liquidity contract happens via `liquidityCallback`
        shares_ = _executeDeposit(assets_, receiver_, abi.encode(msg.sender));
    }

    function _mintShares(uint256 shares_, address receiver_) internal returns (uint256 assets_) {
        if (shares_ == type(uint256).max) {
            assets_ = _asset().balanceOf(msg.sender);
        } else {
            // No need to check for rounding error, previewMint rounds up.
            assets_ = previewMint(shares_);
        }

        // @dev transfer of tokens from `msg.sender` to liquidity contract happens via `liquidityCallback`
        _executeDeposit(assets_, receiver_, abi.encode(msg.sender));
    }

    function _withdraw(uint256 assets_, address receiver_, address owner_) internal returns (uint256 shares_) {
        if (assets_ == type(uint256).max) {
            assets_ = previewRedeem(balanceOf(owner_));
        }
        shares_ = _executeWithdraw(assets_, receiver_, owner_);

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares_);
        }
    }

    function _redeemShares(uint256 shares_, address receiver_, address owner_) internal returns (uint256 assets_) {
        if (shares_ == type(uint256).max) {
            shares_ = balanceOf(owner_);
        }

        assets_ = previewRedeem(shares_);

        uint256 burnedShares_ = _executeWithdraw(assets_, receiver_, owner_);

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, burnedShares_);
        }
    }
}

/// @notice fToken public executable actions: deposit, mint, withdraw and redeem.
/// All actions are optionally also available with an additional param to limit the maximum slippage, e.g. maximum
/// assets used for minting x amount of shares.
abstract contract fTokenActions is fTokenActionsCore {
    /// @notice Deposits assets for receiver and mints shares.
    function deposit(uint256 assets_, address receiver_) public virtual nonReentrant returns (uint256 shares_) {
        return _deposit(assets_, receiver_);
    }

    /// @notice same as {fToken-deposit} but with an additional setting for minimum output amount.
    /// reverts with `fToken__MinAmountOut()` if `minAmountOut_` of shares is not reached
    function deposit(uint256 assets_, address receiver_, uint256 minAmountOut_) external returns (uint256 shares_) {
        shares_ = deposit(assets_, receiver_);
        _revertIfBelowMinAmountOut(shares_, minAmountOut_);
    }

    /// @notice Mints shares for receiver using underlying assets.
    function mint(uint256 shares_, address receiver_) public virtual nonReentrant returns (uint256 assets_) {
        return _mintShares(shares_, receiver_);
    }

    /// @notice same as {fToken-mint} but with an additional setting for maximum assets input amount.
    /// reverts with `fToken__MaxAmount()` if `maxAssets_` of assets is surpassed to mint `shares_`.
    function mint(uint256 shares_, address receiver_, uint256 maxAssets_) external returns (uint256 assets_) {
        assets_ = mint(shares_, receiver_);
        _revertIfAboveMaxAmount(assets_, maxAssets_);
    }

    /// @notice Withdraws assets to receiver and burns owner shares.
    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) public virtual nonReentrant returns (uint256 shares_) {
        return _withdraw(assets_, receiver_, owner_);
    }

    /// @notice same as {fToken-withdraw} but with an additional setting for maximum shares burned.
    /// reverts with `fToken__MaxAmount()` if `maxSharesBurn_` of shares burned is surpassed.
    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_,
        uint256 maxSharesBurn_
    ) external returns (uint256 shares_) {
        shares_ = withdraw(assets_, receiver_, owner_);
        _revertIfAboveMaxAmount(shares_, maxSharesBurn_);
    }

    /// @notice Redeems owner shares for assets to receiver.
    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) public virtual nonReentrant returns (uint256 assets_) {
        return _redeemShares(shares_, receiver_, owner_);
    }

    /// @notice same as {fToken-redeem} but with an additional setting for minimum output amount.
    /// reverts with `fToken__MinAmountOut()` if `minAmountOut_` of assets is not reached.
    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_,
        uint256 minAmountOut_
    ) external returns (uint256 assets_) {
        assets_ = redeem(shares_, receiver_, owner_);
        _revertIfBelowMinAmountOut(assets_, minAmountOut_);
    }
}

/// @notice fTokens support EIP-2612 permit approvals via signature so this contract implements
/// withdrawals (withdraw / redeem) with signature used for approval of the fToken shares.
abstract contract fTokenEIP2612Withdrawals is fTokenActions {
    /// @dev creates `sharesToPermit_` allowance for `owner_` via EIP2612 `deadline_` and `signature_`
    function _allowViaPermitEIP2612(
        address owner_,
        uint256 sharesToPermit_,
        uint256 deadline_,
        bytes calldata signature_
    ) internal {
        (uint8 v_, bytes32 r_, bytes32 s_) = _splitSignature(signature_);
        // spender = msg.sender
        permit(owner_, msg.sender, sharesToPermit_, deadline_, v_, r_, s_);
    }

    /// @notice withdraw amount of `assets_` with ERC-2612 permit signature for fToken approval.
    /// `owner_` signs ERC-2612 permit `signature_` to give allowance of fTokens to `msg.sender`.
    /// Note there might be tiny inaccuracies between requested `assets_` and actually received assets amount.
    /// allowance via signature (`sharesToPermit_`) should cover `previewWithdraw(assets_)` plus a little buffer to avoid revert.
    /// Inherent trust assumption that `msg.sender` will set `receiver_` and `maxSharesBurn_` as `owner_` intends
    /// (which is always the case when giving allowance to some spender).
    /// @param sharesToPermit_ shares amount to use for EIP2612 permit(). Should cover `previewWithdraw(assets_)` + small buffer.
    /// @param assets_ amount of assets to withdraw
    /// @param receiver_ receiver of withdrawn assets
    /// @param owner_ owner to withdraw from (must be signature signer)
    /// @param maxSharesBurn_ maximum accepted amount of shares burned
    /// @param deadline_ deadline for signature validity
    /// @param signature_  packed signature of signing the EIP712 hash for ERC-2612 permit
    /// @return shares_ burned shares amount
    function withdrawWithSignature(
        uint256 sharesToPermit_,
        uint256 assets_,
        address receiver_,
        address owner_,
        uint256 maxSharesBurn_,
        uint256 deadline_,
        bytes calldata signature_
    ) external virtual nonReentrant returns (uint256 shares_) {
        if (msg.sender == owner_) {
            // no sense in operating with permit if msg.sender is owner. should call normal `withdraw()` instead.
            revert FluidLendingError(ErrorTypes.fToken__PermitFromOwnerCall);
        }

        // create allowance through signature_
        _allowViaPermitEIP2612(owner_, sharesToPermit_, deadline_, signature_);

        // execute withdraw to get shares_ to spend amount
        shares_ = _executeWithdraw(assets_, receiver_, owner_);

        _revertIfAboveMaxAmount(shares_, maxSharesBurn_);

        _spendAllowance(owner_, msg.sender, shares_);
    }

    /// @notice redeem amount of `shares_` with ERC-2612 permit signature for fToken approval.
    /// `owner_` signs ERC-2612 permit `signature_` to give allowance of fTokens to `msg.sender`.
    /// Note there might be tiny inaccuracies between requested `shares_` to redeem and actually burned shares.
    /// allowance via signature must cover `shares_` plus a tiny buffer.
    /// Inherent trust assumption that `msg.sender` will set `receiver_` and `minAmountOut_` as `owner_` intends
    ///       (which is always the case when giving allowance to some spender).
    /// Recommended to use `withdraw()` over redeem because it is more gas efficient and can set specific amount.
    /// @param shares_ amount of shares to redeem
    /// @param receiver_ receiver of withdrawn assets
    /// @param owner_ owner to withdraw from (must be signature signer)
    /// @param minAmountOut_ minimum accepted amount of assets withdrawn
    /// @param deadline_ deadline for signature validity
    /// @param signature_  packed signature of signing the EIP712 hash for ERC-2612 permit
    /// @return assets_ withdrawn assets amount
    function redeemWithSignature(
        uint256 shares_,
        address receiver_,
        address owner_,
        uint256 minAmountOut_,
        uint256 deadline_,
        bytes calldata signature_
    ) external virtual nonReentrant returns (uint256 assets_) {
        if (msg.sender == owner_) {
            // no sense in operating with permit if msg.sender is owner. should call normal `redeem()` instead.
            revert FluidLendingError(ErrorTypes.fToken__PermitFromOwnerCall);
        }

        assets_ = previewRedeem(shares_);
        _revertIfBelowMinAmountOut(assets_, minAmountOut_);

        // create allowance through signature_
        _allowViaPermitEIP2612(owner_, shares_, deadline_, signature_);

        // execute withdraw to get actual shares to spend amount
        uint256 sharesToSpend_ = _executeWithdraw(assets_, receiver_, owner_);

        _spendAllowance(owner_, msg.sender, sharesToSpend_);
    }
}

/// @notice implements fTokens support for deposit / mint via EIP-2612 permit.
/// @dev methods revert if underlying asset does not support EIP-2612.
abstract contract fTokenEIP2612Deposits is fTokenActions {
    /// @notice deposit `assets_` amount with EIP-2612 Permit2 signature for underlying asset approval.
    ///         IMPORTANT: This will revert if the underlying `asset()` does not support EIP-2612.
    ///         reverts with `fToken__MinAmountOut()` if `minAmountOut_` of shares is not reached.
    ///         `assets_` must at least be `minDeposit()` amount; reverts `fToken__DepositInsignificant()` if not.
    /// @param assets_ amount of assets to deposit
    /// @param receiver_ receiver of minted fToken shares
    /// @param minAmountOut_ minimum accepted amount of shares minted
    /// @param deadline_ deadline for signature validity
    /// @param signature_  packed signature of signing the EIP712 hash for EIP-2612 Permit
    /// @return shares_ amount of minted shares
    function depositWithSignatureEIP2612(
        uint256 assets_,
        address receiver_,
        uint256 minAmountOut_,
        uint256 deadline_,
        bytes calldata signature_
    ) external returns (uint256 shares_) {
        // create allowance through signature_ and spend it
        (uint8 v_, bytes32 r_, bytes32 s_) = _splitSignature(signature_);

        // EIP-2612 permit for underlying asset from owner (msg.sender) to spender (this contract)
        IERC20Permit(address(_asset())).permit(msg.sender, address(this), assets_, deadline_, v_, r_, s_);

        // deposit() includes nonReentrant modifier which is enough to have from this point forward
        shares_ = deposit(assets_, receiver_);
        _revertIfBelowMinAmountOut(shares_, minAmountOut_);
    }

    /// @notice mint amount of `shares_` with EIP-2612 Permit signature for underlying asset approval.
    ///         IMPORTANT: This will revert if the underlying `asset()` does not support EIP-2612.
    ///         Signature should approve a little bit more than expected assets amount (`previewMint()`) to avoid reverts.
    ///         `shares_` must at least be `minMint()` amount; reverts with `fToken__DepositInsignificant()` if not.
    ///         Note there might be tiny inaccuracies between requested `shares_` and actually received shares amount.
    ///         Recommended to use `deposit()` over mint because it is more gas efficient and less likely to revert.
    /// @param shares_ amount of shares to mint
    /// @param receiver_ receiver of minted fToken shares
    /// @param maxAssets_ maximum accepted amount of assets used as input to mint `shares_`
    /// @param deadline_ deadline for signature validity
    /// @param signature_  packed signature of signing the EIP712 hash for EIP-2612 Permit
    /// @return assets_ deposited assets amount
    function mintWithSignatureEIP2612(
        uint256 shares_,
        address receiver_,
        uint256 maxAssets_,
        uint256 deadline_,
        bytes calldata signature_
    ) external returns (uint256 assets_) {
        assets_ = previewMint(shares_);

        // create allowance through signature_ and spend it
        (uint8 v_, bytes32 r_, bytes32 s_) = _splitSignature(signature_);

        // EIP-2612 permit for underlying asset from owner (msg.sender) to spender (this contract)
        IERC20Permit(address(_asset())).permit(msg.sender, address(this), assets_, deadline_, v_, r_, s_);

        // mint() includes nonReentrant modifier which is enough to have from this point forward
        assets_ = mint(shares_, receiver_);
        _revertIfAboveMaxAmount(assets_, maxAssets_);
    }
}

/// @notice implements fTokens support for deposit / mint via Permit2 signature.
abstract contract fTokenPermit2Deposits is fTokenActions {
    /// @notice Deposits assets using a Permit2 approval signature.
    function depositWithSignature(
        uint256 assets_,
        address receiver_,
        uint256 minAmountOut_,
        IAllowanceTransfer.PermitSingle calldata permit_,
        bytes calldata signature_
    ) external nonReentrant returns (uint256 shares_) {
        // give allowance to address(this) via Permit2 signature -> to spend allowance in LiquidityCallback
        // to transfer funds directly from msg.sender to liquidity
        PERMIT2.permit(
            // owner - Who signed the permit and also holds the tokens
            // @dev Note if this is modified to not be msg.sender, extra steps would be needed for security!
            // the caller could use this signature and deposit to the balance of receiver_, which could be set to any address,
            // because it is not included in the signature. Use permitWitnessTransferFrom in that case. Same for `minAmountOut_`.
            msg.sender,
            permit_, // permit message
            signature_ // packed signature of signing the EIP712 hash of `permit_`
        );

        // @dev transfer of tokens from `msg.sender` to liquidity contract happens via `liquidityCallback`

        shares_ = _executeDeposit(assets_, receiver_, abi.encode(true, msg.sender));
        _revertIfBelowMinAmountOut(shares_, minAmountOut_);
    }

    /// @notice Mints shares using a Permit2 approval signature.
    function mintWithSignature(
        uint256 shares_,
        address receiver_,
        uint256 maxAssets_,
        IAllowanceTransfer.PermitSingle calldata permit_,
        bytes calldata signature_
    ) external nonReentrant returns (uint256 assets_) {
        assets_ = previewMint(shares_);
        _revertIfAboveMaxAmount(assets_, maxAssets_);

        // give allowance to address(this) via Permit2 PermitSingle. to spend allowance in LiquidityCallback
        // to transfer funds directly from msg.sender to liquidity
        PERMIT2.permit(
            // owner - Who signed the permit and also holds the tokens
            // @dev Note if this is modified to not be msg.sender, extra steps would be needed for security!
            // the caller could use this signature and deposit to the balance of receiver_, which could be set to any address,
            // because it is not included in the signature. Use permitWitnessTransferFrom in that case. Same for `minAmountOut_`.
            msg.sender,
            permit_, // permit message
            signature_ // packed signature of signing the EIP712 hash of `permit_`
        );

        // @dev transfer of tokens from `msg.sender` to liquidity contract happens via `liquidityCallback`

        _executeDeposit(assets_, receiver_, abi.encode(true, msg.sender));
    }
}

/// @title Fluid fToken (Lending with interest)
/// @notice fToken is a token that can be used to supply liquidity to the Fluid Liquidity pool and earn interest for doing so.
/// The fToken is backed by the underlying balance and can be redeemed for the underlying token at any time.
/// The interest is earned via Fluid Liquidity, e.g. because borrowers pay a borrow rate on it. In addition, fTokens may also
/// have active rewards going on that count towards the earned yield for fToken holders.
/// @dev The fToken implements the ERC20 and ERC4626 standard, which means it can be transferred, minted and burned.
/// The fToken supports EIP-2612 permit approvals via signature.
/// The fToken implements withdrawals via EIP-2612 permits and deposits with Permit2 or EIP-2612 (if underlying supports it) signatures.
/// fTokens are not upgradeable.
/// @dev For view methods / accessing data, use the "LendingResolver" periphery contract.
//
// fTokens can only be deployed for underlying tokens that are listed at Liquidity (`_getLiquidityExchangePrice()` reverts
// otherwise, which is called in the constructor).
contract fToken is fTokenBase, fTokenActions, fTokenEIP2612Withdrawals, fTokenPermit2Deposits, fTokenEIP2612Deposits {
    /// @param liquidity_ liquidity contract address
    /// @param lendingFactory_ lending factory contract address
    /// @param asset_ underlying token address
    constructor(
        IFluidLiquidity liquidity_,
        IFluidLendingFactory lendingFactory_,
        IERC20 asset_
    )
        validAddress(address(liquidity_))
        validAddress(address(lendingFactory_))
        validAddress(address(asset_))
        Variables(liquidity_, lendingFactory_, asset_)
        ERC20(
            string(abi.encodePacked(TOKEN_NAME_PREFIX, IERC20Metadata(address(asset_)).name())),
            string(abi.encodePacked(TOKEN_SYMBOL_PREFIX, IERC20Metadata(address(asset_)).symbol()))
        )
        ERC20Permit(string(abi.encodePacked(TOKEN_NAME_PREFIX, IERC20Metadata(address(asset_)).name())))
    {
        _initializeFTokenState();
    }

    /// @inheritdoc IERC20Metadata
    function decimals() public view override(fTokenBase) returns (uint8) {
        return _decimals();
    }
}
