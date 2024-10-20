// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Events {
    /// @notice Emitted when an address is added or removed from the allowed proposers
    event LogUpdateProposer(address proposer, bool isProposer);

    /// @notice Emitted when an address is added or removed from the allowed approvers
    event LogUpdateApprover(address approver, bool isApprover);

    /// @notice Emitted when a new cycle root hash is proposed
    event LogRootProposed(uint256 cycle, bytes32 root, bytes32 contentHash, uint256 timestamp, uint256 blockNumber);

    /// @notice Emitted when a new cycle root hash is approved by the owner and becomes the new active root
    event LogRootUpdated(uint256 cycle, bytes32 root, bytes32 contentHash, uint256 timestamp, uint256 blockNumber);

    /// @notice Emitted when a `user` claims `amount` via a valid merkle proof
    event LogClaimed(
        address user,
        uint256 amount,
        uint256 cycle,
        bytes32 positionId,
        uint256 timestamp,
        uint256 blockNumber
    );
}
