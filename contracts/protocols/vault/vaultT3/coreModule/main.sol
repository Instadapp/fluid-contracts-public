// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../../errorTypes.sol";
import { FluidVault } from "../../vaultTypesCommon/coreModule/main.sol";

/// @notice Fluid "VaultT3" (Vault Type 3). Fluid vault protocol main contract. T3 -> Normal collateral | Smart debt
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
    function _debtLiquidateBefore(
        uint token0DebtAmt_,
        uint token1DebtAmt_,
        uint debtSharesMin_
    ) internal returns (uint shares_) {
        // paying back and burning shares
        if (token0DebtAmt_ == 0 && token1DebtAmt_ == 0) {
            // when burning shares, debt amount should always be > 0 (aka payback)
            revert FluidVaultError(ErrorTypes.VaultDex__InvalidOperateAmount);
        }

        shares_ = BORROW.payback{
            value: (BORROW_TOKEN0 == NATIVE_TOKEN)
                ? token0DebtAmt_
                : (BORROW_TOKEN1 == NATIVE_TOKEN)
                    ? token1DebtAmt_
                    : 0
        }(token0DebtAmt_, token1DebtAmt_, debtSharesMin_, false);
    }

    function _debtLiquidatePerfectPayback(
        uint perfectDebtShares_,
        uint token0DebtAmtPerUnitShares_,
        uint token1DebtAmtPerUnitShares_
    ) internal returns (uint token0DebtPaid_, uint token1DebtPaid_) {
        uint debtToken0Min_ = (token0DebtAmtPerUnitShares_ * perfectDebtShares_) / 1e18;
        uint debtToken1Min_ = (token1DebtAmtPerUnitShares_ * perfectDebtShares_) / 1e18;

        if (debtToken0Min_ > 0 && debtToken1Min_ > 0) {
            (token0DebtPaid_, token1DebtPaid_) = BORROW.paybackPerfect{
                value: (BORROW_TOKEN0 == NATIVE_TOKEN)
                    ? debtToken0Min_
                    : (BORROW_TOKEN1 == NATIVE_TOKEN)
                        ? debtToken1Min_
                        : 0
            }(perfectDebtShares_, debtToken0Min_, debtToken1Min_, false);
        } else if (debtToken0Min_ > 0 && debtToken1Min_ == 0) {
            // payback only in token0, token1DebtPaid_ remains 0
            (token0DebtPaid_) = BORROW.paybackPerfectInOneToken{
                value: (BORROW_TOKEN0 == NATIVE_TOKEN) ? debtToken0Min_ : 0
            }(perfectDebtShares_, debtToken0Min_, debtToken1Min_, false);
        } else if (debtToken0Min_ == 0 && debtToken1Min_ > 0) {
            // payback only in token1, token0DebtPaid_ remains 0
            (token1DebtPaid_) = BORROW.paybackPerfectInOneToken{
                value: (BORROW_TOKEN1 == NATIVE_TOKEN) ? debtToken1Min_ : 0
            }(perfectDebtShares_, debtToken0Min_, debtToken1Min_, false);
        } else {
            // both sent as 0
            revert FluidVaultError(ErrorTypes.VaultDex__InvalidOperateAmount);
        }
    }

    constructor(ConstantViews memory constants_) FluidVault(constants_) {}
}

contract FluidVaultT3 is Internals {
    /// @notice Performs operations on a vault position
    /// @dev This function allows users to modify their vault position by adjusting collateral and debt
    /// @param nftId_ The ID of the NFT representing the vault position
    /// @param newCol_ The change in collateral amount (positive for deposit, negative for withdrawal)
    /// @param newDebtToken0_ The change in debt amount for token0 (positive for borrowing, negative for repayment)
    /// @param newDebtToken1_ The change in debt amount for token1 (positive for borrowing, negative for repayment)
    /// @param debtSharesMinMax_ Min or max debt shares to burn or mint (positive for borrowing, negative for repayment)
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
        _dexFromAddress
        returns (
            uint256, // nftId_
            int256, // final supply amount. if - then withdraw
            int256 // final borrow amount. if - then payback
        )
    {
        return abi.decode(_spell(OPERATE_IMPLEMENTATION, msg.data), (uint, int, int));
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
        _dexFromAddress
        returns (
            uint256, // nftId_
            int256[] memory r_
        )
    {
        return abi.decode(_spell(OPERATE_IMPLEMENTATION, msg.data), (uint, int256[]));
    }

    /// @notice Liquidates a vault position
    /// @dev This function allows users to liquidate a vault position by adjusting collateral and debt
    /// @param token0DebtAmt_ The amount of debt in token0 to payback
    /// @param token1DebtAmt_ The amount of debt in token1 to payback
    /// @param debtSharesMin_ The minimum number of debt shares to liquidate
    /// @param colPerUnitDebt_ The collateral amount per unit of debt shares
    /// @param to_ The address to receive withdrawn collateral (if address(0), defaults to msg.sender)
    /// @param absorb_ Whether to liquidate absorbed liquidity as well
    /// @return actualDebtShares_ The actual number of debt shares liquidated
    /// @return actualCol_ The actual amount of collateral withdrawn
    function liquidate(
        uint256 token0DebtAmt_,
        uint256 token1DebtAmt_,
        uint256 debtSharesMin_,
        uint256 colPerUnitDebt_, // col per unit is w.r.t debt shares and not token0/1 debt amount
        address to_,
        bool absorb_
    ) external payable _dexFromAddress returns (uint256 actualDebtShares_, uint256 actualCol_) {
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

        uint sharesPaid_ = _debtLiquidateBefore(token0DebtAmt_, token1DebtAmt_, debtSharesMin_);
        (actualDebtShares_, actualCol_, vaultVariables_) = abi.decode(
            _liquidate(sharesPaid_, colPerUnitDebt_, to_, absorb_, vaultVariables_),
            (uint, uint, uint)
        );

        if (actualDebtShares_ < sharesPaid_) {
            // shares paid should never be more than actual liquidation available
            revert FluidVaultError(ErrorTypes.VaultDex__DebtSharesPaidMoreThanAvailableLiquidation);
        }

        // disabling re-entrancy and updating on storage
        vaultVariables = vaultVariables_;

        _validateEth(initialEth_);
    }

    struct LiquidatePerfect {
        uint256 vaultVariables;
        uint256 initialEth;
    }

    /// @notice Liquidates a vault position with perfect collateral shares
    /// @dev This function allows users to liquidate a vault position by adjusting collateral and debt
    /// @param debtShares_ The amount of debt shares to liquidate
    /// @param token0DebtAmtPerUnitShares_ The amount of debt in token0 per unit of debt shares (if sent 0 then entire payback is in token1)
    /// @param token1DebtAmtPerUnitShares_ The amount of debt in token1 per unit of debt shares (if sent 0 then entire payback is in token0)
    /// @param colPerUnitDebt_ The collateral amount per unit of debt shares
    /// @param to_ The address to receive withdrawn collateral (if address(0), defaults to msg.sender)
    /// @param absorb_ Whether to liquidate absorbed liquidity as well
    /// @return actualDebtShares_ The actual number of debt shares liquidated
    /// @return token0Debt_ The amount of debt in token0 that was paid back
    /// @return token1Debt_ The amount of debt in token1 that was paid back
    /// @return actualCol_ The actual amount of collateral withdrawn
    function liquidatePerfect(
        uint256 debtShares_,
        uint256 token0DebtAmtPerUnitShares_,
        uint256 token1DebtAmtPerUnitShares_,
        uint256 colPerUnitDebt_, // col per unit is w.r.t debt shares and not token0/1 debt amount
        address to_,
        bool absorb_
    )
        external
        payable
        _dexFromAddress
        returns (uint256 actualDebtShares_, uint256 token0Debt_, uint256 token1Debt_, uint256 actualCol_)
    {
        LiquidatePerfect memory lp_;
        lp_.vaultVariables = vaultVariables;
        // ############# turning re-entrancy bit on #############
        if (lp_.vaultVariables & 1 == 0) {
            // Updating on storage
            vaultVariables = lp_.vaultVariables | 1;
        } else {
            revert FluidVaultError(ErrorTypes.Vault__AlreadyEntered);
        }

        lp_.initialEth = address(this).balance - msg.value;

        to_ = to_ == address(0) ? msg.sender : to_;

        (actualDebtShares_, actualCol_, lp_.vaultVariables) = abi.decode(
            _liquidate(debtShares_, colPerUnitDebt_, to_, absorb_, lp_.vaultVariables),
            (uint, uint, uint)
        );

        (token0Debt_, token1Debt_) = _debtLiquidatePerfectPayback(
            actualDebtShares_,
            token0DebtAmtPerUnitShares_,
            token1DebtAmtPerUnitShares_
        );

        // disabling re-entrancy and updating on storage
        vaultVariables = lp_.vaultVariables;

        _validateEth(lp_.initialEth);
    }

    constructor(ConstantViews memory constants_) Internals(constants_) {
        // Note that vaults are deployed by VaultFactory so we somewhat trust the values being passed in
    }
}