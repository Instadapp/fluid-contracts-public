//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Structs } from "../../../contracts/protocols/lending/merkleDistributor/structs.sol";
import { Errors } from "../../../contracts/protocols/lending/merkleDistributor/errors.sol";
import { Events } from "../../../contracts/protocols/lending/merkleDistributor/events.sol";
import { FluidMerkleDistributor } from "../../../contracts/protocols/lending/merkleDistributor/main.sol";

/// @title MerkleDistributor root approval: pause, replay and cycle-length rules (no fork).
/// @dev merkleDistributor.t.sol is excluded from CI by `.github/fork-test-paths.txt` (it forks for a real
///      reward token), so these never run there. None of these scenarios touch the reward token at all.
contract FluidMerkleDistributorRootCycleTest is Test, Events {
    address internal owner = makeAddr("owner");
    address internal proposer = makeAddr("proposer");
    address internal approver = makeAddr("approver");

    FluidMerkleDistributor internal distributor;

    bytes32 internal constant TEST_ROOT_1 = 0x0af7cd0b7eb0349a5ffc4800cb5177af541a3d211a79770b185331244240ffd3;
    bytes32 internal constant TEST_CONTENT_HASH_1 = 0xebae91a2dcf9b26375431949c62b80633ac52d0dcd47aa0d7964d431950ba14e;

    bytes32 internal constant TEST_ROOT_2 = 0x11a6fc9d28d1b3010cfada6752c570bde414f132e88733d5c0cf2937a16e5b2e;
    bytes32 internal constant TEST_CONTENT_HASH_2 = 0xdce87b958009fb6e99231baa505eedcda278bba89d7aaf1c84509901e33c973e;

    uint40 internal constant DEFAULT_START_BLOCK = 2;
    uint40 internal constant DEFAULT_END_BLOCK = 22;

    bytes internal constant PAUSABLE_PAUSED_ERROR = "Pausable: paused";

    function _deploy(uint40 distributionInHours_, uint40 cycleInHours_) internal returns (FluidMerkleDistributor) {
        // constructor branches on `block.chainid` for its blocks-per-second assumption; pin to mainnet.
        vm.chainId(1);
        return
            new FluidMerkleDistributor(
                Structs.ConstructorParams({
                    name: "Merkle",
                    owner: owner,
                    proposer: proposer,
                    approver: approver,
                    rewardToken: address(0xDEAD),
                    distributionInHours: distributionInHours_,
                    cycleInHours: cycleInHours_,
                    startBlock: block.number,
                    pullFromDistributor: false,
                    vestingTime: 0,
                    vestingStartTime: 0
                })
            );
    }

    function setUp() public {
        distributor = _deploy(1, 1);
    }

    // `approveRoot` must be `whenNotPaused`.

    function test_approveRoot_revertsWhenPaused() public {
        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);
        assertTrue(distributor.hasPendingRoot(), "pending root must exist before pause");

        vm.prank(owner);
        distributor.pause();

        // Approver is authorized; pause should still block promotion.
        vm.prank(approver);
        vm.expectRevert(PAUSABLE_PAUSED_ERROR);
        distributor.approveRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);

        assertTrue(distributor.hasPendingRoot(), "pending root must remain un-promoted while paused");
        assertEq(distributor.currentMerkleCycle().merkleRoot, bytes32(""), "current root must stay empty while paused");
    }

    // Unpause recovery was never broken; also passes pre-fix.
    function test_approveRoot_worksAgainAfterUnpause() public {
        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);

        vm.prank(owner);
        distributor.pause();
        vm.prank(owner);
        distributor.unpause();

        vm.prank(approver);
        distributor.approveRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);

        assertEq(distributor.currentMerkleCycle().merkleRoot, TEST_ROOT_1, "unpaused approval must promote the root");
        assertFalse(distributor.hasPendingRoot(), "no pending root after approval");
    }

    /// @notice governance pauses mid-window (e.g. to investigate a proposal); approver cannot promote.
    function test_pauseBetweenProposeAndApprove_blocksPromotion() public {
        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);

        vm.prank(owner);
        distributor.pause();

        vm.prank(approver);
        vm.expectRevert(PAUSABLE_PAUSED_ERROR);
        distributor.approveRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);
    }

    // an approved pending root must not be replayable once the next cycle has already begun.

    function test_approveRoot_CannotReplayApprovedPendingRoot() public {
        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);
        vm.prank(approver);
        distributor.approveRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);
        assertEq(distributor.pendingMerkleCycle().merkleRoot, bytes32(0), "approval clears the pending root");
        assertEq(distributor.pendingMerkleCycle().cycle, 0, "approval clears the pending cycle");

        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_2, TEST_CONTENT_HASH_2, 2, DEFAULT_END_BLOCK + 1, DEFAULT_END_BLOCK + 10);
        vm.prank(approver);
        distributor.approveRoot(TEST_ROOT_2, TEST_CONTENT_HASH_2, 2, DEFAULT_END_BLOCK + 1, DEFAULT_END_BLOCK + 10);

        assertEq(distributor.previousMerkleRoot(), TEST_ROOT_1, "pre: previous root points to cycle 1");
        assertEq(distributor.hasPendingRoot(), false, "pre: pending root was cleared");

        vm.prank(approver);
        vm.expectRevert(Errors.InvalidParams.selector);
        distributor.approveRoot(TEST_ROOT_2, TEST_CONTENT_HASH_2, 2, DEFAULT_END_BLOCK + 1, DEFAULT_END_BLOCK + 10);

        assertEq(distributor.previousMerkleRoot(), TEST_ROOT_1, "post: replay must not corrupt previous root");
        assertEq(distributor.currentMerkleCycle().cycle, 2, "post: current cycle remains 2");
    }

    // a cycle longer than its distribution window must be rejected, at construction and reconfiguration.

    function test_constructor_RevertsWhenCycleLongerThanDistribution() public {
        vm.expectRevert(Errors.InvalidParams.selector);
        _deploy(1, 2);
    }

    function test_updateDistributionConfig_RevertsWhenBlocksPerCycleWouldBeZero() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidParams.selector);
        distributor.updateDistributionConfig(true, 3, 4);
    }
}
