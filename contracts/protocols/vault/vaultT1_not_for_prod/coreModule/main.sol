// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../../errorTypes.sol";
import { FluidVault } from "../../vaultTypesCommon/coreModule/main.sol";

/// @notice Fluid "VaultT1" (Vault Type 1). Fluid vault protocol main contract. T1 -> Normal collateral | Normal debt
///         Fluid Vault protocol is a borrow / lending protocol, allowing users to create collateral / borrow positions.
///         All funds are deposited into / borrowed from Fluid Liquidity layer.
///         Positions are represented through NFTs minted by the VaultFactory.
///         Deployed by "VaultFactory" and linked together with Vault AdminModule `ADMIN_IMPLEMENTATION` and
///         FluidVaultSecondary (main2.sol) `SECONDARY_IMPLEMENTATION`.
///         AdminModule & FluidVaultSecondary methods are delegateCalled, if the msg.sender has the required authorization.
///         This contract links to an Oracle, which is used to assess collateral / debt value. Oracles implement the
///         "FluidOracle" base contract and return the price in 1e27 precision.
/// @dev    For view methods / accessing data, use the "VaultResolver" periphery contract.
//
// vaults can only be deployed for tokens that are listed at Liquidity (constructor reverts otherwise
// if either the exchange price for the supply token or the borrow token is still not set at Liquidity).
abstract contract Internals is FluidVault {
    // This will remain empty as this codebase has no smart collateral & smart debt

    constructor(ConstantViews memory constants_) FluidVault(constants_) {}
}

contract FluidVaultT1_Not_For_Prod is Internals {
    /// @notice Performs operations on a vault position
    /// @dev This function allows users to modify their vault position by adjusting collateral and debt
    /// @param nftId_ The ID of the NFT representing the vault position
    /// @param newCol_ The change in collateral amount (positive for deposit, negative for withdrawal)
    /// @param newDebt_ The change in debt amount (positive for borrowing, negative for repayment)
    /// @param to_ The address to receive withdrawn collateral or borrowed tokens (if address(0), defaults to msg.sender)
    /// @return nftId_ The ID of the NFT representing the updated vault position
    /// @return Final supply amount (negative if withdrawal occurred)
    /// @return Final borrow amount (negative if repayment occurred)
    /// @custom:security Re-entrancy protection is implemented
    /// @custom:security ETH balance is validated before and after operation
    function operate(
        uint nftId_,
        int newCol_,
        int newDebt_,
        address to_
    )
        external
        payable
        returns (
            uint256, // nftId_
            int256, // final supply amount. if - then withdraw
            int256 // final borrow amount. if - then payback
        )
    {
        return abi.decode(_spell(OPERATE_IMPLEMENTATION, msg.data), (uint, int, int));
    }

    /// @notice Liquidates a vault position
    /// @dev This function allows the liquidation of a vault position by paying back the debt with the collateral
    /// @param debtAmt_ The amount of debt to be liquidated
    /// @param colPerUnitDebt_ The collateral per unit of debt
    /// @param to_ The address to receive the liquidated collateral
    /// @param absorb_ If true, the liquidation absorbs the debt and the collateral is sent to the to_ address
    /// @return actualDebt_ The actual amount of debt that was liquidated
    /// @return actualCol_ The actual amount of collateral that was sent to the to_ address
    function liquidate(
        uint256 debtAmt_,
        uint256 colPerUnitDebt_, // col per unit is w.r.t debt amt
        address to_,
        bool absorb_
    ) external payable returns (uint256 actualDebt_, uint256 actualCol_) {
        uint vaultVariables_ = vaultVariables;
        // ############# turning re-entrancy bit on #############
        if (vaultVariables_ & 1 == 0) {
            // Updating on storage
            vaultVariables = vaultVariables_ | 1;
        } else {
            revert FluidVaultError(ErrorTypes.Vault__AlreadyEntered);
        }

        uint initialEth_ = address(this).balance - msg.value;

        to_ = to_ == address(0) ? msg.sender : to_;

        (actualDebt_, actualCol_, vaultVariables_) = abi.decode(
            _liquidate(debtAmt_, colPerUnitDebt_, to_, absorb_, vaultVariables_),
            (uint, uint, uint)
        );

        // disabling re-entrancy and updating on storage
        vaultVariables = vaultVariables_;

        _validateEth(initialEth_);
    }

    constructor(ConstantViews memory constants_) Internals(constants_) {
        // Note that vaults are deployed by VaultFactory so we somewhat trust the values being passed in
    }
}
