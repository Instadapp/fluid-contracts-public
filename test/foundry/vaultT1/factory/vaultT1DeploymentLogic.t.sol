//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidVaultT1Secondary } from "../../../../contracts/protocols/vault/vaultT1/coreModule/main2.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { FluidVaultT1 } from "../../../../contracts/protocols/vault/vaultT1/coreModule/main.sol";
import { FluidVaultT1DeploymentLogic } from "../../../../contracts/protocols/vault/factory/deploymentLogics/vaultT1Logic.sol";

contract VaultT1DeploymentLogicTest is Test {
    function test_splitsCreationCodeCorrectly() public {
        address vaultAdminImplementation_ = address(new FluidVaultT1Admin());
        address vaultSecondaryImplementation_ = address(new FluidVaultT1Secondary());
        address liquidity = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;

        FluidVaultT1DeploymentLogic vaultT1DeploymentLogic = new FluidVaultT1DeploymentLogic(
            address(liquidity),
            vaultAdminImplementation_,
            vaultSecondaryImplementation_
        );

        assertEq(vaultT1DeploymentLogic.vaultT1CreationBytecode(), type(FluidVaultT1).creationCode);
    }
}
