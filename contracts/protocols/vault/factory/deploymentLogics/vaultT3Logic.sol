// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SSTORE2 } from "solmate/src/utils/SSTORE2.sol";
import { MiniDeployer } from "../deploymentHelpers/miniDeployer.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { Error } from "../../error.sol";
import { IFluidVaultFactory } from "../../interfaces/iVaultFactory.sol";
import { LiquiditySlotsLink } from "../../../../libraries/liquiditySlotsLink.sol";
import { DexSlotsLink } from "../../../../libraries/dexSlotsLink.sol";
import { FluidProtocolTypes } from "../../../../libraries/fluidProtocolTypes.sol";
import { IFluidVaultT3 } from "../../interfaces/iVaultT3.sol";
import { IFluidDexT1 } from "../../../dex/interfaces/iDexT1.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

contract FluidVaultT3DeploymentLogic is Error {
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

    address public immutable VAULT_T3_CREATIONCODE_MAIN_OPERATE;

    address public immutable VAULT_T3_CREATIONCODE_MAIN;

    /// @notice address of this contract
    address public immutable ADDRESS_THIS;

    /// @notice Emitted when a new vaultT3 is deployed.
    /// @param vault The address of the newly deployed vault.
    /// @param vaultId The id of the newly deployed vault.
    /// @param supplyToken The address of the supply token.
    /// @param smartDebt The address of the dex for which the smart debt is used.
    event VaultT3Deployed(
        address indexed vault,
        uint256 vaultId,
        address indexed supplyToken,
        address indexed smartDebt
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

        VAULT_T3_CREATIONCODE_MAIN_OPERATE = vaultOperateImplementation_;

        VAULT_T3_CREATIONCODE_MAIN = vaultMainImplementation_;

        ADDRESS_THIS = address(this);
    }

    function vaultT3(address supplyToken_, address smartDebt_) external returns (bytes memory vaultCreationBytecode_) {
        if (address(this) == ADDRESS_THIS) revert FluidVaultError(ErrorTypes.VaultFactory__OnlyDelegateCallAllowed);

        // verifying that supply token is valid
        if (supplyToken_ != NATIVE_TOKEN) IERC20(supplyToken_).decimals();

        // also verifies that dex address is valid
        IFluidDexT1.ConstantViews memory smartDebtConstants_ = IFluidDexT1(smartDebt_).constantsView();

        IFluidVaultT3.ConstantViews memory constants_;
        constants_.liquidity = LIQUIDITY;
        constants_.factory = address(this);
        constants_.deployer = DEPLOYER;
        constants_.adminImplementation = ADMIN_IMPLEMENTATION;
        constants_.secondaryImplementation = SECONDARY_IMPLEMENTATION;
        constants_.supply = LIQUIDITY;
        constants_.supplyToken.token0 = supplyToken_;
        // supplyToken.token1 will remain 0
        constants_.borrow = smartDebt_;
        constants_.borrowToken.token0 = smartDebtConstants_.token0;
        constants_.borrowToken.token1 = smartDebtConstants_.token1;
        constants_.vaultId = IFluidVaultFactory(address(this)).totalVaults();
        constants_.vaultType = FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE;

        address vault_ = IFluidVaultFactory(address(this)).getVaultAddress(constants_.vaultId);

        constants_ = _calculateVaultSlots(constants_, vault_);

        vaultCreationBytecode_ = abi.encodePacked(
            SSTORE2.read(VAULT_T3_CREATIONCODE_MAIN_OPERATE),
            abi.encode(constants_)
        );

        address operateImplementation_ = MINI_DEPLOYER.deployContract(vaultCreationBytecode_);

        constants_.operateImplementation = operateImplementation_;

        vaultCreationBytecode_ = abi.encodePacked(SSTORE2.read(VAULT_T3_CREATIONCODE_MAIN), abi.encode(constants_));

        emit VaultT3Deployed(vault_, constants_.vaultId, supplyToken_, smartDebt_);

        return vaultCreationBytecode_;
    }

    /// @dev Retrieves the creation code for the Operate contract
    function operateCreationCode() public view returns (bytes memory) {
        return SSTORE2.read(VAULT_T3_CREATIONCODE_MAIN_OPERATE);
    }

    /// @dev Retrieves the creation code for the main contract
    function mainCreationCode() public view returns (bytes memory) {
        return SSTORE2.read(VAULT_T3_CREATIONCODE_MAIN);
    }

    function _calculateVaultSlots(
        IFluidVaultT3.ConstantViews memory constants_,
        address vault_
    ) private pure returns (IFluidVaultT3.ConstantViews memory) {
        constants_.supplyExchangePriceSlot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            constants_.supplyToken.token0
        );
        constants_.borrowExchangePriceSlot = bytes32(0);
        constants_.userSupplySlot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
            vault_,
            constants_.supplyToken.token0
        );
        constants_.userBorrowSlot = DexSlotsLink.calculateMappingStorageSlot(
            DexSlotsLink.DEX_USER_BORROW_MAPPING_SLOT,
            vault_
        );
        return constants_;
    }
}
