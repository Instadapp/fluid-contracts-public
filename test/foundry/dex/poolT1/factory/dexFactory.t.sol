//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { SStore2Deployer } from "../../../../../contracts/protocols/dex/factory/deploymentHelpers/SSTORE2Deployer.sol";
import { LiquidityBaseTest } from "../../../liquidity/liquidityBaseTest.t.sol";
import { IFluidLiquidityLogic } from "../../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidDexT1OperationsCol } from "../../../../../contracts/protocols/dex/poolT1/coreModule/core/colOperations.sol";
import { FluidDexT1OperationsDebt } from "../../../../../contracts/protocols/dex/poolT1/coreModule/core/debtOperations.sol";
import { FluidDexT1PerfectOperationsAndSwapOut } from "../../../../../contracts/protocols/dex/poolT1/coreModule/core/perfectOperationsAndSwapOut.sol";
import { FluidDexT1 } from "../../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import { FluidDexT1Admin } from "../../../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import { Structs as DexStrcuts } from "../../../../../contracts/protocols/dex/poolT1/coreModule/structs.sol";
import { Structs as DexAdminStructs } from "../../../../../contracts/protocols/dex/poolT1/adminModule/structs.sol";

import { FluidDexFactory } from "../../../../../contracts/protocols/dex/factory/main.sol";
import { FluidDexT1DeploymentLogic } from "../../../../../contracts/protocols/dex/factory/deploymentLogics/poolT1Logic.sol";
import { FluidLiquidityResolver } from "../../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidity } from "../../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidContractFactory } from "../../../../../contracts/deployer/main.sol";

import { MockDexCallback } from "../../../../../contracts/mocks/mockDexCallback.sol";


import "../../../testERC20.sol";
import "../../../testERC20Dec6.sol";

abstract contract DexFactoryBaseTest is LiquidityBaseTest {
    using stdStorage for StdStorage;

    FluidDexFactory dexFactory;
    FluidDexT1DeploymentLogic poolT1DeploymentLogic;
    FluidContractFactory contractDeployerFactory;
    address dexAdminImplementation;

    MockDexCallback mockDexCallback;

    FluidLiquidityResolver liquidityResolver_;

    function setUp() public virtual override {
        super.setUp();

        mockDexCallback = new MockDexCallback(address(liquidity));

        address teamMultisig_ = address(0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e);
        bytes memory randomBytecode_ = hex"6001600101";

        // setting team multisig to a random bytecode to avoid address not a contract error
        vm.etch(teamMultisig_, randomBytecode_);

        SStore2Deployer sStore2Deployer = new SStore2Deployer();
        address colOperations_ = sStore2Deployer.deployCode(type(FluidDexT1OperationsCol).creationCode);
        address debtOperations_ = sStore2Deployer.deployCode(type(FluidDexT1OperationsDebt).creationCode);
        (address perfectOperationsAndSwapOut1_, address perfectOperationsAndSwapOut2_) = sStore2Deployer.deployCodeSplit(
            type(FluidDexT1PerfectOperationsAndSwapOut).creationCode
        );
        (address mainAddress1_, address mainAddress2_) = sStore2Deployer.deployCodeSplit(type(FluidDexT1).creationCode);

        dexFactory = new FluidDexFactory(admin);
        vm.prank(admin);
        dexFactory.setDeployer(alice, true);
        dexAdminImplementation = address(new FluidDexT1Admin());
        contractDeployerFactory = new FluidContractFactory(address(bob));
        poolT1DeploymentLogic = new FluidDexT1DeploymentLogic(
            address(liquidity),
            address(dexFactory),
            address(contractDeployerFactory),
            colOperations_,
            debtOperations_,
            perfectOperationsAndSwapOut1_,
            perfectOperationsAndSwapOut2_,
            mainAddress1_,
            mainAddress2_
        );

        vm.prank(admin);
        dexFactory.setGlobalAuth(alice, true);
        vm.prank(admin);
        dexFactory.setDexDeploymentLogic(address(poolT1DeploymentLogic), true);

        liquidityResolver_ = new FluidLiquidityResolver(IFluidLiquidity(address(liquidity)));
    }
}

contract DexFactoryTest is DexFactoryBaseTest {
    function testDeployNewDex() public {
        FluidDexT1Admin dexWithAdmin_;

        address tokenZero = address(DAI);
        address tokenOne = address(USDC);
        address token0 = tokenZero > tokenOne ? tokenOne : tokenZero;
        address token1 = tokenOne > tokenZero ? tokenOne : tokenZero;
        uint256 token0Wei = 10 ** (token0 == address(USDC) ? 6 : 18);
        uint256 token1Wei = 10 ** (token1 == address(USDC) ? 6 : 18);

        uint256 centerPrice = 1e27;

        vm.prank(alice);
        bytes memory poolT1CreationCode = abi.encodeCall(poolT1DeploymentLogic.dexT1, (token0, token1, 10_000));

        address payable dex = payable(dexFactory.deployDex(address(poolT1DeploymentLogic), poolT1CreationCode));

        _setApproval(USDC, dex, alice);
        _setApproval(USDC, dex, bob);
        _setApproval(DAI, dex, alice);
        _setApproval(DAI, dex, bob);

        // set default allowances for vault
        _setUserAllowancesDefault(address(liquidity), address(admin), address(token0), address(dex));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(token1), address(dex));

        // Updating admin related things to setup dex
        dexWithAdmin_ = FluidDexT1Admin(address(dex));
        DexAdminStructs.InitializeVariables memory i = DexAdminStructs.InitializeVariables({
            smartCol: true,
            token0ColAmt: 1000 * token0Wei,
            smartDebt: true,
            token0DebtAmt: 1000 * token0Wei,
            centerPrice: centerPrice,
            fee: 0,
            revenueCut: 0,
            upperPercent: 11 * 1e4, // 1% = 1e4
            lowerPercent: 10 * 1e4, // 1% = 1e4
            upperShiftThreshold: 5 * 1e4, // 1% = 1e4
            lowerShiftThreshold: 5 * 1e4,
            thresholdShiftTime: 1 days,
            centerPriceAddress: 0,
            hookAddress: 0,
            maxCenterPrice: (centerPrice * 110) / 100,
            minCenterPrice: (centerPrice * 90) / 100
        });

        vm.prank(alice);
        FluidDexT1Admin(dex).initialize(i);

        vm.prank(alice);
        FluidDexT1Admin(dex).toggleOracleActivation(true);

        assertNotEq(dex, address(0));

        uint256 dexId = FluidDexT1(payable(dex)).DEX_ID();

        address computedDexAddress = dexFactory.getDexAddress(dexId);
        assertEq(dex, computedDexAddress);
    }
}
