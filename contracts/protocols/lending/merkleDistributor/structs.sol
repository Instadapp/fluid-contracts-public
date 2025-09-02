// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Structs {
    struct ConstructorParams {
        string name;
        address owner;
        address proposer;
        address approver;
        address rewardToken;
        uint256 distributionInHours;
        uint256 cycleInHours;
        uint256 startBlock;
        bool pullFromDistributor;
        uint256 vestingTime;
        uint256 vestingStartTime;
    }

    struct MerkleCycle {
        // slot 1
        bytes32 merkleRoot;
        // slot 2
        bytes32 merkleContentHash;
        // slot 3
        uint40 cycle;
        uint40 timestamp;
        uint40 publishBlock;
        uint40 startBlock;
        uint40 endBlock;
    }

    struct Reward {
        // slot 1
        uint256 amount;
        // slot 2
        uint40 cycle;
        uint40 startBlock;
        uint40 endBlock;
        uint40 epoch;
    }

    struct Distribution {
        // slot 1
        uint256 amount;
        // slot 2
        uint40 epoch;
        uint40 startCycle;
        uint40 endCycle;
        uint40 registrationBlock;
        uint40 registrationTimestamp;
    }
}
