//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { FluidVaultPositionsResolver } from "../../../../contracts/periphery/resolvers/vaultPositions/main.sol";
import { Structs } from "../../../../contracts/periphery/resolvers/vaultPositions/structs.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/iVaultResolver.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidVaultFactory } from "../../../../contracts/protocols/vault/interfaces/iVaultFactory.sol";
import { FluidVaultFactory } from "../../../../contracts/protocols/vault/factory/main.sol";
import { FluidVaultT1DeploymentLogic } from "../../../../contracts/protocols/vault/factory/deploymentLogics/vaultT1Logic.sol";

contract FluidVaultPositionsResolverTest is Test {
    // address internal constant LIQUIDITY_RESOLVER = 0x645C84DeA082328e456892D2E68d434b61AD7dBF;
    IFluidVaultFactory internal constant VAULT_FACTORY = IFluidVaultFactory(0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d);

    address internal constant VAULT_ETH_USDC = 0xeAbBfca72F8a8bf14C4ac59e69ECB2eB69F0811C;

    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);

    FluidVaultPositionsResolver resolver;
    FluidVaultResolver vaultResolver;

    uint256[] expectedArray;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19377005);

        // deploy resolver dependencies newest state
        FluidLiquidityResolver liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
        vaultResolver = new FluidVaultResolver(address(VAULT_FACTORY), address(liquidityResolver));

        // constructor params
        // IFluidVaultResolver vaultResolver_,
        // IFluidVaultFactory vaultFactory_
        resolver = new FluidVaultPositionsResolver(IFluidVaultResolver(address(vaultResolver)), VAULT_FACTORY);
    }

    function test_deployment() public {
        assertEq(address(resolver.VAULT_RESOLVER()), address(vaultResolver));
        assertEq(address(resolver.FACTORY()), address(VAULT_FACTORY));
    }

    function test_getAllVaultNftIds() public {
        uint256[] memory nftIds = resolver.getAllVaultNftIds(VAULT_ETH_USDC);
        assertEq(nftIds.length, 25);
        expectedArray = [
            1,
            7,
            11,
            12,
            15,
            16,
            19,
            20,
            21,
            22,
            24,
            26,
            27,
            28,
            32,
            34,
            35,
            40,
            41,
            42,
            44,
            45,
            46,
            47,
            48
        ];
        assertEqArray(nftIds, expectedArray);
    }

    function test_getPositionsForNftIds() public {
        uint256[] memory nftIds = new uint256[](5);
        nftIds[0] = 1;
        nftIds[1] = 11;
        nftIds[2] = 19;
        nftIds[3] = 34;
        nftIds[4] = 46;

        Structs.UserPosition[] memory positions = resolver.getPositionsForNftIds(nftIds);

        assertEq(positions.length, 5);
        assertEqUserPosition(
            positions[0],
            1,
            0xb0BC021DABA3f2d737bb529c7Eea2a783aE5208b,
            100285659990432387,
            100243612
        );
        assertEqUserPosition(
            positions[1],
            11,
            0x3BD7c3DF5dcf67f3aA314500c683C82Dc65671d5,
            476468795726226000098,
            852069982383
        );
        assertEqUserPosition(
            positions[2],
            19,
            0xD56F9735D180ac3d79b064fEe82122e4D17fB867,
            15062766146787867736,
            17150038287
        );
        assertEqUserPosition(positions[3], 34, 0x768d5dA3F7E8EEC06BaE2E608D78B339E3CB2938, 280444459258189903, 0);
        assertEqUserPosition(
            positions[4],
            46,
            0xCA686974913389D42F3C5F61010503DAccDb487a,
            100353323874905460597,
            200534601505
        );
    }

    function test_getAllVaultPositions() public {
        Structs.UserPosition[] memory positions = resolver.getAllVaultPositions(VAULT_ETH_USDC);

        assertEq(positions.length, 25);
        assertEqUserPosition(
            positions[0],
            1,
            0xb0BC021DABA3f2d737bb529c7Eea2a783aE5208b,
            100285659990432387,
            100243612
        );
        assertEqUserPosition(
            positions[2],
            11,
            0x3BD7c3DF5dcf67f3aA314500c683C82Dc65671d5,
            476468795726226000098,
            852069982383
        );
        assertEqUserPosition(
            positions[6],
            19,
            0xD56F9735D180ac3d79b064fEe82122e4D17fB867,
            15062766146787867736,
            17150038287
        );
        assertEqUserPosition(positions[15], 34, 0x768d5dA3F7E8EEC06BaE2E608D78B339E3CB2938, 280444459258189903, 0);
        assertEqUserPosition(
            positions[22],
            46,
            0xCA686974913389D42F3C5F61010503DAccDb487a,
            100353323874905460597,
            200534601505
        );
    }

    function assertEqArray(uint256[] memory array1, uint256[] memory array2) internal {
        if (keccak256(abi.encode(array1)) != keccak256(abi.encode(array2))) {
            assertTrue(false, "Array mismatch");
        }
    }

    function assertEqUserPosition(
        Structs.UserPosition memory position,
        uint256 nftId,
        address owner,
        uint256 supply,
        uint256 borrow
    ) internal {
        assertEq(position.nftId, nftId);
        assertEq(position.owner, owner);
        assertEq(position.supply, supply);
        assertEq(position.borrow, borrow);
    }
}

contract FluidVaultPositionsResolverRobustnessTest is Test {
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

    FluidVaultPositionsResolver resolver;

    address newVault;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19927377);

        liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
        vaultResolver = new FluidVaultResolver(address(VAULT_FACTORY), address(liquidityResolver));

        resolver = new FluidVaultPositionsResolver(IFluidVaultResolver(address(vaultResolver)), VAULT_FACTORY);

        // create a new vault, without configuring it at Liquidity
        bytes memory vaultT1CreationCode = abi.encodeCall(vaultT1Deployer.vaultT1, (address(USDC), address(WSTETH)));
        vm.prank(ALLOWED_DEPLOYER);
        newVault = FluidVaultFactory(address(VAULT_FACTORY)).deployVault(address(vaultT1Deployer), vaultT1CreationCode);
    }

    function test_allMethodsWithoutReverts() public {
        // this test ensures there are no reverts for any method available on the resolver
        resolver.getAllVaultNftIds(Vault_wstETH_USDC);
        resolver.getAllVaultPositions(Vault_wstETH_USDC);

        resolver.getAllVaultNftIds(newVault);
        resolver.getAllVaultPositions(newVault);

        uint256[] memory nftIds_ = new uint256[](3);
        nftIds_[0] = 2;
        nftIds_[0] = 7;
        nftIds_[0] = 1e8;

        resolver.getPositionsForNftIds(nftIds_);
    }
}

contract FluidVaultPositionsResolverGasTest is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidVaultFactory internal constant VAULT_FACTORY = IFluidVaultFactory(0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d);

    address internal constant VAULT_WEETH_WSTETH = 0x40D9b8417E6E1DcD358f04E3328bCEd061018A82;
    address internal constant Vault_wstETH_USDC = 0x51197586F6A9e2571868b6ffaef308f3bdfEd3aE;

    FluidLiquidityResolver liquidityResolver;
    FluidVaultResolver vaultResolver;

    FluidVaultPositionsResolver resolver;

    FluidVaultPositionsResolver internal constant OLD_VAULT_POSITIONS_RESOLVER =
        FluidVaultPositionsResolver(0x99e83869417bDEa4E526Af50430e5082aB386bEB);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(20021006);

        liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
        vaultResolver = new FluidVaultResolver(address(VAULT_FACTORY), address(liquidityResolver));

        resolver = new FluidVaultPositionsResolver(IFluidVaultResolver(address(vaultResolver)), VAULT_FACTORY);
    }

    function test_getAllVaultNftIds() public {
        resolver.getAllVaultNftIds(VAULT_WEETH_WSTETH);
    }

    function test_getAllVaultPositions() public {
        resolver.getAllVaultPositions(VAULT_WEETH_WSTETH);
    }

    function test_getAllVaulPositionsSameAsOldResolver() public {
        Structs.UserPosition[] memory positionsNew = resolver.getAllVaultPositions(Vault_wstETH_USDC);
        Structs.UserPosition[] memory positionsOld = OLD_VAULT_POSITIONS_RESOLVER.getAllVaultPositions(
            Vault_wstETH_USDC
        );

        assertEq(keccak256(abi.encode(positionsNew)), keccak256(abi.encode(positionsOld)));
    }
}
