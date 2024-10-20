//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Structs } from "./structs.sol";

interface IFluidVaultResolver {
    function vaultByNftId(uint nftId_) external view returns (address vault_);

    function positionByNftId(
        uint nftId_
    ) external view returns (Structs.UserPosition memory userPosition_, Structs.VaultEntireData memory vaultData_);

    function getVaultVariablesRaw(address vault_) external view returns (uint);

    function getVaultVariables2Raw(address vault_) external view returns (uint);

    function getTickHasDebtRaw(address vault_, int key_) external view returns (uint);

    function getTickDataRaw(address vault_, int tick_) external view returns (uint);

    function getBranchDataRaw(address vault_, uint branch_) external view returns (uint);

    function getPositionDataRaw(address vault_, uint positionId_) external view returns (uint);

    function getAllVaultsAddresses() external view returns (address[] memory vaults_);

    function getVaultLiquidation(
        address vault_,
        uint tokenInAmt_
    ) external returns (Structs.LiquidationStruct memory liquidationData_);

    function getVaultEntireData(address vault_) external view returns (Structs.VaultEntireData memory vaultData_);
}
