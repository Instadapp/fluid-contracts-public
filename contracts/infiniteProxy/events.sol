// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

contract Events {
    /// @notice emitted when a new admin is set
    event LogSetAdmin(address indexed oldAdmin, address indexed newAdmin);

    /// @notice emitted when a new dummy implementation is set
    event LogSetDummyImplementation(address indexed oldDummyImplementation, address indexed newDummyImplementation);

    /// @notice emitted when a new implementation is set with certain sigs
    event LogSetImplementation(address indexed implementation, bytes4[] sigs);

    /// @notice emitted when an implementation is removed
    event LogRemoveImplementation(address indexed implementation);
}
