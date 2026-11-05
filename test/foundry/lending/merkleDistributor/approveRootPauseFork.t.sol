// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { FluidMerkleDistributorTest } from "./merkleDistributor.t.sol";
import { Errors } from "../../../../contracts/protocols/lending/merkleDistributor/errors.sol";

/// @title `approveRoot` must be `whenNotPaused`
contract FluidMerkleDistributorApproveRootPauseForkTest is FluidMerkleDistributorTest {
    bytes internal constant PAUSABLE_PAUSED_ERROR = "Pausable: paused";

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

    /// @notice Mid-window defence: a proposer creates a root, governance then pauses (e.g. to investigate the
    ///         proposal), approver cannot promote while the pause is in place.
    function test_pauseBetweenProposeAndApprove_blocksPromotion() public {
        vm.prank(proposer);
        distributor.proposeRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);

        // governance discovers a problem and pauses during the approval window
        vm.prank(owner);
        distributor.pause();

        vm.prank(approver);
        vm.expectRevert(PAUSABLE_PAUSED_ERROR);
        distributor.approveRoot(TEST_ROOT_1, TEST_CONTENT_HASH_1, 1, DEFAULT_START_BLOCK, DEFAULT_END_BLOCK);
    }
}
