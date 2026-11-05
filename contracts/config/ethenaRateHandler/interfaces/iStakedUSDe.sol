// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IStakedUSDe is IERC4626 {
    /// @notice The amount of the last asset distribution from the controller contract into this
    /// contract + any unvested remainder at that time
    function vestingAmount() external view returns (uint256);

    /// @notice The timestamp of the last asset distribution from the controller contract into this contract
    function lastDistributionTimestamp() external view returns (uint256);

    /// @notice Returns the amount of USDe tokens that are vested in the contract.
    function totalAssets() external view returns (uint256);
}
