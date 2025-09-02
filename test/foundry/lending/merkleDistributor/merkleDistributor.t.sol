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

// To test run: forge test -vvv --match-path test/foundry/lending/merkleDistributor/merkleDistributor.t.sol
contract FluidMerkleDistributorTest is Test, Events {
    address owner = makeAddr("owner");
    address proposer = makeAddr("proposer");
    address approver = makeAddr("approver");
    address alice = makeAddr("alice");

    FluidMerkleDistributor distributor;
    FluidMerkleDistributor ghoDistributor;

    // @dev see source of these test values at the bottom of the file
    bytes32 internal constant TEST_ROOT_1 = 0x0af7cd0b7eb0349a5ffc4800cb5177af541a3d211a79770b185331244240ffd3;
    bytes32 internal constant TEST_CONTENT_HASH_1 = 0xebae91a2dcf9b26375431949c62b80633ac52d0dcd47aa0d7964d431950ba14e; // for test here just a random bytes32

    bytes32 internal constant TEST_ROOT_2 = 0x11a6fc9d28d1b3010cfada6752c570bde414f132e88733d5c0cf2937a16e5b2e;
    bytes32 internal constant TEST_CONTENT_HASH_2 = 0xdce87b958009fb6e99231baa505eedcda278bba89d7aaf1c84509901e33c973e; // for test here just a random bytes32

    bytes32 internal constant TEST_ROOT_3 = 0xb5baf06a349178debd4c137fe78fbe1250f4f624dc3f256314e1f6814ad0013b;
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
        distributor = new FluidMerkleDistributor(
            Structs.ConstructorParams({
                name: "Merkle",
                owner: owner,
                proposer: proposer,
                approver: approver,
                rewardToken: INST,
                distributionInHours: 1,
                cycleInHours: 1,
                startBlock: block.number,
                pullFromDistributor: false,
                vestingTime: 0,
                vestingStartTime: 0
            })
        );

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
        proofs[0] = 0x0dd18999347c4ee2aadd74dd417464aba3fbf0e81ae3329dfb8c4a3470e9c548;
        proofs[1] = 0xedaca12b19e8ba9d3accc9297d68b0590e331788bddb35ed6a6854e31357a006;
        proofs[2] = 0x9aa24e378a9bc4559be5339be001f36d168756f3eb0fc7c331ebf6e3054c130d;
        uint256 preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        vm.expectEmit(true, true, true, true);
        emit LogClaimed(recipient, amount, 1, 1, fToken, block.timestamp, block.number);
        vm.prank(recipient);
        distributor.claim(recipient, amount, 1, fToken, 1, proofs, new bytes(0));

        // claiming again should fail
        vm.expectRevert(Errors.NothingToClaim.selector);
        vm.prank(recipient);
        distributor.claim(recipient, amount, 1, fToken, 1, proofs, new bytes(0));
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + amount);

        // can NOT claim for another address (requirement on msg.sender)
        fToken = bytes32(uint256(uint160(0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB)));
        recipient = 0x2222222222222222222222222222222222222222;
        amount = 2500000000000000000;
        proofs[0] = 0x028c81e98db687dd63fc119fd39bf2b905dcc13639444fd82c210a123040977c;
        proofs[1] = 0xedaca12b19e8ba9d3accc9297d68b0590e331788bddb35ed6a6854e31357a006;
        proofs[2] = 0x9aa24e378a9bc4559be5339be001f36d168756f3eb0fc7c331ebf6e3054c130d;
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        vm.expectRevert(Errors.MsgSenderNotRecipient.selector);
        distributor.claim(recipient, amount, 1, fToken, 1, proofs, new bytes(0));

        vm.prank(recipient);
        distributor.claim(recipient, amount, 1, fToken, 1, proofs, new bytes(0));
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
        proofs[0] = 0x3e1a67398067442c923973fec25c360285130fb452076ec177c841fb711dc557;
        proofs[1] = 0xe4031d0dafa85118a42e5941ec78ec41b1914a1309155c0e16b56e1c90de92f6;
        proofs[2] = 0x0f4aaf27082d1b48e5e6e15a496fa544db7a513ea5151f3c7268519f842182fc;
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        vm.prank(recipient);
        distributor.claim(recipient, amount, 1, fToken, 2, proofs, new bytes(0));
        uint256 expectedReceiveAmount = 5500000000000000000 - 2500000000000000000; // already claimed a part previously
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + expectedReceiveAmount);

        // revert with invalid proof
        fToken = bytes32(uint256(uint160(0x4Ce05f946fe262840496F653817CC1121aE74fac)));
        recipient = 0x2222222222222222222222222222222222222223;
        amount = 5500000000000000000;
        proofs = new bytes32[](3);

        proofs[0] = 0x889800e6851648e8e54c11ad7bb816c6755b21efe203ece07d260c46a6631237;
        proofs[1] = 0x76c8efa363cf15fd80acbf3fbab07c350d0a6c9687a30d364a194fe93e3db568;
        proofs[2] = 0x0f4aaf27082d1b48e5e6e15a496fa544db7a513ea5151f3c7268519f842182fc;
        vm.expectRevert(Errors.InvalidProof.selector);
        vm.prank(recipient);
        distributor.claim(recipient, amount, 1, fToken, 2, proofs, new bytes(0));

        // revert with invalid cycle
        proofs[0] = 0xd673d8e8b917f8fdbd6f5871a48ca750e79502534cd746e4a9e90fae64490d37;
        proofs[1] = 0x25bb7995965a63a80d8ecfb1ac493b59ca7d0e378fef88f27b76b46aa8359bd9;
        proofs[2] = 0xc2b91c33608f4260c9612544815ab14d3be1e021ac4af93f6624273ab56817d3;
        vm.expectRevert(Errors.InvalidCycle.selector);
        vm.prank(recipient);
        distributor.claim(recipient, amount, 1, fToken, 3, proofs, new bytes(0));

        // claim full amount at once
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        vm.prank(recipient);
        distributor.claim(recipient, amount, 1, fToken, 2, proofs, new bytes(0));
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
        proofs = new bytes32[](2);
        proofs[0] = 0xe7e76fc050d2a389b8030cbac820d38ce5587a0c96223b56767139fda86c6319;
        proofs[1] = 0x5ff386be94619ed8c5fd142f7b75b3eae51b29dadac45af85cc178c1d8d4395d;
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        vm.prank(recipient);
        distributor.claim(recipient, amount, 2, fToken, 3, proofs, abi.encodePacked(bytes2(0x1234)));
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + amount);

        fToken = bytes32(uint256(uint160(0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2)));
        proofs = new bytes32[](3);
        proofs[0] = 0x27ae11729acca4e17bcb76fb6c141c0802c65ac750247e31ef40672efe61c734;
        proofs[1] = 0xeb6df30129039ab04e20fd78ffa7af8570d0e3e49c7dac751eabba32cf927ddd;
        proofs[2] = 0x5ff386be94619ed8c5fd142f7b75b3eae51b29dadac45af85cc178c1d8d4395d;
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        vm.prank(recipient);
        distributor.claim(recipient, amount, 2, fToken, 3, proofs, abi.encodePacked(bytes2(0x1234)));
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + amount);

        fToken = bytes32(uint256(uint160(0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473)));
        proofs[0] = 0x830b3649b55cd4250be01e38475823e2fa621fa54bb61eaf6b3d66acb5e4b02c;
        proofs[1] = 0x6389726f83e624c3b543d247131ac424e633cacb89fb2515e6eb1c03630b45fe;
        proofs[2] = 0x4d673afd439fc32654c70e5bda574ebc62d2cdc20d66352865fda7c59859a328;
        preClaimBalance = DISTRIUBTION_TOKEN.balanceOf(recipient);
        vm.prank(recipient);
        distributor.claim(recipient, amount, 2, fToken, 3, proofs, abi.encodePacked(bytes2(0x1234)));
        assertEq(DISTRIUBTION_TOKEN.balanceOf(recipient), preClaimBalance + amount);
    }
}

contract FluidGHO_MerkleDistributorTest is Test, Events {
    address owner = makeAddr("owner");
    address proposer = makeAddr("proposer");
    address approver = makeAddr("approver");

    FluidMerkleDistributor ghoDistributor;

    // @dev see source of these test values at the bottom of the file
    bytes32 internal constant TEST_ROOT_1 = 0x629e910a96a92d943fcbbdc0297ce02970e36838c19b7dfe416b2af3d075a93b;
    bytes32 internal constant TEST_CONTENT_HASH_1 = 0xebae91a2dcf9b26375431949c62b80633ac52d0dcd47aa0d7964d431950ba14e; // for test here just a random bytes32

    uint40 internal constant DEFAULT_START_BLOCK = 21866154;
    uint40 internal constant DEFAULT_END_BLOCK = 21876154;

    address internal recipient = 0x1111111111111111111111111111111111111111;

    address GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;

    address GHO_DISTRIBUTOR = 0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21866154);

        // address owner_, address proposer_, address approver_, address rewardsToken_
        ghoDistributor = new FluidMerkleDistributor(
            Structs.ConstructorParams({
                name: "GHO_Rewards",
                owner: owner,
                proposer: proposer,
                approver: approver,
                rewardToken: GHO,
                distributionInHours: 1,
                cycleInHours: 1,
                startBlock: block.number,
                pullFromDistributor: false,
                vestingTime: 0,
                vestingStartTime: 0
            })
        );

        vm.startPrank(owner);
        ghoDistributor.toggleRewardsDistributor(GHO_DISTRIBUTOR);
        ghoDistributor.updateDistributionConfig(true, 28 days / 12 seconds, 4);
        vm.stopPrank();
    }

    function test_deployment() public view {
        assertEq(address(ghoDistributor.owner()), owner);
        assertEq(ghoDistributor.isProposer(proposer), true);
        assertEq(ghoDistributor.isProposer(owner), true);
    }

    function _initiateRewards() internal {
        uint256 amount = 1_000_000 * 1e18; // 1M GHO

        vm.startPrank(GHO_DISTRIBUTOR);
        IERC20(GHO).approve(address(ghoDistributor), amount);
        ghoDistributor.distributeRewards(amount);

        uint cyclesPerDistribution_ = ghoDistributor.cyclesPerDistribution();
        uint blocksPerCycle_ = ghoDistributor.blocksPerDistribution() / cyclesPerDistribution_;

        FluidMerkleDistributor.Distribution[] memory distributions_ = ghoDistributor.getDistributions();

        assertEq(distributions_.length, 1);
        assertEq(distributions_[0].amount, amount);
        assertEq(distributions_[0].startCycle, 1);
        assertEq(distributions_[0].endCycle, cyclesPerDistribution_);
        assertEq(distributions_[0].registrationBlock, block.number);

        FluidMerkleDistributor.Reward[] memory rewards_ = ghoDistributor.getCycleRewards();
        assertEq(rewards_.length, cyclesPerDistribution_);

        for (uint256 i = 0; i < cyclesPerDistribution_; i++) {
            assertEq(rewards_[i].amount, amount / cyclesPerDistribution_);
            assertEq(rewards_[i].startBlock, block.number + i * blocksPerCycle_);
            assertEq(rewards_[i].endBlock, block.number + (i + 1) * blocksPerCycle_ - 1);
        }

        vm.stopPrank();
    }

    function _proposeRoot() internal {
        vm.prank(proposer);
        ghoDistributor.proposeRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);
    }

    function _approveRoot() internal {
        vm.prank(approver);
        ghoDistributor.approveRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);
    }

    function _claim(bool expectRevert_) internal {
        bytes32 token = bytes32(uint256(uint160(GHO)));
        bytes32[] memory proofs = new bytes32[](1);

        proofs[0] = 0x1d8aa43dd246a1b80dd0063fdecfd32ffac6e03ac43b692d1c8a0ac66b870205;

        vm.startPrank(recipient);
        if (!expectRevert_) vm.expectEmit(true, true, true, true);
        uint256 claimAmount_ = 50 * 1e18;

        if (!expectRevert_) emit LogClaimed(recipient, claimAmount_, 1, 1, token, block.timestamp, block.number);
        if (expectRevert_) vm.expectRevert(abi.encodeWithSelector(Errors.NothingToClaim.selector));
        ghoDistributor.claim(recipient, claimAmount_, 1, token, 1, proofs, new bytes(0));
        if (!expectRevert_) assertEq(IERC20(GHO).balanceOf(recipient), claimAmount_);

        vm.stopPrank();
    }

    function test_initiateRewards() public {
        _initiateRewards();
    }

    function test_proposeRoot() public {
        _initiateRewards();
        _proposeRoot();
    }

    function test_approveRoot() public {
        _initiateRewards();
        _proposeRoot();
        _approveRoot();
    }

    function test_claim() public {
        _initiateRewards();
        _proposeRoot();
        _approveRoot();
        _claim(false);
    }

    function test_RevertIfClaimedMultipleTimes() public {
        _initiateRewards();
        _proposeRoot();
        _approveRoot();
        _claim(false);

        // this should fail
        _claim(true);
    }
}

// @dev can build a simple merkle root for testing like this in JS:
// import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
// const values = [
//   ["1", "0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33", "0x1111111111111111111111111111111111111111", "1", "5000000000000000000", "0x"],
//   ["1", "0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB", "0x2222222222222222222222222222222222222222", "1", "2500000000000000000", "0x"],
//   ["1", "0x4Ce05f946fe262840496F653817CC1121aE74fac", "0x2222222222222222222222222222222222222223", "1", "2500000000000000000", "0x"],
//   ["1", "0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1", "0x2222222222222222222222222222222222222224", "1", "2500000000000000000", "0x"],
//   ["1", "0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663", "0x2222222222222222222222222222222222222225", "1", "2500000000000000000", "0x"],
//   ["1", "0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2", "0x2222222222222222222222222222222222222226", "1", "2500000000000000000", "0x"],
//   ["1", "0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473", "0x2222222222222222222222222222222222222227", "1", "2500000000000000000", "0x"],
// ];
// const tree = StandardMerkleTree.of(values, ["uint8", "address", "address", "uint256", "uint256", "bytes"]);
// console.log('Merkle Root:', tree.root);
// let i = 0;
// for (const value of values) {
//   console.log(`proof for fToken: ${value[1]}:`, tree.getProof(i));
//   i++;
// }
//
// result:
// Merkle Root:
// 0x0af7cd0b7eb0349a5ffc4800cb5177af541a3d211a79770b185331244240ffd3
// proof for fToken: 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33:
// ['0x0dd18999347c4ee2aadd74dd417464aba3fbf0e81ae3329dfb8c4a3470e9c548',
//   '0xedaca12b19e8ba9d3accc9297d68b0590e331788bddb35ed6a6854e31357a006',
//   '0x9aa24e378a9bc4559be5339be001f36d168756f3eb0fc7c331ebf6e3054c130d'
// ]
// proof for fToken: 0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB:
// ['0x028c81e98db687dd63fc119fd39bf2b905dcc13639444fd82c210a123040977c',
//   '0xedaca12b19e8ba9d3accc9297d68b0590e331788bddb35ed6a6854e31357a006',
//   '0x9aa24e378a9bc4559be5339be001f36d168756f3eb0fc7c331ebf6e3054c130d'
// ]
// proof for fToken: 0x4Ce05f946fe262840496F653817CC1121aE74fac:
// ['0xc56dc9cf563ad79c1d4c2683ceee0386891f1c43dd0e2062f51c354f0b4353ba',
//   '0x89487e62477dae9c0ee417c62e4193528657d846153b4974c46e7485b1b64402',
//   '0x90a6e8ccf59e31d3d2ae7863ac76beb83c24074df231afe47f46bbcb067bf30f'
// ]
// proof for fToken: 0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1:
// ['0xceed9e3fb8d0fa088f14266beb983f9ce2bd962bf86add574a719378b995dadd',
//   '0xd21094600db013d07b2888deed55c3144a8b978e9d6f98c17d470fc5a077e064',
//   '0x90a6e8ccf59e31d3d2ae7863ac76beb83c24074df231afe47f46bbcb067bf30f'
// ]
// proof for fToken: 0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663:
// ['0xc86ba61469c38b5ae53bf0f32a8fcfba741d4cf9a2cdbfe83ff91c01652e95ac',
//   '0xd21094600db013d07b2888deed55c3144a8b978e9d6f98c17d470fc5a077e064',
//   '0x90a6e8ccf59e31d3d2ae7863ac76beb83c24074df231afe47f46bbcb067bf30f'
// ]
// proof for fToken: 0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2:
// ['0x4a55f2fc9126821a61fb5fbcc141202e2417d51353ca26abdc80ffd7701ce551',
//   '0x9aa24e378a9bc4559be5339be001f36d168756f3eb0fc7c331ebf6e3054c130d'
// ]
// proof for fToken: 0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473:
// ['0x5adb6600c62e3291d0ca73fe4462212f31cf1e4c3ca7b644f99445d83e544f2c',
//   '0x89487e62477dae9c0ee417c62e4193528657d846153b4974c46e7485b1b64402',
//   '0x90a6e8ccf59e31d3d2ae7863ac76beb83c24074df231afe47f46bbcb067bf30f'
// ]
//
// cycle 2 with increased amounts:
// const values = [
//   ["1", "0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33", "0x1111111111111111111111111111111111111111", "2", "8000000000000000000", "0x"],
//   ["1", "0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB", "0x2222222222222222222222222222222222222222", "2", "5500000000000000000", "0x"],
//   ["1", "0x4Ce05f946fe262840496F653817CC1121aE74fac", "0x2222222222222222222222222222222222222223", "2", "5500000000000000000", "0x"],
//   ["1", "0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1", "0x2222222222222222222222222222222222222224", "2", "5500000000000000000", "0x"],
//   ["1", "0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663", "0x2222222222222222222222222222222222222225", "2", "5500000000000000000", "0x"],
//   ["1", "0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2", "0x2222222222222222222222222222222222222226", "2", "5500000000000000000", "0x"],
//   ["1", "0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473", "0x2222222222222222222222222222222222222227", "2", "5500000000000000000", "0x"],
// ];
// result:
// Merkle Root:
// 0x11a6fc9d28d1b3010cfada6752c570bde414f132e88733d5c0cf2937a16e5b2e
// proof for fToken: 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33:
// ['0x31bcd30adccfcc6e59a85b3a80c568fa0b5bfb6540cd36df4b9f608cf42a43ee',
//   '0x0f4aaf27082d1b48e5e6e15a496fa544db7a513ea5151f3c7268519f842182fc'
// ]
// proof for fToken: 0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB:
// ['0x3e1a67398067442c923973fec25c360285130fb452076ec177c841fb711dc557',
//   '0xe4031d0dafa85118a42e5941ec78ec41b1914a1309155c0e16b56e1c90de92f6',
//   '0x0f4aaf27082d1b48e5e6e15a496fa544db7a513ea5151f3c7268519f842182fc'
// ]
// proof for fToken: 0x4Ce05f946fe262840496F653817CC1121aE74fac:
// ['0xd673d8e8b917f8fdbd6f5871a48ca750e79502534cd746e4a9e90fae64490d37',
//   '0x25bb7995965a63a80d8ecfb1ac493b59ca7d0e378fef88f27b76b46aa8359bd9',
//   '0xc2b91c33608f4260c9612544815ab14d3be1e021ac4af93f6624273ab56817d3'
// ]
// proof for fToken: 0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1:
// ['0xa6af730d82fbebe4ab5ca5730973f4d849409ad5abb45fd36626a1c44d81aa3c',
//   '0x25bb7995965a63a80d8ecfb1ac493b59ca7d0e378fef88f27b76b46aa8359bd9',
//   '0xc2b91c33608f4260c9612544815ab14d3be1e021ac4af93f6624273ab56817d3'
// ]
// proof for fToken: 0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663:
// ['0x4ad13a01d998425a38318fa848ea5c8829c024fff0ae0c9158bdf2c0b415a368',
//   '0x4cce7068ab4f1570a8095526d94fd82ce56cd1880201ee6abc8aeaa8dd5fb719',
//   '0xc2b91c33608f4260c9612544815ab14d3be1e021ac4af93f6624273ab56817d3'
// ]
// proof for fToken: 0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2:
// ['0x038ac442c8b4ce448c9db17b8ae6a9823a32813fff6a04376bd95890062d486c',
//   '0xe4031d0dafa85118a42e5941ec78ec41b1914a1309155c0e16b56e1c90de92f6',
//   '0x0f4aaf27082d1b48e5e6e15a496fa544db7a513ea5151f3c7268519f842182fc'
// ]
// proof for fToken: 0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473:
// ['0x836af696b75c2f8d3858edba1761bc6b3ea09349531aac35fbbeeef12421d035',
//   '0x4cce7068ab4f1570a8095526d94fd82ce56cd1880201ee6abc8aeaa8dd5fb719',
//   '0xc2b91c33608f4260c9612544815ab14d3be1e021ac4af93f6624273ab56817d3'
// ]
//
// cycle 3 with same user for different fTokens, positionType and metadata:
// const values = [
//   ["2", "0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33", "0x1111111111111111111111111111111111111111", "3", "5000000000000000000", "0x1234"],
//   ["2", "0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB", "0x2222222222222222222222222222222222222222", "3", "2500000000000000000", "0x1234"],
//   ["2", "0x4Ce05f946fe262840496F653817CC1121aE74fac", "0x2222222222222222222222222222222222222223", "3", "2500000000000000000", "0x1234"],
//   ["2", "0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1", "0x2222222222222222222222222222222222222224", "3", "2500000000000000000", "0x1234"],
//   ["2", "0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663", "0x2222222222222222222222222222222222222227", "3", "2500000000000000000", "0x1234"],
//   ["2", "0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2", "0x2222222222222222222222222222222222222227", "3", "2500000000000000000", "0x1234"],
//   ["2", "0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473", "0x2222222222222222222222222222222222222227", "3", "2500000000000000000", "0x1234"],
// ];
// result:
// Merkle Root:
// 0xb5baf06a349178debd4c137fe78fbe1250f4f624dc3f256314e1f6814ad0013b
// proof for fToken: 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33:
// ['0x5d7e3a6944b76c807f6e1b67a64b84cab8784ab95b19e3ba2a033b40ed1ebb11',
//   '0xeb6df30129039ab04e20fd78ffa7af8570d0e3e49c7dac751eabba32cf927ddd',
//   '0x5ff386be94619ed8c5fd142f7b75b3eae51b29dadac45af85cc178c1d8d4395d'
// ]
// proof for fToken: 0x0b5d53972927D4B0f103eea55e19fCfEE025A9AB:
// ['0xb31ae3e7e5c99514fdaf5d4469df5c657f86ef819011584242a972ed73f40371',
//   '0x9600633fd8c636c01322f18282bda5720f4e7085dcfb5db3b669fbf6a2473e4a',
//   '0x4d673afd439fc32654c70e5bda574ebc62d2cdc20d66352865fda7c59859a328'
// ]
// proof for fToken: 0x4Ce05f946fe262840496F653817CC1121aE74fac:
// ['0x8c64e7250ed975e3da9f62ff179e59e65ac6a59ee4a211c414b4e19cf24e4b85',
//   '0x6389726f83e624c3b543d247131ac424e633cacb89fb2515e6eb1c03630b45fe',
//   '0x4d673afd439fc32654c70e5bda574ebc62d2cdc20d66352865fda7c59859a328'
// ]
// proof for fToken: 0x4FA61f7e0f30b8004C8e471F01b2e8e644f6b8C1:
// ['0xcb917ec6f6dfa20cca165db33744a8088a7be12683b2d487c88b1a1e7d439920',
//   '0x9600633fd8c636c01322f18282bda5720f4e7085dcfb5db3b669fbf6a2473e4a',
//   '0x4d673afd439fc32654c70e5bda574ebc62d2cdc20d66352865fda7c59859a328'
// ]
// proof for fToken: 0xFDa9fe8e90f99F9eb5a6CCddA11708ceB10Ba663:
// ['0xe7e76fc050d2a389b8030cbac820d38ce5587a0c96223b56767139fda86c6319',
//   '0x5ff386be94619ed8c5fd142f7b75b3eae51b29dadac45af85cc178c1d8d4395d'
// ]
// proof for fToken: 0x04D44fD629Be46E2f5f7962F6A8420c16d22d4e2:
// ['0x27ae11729acca4e17bcb76fb6c141c0802c65ac750247e31ef40672efe61c734',
//   '0xeb6df30129039ab04e20fd78ffa7af8570d0e3e49c7dac751eabba32cf927ddd',
//   '0x5ff386be94619ed8c5fd142f7b75b3eae51b29dadac45af85cc178c1d8d4395d'
// ]
// proof for fToken: 0xD8Afe4D67Eb2fC91Ce472AA3a3A1618D8A938473:
// ['0x830b3649b55cd4250be01e38475823e2fa621fa54bb61eaf6b3d66acb5e4b02c',
//   '0x6389726f83e624c3b543d247131ac424e633cacb89fb2515e6eb1c03630b45fe',
//   '0x4d673afd439fc32654c70e5bda574ebc62d2cdc20d66352865fda7c59859a328'
// ]
