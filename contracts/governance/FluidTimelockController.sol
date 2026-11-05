// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title FluidTimelockController
/// @notice Thin wrapper around OpenZeppelin `TimelockController` for L2 governance deployments.
/// @dev Admin is disabled at deploy time (`admin = address(0)`); role changes require timelocked proposals.
contract FluidTimelockController is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
