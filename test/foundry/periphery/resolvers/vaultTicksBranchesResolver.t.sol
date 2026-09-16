//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { FluidVaultPositionsResolver } from "../../../../contracts/periphery/resolvers/vaultPositions/main.sol";
import { IFluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/iVaultResolver.sol";
import { Structs as FluidVaultTicksBranchesResolverStructs } from "../../../../contracts/periphery/resolvers/vaultTicksBranches/structs.sol";
import { TickMath } from "../../../../contracts/libraries/tickMath.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { FluidVaultTicksBranchesResolver } from "../../../../contracts/periphery/resolvers/vaultTicksBranches/main.sol";
import { IFluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidVaultFactory } from "../../../../contracts/protocols/vault/interfaces/iVaultFactory.sol";
import { FluidVaultT1DeploymentLogic } from "../../../../contracts/protocols/vault/factory/deploymentLogics/vaultT1Logic.sol";
import { FluidVaultFactory } from "../../../../contracts/protocols/vault/factory/main.sol";

contract VaultTicksBranchesResolverTest is Test {
    address internal constant VAULT_FACTORY = 0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d;
    address internal constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;

    address internal constant VAULT_ETH_USDC = 0xeAbBfca72F8a8bf14C4ac59e69ECB2eB69F0811C;
    address internal constant VAULT_WSTETH_ETH = 0xA0F83Fc5885cEBc0420ce7C7b139Adc80c4F4D91;

    IFluidLiquidityResolver liquidityResolver;
    FluidVaultResolver vaultResolver;
    FluidVaultTicksBranchesResolver resolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19377005);

        liquidityResolver = IFluidLiquidityResolver(address(new FluidLiquidityResolver(IFluidLiquidity(LIQUIDITY))));

        vaultResolver = new FluidVaultResolver(VAULT_FACTORY, address(liquidityResolver));

        resolver = new FluidVaultTicksBranchesResolver(IFluidVaultResolver(address(vaultResolver)));
    }

    function test_deployment() public {
        assertEq(address(resolver.VAULT_RESOLVER()), address(vaultResolver));
    }

    function test_getAllTicksDebt() public {
        // note: Adding only 10 here for testing as the function takes time to execute
        // It works fine with 500. But this test will take a lot more time to execute
        resolver.getAllVaultsTicksDebt(500);
    }

    function test_getTicksDebt() public {
        (FluidVaultTicksBranchesResolverStructs.TickDebt[] memory ticksDebt, int toTick_) = resolver.getTicksDebt(
            VAULT_ETH_USDC,
            -13266,
            389
        );
        console.log(uint(-toTick_));
        // should touch mapIds -52, -53, -54 and take 11 ticks debt

        assertEq(ticksDebt.length, 11);
        assertEq(ticksDebt[0].debtRaw, 94912982818);
        assertEq(ticksDebt[0].collateralRaw, 41070257517745793445);
        assertEq(ticksDebt[0].debtNormal, 95147178491);
        assertEq(ticksDebt[0].collateralNormal, 41188121385302245076);
        assertEq(ticksDebt[0].ratio, TickMath.getRatioAtTick(ticksDebt[0].tick));
        assertEq(ticksDebt[0].tick, -13267);

        assertEq(ticksDebt[1].debtRaw, 179955118540);
        assertEq(ticksDebt[1].collateralRaw, 79998744855130300930);
        assertEq(ticksDebt[1].debtNormal, 180399153790);
        assertEq(ticksDebt[1].collateralNormal, 80228326115102029681);
        assertEq(ticksDebt[1].ratio, TickMath.getRatioAtTick(ticksDebt[1].tick));
        assertEq(ticksDebt[1].tick, -13285);

        assertEq(ticksDebt[2].debtRaw, 2050170601);
        assertEq(ticksDebt[2].collateralRaw, 998658820306975276);
        assertEq(ticksDebt[2].debtNormal, 2055229351);
        assertEq(ticksDebt[2].collateralNormal, 1001524782150041022);
        assertEq(ticksDebt[2].ratio, TickMath.getRatioAtTick(ticksDebt[2].tick));
        assertEq(ticksDebt[2].tick, -13346);

        assertEq(ticksDebt[3].debtRaw, 200259833777);
        assertEq(ticksDebt[3].collateralRaw, 100066152950577086518);
        assertEq(ticksDebt[3].debtNormal, 200753970461);
        assertEq(ticksDebt[3].collateralNormal, 100353323874527450683);
        assertEq(ticksDebt[3].ratio, TickMath.getRatioAtTick(ticksDebt[3].tick));
        assertEq(ticksDebt[3].tick, -13363);

        assertEq(ticksDebt[4].debtRaw, 500193337537);
        assertEq(ticksDebt[4].collateralRaw, 250312310301750144877);
        assertEq(ticksDebt[4].debtNormal, 501427553468);
        assertEq(ticksDebt[4].collateralNormal, 251030659266969250944);
        assertEq(ticksDebt[4].ratio, TickMath.getRatioAtTick(ticksDebt[4].tick));
        assertEq(ticksDebt[4].tick, -13364);

        assertEq(ticksDebt[5].debtRaw, 150078101255);
        assertEq(ticksDebt[5].collateralRaw, 80948594748414575796);
        assertEq(ticksDebt[5].debtNormal, 150448415630);
        assertEq(ticksDebt[5].collateralNormal, 81180901897844684359);
        assertEq(ticksDebt[5].ratio, TickMath.getRatioAtTick(ticksDebt[5].tick));
        assertEq(ticksDebt[5].tick, -13414);

        assertEq(ticksDebt[6].debtRaw, 3970374925872);
        assertEq(ticksDebt[6].collateralRaw, 2151178099285791482566);
        assertEq(ticksDebt[6].debtNormal, 3980171737660);
        assertEq(ticksDebt[6].collateralNormal, 2157351573374065866767);
        assertEq(ticksDebt[6].ratio, TickMath.getRatioAtTick(ticksDebt[6].tick));
        assertEq(ticksDebt[6].tick, -13417);

        assertEq(ticksDebt[7].debtRaw, 850992994210);
        assertEq(ticksDebt[7].collateralRaw, 475105333321378312335);
        assertEq(ticksDebt[7].debtNormal, 853092800488);
        assertEq(ticksDebt[7].collateralNormal, 476468795726203970353);
        assertEq(ticksDebt[7].ratio, TickMath.getRatioAtTick(ticksDebt[7].tick));
        assertEq(ticksDebt[7].tick, -13437);

        assertEq(ticksDebt[8].debtRaw, 24979214863);
        assertEq(ticksDebt[8].collateralRaw, 14963649436514276891);
        assertEq(ticksDebt[8].debtNormal, 25040850519);
        assertEq(ticksDebt[8].collateralNormal, 15006592278900508241);
        assertEq(ticksDebt[8].ratio, TickMath.getRatioAtTick(ticksDebt[8].tick));
        assertEq(ticksDebt[8].tick, -13484);

        assertEq(ticksDebt[9].debtRaw, 2002280249);
        assertEq(ticksDebt[9].collateralRaw, 1399689899689663418);
        assertEq(ticksDebt[9].debtNormal, 2007220830);
        assertEq(ticksDebt[9].collateralNormal, 1403706744845451483);
        assertEq(ticksDebt[9].ratio, TickMath.getRatioAtTick(ticksDebt[9].tick));
        assertEq(ticksDebt[9].tick, -13587);

        assertEq(ticksDebt[10].debtRaw, 440090827625);
        assertEq(ticksDebt[10].collateralRaw, 340144282732745604605);
        assertEq(ticksDebt[10].debtNormal, 441176741950);
        assertEq(ticksDebt[10].collateralNormal, 341120432460386684386);
        assertEq(ticksDebt[10].ratio, TickMath.getRatioAtTick(ticksDebt[10].tick));
        assertEq(ticksDebt[10].tick, -13654);
    }
}

contract VaultTicksBranchesResolverBranchesTest is Test {
    address internal constant VAULT_FACTORY = 0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d;
    address internal constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;

    address internal constant VAULT_ETH_USDC = 0xeAbBfca72F8a8bf14C4ac59e69ECB2eB69F0811C;
    address internal constant VAULT_WSTETH_ETH = 0xA0F83Fc5885cEBc0420ce7C7b139Adc80c4F4D91;

    IFluidLiquidityResolver liquidityResolver;
    FluidVaultResolver vaultResolver;
    FluidVaultTicksBranchesResolver resolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19782100);

        liquidityResolver = IFluidLiquidityResolver(address(new FluidLiquidityResolver(IFluidLiquidity(LIQUIDITY))));

        vaultResolver = new FluidVaultResolver(VAULT_FACTORY, address(liquidityResolver));

        resolver = new FluidVaultTicksBranchesResolver(IFluidVaultResolver(address(vaultResolver)));
    }

    function test_getBranchesDebt_CaseOne() public {
        FluidVaultTicksBranchesResolverStructs.BranchDebt[] memory branchesDebt = resolver.getBranchesDebt(
            VAULT_ETH_USDC,
            type(uint).max,
            0
        );

        for (uint i = 0; i < branchesDebt.length; i++) {
            console.log("##############", i);
            console.log("debtRaw", branchesDebt[i].debtRaw);
            console.log("collateralRaw", branchesDebt[i].collateralRaw);
            console.log("debtNormal", branchesDebt[i].debtNormal);
            console.log("collateralNormal", branchesDebt[i].collateralNormal);
            console.log("branchId", branchesDebt[i].branchId);
            console.log("status", branchesDebt[i].status);
            if (branchesDebt[i].tick == type(int).min) {
                console.log("0", uint(0));
            } else if (branchesDebt[i].tick < 0) {
                console.log("-", uint(-branchesDebt[i].tick));
            } else {
                console.log("+", uint(branchesDebt[i].tick));
            }
            console.log("partials", branchesDebt[i].partials);
            console.log("ratio", branchesDebt[i].ratio);
            console.log("debtFactor", branchesDebt[i].debtFactor);
            console.log("baseBranchId", branchesDebt[i].baseBranchId);
            if (branchesDebt[i].baseBranchTick == type(int).min) {
                console.log("0", uint(0));
            } else if (branchesDebt[i].baseBranchTick < 0) {
                console.log("-", uint(-branchesDebt[i].baseBranchTick));
            } else {
                console.log("+", uint(branchesDebt[i].baseBranchTick));
            }
        }

        assertEq(branchesDebt.length, 3);
        assertEq(branchesDebt[0].debtRaw, 1942964);
        assertEq(branchesDebt[0].collateralRaw, 728073139818586);
        assertEq(branchesDebt[0].debtNormal, 1998287);
        assertEq(branchesDebt[0].collateralNormal, 747926715125294);
        assertEq(branchesDebt[0].branchId, 3);
        assertEq(branchesDebt[0].status, 1);

        assertEq(branchesDebt[1].debtRaw, 1213342467);
        assertEq(branchesDebt[1].collateralRaw, 464255286302575154);
        assertEq(branchesDebt[1].debtNormal, 1247890666);
        assertEq(branchesDebt[1].collateralNormal, 476914903563613108);
        assertEq(branchesDebt[1].branchId, 2);
        assertEq(branchesDebt[1].status, 1);

        assertEq(branchesDebt[2].debtRaw, 0);
        assertEq(branchesDebt[2].collateralRaw, 0);
        assertEq(branchesDebt[2].debtNormal, 0);
        assertEq(branchesDebt[2].collateralNormal, 0);
        assertEq(branchesDebt[2].branchId, 1);
        assertEq(branchesDebt[2].status, 3);
    }

    function test_getAllBranchesDebt() public {
        resolver.getAllVaultsBranchesDebt();
    }

    // function test_getBranchesDebt_CaseTwo() public {
    //     FluidVaultTicksBranchesResolverStructs.BranchDebt[] memory branchesDebt = resolver.getBranchesDebt(
    //         VAULT_WSTETH_ETH,
    //         type(uint).max,
    //         type(uint).min
    //     );

    //     assertEq(branchesDebt.length, 1);
    //     assertEq(branchesDebt[0].debtRaw, 27438541083476801693060);
    //     assertEq(branchesDebt[0].collateralRaw, 30725342564402648900048);
    //     assertEq(branchesDebt[0].debtNormal, 27966072239780379385143);
    //     assertEq(branchesDebt[0].collateralNormal, 31266501705367436032909);
    //     assertEq(branchesDebt[0].branchId, 1);
    //     assertEq(branchesDebt[0].status, 0);
    // }
}

contract VaultTicksBranchesResolverRobustnessTest is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidVaultFactory internal constant VAULT_FACTORY = IFluidVaultFactory(0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d);

    FluidVaultT1DeploymentLogic vaultT1Deployer =
        FluidVaultT1DeploymentLogic(0x15f6F562Ae136240AB9F4905cb50aCA54bCbEb5F);

    address internal constant ALLOWED_DEPLOYER = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e; // team multisig is an allowed deployer

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address internal constant Vault_wstETH_USDC = 0x51197586F6A9e2571868b6ffaef308f3bdfEd3aE;

    FluidLiquidityResolver liquidityResolver;
    FluidVaultResolver vaultResolver;

    FluidVaultTicksBranchesResolver resolver;

    address newVault;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19927377);

        liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
        vaultResolver = new FluidVaultResolver(address(VAULT_FACTORY), address(liquidityResolver));

        resolver = new FluidVaultTicksBranchesResolver(IFluidVaultResolver(address(vaultResolver)));

        // create a new vault, without configuring it at Liquidity
        bytes memory vaultT1CreationCode = abi.encodeCall(vaultT1Deployer.vaultT1, (address(USDC), address(WSTETH)));
        vm.prank(ALLOWED_DEPLOYER);
        newVault = FluidVaultFactory(address(VAULT_FACTORY)).deployVault(address(vaultT1Deployer), vaultT1CreationCode);
    }

    function test_allMethodsWithoutReverts() public {
        // this test ensures there are no reverts for any method available on the resolver

        resolver.getAllVaultsBranchesDebt();

        uint256 totalTicks = 100;
        resolver.getAllVaultsTicksDebt(totalTicks);

        address[] memory vaults_ = new address[](2);
        vaults_[0] = Vault_wstETH_USDC;
        vaults_[1] = newVault;
        uint256[] memory totalTicks_ = new uint256[](2);
        totalTicks_[0] = 100;
        totalTicks_[1] = 200;
        int256[] memory fromTicks_ = new int256[](2);
        fromTicks_[0] = -1000;
        fromTicks_[1] = 1000;
        resolver.getMultipleVaultsTicksDebt(vaults_, fromTicks_, totalTicks_);

        uint256[] memory fromBranchIds_ = new uint256[](2);
        fromBranchIds_[0] = 100;
        fromBranchIds_[1] = 1000;
        uint256[] memory toBranchIds_ = new uint256[](2);
        toBranchIds_[0] = 0;
        toBranchIds_[1] = 1;
        resolver.getMultipleVaultsBranchesDebt(vaults_, fromBranchIds_, toBranchIds_);

        int256 fromTick_ = 10000;
        uint256 fromBranchId_ = 100;
        uint256 toBranchId_ = 0;
        address vault_ = Vault_wstETH_USDC;
        resolver.getTicksDebt(vault_, fromTick_, totalTicks);
        resolver.getBranchesDebt(vault_, fromBranchId_, toBranchId_);
        vault_ = newVault;
        resolver.getTicksDebt(vault_, fromTick_, totalTicks);
        resolver.getBranchesDebt(vault_, fromBranchId_, toBranchId_);
    }
}
