// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.36;

import { IFluidOracle } from "./iFluidOracle.sol";

/// @notice Fluid oracle that exposes directional debt getters (e.g. CLX stock oracles).
/// @dev Distinct from `IFluidCappedRate`: no `centerPrice()` required.
interface IFluidOracleWithDebt is IFluidOracle {
    /// @notice Operate exchange rate for the debt asset side
    function getExchangeRateOperateDebt() external view returns (uint256 exchangeRate_);

    /// @notice Liquidate exchange rate for the debt asset side
    function getExchangeRateLiquidateDebt() external view returns (uint256 exchangeRate_);
}
