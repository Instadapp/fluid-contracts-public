// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Owned } from "solmate/src/auth/Owned.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

import { Structs } from "./structs.sol";

abstract contract Constants {
    IERC20 public immutable TOKEN;

    constructor(address rewardToken_) {
        TOKEN = IERC20(rewardToken_);
    }
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

    // ----------------------- slot 2 ---------------------------

    /// @dev allow list for allowed root proposer addresses
    mapping(address => bool) internal _approvers;

    // ----------------------- slot 3-5 ---------------------------

    /// @dev merkle root data related to current cycle (proposed and approved).
    /// @dev timestamp & publishBlock = data from last publish.
    // with custom getter to return whole struct at once instead of default solidity getter splitting it into tuple
    MerkleCycle internal _currentMerkleCycle;

    // ----------------------- slot 6-8 ---------------------------

    /// @dev merkle root data related to pending cycle (proposed but not yet approved).
    /// @dev timestamp & publishBlock = data from last propose.
    // with custom getter to return whole struct at once instead of default solidity getter splitting it into tuple
    MerkleCycle internal _pendingMerkleCycle;

    // ----------------------- slot 9 ---------------------------

    /// @notice merkle root of the previous cycle
    bytes32 public previousMerkleRoot;

    // ----------------------- slot 10 ---------------------------

    /// @notice total claimed amount per user address and fToken. user => positionId => claimed amount
    mapping(address => mapping(bytes32 => uint256)) public claimed;

    constructor(address owner_, address rewardToken_) Constants(rewardToken_) Owned(owner_) {}
}
