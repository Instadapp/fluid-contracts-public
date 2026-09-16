// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { IFluidOracle } from "../../interfaces/iFluidOracle.sol";
import { Structs } from "../clxStockOracle/structs.sol";

/// @notice Chainlink 24/5 × Backed wrapper stock oracle (session-aware caps). Not upgradeable.
interface IFluidCLXStockOracle is IFluidOracle {
    function getConfig() external view returns (Structs.CLXStockOracleConfig memory config_);

    /// @notice Backed underlying (`wrapper.asset()`); separate from `getConfig()` to keep that ABI stable.
    function backedUnderlying() external view returns (address);

    /// @notice Debt operate: extended-hours clamp inverted vs collateral (floor downside).
    function getExchangeRateOperateDebt() external view returns (uint256 exchangeRate_);

    /// @notice Debt liquidate: extended-hours clamp inverted vs collateral (cap upside).
    function getExchangeRateLiquidateDebt() external view returns (uint256 exchangeRate_);

    /// @notice Permissionless RTH anchor: latest CL round in current regular window (+ buffer); once the
    ///         window is past, also the latest pre-window round within heartbeat of the close.
    ///         Gov / class ≥ 3 may roll out-of-band vs the gap reference — accepts a verified CL↔split re-sync.
    /// @param roundId_ Start hint (`0` = stored/latest). Walks to last in-window round.
    function updateRegularHoursAnchor(uint80 roundId_) external;
}
