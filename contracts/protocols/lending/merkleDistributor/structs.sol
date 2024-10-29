// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Structs {
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
}
