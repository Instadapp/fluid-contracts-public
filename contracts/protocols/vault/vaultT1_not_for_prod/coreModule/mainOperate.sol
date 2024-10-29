// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../../errorTypes.sol";
import { FluidVaultOperate } from "../../vaultTypesCommon/coreModule/mainOperate.sol";

/// @notice Fluid "VaultT1" (Vault Type 1). Fluid vault protocol main operate contract. T1 -> Normal collateral | Normal debt
abstract contract Internals is FluidVaultOperate {
    // This will remain empty as this codebase has no smart collateral & smart debt

    constructor(ConstantViews memory constants_) FluidVaultOperate(constants_) {}
}

contract FluidVaultT1Operate_Not_For_Prod is Internals {
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
        _delegateCallCheck
        returns (
            uint256, // nftId_
            int256, // final supply amount. if - then withdraw
            int256 // final borrow amount. if - then payback
        )
    {
        uint vaultVariables_ = vaultVariables;
        // re-entrancy check
        if (vaultVariables_ & 1 == 0) {
            // Updating on storage
            vaultVariables = vaultVariables_ | 1;
        } else {
            revert FluidVaultError(ErrorTypes.Vault__AlreadyEntered);
        }

        uint initialEth_ = address(this).balance - msg.value;

        to_ = to_ == address(0) ? msg.sender : to_;

        // operate will throw is user tried to withdraw excess shares
        (nftId_, newCol_, newDebt_, vaultVariables_) = _operate(nftId_, newCol_, newDebt_, to_, vaultVariables_);

        // disabling re-entrancy and updating vault variables
        vaultVariables = vaultVariables_;

        _validateEth(initialEth_);

        return (nftId_, newCol_, newDebt_);
    }

    constructor(ConstantViews memory constants_) Internals(constants_) {}
}
