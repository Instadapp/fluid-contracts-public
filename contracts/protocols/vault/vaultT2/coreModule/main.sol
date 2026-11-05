// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../../errorTypes.sol";
import { FluidVault } from "../../vaultTypesCommon/coreModule/main.sol";

/// @notice Fluid "VaultT2" (Vault Type 2). Fluid vault protocol main contract. T2 -> Smart collateral | Normal debt
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
    function _colLiquidatePerfectAfter(
        uint perfectColShares_,
        uint token0ColAmtPerUnitShares_,
        uint token1ColAmtPerUnitShares_,
        address to_
    ) internal returns (uint newColToken0_, uint newColToken1_) {
        uint colToken0Min_ = (token0ColAmtPerUnitShares_ * perfectColShares_) / 1e18;
        uint colToken1Min_ = (token1ColAmtPerUnitShares_ * perfectColShares_) / 1e18;

        if (colToken0Min_ > 0 && colToken1Min_ > 0) {
            (newColToken0_, newColToken1_) = SUPPLY.withdrawPerfect(
                perfectColShares_,
                colToken0Min_,
                colToken1Min_,
                to_
            );
        } else if (colToken0Min_ > 0 && colToken1Min_ == 0) {
            // withdraw only in token0, newColToken1_ remains 0
            (newColToken0_) = SUPPLY.withdrawPerfectInOneToken(perfectColShares_, colToken0Min_, colToken1Min_, to_);
        } else if (colToken0Min_ == 0 && colToken1Min_ > 0) {
            // withdraw only in token1, newColToken0_ remains 0
            (newColToken1_) = SUPPLY.withdrawPerfectInOneToken(perfectColShares_, colToken0Min_, colToken1Min_, to_);
        } else {
            // both sent as 0
            revert FluidVaultError(ErrorTypes.VaultDex__InvalidOperateAmount);
        }
    }

    constructor(ConstantViews memory constants_) FluidVault(constants_) {}
}

contract FluidVaultT2 is Internals {
    /// @notice Performs operations on a vault position
    /// @dev This function allows users to modify their vault position by adjusting collateral and debt
    /// @param nftId_ The ID of the NFT representing the vault position
    /// @param newColToken0_ The change in collateral amount of token0 (positive for deposit, negative for withdrawal)
    /// @param newColToken1_ The change in collateral amount of token1 (positive for deposit, negative for withdrawal)
    /// @param colSharesMinMax_ min or max collateral shares to mint or burn (positive for deposit, negative for withdrawal)
    /// @param newDebt_ The change in debt amount (positive for borrowing, negative for repayment)
    /// @param to_ The address to receive withdrawn collateral or borrowed tokens (if address(0), defaults to msg.sender)
    /// @return nftId_ The ID of the NFT representing the updated vault position
    /// @return supplyAmt_ Final supply amount (negative if withdrawal occurred)
    /// @return borrowAmt_ Final borrow amount (negative if repayment occurred)
    function operate(
        uint nftId_,
        int newColToken0_,
        int newColToken1_,
        int colSharesMinMax_,
        int newDebt_,
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
    /// @param perfectColShares_ The change in collateral shares (positive for deposit, negative for withdrawal)
    /// @param colToken0MinMax_ min or max collateral amount of token0 to withdraw or deposit (positive for deposit, negative for withdrawal)
    /// @param colToken1MinMax_ min or max collateral amount of token1 to withdraw or deposit (positive for deposit, negative for withdrawal)
    /// @param newDebt_ The change in debt amount (positive for borrowing, negative for repayment)
    /// @param to_ The address to receive withdrawn collateral or borrowed tokens (if address(0), defaults to msg.sender)
    /// @return nftId_ The ID of the NFT representing the updated vault position
    /// @return r_ int256 array of return values:
    ///              0 - final col shares amount (can only change on max withdrawal)
    ///              1 - token0 deposit or withdraw amount
    ///              2 - token1 deposit or withdraw amount
    ///              3 - newDebt_ will only change if user sent type(int).min
    function operatePerfect(
        uint nftId_,
        int perfectColShares_,
        int colToken0MinMax_,
        int colToken1MinMax_,
        int newDebt_,
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
    /// @param debtAmt_ The amount of debt to liquidate, if 0 then we are only absorbing the debt
    /// @param colPerUnitDebt_ The collateral shares per unit of debt
    /// @param token0ColAmtPerUnitShares_ The collateral amount of token0 per unit of shares to withdraw
    /// @param token1ColAmtPerUnitShares_ The collateral amount of token1 per unit of shares to withdraw
    /// @param to_ The address to receive withdrawn collateral (if address(0), defaults to msg.sender)
    /// @param absorb_ Whether to liquidate absorbed liquidity as well
    /// @return actualDebt_ The actual amount of debt liquidated
    /// @return actualColShares_ The actual amount of collateral shares liquidated
    /// @return token0Col_ The amount of token0 collateral withdrawn
    /// @return token1Col_ The amount of token1 collateral withdrawn
    function liquidate(
        uint256 debtAmt_,
        uint256 colPerUnitDebt_, // col per unit is w.r.t debt shares and not token0/1 debt amount
        uint256 token0ColAmtPerUnitShares_, // in 1e18
        uint256 token1ColAmtPerUnitShares_, // in 1e18
        address to_,
        bool absorb_
    )
        public
        payable
        _dexFromAddress
        returns (uint256 actualDebt_, uint256 actualColShares_, uint256 token0Col_, uint256 token1Col_)
    {
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

        (actualDebt_, actualColShares_, vaultVariables_) = abi.decode(
            _liquidate(debtAmt_, colPerUnitDebt_, to_, absorb_, vaultVariables_),
            (uint, uint, uint)
        );

        // if debtAmt_ is 0, then we are only absorbing the debt
        if (debtAmt_ > 0) {
            (token0Col_, token1Col_) = _colLiquidatePerfectAfter(
                actualColShares_,
                token0ColAmtPerUnitShares_,
                token1ColAmtPerUnitShares_,
                to_
            );
        }

        // disabling re-entrancy and updating on storage
        vaultVariables = vaultVariables_;

        _validateEth(initialEth_);
    }

    /// @notice Liquidates a vault position with perfect collateral shares
    /// @dev This function allows users to liquidate a vault position by adjusting collateral and debt
    /// @param debtAmt_ The amount of debt to liquidate
    /// @param colPerUnitDebt_ The collateral shares per unit of debt
    /// @param token0ColAmtPerUnitShares_ The collateral amount of token0 per unit of shares to withdraw
    /// @param token1ColAmtPerUnitShares_ The collateral amount of token1 per unit of shares to withdraw
    /// @param to_ The address to receive withdrawn collateral (if address(0), defaults to msg.sender)
    /// @param absorb_ Whether to liquidate absorbed liquidity as well
    /// @return actualDebt_ The actual amount of debt liquidated
    /// @return actualColShares_ The actual amount of collateral shares liquidated
    /// @return token0Col_ The amount of token0 collateral withdrawn
    /// @return token1Col_ The amount of token1 collateral withdrawn
    function liquidatePerfect(
        uint256 debtAmt_,
        uint256 colPerUnitDebt_, // col per unit is w.r.t debt shares and not token0/1 debt amount
        uint256 token0ColAmtPerUnitShares_, // in 1e18
        uint256 token1ColAmtPerUnitShares_, // in 1e18
        address to_,
        bool absorb_
    ) external payable returns (uint256 actualDebt_, uint256 actualColShares_, uint256 token0Col_, uint256 token1Col_) {
        return
            liquidate(debtAmt_, colPerUnitDebt_, token0ColAmtPerUnitShares_, token1ColAmtPerUnitShares_, to_, absorb_);
    }

    constructor(ConstantViews memory constants_) Internals(constants_) {
        // Note that vaults are deployed by VaultFactory so we somewhat trust the values being passed in
    }
}
