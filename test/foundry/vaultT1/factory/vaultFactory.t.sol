//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { LiquidityBaseTest } from "../../liquidity/liquidityBaseTest.t.sol";
import { IFluidLiquidityLogic } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidVaultT1 } from "../../../../contracts/protocols/vault/vaultT1/coreModule/main.sol";
import { FluidVaultT1Secondary } from "../../../../contracts/protocols/vault/vaultT1/coreModule/main2.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";
import { FluidVaultFactory } from "../../../../contracts/protocols/vault/factory/main.sol";
import { FluidVaultT1DeploymentLogic } from "../../../../contracts/protocols/vault/factory/deploymentLogics/vaultT1Logic.sol";
import { MockonERC721Received } from "../../../../contracts/mocks/mockERC721.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

import "../../testERC20.sol";
import "../../testERC20Dec6.sol";
import "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";

abstract contract VaultFactoryBaseTest is LiquidityBaseTest {
    using stdStorage for StdStorage;

    FluidVaultFactory vaultFactory;
    FluidVaultT1DeploymentLogic vaultT1Deployer;
    address vaultAdminImplementation_;
    address vaultSecondaryImplementation_;

    FluidLiquidityResolver liquidityResolver;
    FluidVaultResolver vaultResolver;

    function setUp() public virtual override {
        super.setUp();

        vaultFactory = new FluidVaultFactory(admin);
        vm.prank(admin);
        vaultFactory.setDeployer(alice, true);
        vaultAdminImplementation_ = address(new FluidVaultT1Admin());
        vaultSecondaryImplementation_ = address(new FluidVaultT1Secondary());
        vaultT1Deployer = new FluidVaultT1DeploymentLogic(
            address(liquidity),
            vaultAdminImplementation_,
            vaultSecondaryImplementation_
        );

        vm.prank(admin);
        vaultFactory.setGlobalAuth(alice, true);
        vm.prank(admin);
        vaultFactory.setVaultDeploymentLogic(address(vaultT1Deployer), true);

        liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(address(liquidity)));
        vaultResolver = new FluidVaultResolver(address(vaultFactory), address(liquidityResolver));
    }

    function _deployVault(uint64 nonce) internal returns (uint256) {
        vm.setNonceUnsafe(address(vaultFactory), nonce);
        stdstore.target(address(vaultFactory)).sig("totalVaults()").checked_write(nonce - 1);
        vm.startPrank(alice);
        nonce = vm.getNonce(address(vaultFactory));
        bytes memory vaultT1CreationCode = abi.encodeCall(vaultT1Deployer.vaultT1, (address(USDC), address(DAI)));
        address vault = vaultFactory.deployVault(address(vaultT1Deployer), vaultT1CreationCode);
        uint256 vaultId = FluidVaultT1(vault).VAULT_ID();
        address computedVaultAddress = vaultFactory.getVaultAddress(vaultId);
        vm.stopPrank();
        // console.log("Computed Vault Address for vaultId '%s' with nonce '%s': ", vaultId, nonce, computedVaultAddress);
        assertEq(vault, computedVaultAddress);
        return vaultId;
    }

    struct ERC721Data {
        address owner;
        uint256 id;
        uint256 positionIndex;
        uint256 vaultId;
    }

    function calculateStorageSlotUintMapping(uint256 slot_, uint key_) internal pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    function calculateDoubleAddressUintMapping(
        uint256 slot_,
        address key1_,
        uint key2_
    ) internal pure returns (bytes32) {
        bytes32 intermediateSlot_ = keccak256(abi.encode(key1_, slot_));
        return keccak256(abi.encode(key2_, intermediateSlot_));
    }

    function _getERC721BalanceOf(address owner) internal returns (uint256) {
        return (vaultFactory.readFromStorage(calculateDoubleAddressUintMapping(4, owner, 0))) & type(uint32).max;
    }

    function _getERC721VaultId(uint256 id) internal returns (uint256) {
        return (vaultFactory.readFromStorage(calculateStorageSlotUintMapping(3, id)) >> 192) & type(uint32).max;
    }

    function _getERC721PositionIndex(uint256 id) internal returns (uint256) {
        return (vaultFactory.readFromStorage(calculateStorageSlotUintMapping(3, id)) >> 160) & type(uint32).max;
    }

    function _getERC721TokenIndex(address owner, uint256 i) internal returns (uint256) {
        uint256 index = i + 1;
        uint256 word = index / 8;
        uint256 bitIndex = (index % 8) * 32;
        uint256 temp = (vaultFactory.readFromStorage(calculateDoubleAddressUintMapping(4, owner, word)));
        return (temp >> bitIndex) & type(uint32).max;
    }

    function _getERC721DataOfOwner(address owner) internal returns (ERC721Data[] memory datas) {
        uint256 balance = _getERC721BalanceOf(owner);

        datas = new ERC721Data[](balance);

        for (uint256 i = 0; i < balance; i++) {
            uint256 id = _getERC721TokenIndex(owner, i);
            uint256 vaultId = _getERC721VaultId(id);
            uint256 positionIndex = _getERC721PositionIndex(id);
            datas[i] = ERC721Data({
                id: id,
                owner: vaultFactory.ownerOf(id),
                vaultId: vaultId,
                positionIndex: positionIndex
            });
        }

        return datas;
    }

    function _mintERC721ForOwnerWithVaultId(address owner, uint256 vaultId) internal returns (uint256) {
        address computedVaultAddress = vaultFactory.getVaultAddress(vaultId);
        vm.prank(computedVaultAddress);
        return vaultFactory.mint(vaultId, owner);
    }

    function _validateTotalSupply() internal {
        uint256 totalSupply = vaultFactory.totalSupply();

        for (uint i = 0; i < totalSupply; i++) {
            assertEq(vaultFactory.tokenByIndex(i), i + 1, "Validate: totalSupply");
        }
    }

    function _validateOwnerByIndex(address owner) internal {
        uint256 balanceOf = vaultFactory.balanceOf(owner);
        assertEq(_getERC721BalanceOf(owner), balanceOf);
        for (uint i = 0; i < balanceOf; i++) {
            uint256 id = vaultFactory.tokenOfOwnerByIndex(owner, i);
            assertNotEq(id, 0, "Validate: OwnerByIndex");
            assertEq(id, _getERC721TokenIndex(owner, i), "Validate: OwnerByIndex by low level");
        }
        assertEq(_getERC721TokenIndex(owner, balanceOf), 0);
    }

    function _validate(address fromOwner, address toOwner) internal {
        _validateTotalSupply();
        _validateOwnerByIndex(fromOwner);
        _validateOwnerByIndex(toOwner);
    }

    function _transferAndValidate(uint256 id, address from, address to) internal {
        ERC721Data[] memory beforeFromERC721Datas = _getERC721DataOfOwner(from);
        ERC721Data[] memory beforeToERC721Datas = _getERC721DataOfOwner(to);

        uint256 positionIndex = _getERC721PositionIndex(id);
        assertNotEq(positionIndex, 0, "Validate: Position Index of ERC721 to transfer if not 0");
        uint256 vaultId = _getERC721VaultId(id);
        assertNotEq(vaultId, 0);

        _validate(from, to);

        vm.prank(from);
        vaultFactory.transferFrom(from, to, id);

        _validate(from, to);

        ERC721Data[] memory afterToERC721Datas = _getERC721DataOfOwner(to);

        for (uint256 i = 0; i < beforeFromERC721Datas.length; i++) {
            uint256 checkERC721Id = beforeFromERC721Datas[i].id;
            address checkERC721Owner = vaultFactory.ownerOf(checkERC721Id);
            uint256 checkERC721PositionIndex = _getERC721PositionIndex(checkERC721Id);
            assertEq(
                beforeFromERC721Datas[i].vaultId,
                _getERC721VaultId(checkERC721Id),
                "Loop: Validate vaultId for 'from'"
            );
            if (i + 1 < positionIndex) {
                assertEq(checkERC721Owner, from, "Loop: Validate checkERC721Owner < for 'from'");
                assertEq(
                    beforeFromERC721Datas[i].positionIndex,
                    checkERC721PositionIndex,
                    "Loop: Validate positionIndex < for 'from'"
                );
            } else if (i + 1 == positionIndex) {
                assertEq(beforeFromERC721Datas[i].id, checkERC721Id, "Loop: Validate NFT ID == for 'from'");
                assertEq(checkERC721Owner, to, "Loop: Validate checkERC721Owner == for 'from'");
            } else if (i + 1 == beforeFromERC721Datas.length) {
                assertEq(checkERC721Owner, from, "Loop: Validate checkERC721Owner +1 for 'from'");
                assertEq(positionIndex, checkERC721PositionIndex, "Loop: Validate positionIndex +1 for 'from'");
            } else {
                assertEq(checkERC721Owner, from);
                assertEq(
                    beforeFromERC721Datas[i].positionIndex,
                    checkERC721PositionIndex,
                    "Loop: Validate positionIndex > for 'from'"
                );
            }
        }

        for (uint256 i = 0; i < beforeToERC721Datas.length; i++) {
            assertEq(beforeToERC721Datas[i].id, afterToERC721Datas[i].id, "Loop: validate NftID of 'to'");
            assertEq(beforeToERC721Datas[i].vaultId, afterToERC721Datas[i].vaultId, "Loop: validate vaultId of 'to'");
            assertEq(beforeToERC721Datas[i].owner, afterToERC721Datas[i].owner, "Loop: validate owner of 'to'");
            assertEq(
                beforeToERC721Datas[i].positionIndex,
                afterToERC721Datas[i].positionIndex,
                "Loop: validate position of 'to'"
            );
        }
        assertEq(
            (beforeToERC721Datas.length > 0 ? beforeToERC721Datas[beforeToERC721Datas.length - 1].positionIndex : 0) +
                1,
            afterToERC721Datas[beforeToERC721Datas.length].positionIndex,
            "Validate Last PositionIndex of 'to'"
        );
        assertEq(vaultId, afterToERC721Datas[beforeToERC721Datas.length].vaultId, "Validate Last VaultId of 'to'");
    }

    uint256[] aliceERC721TransferData;
    uint256[] bobERC721TransferData;

    function _ERC721SimulateTransfer(uint256 nftToTransferPosition) internal {
        uint32[3] memory nonces = [uint32(1), 2, 3];
        uint256[] memory vaultIds = new uint256[](nonces.length);

        for (uint256 i = 0; i < nonces.length; i++) {
            vaultIds[i] = _deployVault(uint64(nonces[i]));
        }

        uint256 aliceNFTId;
        for (uint256 i = 0; i < aliceERC721TransferData.length; i++) {
            if (i == nftToTransferPosition - 1) {
                aliceNFTId = _mintERC721ForOwnerWithVaultId(address(alice), aliceERC721TransferData[i]);
            } else {
                _mintERC721ForOwnerWithVaultId(address(alice), aliceERC721TransferData[i]);
            }
        }
        assertEq(vaultFactory.balanceOf(alice), aliceERC721TransferData.length);

        for (uint256 i = 0; i < bobERC721TransferData.length; i++) {
            _mintERC721ForOwnerWithVaultId(address(bob), bobERC721TransferData[i]);
        }
        assertEq(vaultFactory.balanceOf(bob), bobERC721TransferData.length);

        _transferAndValidate(aliceNFTId, alice, bob);
        assertEq(vaultFactory.balanceOf(alice), aliceERC721TransferData.length - 1);
        assertEq(vaultFactory.balanceOf(bob), bobERC721TransferData.length + 1);
    }
}

contract VaultFactoryTest is VaultFactoryBaseTest {
    function testDeployNewVault() public {
        MockOracle oracle = new MockOracle();

        FluidVaultT1Admin vaultWithAdmin_;

        vm.prank(alice);

        bytes memory vaultT1CreationCode = abi.encodeCall(vaultT1Deployer.vaultT1, (address(USDC), address(DAI)));

        address vault = vaultFactory.deployVault(address(vaultT1Deployer), vaultT1CreationCode);

        // Updating admin related things to setup vault
        vaultWithAdmin_ = FluidVaultT1Admin(address(vault));
        vm.prank(alice);
        vaultWithAdmin_.updateCoreSettings(
            10000, // supplyFactor_ => 100%
            10000, // borrowFactor_ => 100%
            8000, // collateralFactor_ => 80%
            9000, // liquidationThreshold_ => 90%
            9500, // liquidationMaxLimit_ => 95%
            500, // withdrawGap_ => 5%
            100, // liquidationPenalty_ => 1%
            100 // borrowFee_ => 1%
        );
        vm.prank(alice);
        vaultWithAdmin_.updateOracle(address(oracle));
        vm.prank(alice);
        vaultWithAdmin_.updateRebalancer(address(admin));

        // console.log("Vault Address", vault);
        assertNotEq(vault, address(0));

        uint256 vaultId = FluidVaultT1(vault).VAULT_ID();
        // console.log("Vault Id", vaultId);

        address computedVaultAddress = vaultFactory.getVaultAddress(vaultId);
        // console.log("Computed Vault Address", computedVaultAddress);
        assertEq(vault, computedVaultAddress);
    }

    /////////// Bob no NFTs ///////
    function testTransferOfNFTAliceOneToBobZero() public {
        aliceERC721TransferData = [1];
        bobERC721TransferData = new uint256[](0);
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceSevenToBobZero() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = new uint256[](0);
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceEightToBobZero() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = new uint256[](0);
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceSevenLastToBobZero() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = new uint256[](0);
        _ERC721SimulateTransfer(7);
    }

    function testTransferOfNFTAliceEightLastToBobZero() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = new uint256[](0);
        _ERC721SimulateTransfer(8);
    }

    function testTransferOfNFTAliceSevenRandomToBobZero() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = new uint256[](0);
        _ERC721SimulateTransfer(3);
    }

    function testTransferOfNFTAliceEightRandomToBobZero() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = new uint256[](0);
        _ERC721SimulateTransfer(3);
    }

    /////////// Bob no NFTs ///////

    /////////// Bob 1 NFTs ///////
    function testTransferOfNFTAliceOneToBobOne() public {
        aliceERC721TransferData = [1];
        bobERC721TransferData = [2];
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceSevenToBobOne() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = [2];
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceEightToBobOne() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = [2];
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceSevenLastToBobOne() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = [2];
        _ERC721SimulateTransfer(7);
    }

    function testTransferOfNFTAliceEightLastToBobOne() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = [2];
        _ERC721SimulateTransfer(8);
    }

    function testTransferOfNFTAliceSevenRandomToBobOne() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = [2];
        _ERC721SimulateTransfer(3);
    }

    function testTransferOfNFTAliceEightRandomToBobOne() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = [2];
        _ERC721SimulateTransfer(3);
    }

    /////////// Bob 1 NFTs ///////

    /////////// Bob 7 NFTs ///////

    function testTransferOfNFTAliceOneToBobSeven() public {
        aliceERC721TransferData = [1];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1];
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceSevenToBobSeven() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1];
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceEightToBobSeven() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1];
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceSevenLastToBobSeven() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1];
        _ERC721SimulateTransfer(7);
    }

    function testTransferOfNFTAliceEightLastToBobSeven() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1];
        _ERC721SimulateTransfer(8);
    }

    function testTransferOfNFTAliceSevenRandomToBobSeven() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1];
        _ERC721SimulateTransfer(3);
    }

    function testTransferOfNFTAliceEightRandomToBobSeven() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1];
        _ERC721SimulateTransfer(3);
    }

    /////////// Bob 7 NFTs ///////
    /////////// Bob 8 NFTs ///////

    function testTransferOfNFTAliceOneToBobEight() public {
        aliceERC721TransferData = [1];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1, 3];
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceSevenToBobEight() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1, 3];
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceEightToBobEight() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1, 3];
        _ERC721SimulateTransfer(1);
    }

    function testTransferOfNFTAliceSevenLastToBobEight() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1, 3];
        _ERC721SimulateTransfer(7);
    }

    function testTransferOfNFTAliceEightLastToBobEight() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1, 3];
        _ERC721SimulateTransfer(8);
    }

    function testTransferOfNFTAliceSevenRandomToBobEight() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1, 3];
        _ERC721SimulateTransfer(3);
    }

    function testTransferOfNFTAliceEightRandomToBobEight() public {
        aliceERC721TransferData = [1, 2, 3, 1, 3, 2, 2, 3];
        bobERC721TransferData = [2, 2, 3, 1, 1, 3, 1, 3];
        _ERC721SimulateTransfer(3);
    }

    // /////////// Bob 8 NFTs ///////

    function testDoubleTransfer() public {
        address mockFactoryContract = address(new MockonERC721Received());

        uint32[3] memory nonces = [uint32(1), 2, 3];
        uint256[] memory vaultIds = new uint256[](nonces.length);

        for (uint256 i = 0; i < nonces.length; i++) {
            vaultIds[i] = _deployVault(uint64(nonces[i]));
        }

        _mintERC721ForOwnerWithVaultId(address(alice), 1);
        uint256 aliceNFTId = _mintERC721ForOwnerWithVaultId(address(alice), 3);
        _mintERC721ForOwnerWithVaultId(address(alice), 2);
        _mintERC721ForOwnerWithVaultId(address(alice), 3);

        assertEq(_getERC721PositionIndex(aliceNFTId), 2);
        vm.prank(alice);
        vaultFactory.safeTransferFrom(alice, mockFactoryContract, aliceNFTId, abi.encode(alice));

        assertEq(vaultFactory.balanceOf(alice), 4);
        assertEq(vaultFactory.balanceOf(mockFactoryContract), 0);
        assertEq(vaultFactory.totalSupply(), 4);
        assertEq(_getERC721PositionIndex(aliceNFTId), 4);
    }

    function testComputeAddress() public {
        // nonce of deployment starts with 1.
        uint32[20] memory nonces = [
            1,
            2,
            3,
            10,
            126,
            127,
            128,
            129,
            254,
            255,
            256,
            257,
            65534,
            65535,
            65536,
            65537,
            16777214,
            16777215,
            16777216,
            16777217
        ];

        for (uint256 i = 0; i < nonces.length; i++) {
            _deployVault(uint64(nonces[i]));
        }
    }
}
