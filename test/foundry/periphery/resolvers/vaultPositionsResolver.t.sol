//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { FluidVaultPositionsResolver } from "../../../../contracts/periphery/resolvers/vaultPositions/main.sol";
import { Structs } from "../../../../contracts/periphery/resolvers/vaultPositions/structs.sol";
import { IFluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/iVaultResolver.sol";
import { IFluidVaultFactory } from "../../../../contracts/protocols/vault/interfaces/iVaultFactory.sol";

contract FluidVaultPositionsResolverTest is Test {
    IFluidVaultResolver internal constant VAULT_RESOLVER =
        IFluidVaultResolver(0x8DD65DaDb217f73A94Efb903EB2dc7B49D97ECca);
    IFluidVaultFactory internal constant VAULT_FACTORY = IFluidVaultFactory(0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d);

    address internal constant VAULT_ETH_USDC = 0xeAbBfca72F8a8bf14C4ac59e69ECB2eB69F0811C;

    FluidVaultPositionsResolver resolver;

    uint256[] expectedArray;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19377005);

        // constructor params
        // IFluidVaultResolver vaultResolver_,
        // IFluidVaultFactory vaultFactory_
        resolver = new FluidVaultPositionsResolver(VAULT_RESOLVER, VAULT_FACTORY);
    }

    function test_deployment() public {
        assertEq(address(resolver.VAULT_RESOLVER()), address(VAULT_RESOLVER));
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
