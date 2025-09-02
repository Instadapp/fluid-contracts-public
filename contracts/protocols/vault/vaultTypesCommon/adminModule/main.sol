// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IFluidOracle } from "../../../../oracle/fluidOracle.sol";

import { Variables } from "../common/variables.sol";
import { Events } from "./events.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { Error } from "../../error.sol";
import { IFluidVault } from "../../interfaces/iVault.sol";
import { BigMathMinified } from "../../../../libraries/bigMathMinified.sol";
import { TickMath } from "../../../../libraries/tickMath.sol";
import { AddressCalcs } from "../../../../libraries/addressCalcs.sol";
import { SafeTransfer } from "../../../../libraries/safeTransfer.sol";

/// @notice Fluid Vault protocol Admin Module contract.
///         Implements admin related methods to set configs such as liquidation params, rates
///         oracle address etc.
///         Methods are limited to be called via delegateCall only. Vault CoreModule ("VaultT1" contract)
///         is expected to call the methods implemented here after checking the msg.sender is authorized.
///         All methods update the exchange prices in storage before changing configs.
abstract contract FluidVaultAdmin is Variables, Events, Error {
    uint internal constant X8 = 0xff;
    uint internal constant X10 = 0x3ff;
    uint internal constant X15 = 0x7fff;
    uint internal constant X16 = 0xffff;
    uint internal constant X19 = 0x7ffff;
    uint internal constant X24 = 0xffffff;
    uint internal constant X30 = 0x3fffffff;
    uint internal constant X64 = 0xffffffffffffffff;
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address internal immutable addressThis;

    constructor() {
        addressThis = address(this);
    }

    modifier _verifyCaller() {
        if (address(this) == addressThis) {
            revert FluidVaultError(ErrorTypes.VaultAdmin__OnlyDelegateCallAllowed);
        }
        _;
    }

    /// @dev updates exchange price on storage, called on all admin methods in combination with _verifyCaller modifier so
    /// only called by authorized delegatecall
    modifier _updateExchangePrice() {
        IFluidVault(address(this)).updateExchangePricesOnStorage();
        _;
    }

    function _checkLiquidationMaxLimitAndPenalty(uint liquidationMaxLimit_, uint liquidationPenalty_) internal pure {
        // liquidation max limit with penalty should not go above 99.7%
        // As liquidation with penalty can happen from liquidation Threshold to max limit
        // If it goes above 100% than that means liquidator is getting more collateral than user's available
        if ((liquidationMaxLimit_ + liquidationPenalty_) > 9970) {
            revert FluidVaultError(ErrorTypes.VaultAdmin__ValueAboveLimit);
        }
    }

    /// @notice updates the collateral factor to `collateralFactor_`. Input in 1e2 (1% = 100, 100% = 10_000).
    function updateCollateralFactor(uint collateralFactor_) public _updateExchangePrice _verifyCaller {
        emit LogUpdateCollateralFactor(collateralFactor_);

        uint vaultVariables2_ = vaultVariables2;
        uint liquidationThreshold_ = ((vaultVariables2_ >> 42) & X10);

        collateralFactor_ = collateralFactor_ / 10;

        if (collateralFactor_ >= liquidationThreshold_) revert FluidVaultError(ErrorTypes.VaultAdmin__ValueAboveLimit);

        vaultVariables2 =
            (vaultVariables2_ & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffc00ffffffff) |
            (collateralFactor_ << 32);
    }

    /// @notice updates the liquidation threshold to `liquidationThreshold_`. Input in 1e2 (1% = 100, 100% = 10_000).
    function updateLiquidationThreshold(uint liquidationThreshold_) public _updateExchangePrice _verifyCaller {
        emit LogUpdateLiquidationThreshold(liquidationThreshold_);

        uint vaultVariables2_ = vaultVariables2;
        uint collateralFactor_ = ((vaultVariables2_ >> 32) & X10);
        uint liquidationMaxLimit_ = ((vaultVariables2_ >> 52) & X10);

        liquidationThreshold_ = liquidationThreshold_ / 10;

        if ((collateralFactor_ >= liquidationThreshold_) || (liquidationThreshold_ >= liquidationMaxLimit_))
            revert FluidVaultError(ErrorTypes.VaultAdmin__ValueAboveLimit);

        vaultVariables2 =
            (vaultVariables2_ & 0xfffffffffffffffffffffffffffffffffffffffffffffffffff003ffffffffff) |
            (liquidationThreshold_ << 42);
    }

    /// @notice updates the liquidation max limit to `liquidationMaxLimit_`. Input in 1e2 (1% = 100, 100% = 10_000).
    function updateLiquidationMaxLimit(uint liquidationMaxLimit_) public _updateExchangePrice _verifyCaller {
        emit LogUpdateLiquidationMaxLimit(liquidationMaxLimit_);

        uint vaultVariables2_ = vaultVariables2;
        uint liquidationThreshold_ = ((vaultVariables2_ >> 42) & X10);
        uint liquidationPenalty_ = ((vaultVariables2_ >> 72) & X10);

        // both are in 1e2 decimals (1e2 = 1%)
        _checkLiquidationMaxLimitAndPenalty(liquidationMaxLimit_, liquidationPenalty_);

        liquidationMaxLimit_ = liquidationMaxLimit_ / 10;

        if (liquidationThreshold_ >= liquidationMaxLimit_)
            revert FluidVaultError(ErrorTypes.VaultAdmin__ValueAboveLimit);

        vaultVariables2 =
            (vaultVariables2_ & 0xffffffffffffffffffffffffffffffffffffffffffffffffc00fffffffffffff) |
            (liquidationMaxLimit_ << 52);
    }

    /// @notice updates the withdrawal gap to `withdrawGap_`. Input in 1e2 (1% = 100, 100% = 10_000).
    function updateWithdrawGap(uint withdrawGap_) public _updateExchangePrice _verifyCaller {
        emit LogUpdateWithdrawGap(withdrawGap_);

        withdrawGap_ = withdrawGap_ / 10;

        // withdrawGap must not be > 100%
        if (withdrawGap_ > 1000) revert FluidVaultError(ErrorTypes.VaultAdmin__ValueAboveLimit);

        vaultVariables2 =
            (vaultVariables2 & 0xffffffffffffffffffffffffffffffffffffffffffffff003fffffffffffffff) |
            (withdrawGap_ << 62);
    }

    /// @notice updates the liquidation penalty to `liquidationPenalty_`. Input in 1e2 (1% = 100, 100% = 10_000).
    function updateLiquidationPenalty(uint liquidationPenalty_) public _updateExchangePrice _verifyCaller {
        emit LogUpdateLiquidationPenalty(liquidationPenalty_);

        uint vaultVariables2_ = vaultVariables2;
        uint liquidationMaxLimit_ = ((vaultVariables2_ >> 52) & X10);

        // Converting liquidationMaxLimit_ in 1e2 decimals (1e2 = 1%)
        _checkLiquidationMaxLimitAndPenalty((liquidationMaxLimit_ * 10), liquidationPenalty_);

        if (liquidationPenalty_ > X10) revert FluidVaultError(ErrorTypes.VaultAdmin__ValueAboveLimit);

        vaultVariables2 =
            (vaultVariables2_ & 0xfffffffffffffffffffffffffffffffffffffffffffc00ffffffffffffffffff) |
            (liquidationPenalty_ << 72);
    }

    /// @notice updates the borrow fee to `borrowFee_`. Input in 1e2 (1% = 100, 100% = 10_000).
    function updateBorrowFee(uint borrowFee_) public _updateExchangePrice _verifyCaller {
        emit LogUpdateBorrowFee(borrowFee_);

        if (borrowFee_ > X10) revert FluidVaultError(ErrorTypes.VaultAdmin__ValueAboveLimit);

        vaultVariables2 =
            (vaultVariables2 & 0xfffffffffffffffffffffffffffffffffffffffff003ffffffffffffffffffff) |
            (borrowFee_ << 82);
    }

    /// @notice updates the Vault oracle to `newOracleNonce_`. Must implement the FluidOracle interface.
    function updateOracle(uint newOracleNonce_) public _updateExchangePrice _verifyCaller {
        if (newOracleNonce_ > X30) revert FluidVaultError(ErrorTypes.VaultAdmin__ValueAboveLimit);

        // masking to remove old oracle and keep all the other values intact
        vaultVariables2 =
            (vaultVariables2 & 0xfffffffffffffffffffffffffffffffffc0000000fffffffffffffffffffffff) |
            (newOracleNonce_ << 92);

        IFluidVault.ConstantViews memory c_ = IFluidVault(address(this)).constantsView();

        address oracle_ = AddressCalcs.addressCalc(c_.deployer, newOracleNonce_);

        // checking if oracle address follows the standard
        IFluidOracle(oracle_).getExchangeRateOperate();
        IFluidOracle(oracle_).getExchangeRateLiquidate();

        emit LogUpdateOracle(newOracleNonce_, oracle_);
    }

    /// @notice updates the allowed rebalancer to `newRebalancer_`.
    function updateRebalancer(address newRebalancer_) public _updateExchangePrice _verifyCaller {
        if (newRebalancer_ == address(0)) revert FluidVaultError(ErrorTypes.VaultAdmin__AddressZeroNotAllowed);

        rebalancer = newRebalancer_;

        emit LogUpdateRebalancer(newRebalancer_);
    }

    /// @notice sends any potentially stuck funds to Liquidity contract.
    /// @dev this contract never holds any funds as all operations send / receive funds from user <-> Liquidity.
    function rescueFunds(address token_) external _verifyCaller {
        if (token_ == NATIVE_TOKEN) {
            SafeTransfer.safeTransferNative(IFluidVault(address(this)).LIQUIDITY(), address(this).balance);
        } else {
            SafeTransfer.safeTransfer(
                token_,
                IFluidVault(address(this)).LIQUIDITY(),
                IERC20(token_).balanceOf(address(this))
            );
        }

        emit LogRescueFunds(token_);
    }

    /// @notice absorbs accumulated dust debt
    /// @dev in decades if a lot of positions are 100% liquidated (aka absorbed) then dust debt can mount up
    /// which is basically sort of an extra revenue for the protocol.
    //
    // this function might never come in use that's why adding it in admin module
    function absorbDustDebt(uint[] memory nftIds_) public _verifyCaller {
        uint256 vaultVariables_ = vaultVariables;
        // re-entrancy check
        if (vaultVariables_ & 1 == 0) {
            // Updating on storage
            vaultVariables = vaultVariables_ | 1;
        } else {
            revert FluidVaultError(ErrorTypes.Vault__AlreadyEntered);
        }

        uint nftId_;
        uint posData_;
        int posTick_;
        uint tickId_;
        uint posCol_;
        uint posDebt_;
        uint posDustDebt_;
        uint tickData_;

        uint absorbedDustDebt_ = absorbedDustDebt;

        for (uint i = 0; i < nftIds_.length; ) {
            nftId_ = nftIds_[i];
            if (nftId_ == 0) {
                revert FluidVaultError(ErrorTypes.VaultAdmin__NftIdShouldBeNonZero);
            }

            // user's position data
            posData_ = positionData[nftId_];

            if (posData_ == 0) {
                revert FluidVaultError(ErrorTypes.VaultAdmin__NftNotOfThisVault);
            }

            posCol_ = (posData_ >> 45) & X64;
            // Converting big number into normal number
            posCol_ = (posCol_ >> 8) << (posCol_ & X8);

            posDustDebt_ = (posData_ >> 109) & X64;
            // Converting big number into normal number
            posDustDebt_ = (posDustDebt_ >> 8) << (posDustDebt_ & X8);

            if (posDustDebt_ == 0) {
                revert FluidVaultError(ErrorTypes.VaultAdmin__DustDebtIsZero);
            }

            // borrow position (has collateral & debt)
            posTick_ = posData_ & 2 == 2 ? int((posData_ >> 2) & X19) : -int((posData_ >> 2) & X19);
            tickId_ = (posData_ >> 21) & X24;

            posDebt_ = (TickMath.getRatioAtTick(int24(posTick_)) * posCol_) >> 96;

            // Tick data from user's tick
            tickData_ = tickData[posTick_];

            // Checking if tick is liquidated OR if the total IDs of tick is greater than user's tick ID
            if (((tickData_ & 1) == 1) || (((tickData_ >> 1) & X24) > tickId_)) {
                // User got liquidated
                (, posDebt_, , , ) = IFluidVault(address(this)).fetchLatestPosition(
                    posTick_,
                    tickId_,
                    posDebt_,
                    tickData_
                );
                if (posDebt_ > 0) {
                    revert FluidVaultError(ErrorTypes.VaultAdmin__FinalDebtShouldBeZero);
                }
                // absorbing user's debt as it's 100% or almost 100% liquidated
                absorbedDustDebt_ = absorbedDustDebt_ + posDustDebt_;
                // making position as supply only
                positionData[nftId_] = 1;
            } else {
                revert FluidVaultError(ErrorTypes.VaultAdmin__NftNotLiquidated);
            }

            unchecked {
                i++;
            }
        }

        if (absorbedDustDebt_ == 0) {
            revert FluidVaultError(ErrorTypes.VaultAdmin__AbsorbedDustDebtIsZero);
        }

        uint totalBorrow_ = (vaultVariables_ >> 146) & X64;
        // Converting big number into normal number
        totalBorrow_ = (totalBorrow_ >> 8) << (totalBorrow_ & X8);
        // note: by default dust debt is not added into total borrow but on 100% liquidation (aka absorb) dust debt equivalent
        // is removed from total borrow so adding it back again here
        totalBorrow_ = totalBorrow_ + absorbedDustDebt_;
        totalBorrow_ = BigMathMinified.toBigNumber(totalBorrow_, 56, 8, BigMathMinified.ROUND_UP);

        // adding absorbed dust debt to total borrow so it will get included in the next rebalancing.
        // there is some fuzziness here as when the position got fully liquidated (aka absorbed) the exchange price was different
        // than what it'll be now. The fuzziness which will be extremely small so we can ignore it
        // updating on storage
        vaultVariables =
            (vaultVariables_ & 0xfffffffffffc0000000000000003ffffffffffffffffffffffffffffffffffff) |
            (totalBorrow_ << 146);

        // updating on storage
        absorbedDustDebt = 0;

        emit LogAbsorbDustDebt(nftIds_, absorbedDustDebt_);
    }
}
