// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Variables } from "./variables.sol";
import { Structs } from "./structs.sol";
import { Structs as VaultResolverStructs } from "../vault/structs.sol";
import { IFluidVaultResolver } from "../vault/iVaultResolver.sol";
import { IFluidVaultT1 } from "../../../protocols/vault/interfaces/iVaultT1.sol";

/// @notice Resolver contract that helps in finding available token swaps through Fluid Vault liquidations.
contract FluidVaultLiquidationResolver is Variables, Structs {
    /// @notice thrown if an input param address is zero
    error FluidVaultLiquidationsResolver__AddressZero();
    /// @notice thrown if an invalid param is given to a method
    error FluidVaultLiquidationsResolver__InvalidParams();

    /// @notice constructor sets the immutable vault resolver address
    constructor(IFluidVaultResolver vaultResolver_) Variables(vaultResolver_) {
        if (address(vaultResolver_) == address(0)) {
            revert FluidVaultLiquidationsResolver__AddressZero();
        }
    }

    /// @notice returns all token swap pairs available through Fluid Vault Liquidations
    function getAllSwapPairs() public view returns (VaultData[] memory vaultDatas_) {
        address[] memory vaultAddresses_ = VAULT_RESOLVER.getAllVaultsAddresses();
        vaultDatas_ = new VaultData[](vaultAddresses_.length);

        IFluidVaultT1.ConstantViews memory constants_;
        for (uint256 i; i < vaultAddresses_.length; ++i) {
            constants_ = IFluidVaultT1(vaultAddresses_[i]).constantsView();
            vaultDatas_[i] = VaultData({
                vault: vaultAddresses_[i],
                tokenIn: constants_.borrowToken,
                tokenOut: constants_.supplyToken
            });
        }
    }

    /// @notice returns the vault address for a certain `tokenIn_` swapped to a `tokenOut_`.
    ///         returns zero address if no vault is available for a given pair.
    /// @dev    for native token, send 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE.
    function getVaultForSwap(address tokenIn_, address tokenOut_) public view returns (address vault_) {
        address[] memory vaults_ = VAULT_RESOLVER.getAllVaultsAddresses();

        IFluidVaultT1.ConstantViews memory constants_;
        for (uint256 i; i < vaults_.length; ++i) {
            constants_ = IFluidVaultT1(vaults_[i]).constantsView();

            if (constants_.borrowToken == tokenIn_ && constants_.supplyToken == tokenOut_) {
                return vaults_[i];
            }
        }
    }

    /// @notice returns all available token pair swaps for any `tokensIn_` to any `tokensOut_` with the vault address.
    /// @dev    for native token, send 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE.
    function getVaultsForSwap(
        address[] calldata tokensIn_,
        address[] calldata tokensOut_
    ) public view returns (VaultData[] memory vaultDatas_) {
        uint256 maxCombinations_ = tokensIn_.length * tokensOut_.length;

        VaultData[] memory allVaults_ = new VaultData[](maxCombinations_);

        address[] memory vaultAddresses_ = VAULT_RESOLVER.getAllVaultsAddresses();

        uint256 matches_;
        uint256 index_;

        IFluidVaultT1.ConstantViews memory constants_;
        for (uint256 vi; vi < vaultAddresses_.length; ++vi) {
            constants_ = IFluidVaultT1(vaultAddresses_[vi]).constantsView();

            index_ = 0;
            // for each vault, iterate over all possible input params token combinations
            for (uint256 i; i < tokensIn_.length; ++i) {
                for (uint256 j; j < tokensOut_.length; ++j) {
                    if (constants_.borrowToken == tokensIn_[i] && constants_.supplyToken == tokensOut_[j]) {
                        allVaults_[index_] = VaultData({
                            vault: vaultAddresses_[vi],
                            tokenIn: tokensIn_[i],
                            tokenOut: tokensOut_[j]
                        });
                        ++matches_;
                    }
                    ++index_;
                }
            }
        }

        vaultDatas_ = new VaultData[](matches_);
        index_ = 0;
        for (uint256 i; i < maxCombinations_; ++i) {
            if (allVaults_[i].vault != address(0)) {
                vaultDatas_[index_] = allVaults_[i];
                ++index_;
            }
        }
    }

    /// @notice finds the total available swappable amount for a `tokenIn_` to `tokenOut_` swap, considering both a swap
    ///         that uses liquidation with absorb and without absorb. Sometimes with absorb can provide better swaps,
    ///         sometimes without absorb can provide better swaps. But available liquidity for "withAbsorb" amounts will
    ///         always be >= normal amounts.
    /// @dev    returned data can be fed into `getSwapCalldata` to prepare the tx that executes the swap.
    /// @dev    expected to be called with callStatic, although this method does not do any actual state changes anyway.
    /// @dev    for native token, send 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE.
    function getSwapAvailable(address tokenIn_, address tokenOut_) public returns (SwapData memory swapData_) {
        return getSwapDataForVault(getVaultForSwap(tokenIn_, tokenOut_));
    }

    /// @notice finds the total available swappable amount for any `tokensIn_` to any `tokesnOut_` swap, considering both
    ///         a swap that uses liquidation with absorb and without absorb. Sometimes with absorb can provide better swaps,
    ///         sometimes without absorb can provide better swaps. But available liquidity for "withAbsorb" amounts will
    ///         always be >= normal amounts. Token pairs that are not available will not be listed in returned SwapData array.
    ///         e.g. for tokensIn_: USDC & USDT and tokensOut_: ETH & wstETH, this would return any available token pair incl.
    ///         the available swappable amounts, so for USDC -> ETH, USDC -> wstETH, USDT -> ETH, USDT -> wstETH.
    /// @dev    returned data can be fed into `getSwapCalldata` to prepare the tx that executes the swap.
    /// @dev    expected to be called with callStatic, although this method does not do any actual state changes anyway.
    /// @dev    for native token, send 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE.
    function getSwapsAvailable(
        address[] calldata tokensIn_,
        address[] calldata tokensOut_
    ) public returns (SwapData[] memory swapDatas_) {
        VaultData[] memory vaults_ = getVaultsForSwap(tokensIn_, tokensOut_);

        swapDatas_ = new SwapData[](vaults_.length);

        for (uint256 i; i < vaults_.length; ++i) {
            swapDatas_[i] = getSwapDataForVault(vaults_[i].vault);
        }
    }

    /// @notice returns the calldata to execute a swap as found through this contract by triggering a vault liquidation.
    ///         `tokenInAmt_` must come from msg.sender, `tokenOutAmt_` goes to `receiver_`. If the input token is the
    ///         native token, msg.value must be sent along when triggering the actual call with the returned calldata.
    /// @param vault_ vault address at which the liquidation is executed
    /// @param receiver_ receiver address that the output token is sent to
    /// @param tokenInAmt_ input token amount (debt token at vault)
    /// @param tokenOutAmt_ expected output token amount (collateral token at vault)
    /// @param slippage_ maximum allowed slippage for the expected output token amount. Reverts iIf received token out
    ///                   amount is lower than this. in 1e4 percentage, e.g. 1% = 10000, 0.3% = 3000, 0.01% = 100, 0.0001% = 1.
    /// @param withAbsorb_ set to true to trigger liquidation with executing `absorb()` first. Liquidity is >= when this
    ///                    is set to true. Rate can be better with or without, check before via other methods.
    /// @return calldata_ the calldata that can be used to trigger the liquidation call, resulting in the desired swap.
    function getSwapCalldata(
        address vault_,
        address receiver_,
        uint256 tokenInAmt_,
        uint256 tokenOutAmt_,
        uint256 slippage_,
        bool withAbsorb_
    ) public pure returns (bytes memory calldata_) {
        if (vault_ == address(0) || receiver_ == address(0)) {
            revert FluidVaultLiquidationsResolver__AddressZero();
        }
        if (slippage_ >= 1e6 || tokenInAmt_ == 0 || tokenOutAmt_ == 0) {
            revert FluidVaultLiquidationsResolver__InvalidParams();
        }

        uint256 colPerUnitDebt_ = (tokenOutAmt_ * 1e18) / tokenInAmt_;
        colPerUnitDebt_ = (colPerUnitDebt_ * (1e6 - slippage_)) / 1e6; // e.g. 50 * 99% / 100% = 49.5

        calldata_ = abi.encodeWithSelector(
            IFluidVaultT1(vault_).liquidate.selector,
            tokenInAmt_,
            colPerUnitDebt_,
            receiver_,
            withAbsorb_
        );
    }

    /// @notice returns the available swap (liquidation) amounts at a certain `vault_`, considering both
    ///         a swap that uses liquidation with absorb and without absorb. Sometimes with absorb can provide better swaps,
    ///         sometimes without absorb can provide better swaps. But available liquidity for "withAbsorb" amounts will
    ///         always be >= normal amounts.
    /// @dev    returned data can be fed into `getSwapCalldata` to prepare the tx that executes the swap.
    /// @dev    expected to be called with callStatic, although this method does not do any actual state changes anyway.
    function getSwapDataForVault(address vault_) public returns (SwapData memory swapData_) {
        if (vault_ == address(0)) {
            return swapData_;
        }

        VaultResolverStructs.LiquidationStruct memory liquidationData_ = VAULT_RESOLVER.getVaultLiquidation(vault_, 0);
        swapData_.vault = vault_;
        swapData_.inAmt = liquidationData_.tokenInAmtOne;
        swapData_.outAmt = liquidationData_.tokenOutAmtOne;
        swapData_.inAmtWithAbsorb = liquidationData_.tokenInAmtTwo;
        swapData_.outAmtWithAbsorb = liquidationData_.tokenOutAmtTwo;
    }

    /// @notice finds a swap from `tokenIn_` to `tokenOut_` for an exact input amount `inAmt_`. If available amount is
    ///         less then the desired input amount, it returns the available amount. Considers the best rate available
    ///         for mode with absorb and mode without absorb.
    /// @dev    returned data can be fed into `getSwapCalldata` to prepare the tx that executes the swap.
    /// @param tokenIn_ input token (debt token at vault)
    /// @param tokenOut_ output token (collateral token at vault)
    /// @param inAmt_ exact input token amount that should be swapped to output token
    /// @return vault_ vault address at which the swap is available.
    /// @return actualInAmt_ actual input token amount. Equals `inAmt_`, but if less then the desired swap amount is
    ///                      available, then the available amount is returned instead.
    /// @return outAmt_ received output token amount for `actualInAmt_` of input token
    /// @return withAbsorb_ flag for using mode "withAbsorb". Is set to true if a) liquidity without absorb would not
    ///                     cover the desired `inAmt_` or if b) the rate of with absorb is better than without absorb.
    function exactInput(
        address tokenIn_,
        address tokenOut_,
        uint256 inAmt_
    ) public returns (address vault_, uint256 actualInAmt_, uint256 outAmt_, bool withAbsorb_) {
        SwapData memory swapData_ = getSwapAvailable(tokenIn_, tokenOut_);
        vault_ = swapData_.vault;

        actualInAmt_ = inAmt_; // assume inAmt_ can be covered by available amount, var is updated otherwise

        uint256 withAbsorbRatio_ = (swapData_.outAmtWithAbsorb * 1e27) / swapData_.inAmtWithAbsorb;
        if (inAmt_ > swapData_.inAmt && swapData_.inAmtWithAbsorb > swapData_.inAmt) {
             // with absorb has more liquidity 
            withAbsorb_ = true;
            if (inAmt_ > swapData_.inAmtWithAbsorb) {
                actualInAmt_ = swapData_.inAmtWithAbsorb; // can not cover full requested inAmt_, so set to available
                outAmt_ = swapData_.outAmtWithAbsorb;
            } else {
                // inAmt_ fully covered by with absorb liquidation, get out amount
                outAmt_ = (inAmt_ * withAbsorbRatio_) / 1e27;
            }
        } else {
            // inAmt_ is covered by available liquidation with or without absorb, check which one has better ratio
            uint256 withoutAbsorbRatio_ = (swapData_.outAmt * 1e27) / swapData_.inAmt;
            if (withAbsorbRatio_ > withoutAbsorbRatio_) {
                withAbsorb_ = true;
                outAmt_ = (inAmt_ * withAbsorbRatio_) / 1e27;
            } else {
                outAmt_ = (inAmt_ * withoutAbsorbRatio_) / 1e27;
            }
        }
    }

    /// @notice finds a swap from `tokenIn_` to `tokenOut_` for an exact output amount `outAmt_`. If available amount is
    ///         less then the desired output amount, it returns the available amount. Considers the best rate available
    ///         for mode with absorb and mode without absorb.
    /// @dev    returned data can be fed into `getSwapCalldata` to prepare the tx that executes the swap.
    /// @param tokenIn_ input token (debt token at vault)
    /// @param tokenOut_ output token (collateral token at vault)
    /// @param outAmt_ exact output token amount that should be received as a result of the swap
    /// @return vault_ vault address at which the swap is available.
    /// @return inAmt_ required input token amount to receive `actualOutAmt_` of output token
    /// @return actualOutAmt_ actual output token amount. Equals `outAmt_`, but if less then the desired swap amount is
    ///                      available, then the available amount is returned instead
    /// @return withAbsorb_ flag for using mode "withAbsorb". Is set to true if a) liquidity without absorb would not
    ///                     cover the desired `outAmt_` or if b) the rate of with absorb is better than without absorb.
    function exactOutput(
        address tokenIn_,
        address tokenOut_,
        uint256 outAmt_
    ) public returns (address vault_, uint256 inAmt_, uint256 actualOutAmt_, bool withAbsorb_) {
        SwapData memory swapData_ = getSwapAvailable(tokenIn_, tokenOut_);
        vault_ = swapData_.vault;

        actualOutAmt_ = outAmt_; // assume outAmt_ can be covered by available amount, var is updated otherwise

        uint256 withAbsorbRatio_ = (swapData_.inAmtWithAbsorb * 1e27) / swapData_.outAmtWithAbsorb;
        if (outAmt_ > swapData_.outAmt && swapData_.inAmtWithAbsorb > swapData_.inAmt) {
             // with absorb has more liquidity 
            withAbsorb_ = true;
            if (outAmt_ > swapData_.outAmtWithAbsorb) {
                actualOutAmt_ = swapData_.outAmtWithAbsorb; // can not cover full requested inAmt_, so set to available
                inAmt_ = swapData_.inAmtWithAbsorb;
            } else {
                // outAmt_ fully covered by with absorb liquidation, get in amount
                inAmt_ = (outAmt_ * withAbsorbRatio_) / 1e27;
            }
        } else {
            // outAmt_ is covered by available liquidation with or without absorb, check which one has better ratio
            uint256 withoutAbsorbRatio_ = (swapData_.inAmt * 1e27) / swapData_.outAmt; // in per out
            if (withAbsorbRatio_ < withoutAbsorbRatio_) {
                withAbsorb_ = true;
                inAmt_ = (outAmt_ * withAbsorbRatio_) / 1e27;
            } else {
                inAmt_ = (outAmt_ * withoutAbsorbRatio_) / 1e27;
            }
        }
    }
}
