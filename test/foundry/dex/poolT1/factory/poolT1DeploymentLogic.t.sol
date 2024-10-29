//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { SStore2Deployer } from "../../../../../contracts/protocols/dex/factory/deploymentHelpers/SSTORE2Deployer.sol";
import { FluidDexT1Admin } from "../../../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import { FluidDexT1OperationsCol } from "../../../../../contracts/protocols/dex/poolT1/coreModule/core/colOperations.sol";
import { FluidDexT1OperationsDebt } from "../../../../../contracts/protocols/dex/poolT1/coreModule/core/debtOperations.sol";
import { FluidDexT1PerfectOperationsAndSwapOut } from "../../../../../contracts/protocols/dex/poolT1/coreModule/core/perfectOperationsAndSwapOut.sol";
import { FluidDexT1 } from "../../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import { FluidDexT1DeploymentLogic } from "../../../../../contracts/protocols/dex/factory/deploymentLogics/poolT1Logic.sol";
import { FluidContractFactory } from "../../../../../contracts/deployer/main.sol";

contract PoolT1DeploymentLogicTest is Test {
    function test_splitsCreationCodeCorrectly() public {
        SStore2Deployer sStore2Deployer = new SStore2Deployer();
        address dexAdminImplementation_ = address(new FluidDexT1Admin());
        address liquidity_ = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
        address colOperations_ = sStore2Deployer.deployCode(type(FluidDexT1OperationsCol).creationCode);
        address debtOperations_ = sStore2Deployer.deployCode(type(FluidDexT1OperationsDebt).creationCode);
        (address perfectOperationsAndSwapOut1_, address perfectOperationsAndSwapOut2_) = sStore2Deployer.deployCodeSplit(
            type(FluidDexT1PerfectOperationsAndSwapOut).creationCode
        );
        (address mainAddress1_, address mainAddress2_) = sStore2Deployer.deployCodeSplit(type(FluidDexT1).creationCode);
        FluidDexT1DeploymentLogic poolT1DeploymentLogic = new FluidDexT1DeploymentLogic(
            address(liquidity_),
            dexAdminImplementation_,
            address(new FluidContractFactory(address(0))),
            colOperations_,
            debtOperations_,
            perfectOperationsAndSwapOut1_,
            perfectOperationsAndSwapOut2_,
            mainAddress1_,
            mainAddress2_
        );

        assertEq(poolT1DeploymentLogic.dexT1CreationBytecode(), type(FluidDexT1).creationCode);
    }
}
