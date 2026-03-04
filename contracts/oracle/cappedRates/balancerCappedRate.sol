// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IBalancerRateProvider } from "../interfaces/external/IBalancerRateProvider.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for a BalancerRateProvider, e.g. ezETH / ETH rate.
///
/// @dev e.g. EZETH BalancerRateProvider contract; 0x387dbc0fb00b26fb085aa658527d5be98302c84c
contract FluidBalancerCappedRate is IBalancerRateProvider, FluidCappedRate {
    constructor(FluidCappedRate.CappedRateConstructorParams memory params_) FluidCappedRate(params_) {}

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        return IBalancerRateProvider(_RATE_SOURCE).getRate();
    }

    /// @inheritdoc IBalancerRateProvider
    function getRate() external view override returns (uint256) {
        return uint256(_slot0.rate) / _RATE_MULTIPLIER; // scale to 1e18
    }
}
