// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SSTORE2 } from "solmate/src/utils/SSTORE2.sol";
import { MiniDeployer } from "../deploymentHelpers/miniDeployer.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { Error } from "../../error.sol";
import { IFluidVaultFactory } from "../../interfaces/iVaultFactory.sol";
import { DexSlotsLink } from "../../../../libraries/dexSlotsLink.sol";
import { FluidProtocolTypes } from "../../../../libraries/fluidProtocolTypes.sol";
import { IFluidVaultT4 } from "../../interfaces/iVaultT4.sol";
import { IFluidDexT1 } from "../../../dex/interfaces/iDexT1.sol";
import { BytesSliceAndConcat } from "../../../../libraries/bytesSliceAndConcat.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

contract FluidVaultT4DeploymentLogic is Error {
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

    address public immutable VAULT_T4_CREATIONCODE_MAIN_OPERATE;

    /// @dev SSTORE2 pointer for the VaultT4 creation code. Stored externally to reduce factory bytecode (in 2 parts)
    address internal immutable VAULT_T4_CREATIONCODE_MAIN_ADDRESS_1;
    address internal immutable VAULT_T4_CREATIONCODE_MAIN_ADDRESS_2;

    /// @notice address of this contract
    address public immutable ADDRESS_THIS;

    /// @notice Emitted when a new vaultT4 is deployed.
    /// @param vault The address of the newly deployed vault.
    /// @param vaultId The id of the newly deployed vault.
    /// @param smartCol The address of the dex for which the smart collateral is used.
    /// @param smartDebt The address of the dex for which the smart debt is used.
    event VaultT4Deployed(address indexed vault, uint256 vaultId, address indexed smartCol, address indexed smartDebt);

    /// @dev each vault type has different vaultAdminImplementation but same vaultSecondaryImplementatio
    constructor(
        address liquidity_,
        address vaultFactory_,
        address deployer_,
        address vaultAdminImplementation_,
        address vaultSecondaryImplementation_,
        address vaultOperateImplementation_,
        address vaultMainImplementation1_,
        address vaultMainImplementation2_
    ) {
        LIQUIDITY = liquidity_;
        DEPLOYER = deployer_;
        ADMIN_IMPLEMENTATION = vaultAdminImplementation_;
        SECONDARY_IMPLEMENTATION = vaultSecondaryImplementation_;

        // Deploy mini deployer
        MINI_DEPLOYER = new MiniDeployer(vaultFactory_);

        VAULT_T4_CREATIONCODE_MAIN_OPERATE = vaultOperateImplementation_;

        VAULT_T4_CREATIONCODE_MAIN_ADDRESS_1 = vaultMainImplementation1_;
        VAULT_T4_CREATIONCODE_MAIN_ADDRESS_2 = vaultMainImplementation2_;

        ADDRESS_THIS = address(this);
    }

    function vaultT4(address smartCol_, address smartDebt_) external returns (bytes memory vaultCreationBytecode_) {
        if (address(this) == ADDRESS_THIS) revert FluidVaultError(ErrorTypes.VaultFactory__OnlyDelegateCallAllowed);

        // verifying that dex address are valid
        IFluidDexT1.ConstantViews memory smartColConstants_ = IFluidDexT1(smartCol_).constantsView();
        IFluidDexT1.ConstantViews memory smartDebtConstants_ = IFluidDexT1(smartDebt_).constantsView();

        IFluidVaultT4.ConstantViews memory constants_;
        constants_.liquidity = LIQUIDITY;
        constants_.factory = address(this);
        constants_.deployer = DEPLOYER;
        constants_.adminImplementation = ADMIN_IMPLEMENTATION;
        constants_.secondaryImplementation = SECONDARY_IMPLEMENTATION;
        constants_.supply = smartCol_;
        constants_.supplyToken.token0 = smartColConstants_.token0;
        constants_.supplyToken.token1 = smartColConstants_.token1;
        constants_.borrow = smartDebt_;
        constants_.borrowToken.token0 = smartDebtConstants_.token0;
        constants_.borrowToken.token1 = smartDebtConstants_.token1;
        constants_.vaultId = IFluidVaultFactory(address(this)).totalVaults();
        constants_.vaultType = FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE;

        address vault_ = IFluidVaultFactory(address(this)).getVaultAddress(constants_.vaultId);

        constants_ = _calculateVaultSlots(constants_, vault_);

        vaultCreationBytecode_ = abi.encodePacked(
            SSTORE2.read(VAULT_T4_CREATIONCODE_MAIN_OPERATE),
            abi.encode(constants_)
        );

        address operateImplementation_ = MINI_DEPLOYER.deployContract(vaultCreationBytecode_);

        constants_.operateImplementation = operateImplementation_;

        vaultCreationBytecode_ = abi.encodePacked(mainCreationCode(), abi.encode(constants_));

        emit VaultT4Deployed(vault_, constants_.vaultId, smartCol_, smartDebt_);

        return vaultCreationBytecode_;
    }

    /// @dev Retrieves the creation code for the Operate contract
    function operateCreationCode() public view returns (bytes memory) {
        return SSTORE2.read(VAULT_T4_CREATIONCODE_MAIN_OPERATE);
    }

    /// @notice returns the stored DexT1 creation bytecode
    function mainCreationCode() public view returns (bytes memory) {
        return
            BytesSliceAndConcat.bytesConcat(
                SSTORE2.read(VAULT_T4_CREATIONCODE_MAIN_ADDRESS_1),
                SSTORE2.read(VAULT_T4_CREATIONCODE_MAIN_ADDRESS_2)
            );
    }

    function _calculateVaultSlots(
        IFluidVaultT4.ConstantViews memory constants_,
        address vault_
    ) private pure returns (IFluidVaultT4.ConstantViews memory) {
        constants_.supplyExchangePriceSlot = bytes32(0);
        constants_.borrowExchangePriceSlot = bytes32(0);
        constants_.userSupplySlot = DexSlotsLink.calculateMappingStorageSlot(
            DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT,
            vault_
        );
        constants_.userBorrowSlot = DexSlotsLink.calculateMappingStorageSlot(
            DexSlotsLink.DEX_USER_BORROW_MAPPING_SLOT,
            vault_
        );
        return constants_;
    }
}
