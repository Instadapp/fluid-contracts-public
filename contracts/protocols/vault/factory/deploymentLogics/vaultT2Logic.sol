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
import { IFluidVaultT2 } from "../../interfaces/iVaultT2.sol";
import { IFluidDexT1 } from "../../../dex/interfaces/iDexT1.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

contract FluidVaultT2DeploymentLogic is Error {
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

    address public immutable VAULT_T2_CREATIONCODE_MAIN_OPERATE;

    address public immutable VAULT_T2_CREATIONCODE_MAIN;

    /// @notice address of this contract
    address public immutable ADDRESS_THIS;

    /// @notice Emitted when a new vaultT2 is deployed.
    /// @param vault The address of the newly deployed vault.
    /// @param vaultId The id of the newly deployed vault.
    /// @param smartCol The address of the dex for which the smart collateral is used.
    /// @param borrowToken The address of the borrow token.
    event VaultT2Deployed(
        address indexed vault,
        uint256 vaultId,
        address indexed smartCol,
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

        VAULT_T2_CREATIONCODE_MAIN_OPERATE = vaultOperateImplementation_;

        VAULT_T2_CREATIONCODE_MAIN = vaultMainImplementation_;

        ADDRESS_THIS = address(this);
    }

    function vaultT2(address smartCol_, address borrowToken_) external returns (bytes memory vaultCreationBytecode_) {
        if (address(this) == ADDRESS_THIS) revert FluidVaultError(ErrorTypes.VaultFactory__OnlyDelegateCallAllowed);

        // also verifies that dex address is valid
        IFluidDexT1.ConstantViews memory smartColConstants_ = IFluidDexT1(smartCol_).constantsView();

        // verifying that borrow token is valid
        if (borrowToken_ != NATIVE_TOKEN) IERC20(borrowToken_).decimals();

        IFluidVaultT2.ConstantViews memory constants_;
        constants_.liquidity = LIQUIDITY;
        constants_.factory = address(this);
        constants_.deployer = DEPLOYER;
        constants_.adminImplementation = ADMIN_IMPLEMENTATION;
        constants_.secondaryImplementation = SECONDARY_IMPLEMENTATION;
        constants_.supply = smartCol_;
        constants_.supplyToken.token0 = smartColConstants_.token0;
        constants_.supplyToken.token1 = smartColConstants_.token1;
        constants_.borrow = LIQUIDITY;
        constants_.borrowToken.token0 = borrowToken_;
        // borrowToken.token1 will remain 0
        constants_.vaultId = IFluidVaultFactory(address(this)).totalVaults();
        constants_.vaultType = FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE;

        address vault_ = IFluidVaultFactory(address(this)).getVaultAddress(constants_.vaultId);

        constants_ = _calculateVaultSlots(constants_, vault_);

        vaultCreationBytecode_ = abi.encodePacked(
            SSTORE2.read(VAULT_T2_CREATIONCODE_MAIN_OPERATE),
            abi.encode(constants_)
        );

        address operateImplementation_ = MINI_DEPLOYER.deployContract(vaultCreationBytecode_);

        constants_.operateImplementation = operateImplementation_;

        vaultCreationBytecode_ = abi.encodePacked(SSTORE2.read(VAULT_T2_CREATIONCODE_MAIN), abi.encode(constants_));

        emit VaultT2Deployed(vault_, constants_.vaultId, smartCol_, borrowToken_);

        return vaultCreationBytecode_;
    }

    /// @dev Retrieves the creation code for the Operate contract
    function operateCreationCode() public view returns (bytes memory) {
        return SSTORE2.read(VAULT_T2_CREATIONCODE_MAIN_OPERATE);
    }

    /// @dev Retrieves the creation code for the main contract
    function mainCreationCode() public view returns (bytes memory) {
        return SSTORE2.read(VAULT_T2_CREATIONCODE_MAIN);
    }

    function _calculateVaultSlots(
        IFluidVaultT2.ConstantViews memory constants_,
        address vault_
    ) private pure returns (IFluidVaultT2.ConstantViews memory) {
        constants_.supplyExchangePriceSlot = bytes32(0);
        constants_.borrowExchangePriceSlot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            constants_.borrowToken.token0
        );
        constants_.userSupplySlot = DexSlotsLink.calculateMappingStorageSlot(
            DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT,
            vault_
        );
        constants_.userBorrowSlot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
            vault_,
            constants_.borrowToken.token0
        );
        return constants_;
    }
}
