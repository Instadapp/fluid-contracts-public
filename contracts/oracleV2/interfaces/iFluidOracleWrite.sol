// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.36;

/// @notice Optional non-view oracle getters for vault / USD-oracle hot paths (e.g. CLX cache warm).
///         Directional getters mirror `IFluidOracleWithDebt`.
/// @dev Each getter is optional; implementations may expose only the subset that applies to them.
///      Implementations must enforce equivalent checks on their view getters, so callers can fall back to those.
///      Vault core falls back only on empty revert data (missing selector) and rethrows non-empty reverts;
///      readers with per-leg failure isolation (USD oracle price tree) fall back on any failure.
interface IFluidOracleWrite {
    /// @notice Non-view operate rate. May persist oracle state (e.g. last regular-hours price).
    function getExchangeRateOperateWrite() external returns (uint256 exchangeRate_);

    /// @notice Non-view liquidate rate. May persist oracle state (e.g. last regular-hours price).
    function getExchangeRateLiquidateWrite() external returns (uint256 exchangeRate_);

    /// @notice Non-view operate debt rate. May persist oracle state (e.g. last regular-hours price).
    function getExchangeRateOperateDebtWrite() external returns (uint256 exchangeRate_);

    /// @notice Non-view liquidate debt rate. May persist oracle state (e.g. last regular-hours price).
    function getExchangeRateLiquidateDebtWrite() external returns (uint256 exchangeRate_);
}
