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

    /// @dev Name of the Merkle Distributor
    string public name;

    // ----------------------- slot 2 ---------------------------

    /// @dev allow list for allowed root proposer addresses
    mapping(address => bool) internal _proposers;

    // ----------------------- slot 3 ---------------------------

    /// @dev allow list for allowed root proposer addresses
    mapping(address => bool) internal _approvers;

    // ----------------------- slot 4-6 ---------------------------

    /// @dev merkle root data related to current cycle (proposed and approved).
    /// @dev timestamp & publishBlock = data from last publish.
    // with custom getter to return whole struct at once instead of default solidity getter splitting it into tuple
    MerkleCycle internal _currentMerkleCycle;

    // ----------------------- slot 7-9 ---------------------------

    /// @dev merkle root data related to pending cycle (proposed but not yet approved).
    /// @dev timestamp & publishBlock = data from last propose.
    // with custom getter to return whole struct at once instead of default solidity getter splitting it into tuple
    MerkleCycle internal _pendingMerkleCycle;

    // ----------------------- slot 10 ---------------------------

    /// @notice merkle root of the previous cycle
    bytes32 public previousMerkleRoot;

    // ----------------------- slot 11 ---------------------------

    /// @notice total claimed amount per user address and fToken. user => positionId => claimed amount
    mapping(address => mapping(bytes32 => uint256)) public claimed;

    // ----------------------- slot 12 ---------------------------

    /// @notice Data of cycle rewards
    Reward[] internal rewards;

    // ----------------------- slot 13 ---------------------------

    /// @notice data of distributions
    Distribution[] internal distributions;

    // ----------------------- slot 14 ---------------------------

    /// @notice allow list for rewards distributors
    mapping(address => bool) public rewardsDistributor;

    // ----------------------- slot 15 ---------------------------

    /// @notice Number of cycles to distribute rewards
    uint40 public cyclesPerDistribution;

    /// @notice Duration of each distribution in blocks
    uint40 public blocksPerDistribution;

    /// @notice Start block of the next cycle
    uint40 public startBlockOfNextCycle;

    /// @notice Whether to pull tokens from distributor or not
    bool public pullFromDistributor;

    /// @notice Vesting time for rewards
    uint40 public vestingTime;

    /// @notice Vesting start time
    uint40 public vestingStartTime;

    constructor(address owner_, address rewardToken_) Constants(rewardToken_) Owned(owner_) {}
}
