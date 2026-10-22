// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidVaultT1Admin } from "../../protocols/vault/vaultT1/adminModule/main.sol";
import { FluidVaultT2Admin } from "../../protocols/vault/vaultT2/adminModule/main.sol";
import { FluidVaultT3Admin } from "../../protocols/vault/vaultT3/adminModule/main.sol";
import { IFluidVault } from "../../protocols/vault/interfaces/iVault.sol";
import { FluidProtocolTypes } from "../../libraries/fluidProtocolTypes.sol";

import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

abstract contract Constants {
    /// @notice Team multisig allowed to trigger collecting revenue
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

    uint internal constant X15 = 0x7fff;
    uint internal constant X16 = 0xffff;
}

abstract contract Events {
    /// @notice emitted when supply rate magnifier is updated at a vault
    /// @param vault The address of the vault
    /// @param oldSupplyRateMagnifier The previous supply rate magnifier value
    /// @param newSupplyRateMagnifier The new supply rate magnifier value
    event LogUpdateSupplyRateMagnifier(address vault, uint256 oldSupplyRateMagnifier, uint256 newSupplyRateMagnifier);

    /// @notice emitted when borrow rate magnifier is updated at a vault
    /// @param vault The address of the vault
    /// @param oldBorrowRateMagnifier The previous borrow rate magnifier value
    /// @param newBorrowRateMagnifier The new borrow rate magnifier value
    event LogUpdateBorrowRateMagnifier(address vault, uint256 oldBorrowRateMagnifier, uint256 newBorrowRateMagnifier);

    /// @notice emitted when supply rate is updated at a vault
    /// @param vault The address of the vault
    /// @param oldSupplyRate The previous supply rate value
    /// @param newSupplyRate The new supply rate value
    event LogUpdateSupplyRate(address vault, int256 oldSupplyRate, int256 newSupplyRate);

    /// @notice emitted when borrow rate is updated at a vault
    /// @param vault The address of the vault
    /// @param oldBorrowRate The previous borrow rate value
    /// @param newBorrowRate The new borrow rate value
    event LogUpdateBorrowRate(address vault, int256 oldBorrowRate, int256 newBorrowRate);
}

contract FluidVaultFeeRewardsAuth is Constants, Error, Events {
    /// @dev Validates that an address is the team multisig
    modifier onlyMultisig() {
        if (msg.sender != TEAM_MULTISIG && TEAM_MULTISIG2 != msg.sender) {
            revert FluidConfigError(ErrorTypes.VaultFeeRewardsAuth__Unauthorized);
        }
        _;
    }

    /// @notice updates the supply rate for a given SMART COL vault.
    /// @param smartColVault_ The address of the SMART COL vault to update
    /// @param newSupplyRate_ The new supply rate to set. Input in 1e2 (1% = 100, 100% = 10_000). If positive then incentives else charging
    function updateSupplyRate(address smartColVault_, int newSupplyRate_) external onlyMultisig {
        int256 oldSupplyRate_ = currentSupplyRate(smartColVault_);

        FluidVaultT2Admin(address(smartColVault_)).updateSupplyRate(newSupplyRate_);

        emit LogUpdateSupplyRate(smartColVault_, oldSupplyRate_, newSupplyRate_);
    }

    /// @notice updates the borrow rate for a given SMART DEBT vault.
    /// @param smartDebtVault_ The address of the SMART DEBT vault to update
    /// @param newBorrowRate_ The new borrow rate to set. Input in 1e2 (1% = 100, 100% = 10_000). If positive then charging else incentives
    function updateBorrowRate(address smartDebtVault_, int newBorrowRate_) external onlyMultisig {
        int256 oldBorrowRate_ = currentBorrowRate(smartDebtVault_);

        FluidVaultT3Admin(address(smartDebtVault_)).updateBorrowRate(newBorrowRate_);

        emit LogUpdateBorrowRate(smartDebtVault_, oldBorrowRate_, newBorrowRate_);
    }

    /// @notice Sets the supply rate magnifier for a given NORMAL COL vault.
    /// @param normalColVault_ The address of the NORMAL COL vault to update.
    /// @param newMagnifier_ The new supply rate magnifier value to set.
    function updateSupplyRateMagnifier(address normalColVault_, uint256 newMagnifier_) external onlyMultisig {
        uint256 oldMagnifier_ = currentSupplyRateMagnifier(normalColVault_);

        FluidVaultT1Admin(address(normalColVault_)).updateSupplyRateMagnifier(newMagnifier_);

        emit LogUpdateSupplyRateMagnifier(normalColVault_, oldMagnifier_, newMagnifier_);
    }

    /// @notice Sets the borrow rate magnifier for a given NORMAL DEBT vault.
    /// @param normalDebtVault_ The address of the NORMAL DEBT vault to update.
    /// @param newMagnifier_ The new borrow rate magnifier value to set.
    function updateBorrowRateMagnifier(address normalDebtVault_, uint256 newMagnifier_) external onlyMultisig {
        uint256 oldMagnifier_ = currentBorrowRateMagnifier(normalDebtVault_);

        FluidVaultT1Admin(address(normalDebtVault_)).updateBorrowRateMagnifier(newMagnifier_);

        emit LogUpdateBorrowRateMagnifier(normalDebtVault_, oldMagnifier_, newMagnifier_);
    }

    /// @notice Get the type of a vault (assumes valid Fluid vault address is passed in)
    /// @param vault_ The address of the vault.
    /// @return isSmartCol_ True if the vault is a SMART COL vault, false otherwise.
    /// @return isSmartDebt_ True if the vault is a SMART DEBT vault, false otherwise.
    function getVaultType(address vault_) public view returns (bool isSmartCol_, bool isSmartDebt_) {
        try IFluidVault(vault_).TYPE() returns (uint type_) {
            if (type_ == FluidProtocolTypes.VAULT_T1_TYPE) {
                return (false, false);
            }
            if (type_ == FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE) {
                return (true, false);
            }
            if (type_ == FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE) {
                return (false, true);
            }
            if (type_ == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE) {
                return (true, true);
            }
        } catch {
            // if TYPE() is not available but address is valid vault id, it must be vault T1
            return (false, false);
        }
    }

    /// @notice returns the currently configured supply rate magnifier at the `vault_`
    /// @param normalColVault_ The address of the NORMAL COL vault to query.
    /// @return The current supply rate magnifier value.
    function currentSupplyRateMagnifier(address normalColVault_) public view returns (uint256) {
        (bool isSmartCol_, ) = getVaultType(normalColVault_);
        if (isSmartCol_) {
            revert FluidConfigError(ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType);
        }

        // read supply rate magnifier from Vault `vaultVariables2` located in storage slot 1, 16 bits from 0-15
        return (IFluidVault(normalColVault_).readFromStorage(bytes32(uint256(1)))) & X16;
    }

    /// @notice returns the currently configured borrow rate magnifier at the `vault_`
    /// @param normalDebtVault_ The address of the NORMAL DEBT vault to query.
    /// @return The current borrow rate magnifier value.
    function currentBorrowRateMagnifier(address normalDebtVault_) public view returns (uint256) {
        (, bool isSmartDebt_) = getVaultType(normalDebtVault_);
        if (isSmartDebt_) {
            revert FluidConfigError(ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType);
        }

        // read borrow rate magnifier from Vault `vaultVariables2` located in storage slot 1, 16 bits from 16-31
        return (IFluidVault(normalDebtVault_).readFromStorage(bytes32(uint256(1))) >> 16) & X16;
    }

    /// @notice returns the currently configured supply rate at the `vault_`
    /// @param smartColVault_ The address of the SMART COL vault to query.
    /// @return supplyRate_ The current supply rate value.
    function currentSupplyRate(address smartColVault_) public view returns (int256 supplyRate_) {
        (bool isSmartCol_, ) = getVaultType(smartColVault_);
        if (!isSmartCol_) {
            revert FluidConfigError(ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType);
        }
        uint256 supplyRateMagnifier_ = (IFluidVault(smartColVault_).readFromStorage(bytes32(uint256(1)))) & X16;

        // in case of smart collateral supply magnifier bits stores supply interest rate positive or negative
        // negative meaning charging users, positive means incentivizing users
        supplyRate_ = int256((supplyRateMagnifier_ >> 1) & X15);
        // if first bit == 1 then positive else negative
        if ((supplyRateMagnifier_ & 1) == 0) {
            supplyRate_ = -supplyRate_;
        }
    }

    /// @notice returns the currently configured borrow rate at the `vault_`
    /// @param smartDebtVault_ The address of the SMART DEBT vault to query.
    /// @return borrowRate_ The current borrow rate value.
    function currentBorrowRate(address smartDebtVault_) public view returns (int256 borrowRate_) {
        (, bool isSmartDebt_) = getVaultType(smartDebtVault_);
        if (!isSmartDebt_) {
            revert FluidConfigError(ErrorTypes.VaultFeeRewardsAuth__InvalidVaultType);
        }

        uint256 borrowRateMagnifier_ = (IFluidVault(smartDebtVault_).readFromStorage(bytes32(uint256(1))) >> 16) & X16;

        // in case of smart debt borrow magnifier bits stores borrow interest rate positive or negative
        // negative meaning incentivizing users, positive means charging users
        borrowRate_ = int256((borrowRateMagnifier_ >> 1) & X15);
        // if first bit == 1 then positive else negative
        if ((borrowRateMagnifier_ & 1) == 0) {
            borrowRate_ = -borrowRate_;
        }
    }
}
