// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SSTORE2 } from "solmate/src/utils/SSTORE2.sol";

import { ErrorTypes } from "../../errorTypes.sol";
import { Error } from "../../error.sol";
import { IFluidVaultFactory } from "../../interfaces/iVaultFactory.sol";

import { LiquiditySlotsLink } from "../../../../libraries/liquiditySlotsLink.sol";

import { IFluidVaultT1 } from "../../interfaces/iVaultT1.sol";
import { FluidVaultT1 } from "../../vaultT1/coreModule/main.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

contract FluidVaultT1DeploymentLogic is Error {
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice SSTORE2 pointer for the VaultT1 creation code. Stored externally to reduce factory bytecode
    address public immutable VAULT_T1_CREATIONCODE_ADDRESS;

    /// @notice address of liquidity contract
    address public immutable LIQUIDITY;

    /// @notice address of Admin implementation
    address public immutable ADMIN_IMPLEMENTATION;

    /// @notice address of Secondary implementation
    address public immutable SECONDARY_IMPLEMENTATION;

    /// @notice address of this contract
    address public immutable ADDRESS_THIS;

    /// @notice Emitted when a new vaultT1 is deployed.
    /// @param vault The address of the newly deployed vault.
    /// @param vaultId The id of the newly deployed vault.
    /// @param supplyToken The address of the supply token.
    /// @param borrowToken The address of the borrow token.
    event VaultT1Deployed(
        address indexed vault,
        uint256 vaultId,
        address indexed supplyToken,
        address indexed borrowToken
    );

    constructor(address liquidity_, address vaultAdminImplementation_, address vaultSecondaryImplementation_) {
        LIQUIDITY = liquidity_;
        ADMIN_IMPLEMENTATION = vaultAdminImplementation_;
        SECONDARY_IMPLEMENTATION = vaultSecondaryImplementation_;
        VAULT_T1_CREATIONCODE_ADDRESS = SSTORE2.write(type(FluidVaultT1).creationCode);
        ADDRESS_THIS = address(this);
    }

    /// @dev                            Calculates the liquidity vault slots for the given supply token, borrow token, and vault (`vault_`).
    /// @param constants_               Constants struct as used in Vault T1
    /// @param vault_                   The address of the vault.
    /// @return liquidityVaultSlots_    Returns the calculated liquidity vault slots set in the `IFluidVaultT1.ConstantViews` struct.
    function _calculateLiquidityVaultSlots(
        IFluidVaultT1.ConstantViews memory constants_,
        address vault_
    ) private pure returns (IFluidVaultT1.ConstantViews memory) {
        constants_.liquiditySupplyExchangePriceSlot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            constants_.supplyToken
        );
        constants_.liquidityBorrowExchangePriceSlot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            constants_.borrowToken
        );
        constants_.liquidityUserSupplySlot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
            vault_,
            constants_.supplyToken
        );
        constants_.liquidityUserBorrowSlot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
            vault_,
            constants_.borrowToken
        );
        return constants_;
    }

    /// @notice                         Computes vaultT1 bytecode for the given supply token (`supplyToken_`) and borrow token (`borrowToken_`).
    ///                                 This will be called by the VaultFactory via .delegateCall
    /// @param supplyToken_             The address of the supply token.
    /// @param borrowToken_             The address of the borrow token.
    /// @return vaultCreationBytecode_  Returns the bytecode of the new vault to deploy.
    function vaultT1(
        address supplyToken_,
        address borrowToken_
    ) external returns (bytes memory vaultCreationBytecode_) {
        if (address(this) == ADDRESS_THIS) revert FluidVaultError(ErrorTypes.VaultFactory__OnlyDelegateCallAllowed);

        if (supplyToken_ == borrowToken_) revert FluidVaultError(ErrorTypes.VaultFactory__SameTokenNotAllowed);

        IFluidVaultT1.ConstantViews memory constants_;
        constants_.liquidity = LIQUIDITY;
        constants_.factory = address(this);
        constants_.adminImplementation = ADMIN_IMPLEMENTATION;
        constants_.secondaryImplementation = SECONDARY_IMPLEMENTATION;
        constants_.supplyToken = supplyToken_;
        constants_.supplyDecimals = supplyToken_ != NATIVE_TOKEN ? IERC20(supplyToken_).decimals() : 18;
        constants_.borrowToken = borrowToken_;
        constants_.borrowDecimals = borrowToken_ != NATIVE_TOKEN ? IERC20(borrowToken_).decimals() : 18;
        constants_.vaultId = IFluidVaultFactory(address(this)).totalVaults();

        address vault_ = IFluidVaultFactory(address(this)).getVaultAddress(constants_.vaultId);

        constants_ = _calculateLiquidityVaultSlots(constants_, vault_);

        vaultCreationBytecode_ = abi.encodePacked(SSTORE2.read(VAULT_T1_CREATIONCODE_ADDRESS), abi.encode(constants_));

        emit VaultT1Deployed(vault_, constants_.vaultId, supplyToken_, borrowToken_);

        return vaultCreationBytecode_;
    }
}
