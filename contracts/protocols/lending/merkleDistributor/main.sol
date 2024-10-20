// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { Structs } from "./structs.sol";
import { Variables } from "./variables.sol";
import { Events } from "./events.sol";
import { Errors } from "./errors.sol";

// ---------------------------------------------------------------------------------------------
//
// @dev WARNING: DO NOT USE `multiProof` related methods of `MerkleProof`.
// This repo uses OpenZeppelin 4.8.2 which has a vulnerability for multi proofs. See:
// https://github.com/OpenZeppelin/openzeppelin-contracts/security/advisories/GHSA-wprv-93r4-jj2p
//
// ---------------------------------------------------------------------------------------------

abstract contract FluidMerkleDistributorCore is Structs, Variables, Events, Errors {
    /// @dev validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert InvalidParams();
        }
        _;
    }
}

abstract contract FluidMerkleDistributorAdmin is FluidMerkleDistributorCore {
    /// @notice                  Updates an address status as a root proposer
    /// @param proposer_         The address to update
    /// @param isProposer_       Whether or not the address should be an allowed proposer
    function updateProposer(address proposer_, bool isProposer_) public onlyOwner validAddress(proposer_) {
        _proposers[proposer_] = isProposer_;
        emit LogUpdateProposer(proposer_, isProposer_);
    }

    /// @notice                  Updates an address status as a root approver
    /// @param approver_         The address to update
    /// @param isApprover_       Whether or not the address should be an allowed approver
    function updateApprover(address approver_, bool isApprover_) public onlyOwner validAddress(approver_) {
        _approvers[approver_] = isApprover_;
        emit LogUpdateApprover(approver_, isApprover_);
    }

    /// @dev open payload method for admin to resolve emergency cases
    function spell(address[] memory targets_, bytes[] memory calldatas_) public onlyOwner {
        for (uint256 i = 0; i < targets_.length; i++) {
            Address.functionDelegateCall(targets_[i], calldatas_[i]);
        }
    }

    /// @notice Pause contract functionality of new roots and claiming
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause contract functionality of new roots and claiming
    function unpause() external onlyOwner {
        _unpause();
    }
}

abstract contract FluidMerkleDistributorApprover is FluidMerkleDistributorCore {
    /// @dev Checks that the sender is an approver
    modifier onlyApprover() {
        if (!isApprover(msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /// @notice checks if the `approver_` is an allowed root approver
    function isApprover(address approver_) public view returns (bool) {
        return (_approvers[approver_] || owner == approver_);
    }

    /// @notice Approve the current pending root and content hash
    function approveRoot(
        bytes32 root_,
        bytes32 contentHash_,
        uint40 cycle_,
        uint40 startBlock_,
        uint40 endBlock_
    ) external onlyApprover {
        MerkleCycle memory merkleCycle_ = _pendingMerkleCycle;

        if (
            root_ != merkleCycle_.merkleRoot ||
            contentHash_ != merkleCycle_.merkleContentHash ||
            cycle_ != merkleCycle_.cycle ||
            startBlock_ != merkleCycle_.startBlock ||
            endBlock_ != merkleCycle_.endBlock
        ) {
            revert InvalidParams();
        }

        previousMerkleRoot = _currentMerkleCycle.merkleRoot;

        merkleCycle_.timestamp = uint40(block.timestamp);
        merkleCycle_.publishBlock = uint40(block.number);

        _currentMerkleCycle = merkleCycle_;

        emit LogRootUpdated(cycle_, root_, contentHash_, block.timestamp, block.number);
    }
}

abstract contract FluidMerkleDistributorProposer is FluidMerkleDistributorCore {
    /// @dev Checks that the sender is a proposer
    modifier onlyProposer() {
        if (!isProposer(msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /// @notice checks if the `proposer_` is an allowed root proposer
    function isProposer(address proposer_) public view returns (bool) {
        return (_proposers[proposer_] || owner == proposer_);
    }

    /// @notice Propose a new root and content hash, which will be stored as pending until approved
    function proposeRoot(
        bytes32 root_,
        bytes32 contentHash_,
        uint40 cycle_,
        uint40 startBlock_,
        uint40 endBlock_
    ) external whenNotPaused onlyProposer {
        if (cycle_ != _currentMerkleCycle.cycle + 1 || startBlock_ > endBlock_) {
            revert InvalidParams();
        }

        _pendingMerkleCycle = MerkleCycle({
            merkleRoot: root_,
            merkleContentHash: contentHash_,
            cycle: cycle_,
            startBlock: startBlock_,
            endBlock: endBlock_,
            timestamp: uint40(block.timestamp),
            publishBlock: uint40(block.number)
        });

        emit LogRootProposed(cycle_, root_, contentHash_, block.timestamp, block.number);
    }
}

contract FluidMerkleDistributor is
    FluidMerkleDistributorCore,
    FluidMerkleDistributorAdmin,
    FluidMerkleDistributorApprover,
    FluidMerkleDistributorProposer
{
    constructor(
        address owner_,
        address proposer_,
        address approver_,
        address rewardToken_
    )
        validAddress(owner_)
        validAddress(proposer_)
        validAddress(approver_)
        validAddress(rewardToken_)
        Variables(owner_, rewardToken_)
    {
        _proposers[proposer_] = true;
        emit LogUpdateProposer(proposer_, true);

        _approvers[approver_] = true;
        emit LogUpdateApprover(approver_, true);
    }

    /// @notice checks if there is a proposed root waiting to be approved
    function hasPendingRoot() external view returns (bool) {
        return _pendingMerkleCycle.cycle == _currentMerkleCycle.cycle + 1;
    }

    /// @notice merkle root data related to current cycle (proposed and approved).
    function currentMerkleCycle() public view returns (MerkleCycle memory) {
        return _currentMerkleCycle;
    }

    /// @notice merkle root data related to pending cycle (proposed but not yet approved).
    function pendingMerkleCycle() public view returns (MerkleCycle memory) {
        return _pendingMerkleCycle;
    }

    function encodeClaim(
        address recipient_,
        uint256 cumulativeAmount_,
        bytes32 positionId_,
        uint256 cycle_
    ) public pure returns (bytes memory encoded_, bytes32 hash_) {
        encoded_ = abi.encode(positionId_, recipient_, cycle_, cumulativeAmount_);
        hash_ = keccak256(bytes.concat(keccak256(encoded_)));
    }

    function claim(
        address recipient_,
        uint256 cumulativeAmount_,
        bytes32 positionId_,
        uint256 cycle_,
        bytes32[] calldata merkleProof_
    ) external whenNotPaused {
        uint256 currentCycle_ = uint256(_currentMerkleCycle.cycle);

        if (!(cycle_ == currentCycle_ || (currentCycle_ > 0 && cycle_ == currentCycle_ - 1))) {
            revert InvalidCycle();
        }

        // Verify the merkle proof.
        bytes32 node_ = keccak256(
            bytes.concat(keccak256(abi.encode(positionId_, recipient_, cycle_, cumulativeAmount_)))
        );
        if (
            !MerkleProof.verify(
                merkleProof_,
                cycle_ == currentCycle_ ? _currentMerkleCycle.merkleRoot : previousMerkleRoot,
                node_
            )
        ) {
            revert InvalidProof();
        }

        uint256 claimable_ = cumulativeAmount_ - claimed[recipient_][positionId_];
        if (claimable_ == 0) {
            revert NothingToClaim();
        }

        claimed[recipient_][positionId_] = cumulativeAmount_;

        SafeERC20.safeTransfer(TOKEN, recipient_, claimable_);

        emit LogClaimed(recipient_, claimable_, cycle_, positionId_, block.timestamp, block.number);
    }
}
