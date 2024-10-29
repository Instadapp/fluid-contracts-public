//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "forge-std/StdUtils.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Structs } from "../../../../contracts/protocols/lending/merkleDistributor/structs.sol";
import { Errors } from "../../../../contracts/protocols/lending/merkleDistributor/errors.sol";
import { Events } from "../../../../contracts/protocols/lending/merkleDistributor/events.sol";
import { FluidMerkleDistributor } from "../../../../contracts/protocols/lending/merkleDistributor/main.sol";

contract FluidMerkleDistributorTest is Test, Events {
    address owner = makeAddr("owner");
    address proposer = makeAddr("proposer");
    address approver = makeAddr("approver");
    address alice = makeAddr("alice");

    FluidMerkleDistributor distributor;

    // @dev see source of these test values at the bottom of the file
    bytes32 internal constant TEST_ROOT_1 = 0xb722f4b18110d2040f218f6bdeee9167c957f23490903d7673a04650dbe621dd;
    bytes32 internal constant TEST_CONTENT_HASH_1 = 0xebae91a2dcf9b26375431949c62b80633ac52d0dcd47aa0d7964d431950ba14e; // for test here just a random bytes32

    bytes32 internal constant TEST_ROOT_2 = 0xdcdc1e16ec7162bbb11074691d5ce88194442e0508d0ef03907c40e825bd709a;
    bytes32 internal constant TEST_CONTENT_HASH_2 = 0xdce87b958009fb6e99231baa505eedcda278bba89d7aaf1c84509901e33c973e; // for test here just a random bytes32

    bytes32 internal constant TEST_ROOT_3 = 0xbb82a0e2430c67c7f773c9b07f21f091adc4580ee5f9e18e9b73751c99c6f88f;
    bytes32 internal constant TEST_CONTENT_HASH_3 = 0x2411d11e02a26d1abb186dfd0feed4508a1383e182680a5e1b7ddbde46a362db; // for test here just a random bytes32

    uint40 internal constant DEFAULT_START_BLOCK = 2;
    uint40 internal constant DEFAULT_END_BLOCK = 22;

    address INST = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;

    IERC20 internal DISTRIUBTION_TOKEN;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19377005);

        // constructor params
        // address owner_, address proposer_, address approver_, address rewardsToken_
        distributor = new FluidMerkleDistributor(owner, proposer, approver, INST);

        DISTRIUBTION_TOKEN = distributor.TOKEN();

        // fill with INST tokens from treasury
        vm.prank(0x28849D2b63fA8D361e5fc15cB8aBB13019884d09);
        DISTRIUBTION_TOKEN.transfer(address(distributor), 1e23);
    }

    function test_deployment() public {
        assertEq(address(distributor.owner()), owner);
        assertEq(distributor.isProposer(proposer), true);
        assertEq(distributor.isProposer(owner), true);
    }

    function test_proposeRoot() public {
        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        distributor.proposeRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);

        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);

        assertEq(distributor.hasPendingRoot(), true);

        Structs.MerkleCycle memory merkleCycle = distributor.pendingMerkleCycle();

        assertEq(merkleCycle.merkleRoot, TEST_ROOT_1);
        assertEq(merkleCycle.merkleContentHash, TEST_CONTENT_HASH_1);
        assertEq(merkleCycle.cycle, 1);
        assertEq(merkleCycle.startBlock, DEFAULT_START_BLOCK);
        assertEq(merkleCycle.endBlock, DEFAULT_END_BLOCK);
        assertNotEq(merkleCycle.publishBlock, 0);
        assertNotEq(merkleCycle.timestamp, 0);
    }

    function test_approveRoot() public {
        assertEq(distributor.currentMerkleCycle().merkleRoot, bytes32(""));

        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);

        assertEq(distributor.hasPendingRoot(), true);

        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        distributor.approveRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);
        vm.prank(proposer);
        vm.expectRevert(Errors.Unauthorized.selector);
        distributor.approveRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);
        vm.prank(approver);
        distributor.approveRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);

        assertEq(distributor.hasPendingRoot(), false);

        Structs.MerkleCycle memory merkleCycle = distributor.currentMerkleCycle();

        assertEq(merkleCycle.merkleRoot, TEST_ROOT_1);
        assertEq(merkleCycle.merkleContentHash, TEST_CONTENT_HASH_1);
        assertEq(merkleCycle.cycle, 1);
        assertEq(merkleCycle.startBlock, DEFAULT_START_BLOCK);
        assertEq(merkleCycle.endBlock, DEFAULT_END_BLOCK);
        assertNotEq(merkleCycle.publishBlock, 0);
        assertNotEq(merkleCycle.timestamp, 0);

        // add a new cycle with owner
        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_2, TEST_CONTENT_HASH_2, 2, DEFAULT_END_BLOCK + 1, DEFAULT_END_BLOCK + 10);
        vm.prank(owner);
        distributor.approveRoot(TEST_ROOT_2, TEST_CONTENT_HASH_2, 2, DEFAULT_END_BLOCK + 1, DEFAULT_END_BLOCK + 10);
    }

    function test_claim() public {
        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);
        vm.prank(owner);
        distributor.approveRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);

        bytes32 fToken = bytes32(uint256(uint160(0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33)));
        address recipient = 0x1111111111111111111111111111111111111111;
        uint256 amount = 5000000000000000000;
        bytes32[] memory proofs = new bytes32[](3);
        proofs[0] = 0x0f2ee3f211cac82f5d789f744f8e05e4ca718acb642dc9493f872e4c0b59f686;
        proofs[1] = 0xa5061119ea1f853333d705665e53dbf5c541ae43f4e4bee83c7b0a429815e1ff;
        proofs[2] = 0x243ffcb2bc8aebe732adc56aca03d46b21765d092adb872cabcc8260cf91b1f0;
        uint256 preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        vm.expectEmit(true, true, true, true);
        emit LogClaimed(0x1111111111111111111111111111111111111111, amount, 1, fToken, block.timestamp, block.number);
        vm.prank(recipient);
        distributor.claim(recipient, amount, fToken, 1, proofs);

        // claiming again should fail
        vm.expectRevert(Errors.NothingToClaim.selector);
        distributor.claim(recipient, amount, fToken, 1, proofs);
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + amount);

        // can also claim for another address (no requirement on msg.sender)
        fToken = bytes32(uint256(uint160(0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB)));
        recipient = 0x2222222222222222222222222222222222222222;
        amount = 2500000000000000000;
        proofs[0] = 0x1cca30f2fbf18b9e6e696fe49551ab18d1dd61028dc8d64a018aef0eaa1e9d25;
        proofs[1] = 0xa5061119ea1f853333d705665e53dbf5c541ae43f4e4bee83c7b0a429815e1ff;
        proofs[2] = 0x243ffcb2bc8aebe732adc56aca03d46b21765d092adb872cabcc8260cf91b1f0;
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        distributor.claim(recipient, amount, fToken, 1, proofs);
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + amount);

        // add a new cycle
        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_2, TEST_CONTENT_HASH_2, 2, DEFAULT_END_BLOCK + 1, DEFAULT_END_BLOCK + 10);
        vm.prank(owner);
        distributor.approveRoot(TEST_ROOT_2, TEST_CONTENT_HASH_2, 2, DEFAULT_END_BLOCK + 1, DEFAULT_END_BLOCK + 10);

        // claim new increased amount
        fToken = bytes32(uint256(uint160(0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB)));
        recipient = 0x2222222222222222222222222222222222222222;
        amount = 5500000000000000000;
        proofs[0] = 0x889800e6851648e8e54c11ad7bb816c6755b21efe203ece07d260c46a6631237;
        proofs[1] = 0xeda1520064ff7f0c2112900fdac71cd3768db97e03173113a9066c0365b86178;
        proofs[2] = 0x50080647d784950a52dab4a72615591654785fb626599a18842812270f26911e;
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        distributor.claim(recipient, amount, fToken, 2, proofs);
        uint256 expectedReceiveAmount = 5500000000000000000 - 2500000000000000000; // already claimed a part previously
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + expectedReceiveAmount);

        // revert with invalid proof
        fToken = bytes32(uint256(uint160(0x4Ce05f946fe262840496F653817CC1121aE74fac)));
        recipient = 0x2222222222222222222222222222222222222223;
        amount = 5500000000000000000;
        proofs = new bytes32[](2);

        proofs[0] = 0x889800e6851648e8e54c11ad7bb816c6755b21efe203ece07d260c46a6631237;
        proofs[1] = 0x76c8efa363cf15fd80acbf3fbab07c350d0a6c9687a30d364a194fe93e3db568;
        vm.expectRevert(Errors.InvalidProof.selector);
        distributor.claim(recipient, amount, fToken, 2, proofs);

        // revert with invalid cycle
        proofs[0] = 0x3376bbfa988e4f4680d95a6338a4acc408bc8c429d30429a6d9b2ee01f8f7ef4;
        proofs[1] = 0x76c8efa363cf15fd80acbf3fbab07c350d0a6c9687a30d364a194fe93e3db568;
        vm.expectRevert(Errors.InvalidCycle.selector);
        distributor.claim(recipient, amount, fToken, 3, proofs);

        // claim full amount at once
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        distributor.claim(recipient, amount, fToken, 2, proofs);
        expectedReceiveAmount = 5500000000000000000 - 0; // already claimed a part previously
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + expectedReceiveAmount);

        // add a new cycle
        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_3, TEST_CONTENT_HASH_3, 3, DEFAULT_END_BLOCK + 11, DEFAULT_END_BLOCK + 20);
        vm.prank(owner);
        distributor.approveRoot(TEST_ROOT_3, TEST_CONTENT_HASH_3, 3, DEFAULT_END_BLOCK + 11, DEFAULT_END_BLOCK + 20);

        // can claim for multiple fTokens for same user
        recipient = 0x2222222222222222222222222222222222222227;
        amount = 2500000000000000000;

        fToken = bytes32(uint256(uint160(0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663)));
        proofs = new bytes32[](3);
        proofs[0] = 0x78d33aec72ec538b9dc6258b892a509398494928ef66b2411b1c06b4f2b9ed74;
        proofs[1] = 0x496b8a096ce72cb827617fc8c5deb4770cc7fc9afcdaee0fa38f270186790e7b;
        proofs[2] = 0x458904ee917a00c8f950ff287f87653caef1acd1d7d7bec0a72f5c727e0e4606;
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        distributor.claim(recipient, amount, fToken, 3, proofs);
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + amount);

        fToken = bytes32(uint256(uint160(0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2)));
        proofs[0] = 0x823acb9710b95d5bc5c00a094d672b465957e69637128e597df80760ed7a7c36;
        proofs[1] = 0x496b8a096ce72cb827617fc8c5deb4770cc7fc9afcdaee0fa38f270186790e7b;
        proofs[2] = 0x458904ee917a00c8f950ff287f87653caef1acd1d7d7bec0a72f5c727e0e4606;
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        distributor.claim(recipient, amount, fToken, 3, proofs);
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + amount);

        fToken = bytes32(uint256(uint160(0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473)));
        proofs[0] = 0x8f24c81628e7da98aecef7815bf25abfa93f4a04d0119ecec52d0cea29cbd1b3;
        proofs[1] = 0x583e11acf71acb893477d92fcd3cffd4f3e52e44d3a82673998998f7a7e8c06f;
        proofs[2] = 0x458904ee917a00c8f950ff287f87653caef1acd1d7d7bec0a72f5c727e0e4606;
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        distributor.claim(recipient, amount, fToken, 3, proofs);
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + amount);
    }
}

// @dev can build a simple merkle root for testing like this in JS:
// import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
// const values = [
//   ["0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33", "0x1111111111111111111111111111111111111111", "1", "5000000000000000000"],
//   ["0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB", "0x2222222222222222222222222222222222222222", "1", "2500000000000000000"],
//   ["0x4Ce05f946fe262840496F653817CC1121aE74fac", "0x2222222222222222222222222222222222222223", "1", "2500000000000000000"],
//   ["0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1", "0x2222222222222222222222222222222222222224", "1", "2500000000000000000"],
//   ["0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663", "0x2222222222222222222222222222222222222225", "1", "2500000000000000000"],
//   ["0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2", "0x2222222222222222222222222222222222222226", "1", "2500000000000000000"],
//   ["0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473", "0x2222222222222222222222222222222222222227", "1", "2500000000000000000"],
// ];
// const tree = StandardMerkleTree.of(values, ["address", "address", "uint256", "uint256"]);
// console.log('Merkle Root:', tree.root);
// let i = 0;
// for (const value of values) {
//   console.log(`proof for fToken: ${value[0]}:`, tree.getProof(i));
//   i++;
// }
//
// result:
// Merkle Root:
// 0xb722f4b18110d2040f218f6bdeee9167c957f23490903d7673a04650dbe621dd
// proof for fToken: 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33:
// ['0x0f2ee3f211cac82f5d789f744f8e05e4ca718acb642dc9493f872e4c0b59f686',
//   '0xa5061119ea1f853333d705665e53dbf5c541ae43f4e4bee83c7b0a429815e1ff',
//   '0x243ffcb2bc8aebe732adc56aca03d46b21765d092adb872cabcc8260cf91b1f0'
// ]
// proof for fToken: 0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB:
// ['0x1cca30f2fbf18b9e6e696fe49551ab18d1dd61028dc8d64a018aef0eaa1e9d25',
//   '0xa5061119ea1f853333d705665e53dbf5c541ae43f4e4bee83c7b0a429815e1ff',
//   '0x243ffcb2bc8aebe732adc56aca03d46b21765d092adb872cabcc8260cf91b1f0'
// ]
// proof for fToken: 0x4Ce05f946fe262840496F653817CC1121aE74fac:
// ['0x9dede11f8a1e2592231a5154b525122df8b2c10de49a87dfe1e89878836198c2',
//   '0x901ec68d57ecd635b75c3746297687b8d385a5c232ce5ccd3980e83a44f7fa12',
//   '0xb56477057b0fa0c51bd5096706c8287baac4fa361c62e52f275deafc12af1798'
// ]
// proof for fToken: 0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1:
// ['0x4df43a059b5cfd69765ecf486d7e3cf1c2c9564d44f4681529a3e21995f6816b',
//   '0xad3eab359f1996e5422cb2304001c01c0f7a2d81c3837b91d20e04fffa37d986',
//   '0xb56477057b0fa0c51bd5096706c8287baac4fa361c62e52f275deafc12af1798'
// ]
// proof for fToken: 0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663:
// ['0x58a6cdc6b02b1f0dca8c7bad2a8adedd9ceff23639c69cce9f502f88ee2e449b',
//   '0x901ec68d57ecd635b75c3746297687b8d385a5c232ce5ccd3980e83a44f7fa12',
//   '0xb56477057b0fa0c51bd5096706c8287baac4fa361c62e52f275deafc12af1798'
// ]
// proof for fToken: 0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2:
// ['0x27203de0ca7952b867b011a559d36d62fe8f0a450b19e9df1cf36e23a44212ee',
//   '0xad3eab359f1996e5422cb2304001c01c0f7a2d81c3837b91d20e04fffa37d986',
//   '0xb56477057b0fa0c51bd5096706c8287baac4fa361c62e52f275deafc12af1798'
// ]
// proof for fToken: 0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473:
// ['0x9b650ec44a3d61d8b32a8562c7c881b15bf48759afea0750e19fc037b6344af9',
//   '0x243ffcb2bc8aebe732adc56aca03d46b21765d092adb872cabcc8260cf91b1f0'
// ]
//
// cycle 2 with increased amounts:
// const values = [
//   ["0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33", "0x1111111111111111111111111111111111111111", "2", "8000000000000000000"],
//   ["0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB", "0x2222222222222222222222222222222222222222", "2", "5500000000000000000"],
//   ["0x4Ce05f946fe262840496F653817CC1121aE74fac", "0x2222222222222222222222222222222222222223", "2", "5500000000000000000"],
//   ["0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1", "0x2222222222222222222222222222222222222224", "2", "5500000000000000000"],
//   ["0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663", "0x2222222222222222222222222222222222222225", "2", "5500000000000000000"],
//   ["0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2", "0x2222222222222222222222222222222222222226", "2", "5500000000000000000"],
//   ["0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473", "0x2222222222222222222222222222222222222227", "2", "5500000000000000000"],
// ];
// result:
// Merkle Root:
// 0xdcdc1e16ec7162bbb11074691d5ce88194442e0508d0ef03907c40e825bd709a
// proof for fToken: 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33:
// ['0x64d8da7a48f9ddb12c076505241a70ff6dc005a22f44686e0f9a37ec2f30f96a',
//   '0xeda1520064ff7f0c2112900fdac71cd3768db97e03173113a9066c0365b86178',
//   '0x50080647d784950a52dab4a72615591654785fb626599a18842812270f26911e'
// ]
// proof for fToken: 0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB:
// ['0x889800e6851648e8e54c11ad7bb816c6755b21efe203ece07d260c46a6631237',
//   '0xeda1520064ff7f0c2112900fdac71cd3768db97e03173113a9066c0365b86178',
//   '0x50080647d784950a52dab4a72615591654785fb626599a18842812270f26911e'
// ]
// proof for fToken: 0x4Ce05f946fe262840496F653817CC1121aE74fac:
// ['0x3376bbfa988e4f4680d95a6338a4acc408bc8c429d30429a6d9b2ee01f8f7ef4',
//   '0x76c8efa363cf15fd80acbf3fbab07c350d0a6c9687a30d364a194fe93e3db568'
// ]
// proof for fToken: 0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1:
// ['0xa17a97d025b966174c986da52d002fcf6883d3e5163ed64e87440505f5fdc83e',
//   '0x8f0af5ef2d41f7fb76d621fefa1bb0f8445ff21a15522aded243cf56425c922b',
//   '0x50080647d784950a52dab4a72615591654785fb626599a18842812270f26911e'
// ]
// proof for fToken: 0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663:
// ['0xce209d1402e1df9c7033fde9bbdda6c58dba2e9364273eb5ca0af90ec9e60cb4',
//   '0x8f0af5ef2d41f7fb76d621fefa1bb0f8445ff21a15522aded243cf56425c922b',
//   '0x50080647d784950a52dab4a72615591654785fb626599a18842812270f26911e'
// ]
// proof for fToken: 0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2:
// ['0x3a30d50e77d241bf449a4ff2c81c28754b6c184b11dce3187bfd92b3060f77c0',
//   '0xdef3b6b82257e3fe53768aed76d66b3a670c63f7420051c2c8e0a8407b332f58',
//   '0x76c8efa363cf15fd80acbf3fbab07c350d0a6c9687a30d364a194fe93e3db568'
// ]
// proof for fToken: 0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473:
// ['0x489c8ad1341484f7008d69b1280b4e4572c925736290464111224c9890008b31',
//   '0xdef3b6b82257e3fe53768aed76d66b3a670c63f7420051c2c8e0a8407b332f58',
//   '0x76c8efa363cf15fd80acbf3fbab07c350d0a6c9687a30d364a194fe93e3db568'
// ]
//
// cycle 3 with same user for different fTokens:
// const values = [
//   ["0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33", "0x1111111111111111111111111111111111111111", "3", "5000000000000000000"],
//   ["0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB", "0x2222222222222222222222222222222222222222", "3", "2500000000000000000"],
//   ["0x4Ce05f946fe262840496F653817CC1121aE74fac", "0x2222222222222222222222222222222222222223", "3", "2500000000000000000"],
//   ["0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1", "0x2222222222222222222222222222222222222224", "3", "2500000000000000000"],
//   ["0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663", "0x2222222222222222222222222222222222222227", "3", "2500000000000000000"],
//   ["0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2", "0x2222222222222222222222222222222222222227", "3", "2500000000000000000"],
//   ["0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473", "0x2222222222222222222222222222222222222227", "3", "2500000000000000000"],
// ];
// result:
// Merkle Root:
// 0xbb82a0e2430c67c7f773c9b07f21f091adc4580ee5f9e18e9b73751c99c6f88f
// proof for fToken: 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33:
// ['0x9cfa912e27eb4661e288a20061c10b4c4549df52b9c294dd6f7e2b43bfc5a9b9',
//   '0x583e11acf71acb893477d92fcd3cffd4f3e52e44d3a82673998998f7a7e8c06f',
//   '0x458904ee917a00c8f950ff287f87653caef1acd1d7d7bec0a72f5c727e0e4606'
// ]
// proof for fToken: 0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB:
// ['0x08e5de7b7226389886e976fb4f8c552c355b8c80129ed74f0385deb2ef2131d9',
//   '0xcc1123387b54e08e95ab389fb991310fe2ce6d832999473a0a61262e927889a8',
//   '0x7dba5063b48257d6ba141a372b2f3dce88e525d58bac3bdae6e9015195ae183d'
// ]
// proof for fToken: 0x4Ce05f946fe262840496F653817CC1121aE74fac:
// ['0x62f2ef4b532602a6dc17e7fd2e24321dd64cfebed90632cdeb454e4aeb2ea7de',
//   '0x7dba5063b48257d6ba141a372b2f3dce88e525d58bac3bdae6e9015195ae183d'
// ]
// proof for fToken: 0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1:
// ['0x65dbe725b043aedb3bc1921fadd4273bd765d06e5726a5d498615f16a972c6c3',
//   '0xcc1123387b54e08e95ab389fb991310fe2ce6d832999473a0a61262e927889a8',
//   '0x7dba5063b48257d6ba141a372b2f3dce88e525d58bac3bdae6e9015195ae183d'
// ]
// proof for fToken: 0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663:
// ['0x78d33aec72ec538b9dc6258b892a509398494928ef66b2411b1c06b4f2b9ed74',
//   '0x496b8a096ce72cb827617fc8c5deb4770cc7fc9afcdaee0fa38f270186790e7b',
//   '0x458904ee917a00c8f950ff287f87653caef1acd1d7d7bec0a72f5c727e0e4606'
// ]
// proof for fToken: 0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2:
// ['0x823acb9710b95d5bc5c00a094d672b465957e69637128e597df80760ed7a7c36',
//   '0x496b8a096ce72cb827617fc8c5deb4770cc7fc9afcdaee0fa38f270186790e7b',
//   '0x458904ee917a00c8f950ff287f87653caef1acd1d7d7bec0a72f5c727e0e4606'
// ]
// proof for fToken: 0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473:
// ['0x8f24c81628e7da98aecef7815bf25abfa93f4a04d0119ecec52d0cea29cbd1b3',
//   '0x583e11acf71acb893477d92fcd3cffd4f3e52e44d3a82673998998f7a7e8c06f',
//   '0x458904ee917a00c8f950ff287f87653caef1acd1d7d7bec0a72f5c727e0e4606'
// ]
