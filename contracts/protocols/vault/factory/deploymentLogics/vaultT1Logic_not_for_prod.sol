// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SSTORE2 } from "solmate/src/utils/SSTORE2.sol";
import { MiniDeployer } from "../deploymentHelpers/miniDeployer.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { Error } from "../../error.sol";
import { IFluidVaultFactory } from "../../interfaces/iVaultFactory.sol";

import { LiquiditySlotsLink } from "../../../../libraries/liquiditySlotsLink.sol";

import { IFluidVaultT1_Not_For_Prod } from "../../interfaces/iVaultT1_not_for_prod.sol";

import { IFluidContractFactory } from "../../../../deployer/interface.sol";

import { FluidProtocolTypes } from "../../../../libraries/fluidProtocolTypes.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

contract FluidVaultT1DeploymentLogic_Not_For_Prod is Error {
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice address of liquidity contract
    address public immutable LIQUIDITY;

    address public immutable DEPLOYER;

    /// @notice address of MiniDeployer Contract
    MiniDeployer public immutable MINI_DEPLOYER;

    /// @notice address of Admin implementation
    address public immutable ADMIN_IMPLEMENTATION;

    /// @notice address of Secondary implementation
    address public immutable SECONDARY_IMPLEMENTATION;

    address public immutable VAULT_T1_CREATIONCODE_MAIN_OPERATE;

    address public immutable VAULT_T1_CREATIONCODE_MAIN;

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

    /// @dev each vault type has different vaultAdminImplementation but same vaultSecondaryImplementatio
    constructor(
        address liquidity_,
        address vaultFactory_,
        address deployer_,
        address vaultAdminImplementation_,
        address vaultSecondaryImplementation_,
        address vaultOperateImplementation_,
        address vaultMainImplementation_
    ) {
        LIQUIDITY = liquidity_;
        DEPLOYER = deployer_;
        ADMIN_IMPLEMENTATION = vaultAdminImplementation_;
        SECONDARY_IMPLEMENTATION = vaultSecondaryImplementation_;

        // Deploy mini deployer
        MINI_DEPLOYER = new MiniDeployer(vaultFactory_);

        VAULT_T1_CREATIONCODE_MAIN_OPERATE = vaultOperateImplementation_;

        VAULT_T1_CREATIONCODE_MAIN = vaultMainImplementation_;

        ADDRESS_THIS = address(this);
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

        IFluidVaultT1_Not_For_Prod.ConstantViews memory constants_;
        constants_.liquidity = LIQUIDITY;
        constants_.factory = address(this);
        constants_.deployer = DEPLOYER;
        constants_.adminImplementation = ADMIN_IMPLEMENTATION;
        constants_.secondaryImplementation = SECONDARY_IMPLEMENTATION;
        constants_.supply = LIQUIDITY;
        constants_.supplyToken.token0 = supplyToken_;
        constants_.borrow = LIQUIDITY;
        constants_.borrowToken.token0 = borrowToken_;
        constants_.vaultId = IFluidVaultFactory(address(this)).totalVaults();
        constants_.vaultType = FluidProtocolTypes.VAULT_T1_TYPE;

        address vault_ = IFluidVaultFactory(address(this)).getVaultAddress(constants_.vaultId);

        constants_ = _calculateLiquidityVaultSlots(constants_, vault_);
        vaultCreationBytecode_ = abi.encodePacked(
            SSTORE2.read(VAULT_T1_CREATIONCODE_MAIN_OPERATE),
            abi.encode(constants_)
        );

        address operateImplementation_ = MINI_DEPLOYER.deployContract(vaultCreationBytecode_);

        constants_.operateImplementation = operateImplementation_;

        vaultCreationBytecode_ = abi.encodePacked(SSTORE2.read(VAULT_T1_CREATIONCODE_MAIN), abi.encode(constants_));

        emit VaultT1Deployed(vault_, constants_.vaultId, supplyToken_, borrowToken_);

        return vaultCreationBytecode_;
    }

    /// @dev                            Calculates the liquidity vault slots for the given supply token, borrow token, and vault (`vault_`).
    /// @param constants_               Constants struct as used in Vault T1
    /// @param vault_                   The address of the vault.
    /// @return liquidityVaultSlots_    Returns the calculated liquidity vault slots set in the `IFluidVaultT1.ConstantViews` struct.
    function _calculateLiquidityVaultSlots(
        IFluidVaultT1_Not_For_Prod.ConstantViews memory constants_,
        address vault_
    ) private pure returns (IFluidVaultT1_Not_For_Prod.ConstantViews memory) {
        constants_.supplyExchangePriceSlot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            constants_.supplyToken.token0
        );
        constants_.borrowExchangePriceSlot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            constants_.borrowToken.token0
        );
        constants_.userSupplySlot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
            vault_,
            constants_.supplyToken.token0
        );
        constants_.userBorrowSlot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
            vault_,
            constants_.borrowToken.token0
        );
        return constants_;
    }
}
