// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Owned } from "solmate/src/auth/Owned.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

import { Structs } from "./structs.sol";

abstract contract Constants {
    IERC20 public constant TOKEN = IERC20(0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb); // INST
}

abstract contract Variables is Owned, Pausable, Constants, Structs {
    // ------------ storage variables from inherited contracts (Owned, Pausable) come before vars here --------

    // ----------------------- slot 0 ---------------------------
    // address public owner; -> from Owned

    // bool private _paused; -> from Pausable

    // 11 bytes empty

    // ----------------------- slot 1 ---------------------------

    /// @dev allow list for allowed root proposer addresses
    mapping(address => bool) internal _proposers;

    // ----------------------- slot 2-4 ---------------------------

    /// @dev merkle root data related to current cycle (proposed and approved).
    /// @dev timestamp & publishBlock = data from last publish.
    // with custom getter to return whole struct at once instead of default solidity getter splitting it into tuple
    MerkleCycle internal _currentMerkleCycle;

    // ----------------------- slot 5-7 ---------------------------

    /// @dev merkle root data related to pending cycle (proposed but not yet approved).
    /// @dev timestamp & publishBlock = data from last propose.
    // with custom getter to return whole struct at once instead of default solidity getter splitting it into tuple
    MerkleCycle internal _pendingMerkleCycle;

    // ----------------------- slot 8 ---------------------------

    /// @notice merkle root of the previous cycle
    bytes32 public previousMerkleRoot;

    // ----------------------- slot 9 ---------------------------

    /// @notice total claimed amount per user address and fToken. user => fToken => claimed amount
    mapping(address => mapping(address => uint256)) public claimed;

    constructor(address owner_) Owned(owner_) {}
}
