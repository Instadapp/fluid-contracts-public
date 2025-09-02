// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

/// @notice implements a method to read uint256 data from storage at a bytes32 storage slot key.
contract StorageRead {
    function readFromStorage(bytes32 slot_) public view returns (uint256 result_) {
        assembly {
            result_ := sload(slot_) // read value from the storage slot
        }
    }
}
