// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { SafeTransfer } from "../../../../libraries/safeTransfer.sol";
import { LiquiditySlotsLink } from "../../../../libraries/liquiditySlotsLink.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { fTokenCore, fTokenAdmin, fToken } from "../main.sol";

import { IWETH9 } from "../../interfaces/external/iWETH9.sol";
import { IFluidLendingFactory } from "../../interfaces/iLendingFactory.sol";
import { IFTokenAdmin, IFTokenNativeUnderlying, IFToken } from "../../interfaces/iFToken.sol";
import { IFluidLiquidity } from "../../../../liquidity/interfaces/iLiquidity.sol";

/// @dev overrides certain methods from the inherited fToken used as base contract to make them compatible with
/// the native token being used as underlying.
abstract contract fTokenNativeUnderlyingOverrides is fToken, IFTokenNativeUnderlying {
    using FixedPointMathLib for uint256;

    /// @inheritdoc IFTokenNativeUnderlying
    address public constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev gets asset address for liquidity slot links, overridden to set native token address
    function _getLiquiditySlotLinksAsset() internal view virtual override returns (address) {
        return NATIVE_TOKEN_ADDRESS;
    }

    /// @dev Gets current Liquidity underlying token balance
    function _getLiquidityUnderlyingBalance() internal view virtual override returns (uint256) {
        return address(LIQUIDITY).balance;
    }

    /// @inheritdoc IFTokenAdmin
    function rescueFunds(address token_) external virtual override(IFTokenAdmin, fTokenAdmin) nonReentrant {
        _checkIsLendingFactoryAuth();

        if (token_ == NATIVE_TOKEN_ADDRESS) {
            Address.sendValue(payable(address(LIQUIDITY)), address(this).balance);
        } else {
            SafeTransfer.safeTransfer(address(token_), address(LIQUIDITY), IERC20(token_).balanceOf(address(this)));
        }

        emit LogRescueFunds(token_);
    }

    /*//////////////////////////////////////////////////////////////
                                REWARDS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc fTokenAdmin
    function rebalance()
        external
        payable
        virtual
        override(IFTokenAdmin, fTokenAdmin)
        nonReentrant
        returns (uint256 assets_)
    {
        if (msg.sender != _rebalancer) {
            revert FluidLendingError(ErrorTypes.fToken__NotRebalancer);
        }
        // calculating difference in assets. if liquidity balance is bigger it'll throw which is an expected behaviour
        assets_ = totalAssets() - _getLiquidityBalance();

        if (msg.value < assets_) {
            assets_ = msg.value;
        } else if (msg.value > assets_) {
            // send back overfunded msg.value amount
            Address.sendValue(payable(msg.sender), msg.value - assets_);
        }

        // send funds to Liquidity protocol to generate yield
        uint256 liquidityExchangePrice_ = _depositToLiquidity(assets_, new bytes(0));

        // update the exchange prices, always updating on storage
        _updateRates(liquidityExchangePrice_, true);

        // no shares are minted when funding fToken contract for rewards

        emit LogRebalance(assets_);
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
        (exchangePrice_, ) = LIQUIDITY.operate{ value: assets_ }(
            NATIVE_TOKEN_ADDRESS, // deposit to Liquidity is always in native, also if user input is wrapped token
            SafeCast.toInt256(assets_),
            0,
            address(0),
            address(0),
            liquidityCallbackData_ // callback data. -> "from" for transferFrom in `liquidityCallback`
        );
    }

    /// @inheritdoc fTokenCore
    function _executeDeposit(
        uint256 assets_,
        address receiver_,
        // liquidityCallbackData_ not needed for native transfer, sent along as msg.value. But used to recognize Permit2 transfers.
        bytes memory liquidityCallbackData_
    ) internal virtual override returns (uint256 sharesMinted_) {
        // transfer wrapped asset from user to this contract
        if (liquidityCallbackData_.length > 32) {
            // liquidityCallbackData_ with length > 32 can only be Permit2 as all others maximally encode from address
            PERMIT2.transferFrom(msg.sender, address(this), uint160(assets_), address(ASSET));
        } else {
            SafeTransfer.safeTransferFrom(address(ASSET), msg.sender, address(this), assets_);
        }

        // convert WETH to native underlying token
        IWETH9(address(ASSET)).withdraw(assets_);

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
        (exchangePrice_, ) = LIQUIDITY.operate(
            NATIVE_TOKEN_ADDRESS, // withdraw from Liquidity is always in native, also if user output is wrapped token
            -SafeCast.toInt256(assets_),
            0,
            receiver_,
            address(0),
            new bytes(0) // callback data -> withdraw doesn't trigger a callback
        );
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
        IWETH9(address(ASSET)).deposit{ value: assets_ }();
        SafeTransfer.safeTransfer(address(ASSET), receiver_, assets_);
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

    /// @inheritdoc IFTokenNativeUnderlying
    function depositNative(address receiver_) public payable nonReentrant returns (uint256 shares_) {
        shares_ = _executeDepositNative(receiver_);
    }

    /// @inheritdoc IFTokenNativeUnderlying
    function depositNative(address receiver_, uint256 minAmountOut_) external payable returns (uint256 shares_) {
        shares_ = depositNative(receiver_);
        _revertIfBelowMinAmountOut(shares_, minAmountOut_);
    }

    /*//////////////////////////////////////////////////////////////
                                   MINT 
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFTokenNativeUnderlying
    function mintNative(uint256 shares_, address receiver_) public payable nonReentrant returns (uint256 assets_) {
        // No need to check for rounding error, previewMint rounds up.
        assets_ = previewMint(shares_);

        if (msg.value < assets_) {
            // not enough msg.value sent along to cover mint shares amount
            revert FluidLendingError(ErrorTypes.fTokenNativeUnderlying__TransferInsufficient);
        }

        _executeDepositNative(receiver_);
    }

    /// @inheritdoc IFTokenNativeUnderlying
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

    /// @inheritdoc IFTokenNativeUnderlying
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

    /// @inheritdoc IFTokenNativeUnderlying
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

    /// @inheritdoc IFTokenNativeUnderlying
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

    /// @inheritdoc IFTokenNativeUnderlying
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
    /// @inheritdoc IFTokenNativeUnderlying
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

    /// @inheritdoc IFTokenNativeUnderlying
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

    /// @inheritdoc fToken
    function liquidityCallback(
        address /** token_ */,
        uint256 /** amount_ */,
        bytes calldata /** data_ */
    ) external virtual override(IFToken, fToken) {
        // not needed because msg.value is used directly
        revert FluidLendingError(ErrorTypes.fTokenNativeUnderlying__UnexpectedLiquidityCallback);
    }

    receive() external payable {}
}
