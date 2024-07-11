//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IAllowanceTransfer } from "./permit2/iAllowanceTransfer.sol";
import { IFluidLendingRewardsRateModel } from "./iLendingRewardsRateModel.sol";
import { IFluidLendingFactory } from "./iLendingFactory.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";

interface IFTokenAdmin {
    /// @notice updates the rewards rate model contract.
    ///         Only callable by LendingFactory auths.
    /// @param rewardsRateModel_  the new rewards rate model contract address.
    ///                           can be set to address(0) to set no rewards (to save gas)
    function updateRewards(IFluidLendingRewardsRateModel rewardsRateModel_) external;

    /// @notice Balances out the difference between fToken supply at Liquidity vs totalAssets().
    ///         Deposits underlying from rebalancer address into Liquidity but doesn't mint any shares
    ///         -> thus making deposit available as rewards.
    ///         Only callable by rebalancer.
    /// @return assets_ amount deposited to Liquidity
    function rebalance() external payable returns (uint256 assets_);

    /// @notice gets the liquidity exchange price of the underlying asset, calculates the updated exchange price (with reward rates)
    ///         and writes those values to storage.
    ///         Callable by anyone.
    /// @return tokenExchangePrice_ exchange price of fToken share to underlying asset
    /// @return liquidityExchangePrice_ exchange price at Liquidity for the underlying asset
    function updateRates() external returns (uint256 tokenExchangePrice_, uint256 liquidityExchangePrice_);

    /// @notice sends any potentially stuck funds to Liquidity contract. Only callable by LendingFactory auths.
    function rescueFunds(address token_) external;

    /// @notice Updates the rebalancer address (ReserveContract). Only callable by LendingFactory auths.
    function updateRebalancer(address rebalancer_) external;
}

interface IFToken is IERC4626, IFTokenAdmin {
    /// @notice returns minimum amount required for deposit (rounded up)
    function minDeposit() external view returns (uint256);

    /// @notice returns config, rewards and exchange prices data in a single view method.
    /// @return liquidity_ address of the Liquidity contract.
    /// @return lendingFactory_ address of the Lending factory contract.
    /// @return lendingRewardsRateModel_ address of the rewards rate model contract. changeable by LendingFactory auths.
    /// @return permit2_ address of the Permit2 contract used for deposits / mint with signature
    /// @return rebalancer_ address of the rebalancer allowed to execute `rebalance()`
    /// @return rewardsActive_ true if rewards are currently active
    /// @return liquidityBalance_ current Liquidity supply balance of `address(this)` for the underyling asset
    /// @return liquidityExchangePrice_ (updated) exchange price for the underlying assset in the liquidity protocol (without rewards)
    /// @return tokenExchangePrice_ (updated) exchange price between fToken and the underlying assset (with rewards)
    function getData()
        external
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
        );

    /// @notice transfers `amount_` of `token_` to liquidity. Only callable by liquidity contract.
    /// @dev this callback is used to optimize gas consumption (reducing necessary token transfers).
    function liquidityCallback(address token_, uint256 amount_, bytes calldata data_) external;

    /// @notice deposit `assets_` amount with Permit2 signature for underlying asset approval.
    ///         reverts with `fToken__MinAmountOut()` if `minAmountOut_` of shares is not reached.
    ///         `assets_` must at least be `minDeposit()` amount; reverts otherwise.
    /// @param assets_ amount of assets to deposit
    /// @param receiver_ receiver of minted fToken shares
    /// @param minAmountOut_ minimum accepted amount of shares minted
    /// @param permit_ Permit2 permit message
    /// @param signature_  packed signature of signing the EIP712 hash of `permit_`
    /// @return shares_ amount of minted shares
    function depositWithSignature(
        uint256 assets_,
        address receiver_,
        uint256 minAmountOut_,
        IAllowanceTransfer.PermitSingle calldata permit_,
        bytes calldata signature_
    ) external returns (uint256 shares_);

    /// @notice mint amount of `shares_` with Permit2 signature for underlying asset approval.
    ///         Signature should approve a little bit more than expected assets amount (`previewMint()`) to avoid reverts.
    ///         `shares_` must at least be `minMint()` amount; reverts otherwise.
    ///         Note there might be tiny inaccuracies between requested `shares_` and actually received shares amount.
    ///         Recommended to use `deposit()` over mint because it is more gas efficient and less likely to revert.
    /// @param shares_ amount of shares to mint
    /// @param receiver_ receiver of minted fToken shares
    /// @param maxAssets_ maximum accepted amount of assets used as input to mint `shares_`
    /// @param permit_ Permit2 permit message
    /// @param signature_  packed signature of signing the EIP712 hash of `permit_`
    /// @return assets_ deposited assets amount
    function mintWithSignature(
        uint256 shares_,
        address receiver_,
        uint256 maxAssets_,
        IAllowanceTransfer.PermitSingle calldata permit_,
        bytes calldata signature_
    ) external returns (uint256 assets_);
}

interface IFTokenNativeUnderlying is IFToken {
    /// @notice address that is mapped to the chain native token at Liquidity
    function NATIVE_TOKEN_ADDRESS() external view returns (address);

    /// @notice deposits `msg.value` amount of native token for `receiver_`.
    ///         `msg.value` must be at least `minDeposit()` amount; reverts otherwise.
    ///         Recommended to use `depositNative()` with a `minAmountOut_` param instead to set acceptable limit.
    /// @return shares_ actually minted shares
    function depositNative(address receiver_) external payable returns (uint256 shares_);

    /// @notice same as {depositNative} but with an additional setting for minimum output amount.
    /// reverts with `fToken__MinAmountOut()` if `minAmountOut_` of shares is not reached
    function depositNative(address receiver_, uint256 minAmountOut_) external payable returns (uint256 shares_);

    /// @notice mints `shares_` for `receiver_`, paying with underlying native token.
    ///         `shares_` must at least be `minMint()` amount; reverts otherwise.
    ///         `shares_` set to type(uint256).max not supported.
    ///         Note there might be tiny inaccuracies between requested `shares_` and actually received shares amount.
    ///         Recommended to use `depositNative()` over mint because it is more gas efficient and less likely to revert.
    ///         Recommended to use `mintNative()` with a `minAmountOut_` param instead to set acceptable limit.
    /// @return assets_ deposited assets amount
    function mintNative(uint256 shares_, address receiver_) external payable returns (uint256 assets_);

    /// @notice same as {mintNative} but with an additional setting for minimum output amount.
    /// reverts with `fToken__MaxAmount()` if `maxAssets_` of assets is surpassed to mint `shares_`.
    function mintNative(
        uint256 shares_,
        address receiver_,
        uint256 maxAssets_
    ) external payable returns (uint256 assets_);

    /// @notice withdraws `assets_` amount in native underlying to `receiver_`, burning shares of `owner_`.
    ///         If `assets_` equals uint256.max then the whole fToken balance of `owner_` is withdrawn.This does not
    ///         consider withdrawal limit at liquidity so best to check with `maxWithdraw()` before.
    ///         Note there might be tiny inaccuracies between requested `assets_` and actually received assets amount.
    ///         Recommended to use `withdrawNative()` with a `maxSharesBurn_` param instead to set acceptable limit.
    /// @return shares_ burned shares
    function withdrawNative(uint256 assets_, address receiver_, address owner_) external returns (uint256 shares_);

    /// @notice same as {withdrawNative} but with an additional setting for minimum output amount.
    /// reverts with `fToken__MaxAmount()` if `maxSharesBurn_` of shares burned is surpassed.
    function withdrawNative(
        uint256 assets_,
        address receiver_,
        address owner_,
        uint256 maxSharesBurn_
    ) external returns (uint256 shares_);

    /// @notice redeems `shares_` to native underlying to `receiver_`, burning shares of `owner_`.
    ///         If `shares_` equals uint256.max then the whole balance of `owner_` is withdrawn.This does not
    ///         consider withdrawal limit at liquidity so best to check with `maxRedeem()` before.
    ///         Recommended to use `withdrawNative()` over redeem because it is more gas efficient and can set specific amount.
    ///         Recommended to use `redeemNative()` with a `minAmountOut_` param instead to set acceptable limit.
    /// @return assets_ withdrawn assets amount
    function redeemNative(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);

    /// @notice same as {redeemNative} but with an additional setting for minimum output amount.
    /// reverts with `fToken__MinAmountOut()` if `minAmountOut_` of assets is not reached.
    function redeemNative(
        uint256 shares_,
        address receiver_,
        address owner_,
        uint256 minAmountOut_
    ) external returns (uint256 assets_);

    /// @notice withdraw amount of `assets_` in native token with ERC-2612 permit signature for fToken approval.
    /// `owner_` signs ERC-2612 permit `signature_` to give allowance of fTokens to `msg.sender`.
    /// Note there might be tiny inaccuracies between requested `assets_` and actually received assets amount.
    /// allowance via signature should cover `previewWithdraw(assets_)` plus a little buffer to avoid revert.
    /// Inherent trust assumption that `msg.sender` will set `receiver_` and `minAmountOut_` as `owner_` intends
    /// (which is always the case when giving allowance to some spender).
    /// @param sharesToPermit_ shares amount to use for EIP2612 permit(). Should cover `previewWithdraw(assets_)` + small buffer.
    /// @param assets_ amount of assets to withdraw
    /// @param receiver_ receiver of withdrawn assets
    /// @param owner_ owner to withdraw from (must be signature signer)
    /// @param maxSharesBurn_ maximum accepted amount of shares burned
    /// @param deadline_ deadline for signature validity
    /// @param signature_  packed signature of signing the EIP712 hash for ERC-2612 permit
    /// @return shares_ burned shares amount
    function withdrawWithSignatureNative(
        uint256 sharesToPermit_,
        uint256 assets_,
        address receiver_,
        address owner_,
        uint256 maxSharesBurn_,
        uint256 deadline_,
        bytes calldata signature_
    ) external returns (uint256 shares_);

    /// @notice redeem amount of `shares_` as native token with ERC-2612 permit signature for fToken approval.
    /// `owner_` signs ERC-2612 permit `signature_` to give allowance of fTokens to `msg.sender`.
    /// Note there might be tiny inaccuracies between requested `shares_` to redeem and actually burned shares.
    /// allowance via signature must cover `shares_` plus a tiny buffer.
    /// Inherent trust assumption that `msg.sender` will set `receiver_` and `minAmountOut_` as `owner_` intends
    ///       (which is always the case when giving allowance to some spender).
    /// Recommended to use `withdrawNative()` over redeem because it is more gas efficient and can set specific amount.
    /// @param shares_ amount of shares to redeem
    /// @param receiver_ receiver of withdrawn assets
    /// @param owner_ owner to withdraw from (must be signature signer)
    /// @param minAmountOut_ minimum accepted amount of assets withdrawn
    /// @param deadline_ deadline for signature validity
    /// @param signature_  packed signature of signing the EIP712 hash for ERC-2612 permit
    /// @return assets_ withdrawn assets amount
    function redeemWithSignatureNative(
        uint256 shares_,
        address receiver_,
        address owner_,
        uint256 minAmountOut_,
        uint256 deadline_,
        bytes calldata signature_
    ) external returns (uint256 assets_);
}
