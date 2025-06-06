import { deployments, ethers, getUnnamedAccounts } from "hardhat";

import chai from "chai";
import {
  FluidDexT1DeploymentLogic,
  FluidDexT1OperationsCol__factory,
  FluidDexT1OperationsDebt__factory,
  FluidDexT1PerfectOperationsAndSwapOut__factory,
  FluidDexT1__factory,
  SStore2Deployer,
} from "../../typechain-types";
export const { expect } = chai;

describe("PoolT1DeploymentLogic", () => {
  it("should deploy PoolT1DeploymentLogic", async () => {
    const owner = await ethers.getSigner((await getUnnamedAccounts())[0]);

    const liquidity = "0x52Aa899454998Be5b000Ad077a46Bbe360F4e497";

    await deployments.delete("FluidDexT1Admin");
    await deployments.delete("FluidContractFactory");
    await deployments.delete("FluidDexT1DeploymentLogic");
    await deployments.delete("SStore2Deployer");

    const sstore2Deployer = await deployments.deploy("SStore2Deployer", {
      from: owner.address,
      args: [],
      log: false,
      skipIfAlreadyDeployed: false,
      gasLimit: 30000000,
    });

    const sstore2DeployerContract = (await ethers.getContractAt("SStore2Deployer", sstore2Deployer.address)).connect(
      owner
    ) as SStore2Deployer;

    let res = await sstore2DeployerContract.deployCode(FluidDexT1OperationsCol__factory.bytecode, {
      gasLimit: 30000000,
    });
    let event = ((await res.wait())?.events as any as Event[])[0];
    const colOperations = (event as any).args[0];

    res = await sstore2DeployerContract.deployCode(FluidDexT1OperationsDebt__factory.bytecode, {
      gasLimit: 30000000,
    });
    event = ((await res.wait())?.events as any as Event[])[0];
    const debtOperations = (event as any).args[0];

    res = await sstore2DeployerContract.deployCode(FluidDexT1PerfectOperationsAndSwapOut__factory.bytecode, {
      gasLimit: 30000000,
    });
    event = ((await res.wait())?.events as any as Event[])[0];
    const perfectOperationsAndSwapOut = (event as any).args[0];

    res = await sstore2DeployerContract.deployCodeSplit(FluidDexT1__factory.bytecode, {
      gasLimit: 30000000,
    });
    event = ((await res.wait())?.events as any as Event[])[0];
    const mainImplementation1 = (event as any).args[0];
    const mainImplementation2 = (event as any).args[1];

    const adminContract = await deployments.deploy("FluidDexT1Admin", {
      from: owner.address,
      args: [],
      log: false,
      skipIfAlreadyDeployed: false,
      gasLimit: 30000000,
    });

    const factory = await deployments.deploy("FluidContractFactory", {
      from: owner.address,
      args: [owner.address],
      log: false,
      skipIfAlreadyDeployed: false,
      gasLimit: 30000000,
    });

    const deploymentLogic = await deployments.deploy("FluidDexT1DeploymentLogic", {
      from: owner.address,
      args: [
        liquidity,
        adminContract.address,
        factory.address,
        colOperations,
        debtOperations,
        perfectOperationsAndSwapOut,
        mainImplementation1,
        mainImplementation2,
      ],
      log: false,
      skipIfAlreadyDeployed: false,
      gasLimit: 30000000,
    });

    const deployedCode = await ethers.provider.getCode(deploymentLogic.address);
    expect(deployedCode).to.not.equal("");
    expect(deployedCode).to.not.equal("0x");
  });

  it("should match creation codes", async () => {
    const owner = await ethers.getSigner((await getUnnamedAccounts())[0]);
    const deployment = "0xd1dDbc77E3394A50D642FB0510d199154e6BD493";

    const poolT1DeploymentLogic = (await ethers.getContractAt("FluidDexT1DeploymentLogic", deployment)).connect(
      owner
    ) as FluidDexT1DeploymentLogic;

    const expectedDexT1CreationCode = await poolT1DeploymentLogic.dexT1CreationBytecode();
    const expectedColOperationsCreationCode = await poolT1DeploymentLogic.colOperationsCreationCode();
    const expectedDebtOperationsCreationCode = await poolT1DeploymentLogic.debtOperationsCreationCode();
    const expectedPerfectOperationsCreationCode = await poolT1DeploymentLogic.perfectOperationsCreationCode();

    const fluidDexT1 = FluidDexT1__factory.bytecode;
    const fluidDexT1OperationsCol = FluidDexT1OperationsCol__factory.bytecode;
    const fluidDexT1OperationsDebt = FluidDexT1OperationsDebt__factory.bytecode;
    const fluidDexT1PerfectOperationsAndSwapOut = FluidDexT1PerfectOperationsAndSwapOut__factory.bytecode;

    console.log(
      "Expected DexT1 Creation Code Hash (from contract):",
      ethers.utils.keccak256(expectedDexT1CreationCode)
    );
    console.log("Expected DexT1 Creation Code Hash (local):", ethers.utils.keccak256(fluidDexT1));
    expect(expectedDexT1CreationCode).to.equal(fluidDexT1);
    console.log(
      "Expected ColOperations Creation Code Hash (from contract):",
      ethers.utils.keccak256(expectedColOperationsCreationCode)
    );
    console.log("Expected ColOperations Creation Code Hash (local):", ethers.utils.keccak256(fluidDexT1OperationsCol));
    expect(expectedColOperationsCreationCode).to.equal(fluidDexT1OperationsCol);
    console.log(
      "Expected DebtOperations Creation Code Hash (from contract):",
      ethers.utils.keccak256(expectedDebtOperationsCreationCode)
    );
    console.log(
      "Expected DebtOperations Creation Code Hash (local):",
      ethers.utils.keccak256(fluidDexT1OperationsDebt)
    );
    expect(expectedDebtOperationsCreationCode).to.equal(fluidDexT1OperationsDebt);
    console.log(
      "Expected PerfectOperations Creation Code Hash (from contract):",
      ethers.utils.keccak256(expectedPerfectOperationsCreationCode)
    );
    console.log(
      "Expected PerfectOperations Creation Code Hash (local):",
      ethers.utils.keccak256(fluidDexT1PerfectOperationsAndSwapOut)
    );
    expect(expectedPerfectOperationsCreationCode).to.equal(fluidDexT1PerfectOperationsAndSwapOut);
  });

  it("should deploy VaultT1DeploymentLogic", async () => {
    const owner = await ethers.getSigner((await getUnnamedAccounts())[0]);

    const liquidity = "0x52Aa899454998Be5b000Ad077a46Bbe360F4e497";

    await deployments.delete("FluidVaultT1Admin");
    await deployments.delete("FluidVaultT1Secondary");
    await deployments.delete("FluidVaultT1DeploymentLogic");

    const adminContract = await deployments.deploy("FluidVaultT1Admin", {
      from: owner.address,
      args: [],
      log: false,
      skipIfAlreadyDeployed: false,
      gasLimit: 30000000,
    });

    const secondary = await deployments.deploy("FluidVaultT1Secondary", {
      from: owner.address,
      args: [],
      log: false,
      skipIfAlreadyDeployed: false,
      gasLimit: 30000000,
    });

    const deploymentLogic = await deployments.deploy("FluidVaultT1DeploymentLogic", {
      from: owner.address,
      args: [liquidity, adminContract.address, secondary.address],
      log: false,
      skipIfAlreadyDeployed: false,
      gasLimit: 30000000,
    });

    const deployedCode = await ethers.provider.getCode(deploymentLogic.address);
    expect(deployedCode).to.not.equal("");
    expect(deployedCode).to.not.equal("0x");
  });
});
