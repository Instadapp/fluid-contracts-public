// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import { Events } from "./events.sol";
import { Errors } from "./errors.sol";
import { Structs } from "./structs.sol";
import { Variables } from "./variables.sol";
import { SafeTransfer } from "../../../libraries/safeTransfer.sol";

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

    /// @notice                         Spell allows owner aka governance to do any arbitrary call on factory
    /// @param target_                  Address to which the call needs to be delegated
    /// @param data_                    Data to execute at the delegated address
    function _spell(address target_, bytes memory data_) internal returns (bytes memory response_) {
        assembly {
            let succeeded := delegatecall(gas(), target_, add(data_, 0x20), mload(data_), 0, 0)
            let size := returndatasize()

            response_ := mload(0x40)
            mstore(0x40, add(response_, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response_, size)
            returndatacopy(add(response_, 0x20), 0, size)

            switch iszero(succeeded)
            case 1 {
                // throw if delegatecall failed
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }

    /// @dev open payload method for admin to resolve emergency cases
    function spell(address[] memory targets_, bytes[] memory calldatas_) public onlyOwner {
        for (uint256 i = 0; i < targets_.length; i++) _spell(targets_[i], calldatas_[i]);
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

abstract contract FluidMerkleDistributorRewards is FluidMerkleDistributorCore {
    /// @dev Modifier to check if the sender is a rewards distributor
    modifier onlyRewardsDistributor() {
        if (!rewardsDistributor[msg.sender] && owner != msg.sender) revert Unauthorized();
        _;
    }

    /// @notice Updates the distribution configuration
    /// @param pullFromDistributor_ - whether to pull rewards from distributor or not
    /// @param blocksPerDistribution_ - duration of distribution in blocks
    /// @param cyclesPerDistribution_ - number of cycles to distribute rewards, if 0 then means paused
    function updateDistributionConfig(
        bool pullFromDistributor_,
        uint40 blocksPerDistribution_,
        uint40 cyclesPerDistribution_
    ) external onlyOwner {
        if (blocksPerDistribution_ == 0 || cyclesPerDistribution_ == 0) revert InvalidParams();
        emit LogDistributionConfigUpdated(
            pullFromDistributor = pullFromDistributor_,
            blocksPerDistribution = blocksPerDistribution_,
            cyclesPerDistribution = cyclesPerDistribution_
        );
    }

    /// @notice Toggles a rewards distributor
    /// @param distributor_ - address of the rewards distributor
    function toggleRewardsDistributor(address distributor_) external onlyOwner {
        if (distributor_ == address(0)) revert InvalidParams();
        emit LogRewardsDistributorToggled(
            distributor_,
            rewardsDistributor[distributor_] = !rewardsDistributor[distributor_]
        );
    }

    /// @notice Sets the start block of the next cycle
    /// @param startBlockOfNextCycle_ The start block of the next cycle
    function setStartBlockOfNextCycle(uint40 startBlockOfNextCycle_) external onlyOwner {
        if (startBlockOfNextCycle_ < block.number || startBlockOfNextCycle_ == 0) revert InvalidParams();
        emit LogStartBlockOfNextCycleUpdated(startBlockOfNextCycle = uint40(startBlockOfNextCycle_));
    }

    /////// Public Functions ///////

    /// @notice Returns the cycle rewards
    /// @return rewards_ - rewards
    function getCycleRewards() external view returns (Reward[] memory) {
        return rewards;
    }

    /// @notice Returns the cycle reward for a given cycle
    /// @param cycle_ - cycle of the reward
    /// @return reward_ - reward
    function getCycleReward(uint256 cycle_) external view returns (Reward memory) {
        if (cycle_ > rewards.length || cycle_ == 0) revert InvalidParams();
        return rewards[cycle_ - 1];
    }

    /// @notice Returns the total number of cycles
    /// @return totalCycles_ - total number of cycles
    function totalCycleRewards() external view returns (uint256) {
        return rewards.length;
    }

    /// @notice Returns the total number of distributions
    /// @return totalDistributions_ - total number of distributions
    function totalDistributions() external view returns (uint256) {
        return distributions.length;
    }

    /// @notice Returns the distribution for a given epoch
    /// @param epoch_ - epoch of the distribution
    /// @return distribution_ - distribution
    function getDistributionForEpoch(uint256 epoch_) external view returns (Distribution memory) {
        if (epoch_ > distributions.length || epoch_ == 0) revert InvalidParams();
        return distributions[epoch_ - 1];
    }

    /// @notice Returns all distributions
    /// @return distributions_ - all distributions
    function getDistributions() external view returns (Distribution[] memory) {
        return distributions;
    }

    ////////// Distribution Function //////////

    /// @notice Distributes rewards for a given token
    /// @param amount_ - amount of tokens to distribute rewards for
    function distributeRewards(uint256 amount_) public onlyRewardsDistributor {
        if (amount_ == 0) revert InvalidParams();

        uint256 amountPerCycle_ = amount_ / cyclesPerDistribution;
        uint256 blocksPerCycle_ = blocksPerDistribution / cyclesPerDistribution;

        uint256 cyclesLength_ = rewards.length;
        uint256 startBlock_ = 0;
        if (cyclesLength_ > 0) {
            uint256 lastCycleEndBlock_ = rewards[cyclesLength_ - 1].endBlock + 1;
            // if there are already some cycles, then we need to check if startBlockOfNextCycle was set in order to start from that block, then assign it to startBlock_
            if (lastCycleEndBlock_ < startBlockOfNextCycle) {
                startBlock_ = startBlockOfNextCycle;
            } else {
                // if lastCycleEndBlock_ of last cycle is still syncing, then we need to start last cycle's end block + 1, else start from current block
                startBlock_ = lastCycleEndBlock_ > block.number ? lastCycleEndBlock_ : block.number;
            }
        } else {
            // if there are no cycles, that means this is the first distribution, then we need to start from startBlockOfNextCycle, if it was set, else start from current block
            startBlock_ = startBlockOfNextCycle > 0 ? startBlockOfNextCycle : block.number;
        }

        if (startBlock_ == 0) revert InvalidParams();

        uint256 distributionEpoch_ = distributions.length + 1;

        distributions.push(
            Distribution({
                amount: amount_,
                epoch: uint40(distributionEpoch_),
                startCycle: uint40(cyclesLength_ + 1),
                endCycle: uint40(cyclesLength_ + cyclesPerDistribution),
                registrationBlock: uint40(block.number),
                registrationTimestamp: uint40(block.timestamp)
            })
        );

        for (uint256 i = 0; i < cyclesPerDistribution; i++) {
            uint256 endBlock_ = startBlock_ + blocksPerCycle_ - 1;
            uint256 cycle_ = cyclesLength_ + 1 + i;
            uint256 cycleAmount_ = amountPerCycle_;
            if (i == cyclesPerDistribution - 1) {
                cycleAmount_ = amount_ - (amountPerCycle_ * i);
            }
            rewards.push(
                Reward({
                    cycle: uint40(cycle_),
                    amount: cycleAmount_,
                    startBlock: uint40(startBlock_),
                    endBlock: uint40(endBlock_),
                    epoch: uint40(distributionEpoch_)
                })
            );
            emit LogRewardCycle(cycle_, distributionEpoch_, cycleAmount_, startBlock_, endBlock_);
            startBlock_ = endBlock_ + 1;
        }

        if (pullFromDistributor) SafeERC20.safeTransferFrom(TOKEN, msg.sender, address(this), amount_);

        emit LogDistribution(
            distributionEpoch_,
            msg.sender,
            amount_,
            cyclesLength_ + 1,
            cyclesLength_ + cyclesPerDistribution,
            block.number,
            block.timestamp
        );
    }
}

contract FluidMerkleDistributor is
    FluidMerkleDistributorCore,
    FluidMerkleDistributorAdmin,
    FluidMerkleDistributorApprover,
    FluidMerkleDistributorProposer,
    FluidMerkleDistributorRewards
{
    constructor(
        ConstructorParams memory params_
    )
        validAddress(params_.owner)
        validAddress(params_.proposer)
        validAddress(params_.approver)
        validAddress(params_.rewardToken)
        Variables(params_.owner, params_.rewardToken)
    {
        if (params_.distributionInHours == 0 || params_.cycleInHours == 0) revert InvalidParams();

        name = params_.name;

        _proposers[params_.proposer] = true;
        emit LogUpdateProposer(params_.proposer, true);

        _approvers[params_.approver] = true;
        emit LogUpdateApprover(params_.approver, true);

        uint40 _blocksPerDistribution = uint40(params_.distributionInHours * 1 hours);
        uint40 _cyclesPerDistribution = uint40(params_.distributionInHours / params_.cycleInHours);

        if (block.chainid == 1) _blocksPerDistribution = _blocksPerDistribution / 12 seconds;
        else if (block.chainid == 42161)
            _blocksPerDistribution = _blocksPerDistribution * 4; // 0.25 seconds blocktime, means 4 blocks per second
        else if (block.chainid == 8453 || block.chainid == 137)
            _blocksPerDistribution = _blocksPerDistribution / 2 seconds;
        else revert("Unsupported chain");

        emit LogDistributionConfigUpdated(
            pullFromDistributor = params_.pullFromDistributor,
            blocksPerDistribution = _blocksPerDistribution,
            cyclesPerDistribution = _cyclesPerDistribution
        );

        vestingTime = uint40(params_.vestingTime);
        vestingStartTime = uint40(params_.vestingStartTime);

        if (params_.startBlock > 0)
            emit LogStartBlockOfNextCycleUpdated(startBlockOfNextCycle = uint40(params_.startBlock));
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
        uint8 positionType_,
        bytes32 positionId_,
        uint256 cycle_,
        bytes memory metadata_
    ) public pure returns (bytes memory encoded_, bytes32 hash_) {
        encoded_ = abi.encode(positionType_, positionId_, recipient_, cycle_, cumulativeAmount_, metadata_);
        hash_ = keccak256(bytes.concat(keccak256(encoded_)));
    }

    /// @notice Claims rewards on behalf of an address for a given recipient. Only for backup claiming for integrating protocols without
    ///         ability to claim on their side. Only callable by owner.
    /// @param onBehalfOf_ - user on behalf of which to claim the rewards. this users rewards get transferred to recipient_
    /// @param recipient_ - address of the recipient
    /// @param cumulativeAmount_ - cumulative amount of rewards to claim
    /// @param positionType_ - type of position, 1 for lending, 2 for vaults, 3 for smart lending, etc
    /// @param positionId_ - id of the position, fToken address for lending and vaultId for vaults
    /// @param cycle_ - cycle of the rewards
    /// @param merkleProof_ - merkle proof of the rewards
    function claimOnBehalfOf(
        address onBehalfOf_,
        address recipient_,
        uint256 cumulativeAmount_,
        uint8 positionType_,
        bytes32 positionId_,
        uint256 cycle_,
        bytes32[] calldata merkleProof_,
        bytes memory metadata_
    ) public onlyOwner whenNotPaused {
        uint256 claimable_ = _claim(
            onBehalfOf_,
            cumulativeAmount_,
            positionType_,
            positionId_,
            cycle_,
            merkleProof_,
            metadata_
        );

        SafeERC20.safeTransfer(TOKEN, recipient_, claimable_);

        emit LogClaimed(onBehalfOf_, claimable_, cycle_, positionType_, positionId_, block.timestamp, block.number);
    }

    /// @notice Claims rewards for a given recipient
    /// @param recipient_ - address of the recipient
    /// @param cumulativeAmount_ - cumulative amount of rewards to claim
    /// @param positionType_ - type of position, 1 for lending, 2 for vaults, 3 for smart lending, etc
    /// @param positionId_ - id of the position, fToken address for lending and vaultId for vaults
    /// @param cycle_ - cycle of the rewards
    /// @param merkleProof_ - merkle proof of the rewards
    function claim(
        address recipient_,
        uint256 cumulativeAmount_,
        uint8 positionType_,
        bytes32 positionId_,
        uint256 cycle_,
        bytes32[] calldata merkleProof_,
        bytes memory metadata_
    ) public whenNotPaused {
        if (msg.sender != recipient_) revert MsgSenderNotRecipient();

        uint256 claimable_ = _claim(
            recipient_,
            cumulativeAmount_,
            positionType_,
            positionId_,
            cycle_,
            merkleProof_,
            metadata_
        );

        SafeERC20.safeTransfer(TOKEN, recipient_, claimable_);

        emit LogClaimed(recipient_, claimable_, cycle_, positionType_, positionId_, block.timestamp, block.number);
    }

    function _claim(
        address recipient_,
        uint256 cumulativeAmount_,
        uint8 positionType_,
        bytes32 positionId_,
        uint256 cycle_,
        bytes32[] calldata merkleProof_,
        bytes memory metadata_
    ) internal returns (uint256 claimable_) {
        uint256 currentCycle_ = uint256(_currentMerkleCycle.cycle);

        if (!(cycle_ == currentCycle_ || (currentCycle_ > 0 && cycle_ == currentCycle_ - 1))) {
            revert InvalidCycle();
        }

        // Verify the merkle proof.
        bytes32 node_ = keccak256(
            bytes.concat(
                keccak256(abi.encode(positionType_, positionId_, recipient_, cycle_, cumulativeAmount_, metadata_))
            )
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

        claimable_ = cumulativeAmount_ - claimed[recipient_][positionId_];
        if (claimable_ == 0) {
            revert NothingToClaim();
        }

        if (vestingTime > 0) {
            uint256 vestingPeriod_ = block.timestamp - vestingStartTime;
            if (vestingPeriod_ < vestingTime) {
                // Calculate total vested amount at current time
                uint256 totalVestedAmount = (cumulativeAmount_ * vestingPeriod_) / vestingTime;
                // Adjust claimable to only what's newly vested
                claimable_ = totalVestedAmount - claimed[recipient_][positionId_];
            }
        }

        claimed[recipient_][positionId_] += claimable_;
    }

    struct Claim {
        address recipient;
        uint256 cumulativeAmount;
        uint8 positionType;
        bytes32 positionId;
        uint256 cycle;
        bytes32[] merkleProof;
        bytes metadata;
    }

    function bulkClaim(Claim[] calldata claims_) external {
        for (uint i = 0; i < claims_.length; i++) {
            claim(
                claims_[i].recipient,
                claims_[i].cumulativeAmount,
                claims_[i].positionType,
                claims_[i].positionId,
                claims_[i].cycle,
                claims_[i].merkleProof,
                claims_[i].metadata
            );
        }
    }
}
