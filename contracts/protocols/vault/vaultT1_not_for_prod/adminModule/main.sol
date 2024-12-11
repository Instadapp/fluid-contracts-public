// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidVaultAdmin } from "../../vaultTypesCommon/adminModule/main.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { VaultT1Events } from "./events.sol";

/// @notice Fluid Vault protocol Admin Module contract.
///         Implements admin related methods to set configs such as liquidation params, rates
///         oracle address etc.
///         Methods are limited to be called via delegateCall only. Vault CoreModule ("VaultT1" contract)
///         is expected to call the methods implemented here after checking the msg.sender is authorized.
///         All methods update the exchange prices in storage before changing configs.
contract FluidVaultT1Admin_Not_For_Prod is FluidVaultAdmin, VaultT1Events {
    /// @notice updates the supply rate magnifier to `supplyRateMagnifier_`. Input in 1e2 (1% = 100, 100% = 10_000).
    function updateSupplyRateMagnifier(uint supplyRateMagnifier_) public _updateExchangePrice _verifyCaller {
        emit LogUpdateSupplyRateMagnifier(supplyRateMagnifier_);

        if (supplyRateMagnifier_ > X16) revert FluidVaultError(ErrorTypes.VaultAdmin__ValueAboveLimit);

        vaultVariables2 =
            (vaultVariables2 & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000) |
            supplyRateMagnifier_;
    }

    /// @notice updates the borrow rate magnifier to `borrowRateMagnifier_`. Input in 1e2 (1% = 100, 100% = 10_000).
    function updateBorrowRateMagnifier(uint borrowRateMagnifier_) public _updateExchangePrice _verifyCaller {
        emit LogUpdateBorrowRateMagnifier(borrowRateMagnifier_);

        if (borrowRateMagnifier_ > X16) revert FluidVaultError(ErrorTypes.VaultAdmin__ValueAboveLimit);

        vaultVariables2 =
            (vaultVariables2 & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000ffff) |
            (borrowRateMagnifier_ << 16);
    }

    /// @notice updates the all Vault core settings according to input params.
    /// All input values are expected in 1e2 (1% = 100, 100% = 10_000).
    function updateCoreSettings(
        uint256 supplyRateMagnifier_,
        uint256 borrowRateMagnifier_,
        uint256 collateralFactor_,
        uint256 liquidationThreshold_,
        uint256 liquidationMaxLimit_,
        uint256 withdrawGap_,
        uint256 liquidationPenalty_,
        uint256 borrowFee_
    ) public _updateExchangePrice _verifyCaller {
        // emitting the event at the start as then we are updating numbers to store in a more optimized way
        emit LogUpdateCoreSettings(
            supplyRateMagnifier_,
            borrowRateMagnifier_,
            collateralFactor_,
            liquidationThreshold_,
            liquidationMaxLimit_,
            withdrawGap_,
            liquidationPenalty_,
            borrowFee_
        );

        _checkLiquidationMaxLimitAndPenalty(liquidationMaxLimit_, liquidationPenalty_);

        collateralFactor_ = collateralFactor_ / 10;
        liquidationThreshold_ = liquidationThreshold_ / 10;
        liquidationMaxLimit_ = liquidationMaxLimit_ / 10;
        withdrawGap_ = withdrawGap_ / 10;

        if (
            (supplyRateMagnifier_ > X16) ||
            (borrowRateMagnifier_ > X16) ||
            (collateralFactor_ >= liquidationThreshold_) ||
            (liquidationThreshold_ >= liquidationMaxLimit_) ||
            (withdrawGap_ > X10) ||
            (liquidationPenalty_ > X10) ||
            (borrowFee_ > X10)
        ) {
            revert FluidVaultError(ErrorTypes.VaultAdmin__ValueAboveLimit);
        }

        vaultVariables2 =
            (vaultVariables2 & 0xfffffffffffffffffffffffffffffffffffffffff00000000000000000000000) |
            supplyRateMagnifier_ |
            (borrowRateMagnifier_ << 16) |
            (collateralFactor_ << 32) |
            (liquidationThreshold_ << 42) |
            (liquidationMaxLimit_ << 52) |
            (withdrawGap_ << 62) |
            (liquidationPenalty_ << 72) |
            (borrowFee_ << 82);
    }
}
