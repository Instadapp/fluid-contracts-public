// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

library ReentrancyLock {
    // bytes32(uint256(keccak256("FLUID_REENTRANCY_LOCK")) - 1)
    bytes32 constant REENTRANCY_LOCK_SLOT = 0xb9cde754d19acfff2b3ccabc66f256d3563a0bc5805da4205f01a9bda38a2df7;

    function lock() internal {
        assembly {
            if tload(REENTRANCY_LOCK_SLOT) { revert(0, 0) }
            tstore(REENTRANCY_LOCK_SLOT, 1)
        }
    }

    function unlock() internal {
        assembly { tstore(REENTRANCY_LOCK_SLOT, 0) }
    }
}
