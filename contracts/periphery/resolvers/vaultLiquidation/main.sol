// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { Variables } from "./variables.sol";
import { Structs } from "./structs.sol";
import { FluidProtocolTypes } from "../../../libraries/fluidProtocolTypes.sol";
import { Structs as VaultResolverStructs } from "../vault/structs.sol";
import { IFluidVaultResolver } from "../vault/iVaultResolver.sol";
import { IFluidVaultT1 } from "../../../protocols/vault/interfaces/iVaultT1.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";

interface TokenInterface {
    function balanceOf(address) external view returns (uint);
}

/// @notice Resolver contract that helps in finding available token (liquidation) swaps available in Fluid VaultT1s.
/// @dev    Note that on the same protocol, if "withAbsorb = true" is executed, this also consumes the swap
///         that would be on the same protocol with "withAbsorb = false". So the total available swap amount
///         at a protocol if both a swap with and without absorb is available is not `with inAmt + without inAmt`
///         but rather `with inAmt`.
///         Sometimes with absorb can provide better swaps, sometimes without absorb can provide better swaps.
///         But available liquidity for "withAbsorb" amounts will always be >= without absorb amounts.
/// @dev    The "Raw" methods return both the with and without absorb swaps for the same Fluid Vault, the non-"Raw"
///         methods automatically filter by the better ratio swap. For same cases a better optimization of ratios
///         is possible with custom logic based on the "Raw" methods, see details in comments.
/// @dev    for native token, send 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE.
/// @dev    returned swaps Struct can be fed into `getSwapTx` to prepare the tx that executes the swaps.
/// @dev    non-view methods in this contract are expected to be called with callStatic,
///         although they would anyway not do any actual state changes.
contract FluidVaultLiquidationResolver is Variables, Structs {
    /// @notice thrown if an input param address is zero
    error FluidVaultLiquidationsResolver__AddressZero();
    /// @notice thrown if an invalid param is given to a method
    error FluidVaultLiquidationsResolver__InvalidParams();

    /// @notice constructor sets the immutable vault resolver address
    constructor(IFluidVaultResolver vaultResolver_, IFluidLiquidity liquidity_) Variables(vaultResolver_, liquidity_) {
        if (address(vaultResolver_) == address(0) || address(liquidity_) == address(0)) {
            revert FluidVaultLiquidationsResolver__AddressZero();
        }
    }

    /// @notice returns all available token swap paths
    function getAllSwapPaths() public view returns (SwapPath[] memory paths_) {
        address[] memory vaultAddresses_ = _getVaultT1s();
        paths_ = new SwapPath[](vaultAddresses_.length);

        address borrowToken_;
        address supplyToken_;
        for (uint256 i; i < vaultAddresses_.length; ++i) {
            (borrowToken_, supplyToken_) = _getVaultTokens(vaultAddresses_[i]);
            paths_[i] = SwapPath({ protocol: vaultAddresses_[i], tokenIn: borrowToken_, tokenOut: supplyToken_ });
        }
    }

    /// @notice returns all swap paths for a certain `tokenIn_` swapped to a `tokenOut_`.
    ///         returns empty array if no swap path is available for a given pair.
    function getSwapPaths(address tokenIn_, address tokenOut_) public view returns (SwapPath[] memory paths_) {
        address[] memory vaultAddresses_ = _getVaultT1s();

        uint256 foundVaultsCount_;
        address[] memory foundVaults_ = new address[](vaultAddresses_.length);

        address borrowToken_;
        address supplyToken_;
        for (uint256 i; i < vaultAddresses_.length; ++i) {
            (borrowToken_, supplyToken_) = _getVaultTokens(vaultAddresses_[i]);

            if (borrowToken_ == tokenIn_ && supplyToken_ == tokenOut_) {
                foundVaults_[foundVaultsCount_] = vaultAddresses_[i];
                ++foundVaultsCount_;
            }
        }

        paths_ = new SwapPath[](foundVaultsCount_);
        for (uint256 i; i < foundVaultsCount_; ++i) {
            paths_[i] = SwapPath({ protocol: foundVaults_[i], tokenIn: tokenIn_, tokenOut: tokenOut_ });
        }
    }

    /// @notice returns all available swap paths for any `tokensIn_` to any `tokensOut_`.
    function getAnySwapPaths(
        address[] calldata tokensIn_,
        address[] calldata tokensOut_
    ) public view returns (SwapPath[] memory paths_) {
        SwapPath[] memory maxPaths_ = new SwapPath[](tokensIn_.length * tokensOut_.length);

        address[] memory vaultAddresses_ = _getVaultT1s();

        uint256 matches_;

        address borrowToken_;
        address supplyToken_;
        unchecked {
            for (uint256 vi; vi < vaultAddresses_.length; ++vi) {
                (borrowToken_, supplyToken_) = _getVaultTokens(vaultAddresses_[vi]);

                // for each vault, iterate over all possible input params token combinations
                for (uint256 i; i < tokensIn_.length; ++i) {
                    for (uint256 j; j < tokensOut_.length; ++j) {
                        if (borrowToken_ == tokensIn_[i] && supplyToken_ == tokensOut_[j]) {
                            maxPaths_[matches_] = SwapPath({
                                protocol: vaultAddresses_[vi],
                                tokenIn: borrowToken_,
                                tokenOut: supplyToken_
                            });
                            ++matches_;
                        }
                    }
                }
            }

            paths_ = new SwapPath[](matches_);
            for (uint256 i; i < matches_; ++i) {
                paths_[i] = maxPaths_[i];
            }
        }
    }

    /// @notice returns the swap data for with and without absorb for a Fluid `vault_`.
    function getVaultSwapData(
        address vault_
    ) public returns (SwapData memory withoutAbsorb_, SwapData memory withAbsorb_) {
        VaultResolverStructs.LiquidationStruct memory liquidationData_ = VAULT_RESOLVER.getVaultLiquidation(vault_, 0);

        withoutAbsorb_ = SwapData({
            inAmt: liquidationData_.inAmt,
            outAmt: liquidationData_.outAmt,
            withAbsorb: false,
            ratio: _calcRatio(liquidationData_.inAmt, liquidationData_.outAmt)
        });

        withAbsorb_ = SwapData({
            inAmt: liquidationData_.inAmtWithAbsorb,
            outAmt: liquidationData_.outAmtWithAbsorb,
            withAbsorb: true,
            ratio: _calcRatio(liquidationData_.inAmtWithAbsorb, liquidationData_.outAmtWithAbsorb)
        });
    }

    /// @notice returns the swap data for with and without absorb for multiple Fluid `vaults_`.
    function getVaultsSwapData(
        address[] memory vaults_
    ) public returns (SwapData[] memory withoutAbsorb_, SwapData[] memory withAbsorb_) {
        withoutAbsorb_ = new SwapData[](vaults_.length);
        withAbsorb_ = new SwapData[](vaults_.length);
        for (uint256 i; i < vaults_.length; ++i) {
            (withoutAbsorb_[i], withAbsorb_[i]) = getVaultSwapData(vaults_[i]);
        }
    }

    /// @notice returns the swap data for with and without absorb for all Fluid vaults.
    function getAllVaultsSwapData() public returns (SwapData[] memory withoutAbsorb_, SwapData[] memory withAbsorb_) {
        return getVaultsSwapData(_getVaultT1s());
    }

    /// @notice returns the available swap amounts at a certain `protocol_`. Only returns non-zero swaps.
    ///         For vault protocol considering both a swap that uses liquidation with absorb and without absorb.
    function getSwapForProtocol(address protocol_) public returns (Swap memory swap_) {
        if (protocol_ == address(0)) {
            return swap_;
        }

        (address borrowToken_, address supplyToken_) = _getVaultTokens(protocol_);
        (SwapData memory withoutAbsorb_, SwapData memory withAbsorb_) = getVaultSwapData(protocol_);

        swap_ = _getSwapAccountingForWithdrawable(
            Swap({
                path: SwapPath({ protocol: protocol_, tokenIn: borrowToken_, tokenOut: supplyToken_ }),
                data: _getBetterRatioSwapData(withoutAbsorb_, withAbsorb_)
            }),
            withAbsorb_.outAmt == 0 ? 0 : _getVaultT1Withdrawable(protocol_, supplyToken_)
        );
    }

    /// @notice returns all available `swaps_` for multiple Fluid `vaults_` raw. Only returns non-zero swaps.
    ///         includes all swaps unfiltered, e.g. with absorb and without absorb swaps are present for the same vault.
    function getVaultsSwapRaw(address[] memory vaults_) public returns (Swap[] memory swaps_) {
        unchecked {
            uint256 nonZeroSwaps_;
            Swap[] memory allSwaps_ = new Swap[](vaults_.length * 2);

            SwapData memory withoutAbsorb_;
            SwapData memory withAbsorb_;
            address borrowToken_;
            address supplyToken_;
            uint256 withdrawable_;
            for (uint256 i; i < vaults_.length; ++i) {
                (withoutAbsorb_, withAbsorb_) = getVaultSwapData(vaults_[i]);
                if (withAbsorb_.inAmt == 0) {
                    // if with absorb is 0, then without absorb can only be 0 too
                    continue;
                }
                (borrowToken_, supplyToken_) = _getVaultTokens(vaults_[i]);
                withdrawable_ = _getVaultT1Withdrawable(vaults_[i], supplyToken_);
                if (withdrawable_ == 0) {
                    continue;
                }
                ++nonZeroSwaps_;
                if (withAbsorb_.inAmt == withoutAbsorb_.inAmt) {
                    // with absorb has the same liquidity as without absorb.
                    // running liquidate() with absorb in that case only costs extra gas. return only without absorb swap
                    withAbsorb_.inAmt = 0;
                } else if (withoutAbsorb_.inAmt > 0) {
                    // both with and without absorb swaps
                    ++nonZeroSwaps_;
                }

                allSwaps_[i * 2] = _getSwapAccountingForWithdrawable(
                    Swap({
                        path: SwapPath({ protocol: vaults_[i], tokenIn: borrowToken_, tokenOut: supplyToken_ }),
                        data: withoutAbsorb_
                    }),
                    withdrawable_
                );
                allSwaps_[i * 2 + 1] = _getSwapAccountingForWithdrawable(
                    Swap({
                        path: SwapPath({ protocol: vaults_[i], tokenIn: borrowToken_, tokenOut: supplyToken_ }),
                        data: withAbsorb_
                    }),
                    withdrawable_
                );
            }

            return _getNonZeroSwaps(allSwaps_, nonZeroSwaps_);
        }
    }

    /// @notice returns all available `swaps_` for all Fluid vaults raw. Only returns non-zero swaps.
    ///         includes all swaps unfiltered, e.g. with absorb and without absorb swaps are present for the same vault.
    function getAllVaultsSwapRaw() public returns (Swap[] memory swaps_) {
        return getVaultsSwapRaw(_getVaultT1s());
    }

    /// @notice returns all the available `swaps_` for certain swap `paths_`. Only returns non-zero swaps.
    ///         includes all swaps unfiltered, e.g. with absorb and without absorb swaps are present for the same vault.
    function getSwapsForPathsRaw(SwapPath[] memory paths_) public returns (Swap[] memory swaps_) {
        unchecked {
            Swap[] memory allSwaps_ = new Swap[](paths_.length * 2);

            uint256 nonZeroSwaps_;
            SwapData memory withoutAbsorb_;
            SwapData memory withAbsorb_;
            uint256 withdrawable_;
            for (uint256 i; i < paths_.length; ++i) {
                (withoutAbsorb_, withAbsorb_) = getVaultSwapData(paths_[i].protocol);

                if (withAbsorb_.inAmt == 0) {
                    // if with absorb is 0, then without absorb can only be 0 too
                    continue;
                }
                withdrawable_ = _getVaultT1Withdrawable(paths_[i].protocol, paths_[i].tokenOut);
                if (withdrawable_ == 0) {
                    continue;
                }
                ++nonZeroSwaps_;
                if (withAbsorb_.inAmt == withoutAbsorb_.inAmt) {
                    // with absorb has the same liquidity as without absorb.
                    // running liquidate() with absorb in that case only costs extra gas. return only without absorb swap
                    withAbsorb_.inAmt = 0;
                } else if (withoutAbsorb_.inAmt > 0) {
                    // both with and without absorb swaps
                    ++nonZeroSwaps_;
                }

                allSwaps_[i * 2] = _getSwapAccountingForWithdrawable(
                    Swap({ path: paths_[i], data: withoutAbsorb_ }),
                    withdrawable_
                );

                allSwaps_[i * 2 + 1] = _getSwapAccountingForWithdrawable(
                    Swap({ path: paths_[i], data: withAbsorb_ }),
                    withdrawable_
                );
            }

            swaps_ = new Swap[](nonZeroSwaps_);
            uint256 index_;
            for (uint256 i; i < allSwaps_.length; ++i) {
                if (allSwaps_[i].data.inAmt > 0) {
                    swaps_[index_] = allSwaps_[i];
                    ++index_;
                }
            }
        }
    }

    /// @notice finds all available `swaps_` for `tokenIn_` to `tokenOut_`.
    ///         includes all swaps unfiltered, e.g. with absorb and without absorb swaps are present for the same vault.
    function getSwapsRaw(address tokenIn_, address tokenOut_) public returns (Swap[] memory swaps_) {
        return getSwapsForPathsRaw(getSwapPaths(tokenIn_, tokenOut_));
    }

    /// @notice finds all available `swaps_` for any `tokensIn_` to any `tokesnOut_`.
    ///         Token pairs that are not available or where available swap amounts are zero
    ///         will not be present in the returned `swaps_` array.
    ///         includes all swaps unfiltered, e.g. with absorb and without absorb swaps are present for the same vault.
    function getAnySwapsRaw(
        address[] calldata tokensIn_,
        address[] calldata tokensOut_
    ) public returns (Swap[] memory swaps_) {
        return getSwapsForPathsRaw(getAnySwapPaths(tokensIn_, tokensOut_));
    }

    /// @notice returns all available `swaps_` for multiple Fluid `vaults_`. Only returns non-zero swaps.
    ///         returns only either the with absorb swap or without absorb swap for each vault, whichever has the
    ///         better ratio.
    function getVaultsSwap(address[] memory vaults_) public returns (Swap[] memory swaps_) {
        unchecked {
            uint256 nonZeroSwaps_;
            Swap[] memory allSwaps_ = new Swap[](vaults_.length);

            SwapData memory withoutAbsorb_;
            SwapData memory withAbsorb_;
            Swap memory swap_;
            uint256 withdrawable_;
            for (uint256 i; i < vaults_.length; ++i) {
                (withoutAbsorb_, withAbsorb_) = getVaultSwapData(vaults_[i]);
                swap_ = Swap({
                    path: SwapPath({ protocol: vaults_[i], tokenIn: address(0), tokenOut: address(0) }),
                    data: _getBetterRatioSwapData(withoutAbsorb_, withAbsorb_)
                });

                if (swap_.data.inAmt == 0) {
                    // no swap available on this vault
                    continue;
                }
                (swap_.path.tokenIn, swap_.path.tokenOut) = _getVaultTokens(vaults_[i]);
                withdrawable_ = _getVaultT1Withdrawable(swap_.path.protocol, swap_.path.tokenOut);
                if (withdrawable_ == 0) {
                    continue;
                }

                ++nonZeroSwaps_;

                allSwaps_[i] = _getSwapAccountingForWithdrawable(swap_, withdrawable_);
            }

            return _getNonZeroSwaps(allSwaps_, nonZeroSwaps_);
        }
    }

    /// @notice returns all available `swaps_` for all Fluid vaults. Only returns non-zero swaps.
    ///         returns only either the with absorb swap or without absorb swap for each vault, whichever has the
    ///         better ratio.
    function getAllVaultsSwap() public returns (Swap[] memory swaps_) {
        return getVaultsSwap(_getVaultT1s());
    }

    /// @notice returns all the available `swaps_` for certain swap `paths_`. Only returns non-zero swaps.
    ///         returns only either the with absorb swap or without absorb swap for each vault, whichever has the
    ///         better ratio.
    function getSwapsForPaths(SwapPath[] memory paths_) public returns (Swap[] memory swaps_) {
        unchecked {
            Swap[] memory allSwaps_ = new Swap[](paths_.length);

            uint256 nonZeroSwaps_;
            Swap memory swap_;
            SwapData memory withoutAbsorb_;
            SwapData memory withAbsorb_;
            uint256 withdrawable_;
            for (uint256 i; i < paths_.length; ++i) {
                (withoutAbsorb_, withAbsorb_) = getVaultSwapData(paths_[i].protocol);
                swap_ = Swap({ path: paths_[i], data: _getBetterRatioSwapData(withoutAbsorb_, withAbsorb_) });

                if (swap_.data.inAmt == 0) {
                    // no swap available on this vault
                    continue;
                }
                withdrawable_ = _getVaultT1Withdrawable(swap_.path.protocol, swap_.path.tokenOut);
                if (withdrawable_ == 0) {
                    continue;
                }

                ++nonZeroSwaps_;

                allSwaps_[i] = _getSwapAccountingForWithdrawable(swap_, withdrawable_);
            }

            return _getNonZeroSwaps(allSwaps_, nonZeroSwaps_);
        }
    }

    /// @notice finds all available `swaps_` for `tokenIn_` to `tokenOut_`.
    ///         returns only either the with absorb swap or without absorb swap for each vault, whichever has the
    ///         better ratio.
    function getSwaps(address tokenIn_, address tokenOut_) public returns (Swap[] memory swaps_) {
        return getSwapsForPaths(getSwapPaths(tokenIn_, tokenOut_));
    }

    /// @notice finds all available `swaps_` for any `tokensIn_` to any `tokesnOut_`.
    ///         Token pairs that are not available or where available swap amounts are zero
    ///         will not be present in the returned `swaps_` array.
    ///         returns only either the with absorb swap or without absorb swap for each vault, whichever has the
    ///         better ratio.
    function getAnySwaps(
        address[] calldata tokensIn_,
        address[] calldata tokensOut_
    ) public returns (Swap[] memory swaps_) {
        return getSwapsForPaths(getAnySwapPaths(tokensIn_, tokensOut_));
    }

    /// @notice returns the calldata to execute a swap as returned by the other methods in this contract.
    ///         `swap_.data.inAmt` must come from msg.sender, `swap_.data.outAmt` goes to `receiver_`. If the input token
    ///         is the native token, msg.value must be sent along when triggering the actual call with the returned calldata
    ///         which should be `swap_.data.inAmt`.
    /// @param swap_ Swap struct as returned by other methods
    /// @param receiver_ receiver address that the output token is sent to
    /// @param slippage_ maximum allowed slippage for the expected output token amount. Reverts iIf received token out
    ///                  amount is lower than this. in 1e4 percentage, e.g. 1% = 10000, 0.3% = 3000, 0.01% = 100, 0.0001% = 1.
    /// @return target_ target address where `calldata_` must be executed
    /// @return calldata_ the calldata that can be used to trigger the liquidation call, resulting in the desired swap.
    function getSwapTx(
        Swap calldata swap_,
        address receiver_,
        uint256 slippage_
    ) public pure returns (address target_, bytes memory calldata_) {
        if (swap_.path.protocol == address(0) || receiver_ == address(0)) {
            revert FluidVaultLiquidationsResolver__AddressZero();
        }
        if (slippage_ >= 1e6 || swap_.data.inAmt == 0 || swap_.data.outAmt == 0) {
            revert FluidVaultLiquidationsResolver__InvalidParams();
        }

        uint256 colPerUnitDebt_ = (swap_.data.outAmt * 1e18) / swap_.data.inAmt;
        colPerUnitDebt_ = (colPerUnitDebt_ * (1e6 - slippage_)) / 1e6; // e.g. 50 * 99% / 100% = 49.5

        calldata_ = abi.encodeWithSelector(
            IFluidVaultT1(swap_.path.protocol).liquidate.selector,
            swap_.data.inAmt,
            colPerUnitDebt_,
            receiver_,
            swap_.data.withAbsorb
        );
        target_ = swap_.path.protocol;
    }

    /// @notice returns the same data as `getSwapTx` for an array of input `swaps_` at once.
    function getSwapTxs(
        Swap[] calldata swaps_,
        address receiver_,
        uint256 slippage_
    ) public pure returns (address[] memory targets_, bytes[] memory calldatas_) {
        targets_ = new address[](swaps_.length);
        calldatas_ = new bytes[](swaps_.length);
        for (uint256 i; i < swaps_.length; ++i) {
            (targets_[i], calldatas_[i]) = getSwapTx(swaps_[i], receiver_, slippage_);
        }
    }

    /// @notice finds all swaps from `tokenIn_` to `tokenOut_` for an exact input amount `inAmt_`.
    ///         filters the available swaps and sorts them by ratio, so the returned swaps are the best available
    ///         swaps to reach the target `inAmt_`.
    ///         If the full available amount is less than the target `inAmt_`, the available amount is returned as `actualInAmt_`.
    /// @dev The only cases that are currently not best possible optimized for are when the ratio for withoutAbsorb is better
    /// but the target swap amount is more than the available without absorb liquidity. For this, currently the available
    /// withAbsorb liquidity is consumed first before tapping into the better ratio withoutAbsorb liquidity.
    /// The optimized version would be to split the tx into two swaps, first executing liquidate() with absorb = false
    /// to fully swap all the withoutAbsorb liquidity, and then in the second tx run with absorb = true to fill the missing
    /// amount up to the target amount with the worse ratio with absorb liquidity.
    /// @param tokenIn_ input token
    /// @param tokenOut_ output token
    /// @param inAmt_ exact input token amount that should be swapped to output token
    /// @return swaps_ swaps to reach the target amount, sorted by ratio in descending order
    ///         (higher ratio = better rate). Best ratio swap will be at pos 0, second best at pos 1 and so on.
    /// @return actualInAmt_ actual input token amount. Can be less than inAmt_ if all available swaps can not cover
    ///                      the target amount.
    /// @return outAmt_ output token amount received for `actualInAmt_`
    function exactInput(
        address tokenIn_,
        address tokenOut_,
        uint256 inAmt_
    ) public returns (Swap[] memory swaps_, uint256 actualInAmt_, uint256 outAmt_) {
        return filterToTargetInAmt(getSwapsRaw(tokenIn_, tokenOut_), inAmt_);
    }

    /// @notice finds all swaps from `tokenIn_` to `tokenOut_` for an APPROXIMATE output amount `outAmt_`.
    ///         filters the available swaps and sorts them by ratio, so the returned swaps are the best available
    ///         swaps to reach the target `outAmt_`.
    ///         If the full available amount is less than the target `outAmt_`, the available amount is returned as `actualOutAmt_`.
    ///         IMPORTANT: guaranteed exact output swaps are not possible with Fluid, this method only aims to
    ///         approximately estimate the required input amounts to reach a certain output amount. This
    ///         will change until execution and should be controlled with a maximum slippage.
    ///         Recommended to use exact input methods instead.
    /// @dev The only cases that are currently not best possible optimized for are when the ratio for withoutAbsorb is better
    /// but the target swap amount is more than the available without absorb liquidity. For this currently the available
    /// withAbsorb liquidity is consumed first before tapping into the better ratio withoutAbsorb liquidity.
    /// The optimized version would be to split the tx into two swaps, first executing liquidate() with absorb = false
    /// to fully swap all the withoutAbsorb liquidity, and then in the second tx run with absorb = true to fill the missing
    /// amount up to the target amount with the worse ratio with absorb liquidity.
    /// @param tokenIn_ input token
    /// @param tokenOut_ output token
    /// @param outAmt_ exact output token amount that should be swapped to from input token
    /// @return swaps_ swaps to reach the target amount, sorted by ratio in descending order
    ///         (higher ratio = better rate). Best ratio swap will be at pos 0, second best at pos 1 and so on.
    /// @return inAmt_ input token amount needed to receive `actualOutAmt_`
    /// @return approxOutAmt_ approximate output token amount. Can be less than `outAmt_` if all available swaps can not cover
    ///                       the target amount.
    function approxOutput(
        address tokenIn_,
        address tokenOut_,
        uint256 outAmt_
    ) public returns (Swap[] memory swaps_, uint256 inAmt_, uint256 approxOutAmt_) {
        return filterToApproxOutAmt(getSwapsRaw(tokenIn_, tokenOut_), outAmt_);
    }

    /// @notice filters the `swaps_` to the point where `targetInAmt_` is reached.
    ///         This is best used in combination with the "Raw" methods, as the `targetInAmt_` allows for more optimized
    ///         filtering than otherwise done with the non-"Raw" methods.
    /// @return filteredSwaps_ swaps to reach the target amount, sorted by ratio in descending order
    ///         (higher ratio = better rate). Best ratio swap will be at pos 0, second best at pos 1 and so on.
    /// @return actualInAmt_ actual input amount. Can be less than targetInAmt_ if all available swaps can not cover
    ///                      the target amount.
    /// @return approxOutAmt_ actual estimated output amount.
    function filterToTargetInAmt(
        Swap[] memory swaps_,
        uint256 targetInAmt_
    ) public returns (Swap[] memory filteredSwaps_, uint256 actualInAmt_, uint256 approxOutAmt_) {
        return _filterToTarget(swaps_, targetInAmt_, type(uint256).max);
    }

    /// @notice filters the `swaps_` to the point where APPROXIMATELY `targetOutAmt_` is reached.
    ///         IMPORTANT: guaranteed exact output swaps are not possible with Fluid, this method only aims to
    ///         approximately estimate the required input amounts to reach a certain output amount. This
    ///         will change until execution and should be controlled with a maximum slippage.
    ///         Recommended to use exact input methods instead.
    ///         This is best used in combination with the "Raw" methods, as the `targetInAmt_` allows for more optimized
    ///         filtering than otherwise done with the non-"Raw" methods.
    /// @return filteredSwaps_ swaps to reach the target amount, sorted by ratio in descending order
    ///         (higher ratio = better rate). Best ratio swap will be at pos 0, second best at pos 1 and so on.
    /// @return actualInAmt_ actual input amount.
    /// @return approxOutAmt_ APPROXIMATE actual output amount. Can be less than targetOutAmt_ if all available swaps
    ///                      can not cover the target amount.
    function filterToApproxOutAmt(
        Swap[] memory swaps_,
        uint256 targetApproxOutAmt_
    ) public returns (Swap[] memory filteredSwaps_, uint256 actualInAmt_, uint256 approxOutAmt_) {
        return _filterToTarget(swaps_, type(uint256).max, targetApproxOutAmt_);
    }

    function _getUserSupplyData(address user_, address token_) internal view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
                    user_,
                    token_
                )
            );
    }

    function _getExchangePricesAndConfig(address token_) internal view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                    token_
                )
            );
    }

    /// @dev get withdrawable amount at a certain T1 vault, which limits liquidations. Incl. balance check at Liquidity
    function _getVaultT1Withdrawable(address vault_, address token_) internal view returns (uint256 withdrawable_) {
        uint256 userSupplyData_ = _getUserSupplyData(vault_, token_);

        if (userSupplyData_ == 0) {
            return 0;
        }

        uint256 userSupply_ = BigMathMinified.fromBigNumber(
            (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & LiquidityCalcs.X64,
            LiquidityCalcs.DEFAULT_EXPONENT_SIZE,
            LiquidityCalcs.DEFAULT_EXPONENT_MASK
        );

        // get updated expanded withdrawal limit
        uint256 withdrawalLimit_ = LiquidityCalcs.calcWithdrawalLimitBeforeOperate(userSupplyData_, userSupply_);

        if (userSupplyData_ & 1 == 1) {
            uint256 exchangePricesAndConfig_ = _getExchangePricesAndConfig(token_);
            if (exchangePricesAndConfig_ == 0) {
                return 0;
            }
            (uint256 supplyExchangePrice_, ) = LiquidityCalcs.calcExchangePrices(exchangePricesAndConfig_);
            // convert raw amounts to normal for withInterest mode
            userSupply_ = (userSupply_ * supplyExchangePrice_) / EXCHANGE_PRICES_PRECISION;
            withdrawalLimit_ = (withdrawalLimit_ * supplyExchangePrice_) / EXCHANGE_PRICES_PRECISION;
        }

        withdrawable_ = userSupply_ > withdrawalLimit_ ? userSupply_ - withdrawalLimit_ : 0;
        uint256 balanceOf_ = token_ == NATIVE_TOKEN_ADDRESS
            ? address(LIQUIDITY).balance
            : TokenInterface(token_).balanceOf(address(LIQUIDITY));

        withdrawable_ = balanceOf_ > withdrawable_ ? withdrawable_ : balanceOf_;
    }

    /// @dev limits a Swap liquidatable amount according to actually col side withdrawable amount
    function _getSwapAccountingForWithdrawable(
        Swap memory swap_,
        uint256 withdrawable_
    ) internal pure returns (Swap memory) {
        if (swap_.data.outAmt == 0) {
            return swap_;
        }

        if (withdrawable_ < swap_.data.outAmt) {
            // reduce swap in and out amount to max withdrawable
            swap_.data.inAmt = (swap_.data.inAmt * withdrawable_) / swap_.data.outAmt;
            swap_.data.outAmt = withdrawable_;
        }

        return swap_;
    }

    /// @dev filters the `swaps_` to the point where either `targetInAmt_` or `targetOutAmt_` is reached.
    ///         To filter only by in or only by out amount, send `type(uint256).max` for the other param.
    /// @return filteredSwaps_ swaps to reach the target amount, sorted by ratio in descending order
    ///         (higher ratio = better rate). Best ratio swap will be at pos 0, second best at pos 1 and so on.
    /// @return actualInAmt_ actual input amount. Can be less than targetInAmt_ if all available swaps can not cover
    ///                      the target amount.
    /// @return actualOutAmt_ actual output amount. Can be less than targetOutAmt_ if all available swaps can not cover
    ///                      the target amount.
    function _filterToTarget(
        Swap[] memory swaps_,
        uint256 targetInAmt_,
        uint256 targetOutAmt_
    ) internal returns (Swap[] memory filteredSwaps_, uint256 actualInAmt_, uint256 actualOutAmt_) {
        swaps_ = _sortByRatio(swaps_);
        (filteredSwaps_, actualInAmt_, actualOutAmt_) = _filterSwapsUntilTarget(swaps_, targetInAmt_, targetOutAmt_);

        if (actualInAmt_ > targetInAmt_ || actualOutAmt_ > targetOutAmt_) {
            // reduce last swap in amt to match target in amt
            uint256 lastSwapIndex_ = filteredSwaps_.length - 1;

            uint256 missingInAmt_;
            if (actualInAmt_ > targetInAmt_) {
                // swaps_[i].data.inAmt is causing that we over reach targetInAmt_
                // so to get missing account from here until targetInAmt_, we only want
                // swaps_[i].data.inAmt minus whatever is too much (actualInAmt_ - targetInAmt_)
                missingInAmt_ = filteredSwaps_[lastSwapIndex_].data.inAmt + 1 - (actualInAmt_ - targetInAmt_);
            } else {
                // get missing in amt to use for liquidation call input param based on missing out amt and ratio
                uint256 missingOutAmt_ = filteredSwaps_[lastSwapIndex_].data.outAmt - (actualOutAmt_ - targetOutAmt_);

                // get total available liquidation and the ratios for with absorb vs without absorb
                VaultResolverStructs.LiquidationStruct memory liquidationDataAvailable_ = VAULT_RESOLVER
                    .getVaultLiquidation(filteredSwaps_[lastSwapIndex_].path.protocol, 0);

                uint256 withoutAbsorbRatio_ = _calcRatio(
                    liquidationDataAvailable_.inAmt,
                    liquidationDataAvailable_.outAmt
                );
                // calculate the ratio of the absorb only liquidity part
                uint256 absorbOnlyRatio_ = _calcRatio(
                    liquidationDataAvailable_.inAmtWithAbsorb - liquidationDataAvailable_.inAmt,
                    liquidationDataAvailable_.outAmtWithAbsorb - liquidationDataAvailable_.outAmt
                );
                if (absorbOnlyRatio_ > withoutAbsorbRatio_ || liquidationDataAvailable_.outAmt < missingOutAmt_) {
                    // with absorb has the better ratio than without absorb or without absorb can not fully cover
                    // the missing out amount. So with absorb has to be run.
                    // Note for the case liquidationDataAvailable_.outAmt < missingOutAmt_:
                    // missing in amt would ideally be a combination of the whole without absorb liquidity +
                    // some left over which has the different (worse) with absorb ratio.
                    // when running withAbsorb = true, always the whole with absorb liquidity is taken first.
                    // so to profit of the better without absorb liquidity, this would have to be turned into 2 swaps.
                    // but this might not always be better because of gas usage etc., so for simplicity we just
                    // take the whole absorb liquidity first.

                    // check if absorb only liquidity covers the missing out amount, if so then the swap ratio is already known
                    // as absorbOnlyRatio_ which can be used to derive the required inAmt
                    uint256 asborbOnlyLiquidity_ = liquidationDataAvailable_.outAmtWithAbsorb -
                        liquidationDataAvailable_.outAmt;
                    if (asborbOnlyLiquidity_ >= missingOutAmt_) {
                        missingInAmt_ = (missingOutAmt_ * 1e27) / absorbOnlyRatio_ + 1;
                    } else {
                        // missing in amt is a combination of the whole absorb liquidity + some left over
                        // which has the different without absorb ratio
                        missingInAmt_ = (asborbOnlyLiquidity_ * 1e27) / absorbOnlyRatio_ + 1;
                        missingInAmt_ += ((missingOutAmt_ - asborbOnlyLiquidity_) * 1e27) / withoutAbsorbRatio_ + 1;
                    }
                } else {
                    // without absorb has the better ratio AND missing out amount can be covered by without absorb liquidity
                    missingInAmt_ = (missingOutAmt_ * 1e27) / withoutAbsorbRatio_ + 1;
                }
            }

            VaultResolverStructs.LiquidationStruct memory liquidationData_ = VAULT_RESOLVER.getVaultLiquidation(
                filteredSwaps_[lastSwapIndex_].path.protocol,
                missingInAmt_
            );

            actualInAmt_ -= filteredSwaps_[lastSwapIndex_].data.inAmt;
            actualOutAmt_ -= filteredSwaps_[lastSwapIndex_].data.outAmt;

            if (filteredSwaps_[lastSwapIndex_].data.withAbsorb) {
                filteredSwaps_[lastSwapIndex_].data.inAmt = liquidationData_.inAmtWithAbsorb;
                filteredSwaps_[lastSwapIndex_].data.outAmt = liquidationData_.outAmtWithAbsorb;
                filteredSwaps_[lastSwapIndex_].data.ratio = _calcRatio(
                    liquidationData_.inAmtWithAbsorb,
                    liquidationData_.outAmtWithAbsorb
                );
            } else {
                filteredSwaps_[lastSwapIndex_].data.inAmt = liquidationData_.inAmt;
                filteredSwaps_[lastSwapIndex_].data.outAmt = liquidationData_.outAmt;
                filteredSwaps_[lastSwapIndex_].data.ratio = _calcRatio(liquidationData_.inAmt, liquidationData_.outAmt);
            }

            actualInAmt_ += filteredSwaps_[lastSwapIndex_].data.inAmt;
            actualOutAmt_ += filteredSwaps_[lastSwapIndex_].data.outAmt;
        }
    }

    /// @dev sorts `swaps_` by ratio descending. Higher ratio is better (getting more output for input).
    ///      Best ratio swap will be at pos 0, second best at pos 1 and so on
    function _sortByRatio(Swap[] memory swaps_) internal pure returns (Swap[] memory) {
        bool swapped_;
        Swap memory helper_;
        for (uint256 i = 1; i < swaps_.length; i++) {
            swapped_ = false;
            for (uint256 j = 0; j < swaps_.length - i; j++) {
                if (swaps_[j + 1].data.ratio > swaps_[j].data.ratio) {
                    helper_ = swaps_[j];
                    swaps_[j] = swaps_[j + 1];
                    swaps_[j + 1] = helper_;
                    swapped_ = true;
                }
            }
            if (!swapped_) {
                return swaps_;
            }
        }

        return swaps_;
    }

    /// @dev filters `swaps_` to exactly reach `targetInAmt_`. Takes into consideration to filter out any swaps
    ///      where both the withAbsorb and withoutAbsorb swap would be present for the same protocol, only
    ///      leaving the withAbsorb swap (as that includes withoutAbsorb).
    ///      Also returns the total in `sumInAmt_` and out `sumOutAmt_` amounts, which will be less than `targetInAmt_`
    ///      in the case that the target amount can not be reached even with all swaps.
    function _filterSwapsUntilTarget(
        Swap[] memory swaps_,
        uint256 targetInAmt_,
        uint256 targetOutAmt_
    ) internal returns (Swap[] memory filteredSwaps_, uint256 sumInAmt_, uint256 sumOutAmt_) {
        if (swaps_.length == 0) {
            return (swaps_, 0, 0);
        }
        uint256 filteredCount_;
        // find swaps needed until target in amt
        while (sumInAmt_ < targetInAmt_ && sumOutAmt_ < targetOutAmt_ && filteredCount_ < swaps_.length) {
            sumInAmt_ += swaps_[filteredCount_].data.inAmt;
            sumOutAmt_ += swaps_[filteredCount_].data.outAmt;
            ++filteredCount_;
        }

        // must not double count without absorb when with absorb is already present
        // until filteredCount, for any protocol where with absorb is present,
        // filter out the without absorb if that swap is present too.
        // if any is found then the while to find swaps until targetAmt must be run again
        // as it will be less with the filtered out element deducted.
        uint256 duplicatesCount_;
        for (uint256 i; i < filteredCount_ - 1; ++i) {
            for (uint256 j = i + 1; j < filteredCount_; ++j) {
                if (swaps_[i].path.protocol == swaps_[j].path.protocol) {
                    // same protocol present twice (with and without absorb).
                    // mark without absorb to be removed by setting the inAmt to 0
                    if (swaps_[i].data.withAbsorb) {
                        swaps_[j].data.inAmt = 0;
                    } else {
                        swaps_[i].data.inAmt = 0;
                    }
                    duplicatesCount_++;
                }
            }
        }

        if (duplicatesCount_ > 0) {
            uint256 index_;
            // filter swaps that are set to 0
            filteredSwaps_ = new Swap[](swaps_.length - duplicatesCount_);
            for (uint256 i; i < swaps_.length; ++i) {
                if (swaps_[i].data.inAmt > 0) {
                    filteredSwaps_[index_] = swaps_[i];
                    ++index_;
                }
            }

            // recursive call again to reach target amount as planned.
            return _filterSwapsUntilTarget(filteredSwaps_, targetInAmt_, targetOutAmt_);
        }

        // when clean of duplicates -> finished, return filtered swaps and total sumInAmt
        filteredSwaps_ = new Swap[](filteredCount_);
        for (uint256 i; i < filteredCount_; ++i) {
            filteredSwaps_[i] = swaps_[i];
        }
        return (filteredSwaps_, sumInAmt_, sumOutAmt_);
    }

    /// @dev gets the better swap based on ratio of with vs without absorb swap data.
    function _getBetterRatioSwapData(
        SwapData memory withoutAbsorb_,
        SwapData memory withAbsorb_
    ) internal pure returns (SwapData memory swap_) {
        if (withAbsorb_.inAmt == 0) {
            // if ratio == 0, meaning inAmt is 0, then the with absorb swap is returned.
            return withAbsorb_;
        }

        if (withAbsorb_.ratio > withoutAbsorb_.ratio) {
            // If (ratio of withAbsorb > ratio of withoutAbsorb) then always absorb should be true.
            return withAbsorb_;
        }

        if (withAbsorb_.ratio == withoutAbsorb_.ratio) {
            if (withAbsorb_.inAmt == withoutAbsorb_.inAmt) {
                // with absorb has the same liquidity as without absorb.
                // running liquidate() with absorb in that case only costs extra gas. return only without absorb swap
                return withoutAbsorb_;
            }

            // with absorb has more liquidity, but same ratio -> return with absorb
            return withAbsorb_;
        }

        // ratio of without absorb is better.
        // Note: case where with absorb has worse ratio. but it could have significant more liquidity -> will not be
        // returned here as long as there is without absorb liquidity...
        return withoutAbsorb_;
    }

    /// @dev filters `allSwaps_` to the non zero amount `swaps_`, knowing the `nonZeroSwapsCount_`
    function _getNonZeroSwaps(
        Swap[] memory allSwaps_,
        uint256 nonZeroSwapsCount_
    ) internal pure returns (Swap[] memory swaps_) {
        unchecked {
            swaps_ = new Swap[](nonZeroSwapsCount_);
            uint256 index_;
            for (uint256 i; i < allSwaps_.length; ++i) {
                if (allSwaps_[i].data.inAmt > 0) {
                    swaps_[index_] = allSwaps_[i];
                    ++index_;
                }
            }
        }
    }

    /// @dev gets the `vault_` token in (borrow token) and token out (supply token)
    function _getVaultTokens(address vault_) internal view returns (address tokenIn_, address tokenOut_) {
        IFluidVaultT1.ConstantViews memory constants_ = IFluidVaultT1(vault_).constantsView();
        return (constants_.borrowToken, constants_.supplyToken);
    }

    /// @dev returns ratio for how much outAmt_ am I getting for inAmt_. scaled by 1e27
    function _calcRatio(uint256 inAmt_, uint256 outAmt_) internal pure returns (uint256) {
        if (outAmt_ == 0) {
            return 0;
        }
        return (outAmt_ * 1e27) / inAmt_;
    }

    /// @dev returns all VaultT1 type protocols at the Fluid VaultFactory
    function _getVaultT1s() internal view returns (address[] memory) {
        return FluidProtocolTypes.filterBy(VAULT_RESOLVER.getAllVaultsAddresses(), FluidProtocolTypes.VAULT_T1_TYPE);
    }
}
