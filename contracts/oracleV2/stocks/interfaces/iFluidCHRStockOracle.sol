// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { IFluidOracleWithDebt } from "../../interfaces/iFluidOracleWithDebt.sol";
import { IFluidOracleWrite } from "../../interfaces/iFluidOracleWrite.sol";
import { Structs } from "../chrStockOracle/structs.sol";

/// @notice Chronicle price × Reality rtoken `uiMultiplier` with a stored regular-session anchor. Not upgradeable.
interface IFluidCHRStockOracle is IFluidOracleWithDebt, IFluidOracleWrite {
    /// @notice Immutables plus stored state (anchor, pending in-session price, accepted multiplier, pause flag).
    function getConfig() external view returns (Structs.CHRStockOracleConfig memory config_);

    /// @notice Permissionless: seals a finished session's hint and records the current in-session print.
    /// @return stored_ true if anything was sealed or recorded
    function updateRegularHoursAnchor() external returns (bool stored_);

    /// @notice Permissionless: pauses the oracle while the issuer has halted the rtoken or changed its multiplier.
    ///         A reverting dependency read is not a cause. Only `unpause` lifts it.
    /// @return causes_ bitmask: 1 tradePaused, 2 rtoken paused, 4 multiplier changed
    function latchPause() external returns (uint256 causes_);

    /// @notice AuthGate MID.
    function pause() external;

    /// @notice AuthGate MID. Reverts while a latch cause holds.
    function unpause() external;

    /// @notice AuthGate HIGH: anchor = live value, accepted multiplier = `expectedMultiplier_`; no continuity check.
    function setAnchor(uint256 expectedMultiplier_) external;
}
