// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { SafeTransfer } from "../../../../libraries/safeTransfer.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { fTokenCore, fTokenAdmin, fToken, fTokenBase } from "../main.sol";

import { IWETH9 } from "../../interfaces/external/iWETH9.sol";
import { IFluidLendingFactory } from "../../interfaces/iLendingFactory.sol";
import { IAllowanceTransfer } from "../../interfaces/permit2/iAllowanceTransfer.sol";
import { IFluidLiquidity } from "../../../../liquidity/interfaces/iLiquidity.sol";

/// @dev Small native-token helpers reused by the permissioned native fToken without inheriting production `fToken`.
abstract contract fTokenNativeUnderlyingHelpers {
    address public constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function _getLiquiditySlotLinksAssetNative() internal pure returns (address) {
        return NATIVE_TOKEN_ADDRESS;
    }

    function _getLiquidityUnderlyingBalanceNative(IFluidLiquidity liquidity_) internal view returns (uint256) {
        return address(liquidity_).balance;
    }

    function _rescueFundsNative(address token_, IFluidLiquidity liquidity_) internal {
        if (token_ == NATIVE_TOKEN_ADDRESS) {
            SafeTransfer.safeTransferNative(payable(address(liquidity_)), address(this).balance);
        } else {
            SafeTransfer.safeTransfer(address(token_), address(liquidity_), IERC20(token_).balanceOf(address(this)));
        }
    }

    function _depositToLiquidityNative(
        IFluidLiquidity liquidity_,
        uint256 assets_,
        bytes memory liquidityCallbackData_
    ) internal returns (uint256 exchangePrice_) {
        (exchangePrice_, ) = liquidity_.operate{ value: assets_ }(
            NATIVE_TOKEN_ADDRESS,
            SafeCast.toInt256(assets_),
            0,
            address(0),
            address(0),
            liquidityCallbackData_
        );
    }

    function _prepareWrappedNativeDeposit(
        IAllowanceTransfer permit2_,
        IERC20 asset_,
        uint256 assets_,
        bytes memory liquidityCallbackData_
    ) internal {
        if (liquidityCallbackData_.length > 32) {
            permit2_.transferFrom(msg.sender, address(this), uint160(assets_), address(asset_));
        } else {
            SafeTransfer.safeTransferFrom(address(asset_), msg.sender, address(this), assets_);
        }
        IWETH9(address(asset_)).withdraw(assets_);
    }

    function _withdrawFromLiquidityNative(
        IFluidLiquidity liquidity_,
        uint256 assets_,
        address receiver_
    ) internal returns (uint256 exchangePrice_) {
        (exchangePrice_, ) = liquidity_.operate(
            NATIVE_TOKEN_ADDRESS,
            -SafeCast.toInt256(assets_),
            0,
            receiver_,
            address(0),
            new bytes(0)
        );
    }

    function _finalizeWrappedNativeWithdraw(IERC20 asset_, uint256 assets_, address receiver_) internal {
        IWETH9(address(asset_)).deposit{ value: assets_ }();
        SafeTransfer.safeTransfer(address(asset_), receiver_, assets_);
    }

    /// @dev shared native rebalance math: caps `assetsNeeded_` at `msgValue_`, refunds any excess to `caller_`, and
    ///      deposits the resolved amount into Liquidity. Returns resolved `assets_` + new liquidity exchange price.
    function _rebalanceNative(
        IFluidLiquidity liquidity_,
        uint256 assetsNeeded_,
        uint256 msgValue_,
        address caller_
    ) internal returns (uint256 assets_, uint256 liquidityExchangePrice_) {
        assets_ = assetsNeeded_;
        if (msgValue_ < assets_) {
            // not enough msg.value sent along; deposit only what was sent
            assets_ = msgValue_;
        } else if (msgValue_ > assets_) {
            // send back overfunded msg.value amount
            SafeTransfer.safeTransferNative(payable(caller_), msgValue_ - assets_);
        }
        liquidityExchangePrice_ = _depositToLiquidityNative(liquidity_, assets_, new bytes(0));
    }

    /// @dev Bidirectional native rebalance shared by production and permissioned native fTokens.
    ///      Rewards: deposit native to Liquidity up to `msgValue_`. Fees: withdraw excess Liquidity to `rebalancer_`.
    /// @return assets_ absolute amount moved (0 if no-op)
    /// @return liquidityExchangePrice_ Liquidity exchange price after the operate (or unchanged if no-op)
    /// @return signedAssets_ LogRebalance payload: +deposit/rewards, -withdraw/fees, 0 no-op
    function _rebalanceNativeBidirectional(
        IFluidLiquidity liquidity_,
        uint256 totalAssets_,
        uint256 liquidityBalance_,
        uint256 msgValue_,
        address caller_,
        address rebalancer_,
        uint256 liquidityExchangePriceIfUnchanged_
    ) internal returns (uint256 assets_, uint256 liquidityExchangePrice_, int256 signedAssets_) {
        if (totalAssets_ > liquidityBalance_) {
            (assets_, liquidityExchangePrice_) = _rebalanceNative(
                liquidity_,
                totalAssets_ - liquidityBalance_,
                msgValue_,
                caller_
            );
            return (assets_, liquidityExchangePrice_, int256(assets_));
        }

        if (msgValue_ > 0) {
            SafeTransfer.safeTransferNative(payable(caller_), msgValue_);
        }

        if (liquidityBalance_ > totalAssets_) {
            assets_ = liquidityBalance_ - totalAssets_;
            liquidityExchangePrice_ = _withdrawFromLiquidityNative(liquidity_, assets_, rebalancer_);
            signedAssets_ = -int256(assets_);
        } else {
            assets_ = 0;
            liquidityExchangePrice_ = liquidityExchangePriceIfUnchanged_;
        }
    }
}

/// @dev overrides certain methods from the inherited fToken used as base contract to make them compatible with
/// the native token being used as underlying.
abstract contract fTokenNativeUnderlyingOverrides is fTokenNativeUnderlyingHelpers, fToken {
    /// @dev gets asset address for liquidity slot links, overridden to set native token address
    function _getLiquiditySlotLinksAsset() internal view virtual override returns (address) {
        return _getLiquiditySlotLinksAssetNative();
    }

    /// @dev Gets current Liquidity underlying token balance
    function _getLiquidityUnderlyingBalance() internal view virtual override returns (uint256) {
        return _getLiquidityUnderlyingBalanceNative(_liquidity());
    }

    /// @notice Sends stuck native or ERC20 funds to Liquidity.
    function rescueFunds(address token_) external virtual override(fTokenAdmin) nonReentrant {
        _checkIsLendingFactoryAuth();
        _rescueFundsNative(token_, _liquidity());
        emit LogRescueFunds(token_);
    }

    /*//////////////////////////////////////////////////////////////
                                REWARDS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc fTokenAdmin
    function rebalance() external payable virtual override(fTokenAdmin) nonReentrant returns (uint256 assets_) {
        if (msg.sender != _rebalancer) {
            revert FluidLendingError(ErrorTypes.fToken__NotRebalancer);
        }

        uint256 liquidityExchangePrice_;
        int256 signedAssets_;
        (assets_, liquidityExchangePrice_, signedAssets_) = _rebalanceNativeBidirectional(
            _liquidity(),
            totalAssets(),
            _getLiquidityBalance(),
            msg.value,
            msg.sender,
            _rebalancer,
            _getLiquidityExchangePrice()
        );

        // update the exchange prices, always updating on storage
        _updateRates(liquidityExchangePrice_, true);

        // no shares are minted when funding fToken contract for rewards.
        emit LogRebalance(signedAssets_);
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc fTokenCore
    function _depositToLiquidity(
        uint256 assets_,
        bytes memory liquidityCallbackData_
    ) internal virtual override returns (uint256 exchangePrice_) {
        // send funds to Liquidity protocol to generate yield, send along msg.value
        return _depositToLiquidityNative(_liquidity(), assets_, liquidityCallbackData_);
    }

    /// @inheritdoc fTokenCore
    function _executeDeposit(
        uint256 assets_,
        address receiver_,
        // liquidityCallbackData_ not needed for native transfer, sent along as msg.value. But used to recognize Permit2 transfers.
        bytes memory liquidityCallbackData_
    ) internal virtual override returns (uint256 sharesMinted_) {
        // transfer wrapped asset from user to this contract and convert WETH to native underlying token
        _prepareWrappedNativeDeposit(PERMIT2, _asset(), assets_, liquidityCallbackData_);

        // super._executeDeposit includes check for validAddress receiver_
        return super._executeDeposit(assets_, receiver_, new bytes(0));
    }

    /// @dev deposits `msg.value` amount of native token into liquidity and mints shares for `receiver_`.
    /// Returns amount of `sharesMinted_`.
    function _executeDepositNative(address receiver_) internal virtual returns (uint256 sharesMinted_) {
        // super._executeDeposit includes check for validAddress receiver_
        return super._executeDeposit(msg.value, receiver_, new bytes(0));
    }

    /*//////////////////////////////////////////////////////////////
                                WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc fTokenCore
    function _withdrawFromLiquidity(
        uint256 assets_,
        address receiver_
    ) internal virtual override returns (uint256 exchangePrice_) {
        // get funds back from Liquidity protocol to send to the user
        return _withdrawFromLiquidityNative(_liquidity(), assets_, receiver_);
    }

    /// @inheritdoc fTokenCore
    function _executeWithdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) internal virtual override returns (uint256 sharesBurned_) {
        // super._executeWithdraw includes check for validAddress(receiver_)

        // withdraw from liquidity to this contract first to convert withdrawn native token to wrapped native for _receiver.
        sharesBurned_ = super._executeWithdraw(assets_, address(this), owner_);

        // convert received native underlying token to WETH and transfer to receiver_
        _finalizeWrappedNativeWithdraw(_asset(), assets_, receiver_);
    }

    /// @dev withdraws `assets_` from liquidity to `receiver_` and burns shares from `owner_`.
    /// Returns amount of `sharesBurned_`.
    function _executeWithdrawNative(
        uint256 assets_,
        address receiver_,
        address owner_
    ) internal virtual returns (uint256 sharesBurned_) {
        // super._executeWithdraw includes check for validAddress(receiver_)
        return super._executeWithdraw(assets_, receiver_, owner_);
    }
}

/// @notice implements deposit / mint / withdraw / redeem actions with Native token being used as interaction token.
abstract contract fTokenNativeUnderlyingActions is fTokenNativeUnderlyingOverrides {
    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits native assets and mints shares.
    function depositNative(address receiver_) public payable nonReentrant returns (uint256 shares_) {
        shares_ = _executeDepositNative(receiver_);
    }

    /// @notice Deposits native assets with a minimum shares check.
    function depositNative(address receiver_, uint256 minAmountOut_) external payable returns (uint256 shares_) {
        shares_ = depositNative(receiver_);
        _revertIfBelowMinAmountOut(shares_, minAmountOut_);
    }

    /*//////////////////////////////////////////////////////////////
                                   MINT 
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints shares using native assets.
    function mintNative(uint256 shares_, address receiver_) public payable nonReentrant returns (uint256 assets_) {
        // No need to check for rounding error, previewMint rounds up.
        assets_ = previewMint(shares_);

        if (msg.value < assets_) {
            // not enough msg.value sent along to cover mint shares amount
            revert FluidLendingError(ErrorTypes.fTokenNativeUnderlying__TransferInsufficient);
        }

        _executeDepositNative(receiver_);
    }

    /// @notice Mints shares using native assets with a max asset check.
    function mintNative(
        uint256 shares_,
        address receiver_,
        uint256 maxAssets_
    ) external payable returns (uint256 assets_) {
        assets_ = mintNative(shares_, receiver_);
        _revertIfAboveMaxAmount(assets_, maxAssets_);
    }

    /*//////////////////////////////////////////////////////////////
                                WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraws native assets and burns owner shares.
    function withdrawNative(
        uint256 assets_,
        address receiver_,
        address owner_
    ) public nonReentrant returns (uint256 shares_) {
        if (assets_ == type(uint256).max) {
            assets_ = previewRedeem(balanceOf(msg.sender));
        }

        shares_ = _executeWithdrawNative(assets_, receiver_, owner_);

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares_);
        }
    }

    /// @notice Withdraws native assets with a max shares-burn check.
    function withdrawNative(
        uint256 assets_,
        address receiver_,
        address owner_,
        uint256 maxSharesBurn_
    ) external returns (uint256 shares_) {
        shares_ = withdrawNative(assets_, receiver_, owner_);
        _revertIfAboveMaxAmount(shares_, maxSharesBurn_);
    }

    /*//////////////////////////////////////////////////////////////
                                REDEEM
    //////////////////////////////////////////////////////////////*/

    /// @notice Redeems owner shares for native assets.
    function redeemNative(
        uint256 shares_,
        address receiver_,
        address owner_
    ) public nonReentrant returns (uint256 assets_) {
        if (shares_ == type(uint256).max) {
            shares_ = balanceOf(msg.sender);
        }

        assets_ = previewRedeem(shares_);

        uint256 burnedShares_ = _executeWithdrawNative(assets_, receiver_, owner_);

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, burnedShares_);
        }
    }

    /// @notice Redeems shares for native assets with a min output check.
    function redeemNative(
        uint256 shares_,
        address receiver_,
        address owner_,
        uint256 minAmountOut_
    ) external returns (uint256 assets_) {
        assets_ = redeemNative(shares_, receiver_, owner_);
        _revertIfBelowMinAmountOut(assets_, minAmountOut_);
    }
}

/// @notice fTokens support EIP-2612 permit approvals via signature so withdrawals are possible with signature.
/// This contract implements those withdrawals for a native underlying asset.
abstract contract fTokenNativeUnderlyingEIP2612Withdrawals is fTokenNativeUnderlyingActions {
    /// @notice Withdraws native assets using an EIP-2612 share permit.
    function withdrawWithSignatureNative(
        uint256 sharesToPermit_,
        uint256 assets_,
        address receiver_,
        address owner_,
        uint256 maxSharesBurn_,
        uint256 deadline_,
        bytes calldata signature_
    ) external nonReentrant returns (uint256 shares_) {
        // @dev logic below is exactly the same as in {fTokenEIP2612Withdrawals-withdrawWithSignature}, just using
        // _executeWithdrawNative instead of _executeWithdraw

        if (msg.sender == owner_) {
            // no sense in operating with permit if msg.sender is owner. should call normal `withdraw()` instead.
            revert FluidLendingError(ErrorTypes.fToken__PermitFromOwnerCall);
        }

        // create allowance through signature_
        _allowViaPermitEIP2612(owner_, sharesToPermit_, deadline_, signature_);

        // execute withdraw to get shares_ to spend amount
        shares_ = _executeWithdrawNative(assets_, receiver_, owner_);

        _revertIfAboveMaxAmount(shares_, maxSharesBurn_);

        _spendAllowance(owner_, msg.sender, shares_);
    }

    /// @notice Redeems shares for native assets using an EIP-2612 share permit.
    function redeemWithSignatureNative(
        uint256 shares_,
        address receiver_,
        address owner_,
        uint256 minAmountOut_,
        uint256 deadline_,
        bytes calldata signature_
    ) external nonReentrant returns (uint256 assets_) {
        // @dev logic below is exactly the same as in {fTokenEIP2612Withdrawals-redeemWithSignature}, just using
        // _executeWithdrawNative instead of _executeWithdraw

        if (msg.sender == owner_) {
            // no sense in operating with permit if msg.sender is owner. should call normal `redeem()` instead.
            revert FluidLendingError(ErrorTypes.fToken__PermitFromOwnerCall);
        }

        assets_ = previewRedeem(shares_);
        _revertIfBelowMinAmountOut(assets_, minAmountOut_);

        // create allowance through signature_
        _allowViaPermitEIP2612(owner_, shares_, deadline_, signature_);

        // execute withdraw to get actual shares to spend amount
        uint256 sharesToSpend_ = _executeWithdrawNative(assets_, receiver_, owner_);

        _spendAllowance(owner_, msg.sender, sharesToSpend_);
    }
}

/// @notice Same as the {fToken} contract but with support for native token as underlying asset.
/// Actual underlying asset is the wrapped native ERC20 version (e.g. WETH), which acts like any other fToken.
/// But in addition the fTokenNativeUnderlying also has methods for doing all the same actions via the native token.
contract fTokenNativeUnderlying is fTokenNativeUnderlyingEIP2612Withdrawals {
    /// @param liquidity_ liquidity contract address
    /// @param lendingFactory_ lending factory contract address
    /// @param weth_ address of wrapped native token (e.g. WETH)
    constructor(
        IFluidLiquidity liquidity_,
        IFluidLendingFactory lendingFactory_,
        IWETH9 weth_
    ) fToken(liquidity_, lendingFactory_, IERC20(address(weth_))) {}

    /// @inheritdoc fTokenBase
    function liquidityCallback(
        address /** token_ */,
        uint256 /** amount_ */,
        bytes calldata /** data_ */
    ) external virtual override(fTokenBase) {
        // not needed because msg.value is used directly
        revert FluidLendingError(ErrorTypes.fTokenNativeUnderlying__UnexpectedLiquidityCallback);
    }

    receive() external payable {}
}
