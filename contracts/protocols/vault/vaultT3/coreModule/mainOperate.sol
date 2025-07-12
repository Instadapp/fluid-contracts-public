// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../../errorTypes.sol";
import { FluidVaultOperate } from "../../vaultTypesCommon/coreModule/mainOperate.sol";

/// @notice Fluid "VaultT3" (Vault Type 3). Fluid vault protocol main operate contract. T3 -> Normal collateral | Smart debt
abstract contract Internals is FluidVaultOperate {
    function _debtOperateBefore(
        int newDebtToken0_,
        int newDebtToken1_,
        int debtSharesMinMax_,
        address to_
    ) internal returns (int shares_) {
        if (debtSharesMinMax_ > 0) {
            // borrowing & minting shares
            if (newDebtToken0_ < 0 || newDebtToken1_ < 0 || (newDebtToken0_ == 0 && newDebtToken1_ == 0)) {
                // when minting shares, debt amount should always be > 0 (aka borrow)
                revert FluidVaultError(ErrorTypes.VaultDex__InvalidOperateAmount);
            }
            // borrowing both tokens from DEX protocol and update shares_
            shares_ = int(BORROW.borrow(uint(newDebtToken0_), uint(newDebtToken1_), uint(debtSharesMinMax_), to_));
        } else if (debtSharesMinMax_ < 0) {
            // paying back and burning shares
            if (newDebtToken0_ > 0 || newDebtToken1_ > 0 || (newDebtToken0_ == 0 && newDebtToken1_ == 0)) {
                // when burning shares, debt amount should always be < 0 (aka payback)
                revert FluidVaultError(ErrorTypes.VaultDex__InvalidOperateAmount);
            }
            shares_ = -int(
                BORROW.payback{
                    value: (BORROW_TOKEN0 == NATIVE_TOKEN)
                        ? uint(-newDebtToken0_)
                        : (BORROW_TOKEN1 == NATIVE_TOKEN)
                            ? uint(-newDebtToken1_)
                            : 0
                }(uint(-newDebtToken0_), uint(-newDebtToken1_), uint(-debtSharesMinMax_), false)
            );
        } else {
            // if 0 then user does not want to borrow or payback, hence shares remain 0
            if (newDebtToken0_ != 0 || newDebtToken1_ != 0) {
                revert FluidVaultError(ErrorTypes.VaultDex__InvalidOperateAmount);
            }
        }
    }

    function _debtOperatePerfectPayback(
        int perfectDebtShares_,
        int debtToken0MinMax_,
        int debtToken1MinMax_
    ) internal returns (int newDebtToken0_, int newDebtToken1_) {
        uint token0Amt_;
        uint token1Amt_;

        if (debtToken0MinMax_ < 0 && debtToken1MinMax_ < 0) {
            (token0Amt_, token1Amt_) = BORROW.paybackPerfect{
                value: (BORROW_TOKEN0 == NATIVE_TOKEN)
                    ? uint(-debtToken0MinMax_)
                    : (BORROW_TOKEN1 == NATIVE_TOKEN)
                        ? uint(-debtToken1MinMax_)
                        : 0
            }(uint(-perfectDebtShares_), uint(-debtToken0MinMax_), uint(-debtToken1MinMax_), false);
        } else if (debtToken0MinMax_ < 0 && debtToken1MinMax_ == 0) {
            // payback only in token0, token1Amt_ remains 0
            (token0Amt_) = BORROW.paybackPerfectInOneToken{
                value: (BORROW_TOKEN0 == NATIVE_TOKEN) ? uint(-debtToken0MinMax_) : 0
            }(uint(-perfectDebtShares_), uint(-debtToken0MinMax_), uint(-debtToken1MinMax_), false);
        } else if (debtToken0MinMax_ == 0 && debtToken1MinMax_ < 0) {
            // payback only in token1, token0Amt_ remains 0
            (token1Amt_) = BORROW.paybackPerfectInOneToken{
                value: (BORROW_TOKEN1 == NATIVE_TOKEN) ? uint(-debtToken1MinMax_) : 0
            }(uint(-perfectDebtShares_), uint(-debtToken0MinMax_), uint(-debtToken1MinMax_), false);
        } else {
            // meaning user sent both amount as >= 0 in case of payback
            revert FluidVaultError(ErrorTypes.VaultDex__InvalidOperateAmount);
        }

        newDebtToken0_ = -int(token0Amt_);
        newDebtToken1_ = -int(token1Amt_);
    }

    function _debtOperatePerfectBorrow(
        int perfectDebtShares_,
        int debtToken0MinMax_,
        int debtToken1MinMax_,
        address to_
    ) internal returns (int newDebtToken0_, int newDebtToken1_) {
        if ((debtToken0MinMax_ <= 0) || (debtToken1MinMax_ <= 0)) {
            // min limit of token should be positive in case of borrow
            revert FluidVaultError(ErrorTypes.VaultDex__InvalidOperateAmount);
        }

        (uint token0Amt_, uint token1Amt_) = BORROW.borrowPerfect(
            uint(perfectDebtShares_),
            uint(debtToken0MinMax_),
            uint(debtToken1MinMax_),
            to_
        );
        newDebtToken0_ = int(token0Amt_);
        newDebtToken1_ = int(token1Amt_);
    }

    constructor(ConstantViews memory constants_) FluidVaultOperate(constants_) {}
}

contract FluidVaultT3Operate is Internals {
    struct SmartOperate {
        uint initialEth;
        int debtShares;
        uint256 vaultVariables;
    }

    /// @notice Performs operations on a vault position
    /// @dev This function allows users to modify their vault position by adjusting collateral and debt
    /// @param nftId_ The ID of the NFT representing the vault position
    /// @param newCol_ The change in collateral amount (positive for deposit, negative for withdrawal)
    /// @param newDebtToken0_ The change in debt amount for token0 (positive for borrowing, negative for repayment)
    /// @param newDebtToken1_ The change in debt amount for token1 (positive for borrowing, negative for repayment)
    /// @param debtSharesMinMax_ Min or max debt shares to mint or burn (positive for borrowing, negative for repayment)
    /// @param to_ The address to receive withdrawn collateral or borrowed tokens (if address(0), defaults to msg.sender)
    /// @return nftId_ The ID of the NFT representing the updated vault position
    /// @return supplyAmt_ Final supply amount (negative if withdrawal occurred)
    /// @return borrowAmt_ Final borrow amount (negative if repayment occurred)
    /// @custom:security Re-entrancy protection is implemented
    /// @custom:security ETH balance is validated before and after operation
    function operate(
        uint nftId_,
        int newCol_,
        int newDebtToken0_,
        int newDebtToken1_,
        int debtSharesMinMax_,
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
        SmartOperate memory so_;

        so_.vaultVariables = vaultVariables;
        // re-entrancy check
        if (so_.vaultVariables & 1 == 0) {
            // Updating on storage
            vaultVariables = so_.vaultVariables | 1;
        } else {
            revert FluidVaultError(ErrorTypes.Vault__AlreadyEntered);
        }

        so_.initialEth = address(this).balance - msg.value;

        to_ = to_ == address(0) ? msg.sender : to_;

        so_.debtShares = _debtOperateBefore(newDebtToken0_, newDebtToken1_, debtSharesMinMax_, to_);

        // operate will throw is user tried to withdraw excess shares
        // so_.colShares returned after should remain same as before
        // so_.debtShares returned after should remain same as before
        (nftId_, newCol_, so_.debtShares, so_.vaultVariables) = _operate(
            nftId_,
            newCol_,
            so_.debtShares,
            to_,
            so_.vaultVariables
        );

        // disabling re-entrancy and updating vault variables
        vaultVariables = so_.vaultVariables;

        _validateEth(so_.initialEth);

        return (nftId_, newCol_, so_.debtShares);
    }

    struct SmartOperatePerfect {
        uint initialEth;
        int newDebtToken0;
        int newDebtToken1;
        uint vaultVariables;
    }

    /// @notice Performs operations on a vault position with perfect collateral shares
    /// @dev This function allows users to modify their vault position by adjusting collateral and debt
    /// @param nftId_ The ID of the NFT representing the vault position
    /// @param newCol_ The change in collateral amount (positive for deposit, negative for withdrawal)
    /// @param perfectDebtShares_ The change in debt shares (positive for borrowing, negative for repayment)
    /// @param debtToken0MinMax_ Min or max debt amount for token0 to payback or borrow (positive for borrowing, negative for repayment)
    /// @param debtToken1MinMax_ Min or max debt amount for token1 to payback or borrow (positive for borrowing, negative for repayment)
    /// @param to_ The address to receive withdrawn collateral or borrowed tokens (if address(0), defaults to msg.sender)
    /// @return nftId_ The ID of the NFT representing the updated vault position
    /// @return r_ int256 array of return values:
    ///              0 - col amount, will only change if user sends type(int).min
    ///              1 - final debt shares amount (can only change on max payback)
    ///              2 - token0 borrow or payback amount
    ///              3 - token1 borrow or payback amount
    function operatePerfect(
        uint nftId_,
        int newCol_,
        int perfectDebtShares_,
        int debtToken0MinMax_,
        int debtToken1MinMax_,
        address to_
    )
        external
        payable
        _delegateCallCheck
        returns (
            uint256, // nftId_
            int256[] memory r_
        )
    {
        SmartOperatePerfect memory sop_;
        r_ = new int256[](4);

        sop_.vaultVariables = vaultVariables;
        // re-entrancy check
        if (sop_.vaultVariables & 1 == 0) {
            // Updating on storage
            vaultVariables = sop_.vaultVariables | 1;
        } else {
            revert FluidVaultError(ErrorTypes.Vault__AlreadyEntered);
        }

        sop_.initialEth = address(this).balance - msg.value;

        to_ = to_ == address(0) ? msg.sender : to_;

        // operate will throw if user tried to withdraw excess shares
        // if max payback then perfectDebtShares_ will change from type(int).min to total user's debt shares
        (nftId_, newCol_, perfectDebtShares_, sop_.vaultVariables) = _operate(
            nftId_,
            newCol_,
            perfectDebtShares_,
            to_,
            sop_.vaultVariables
        );

        // payback back after operate because user might want to payback max and in that case below function won't work
        if (perfectDebtShares_ < 0) {
            (sop_.newDebtToken0, sop_.newDebtToken1) = _debtOperatePerfectPayback(
                perfectDebtShares_,
                debtToken0MinMax_,
                debtToken1MinMax_
            );
        } else if (perfectDebtShares_ > 0) {
            (sop_.newDebtToken0, sop_.newDebtToken1) = _debtOperatePerfectBorrow(
                perfectDebtShares_,
                debtToken0MinMax_,
                debtToken1MinMax_,
                to_
            );
        }

        r_[0] = newCol_;
        r_[1] = perfectDebtShares_;
        r_[2] = sop_.newDebtToken0;
        r_[3] = sop_.newDebtToken1;

        // disabling re-entrancy and updating vault variables
        vaultVariables = sop_.vaultVariables;

        _validateEth(sop_.initialEth);

        return (nftId_, r_);
    }

    constructor(ConstantViews memory constants_) Internals(constants_) {}
}
