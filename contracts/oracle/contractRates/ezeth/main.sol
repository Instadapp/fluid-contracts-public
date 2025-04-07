// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IEZETHBalancerRateProvider } from "../../interfaces/external/IEZETHBalancerRateProvider.sol";
import { FluidContractRate } from "../../fluidContractRate.sol";

/// @notice This contract stores the rate of ETH for 1 ezETH in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
/// @dev EZETH BalancerRateProvider contract; 0x387dbc0fb00b26fb085aa658527d5be98302c84c
contract EZETHContractRate is IEZETHBalancerRateProvider, FluidContractRate {
    constructor(
        string memory infoName_,
        address rateSource_,
        uint256 minUpdateDiffPercent_,
        uint256 minHeartBeat_
    ) FluidContractRate(infoName_, rateSource_, minUpdateDiffPercent_, minHeartBeat_) {}

    function _getNewRate1e27() internal view virtual override returns (uint256 exchangeRate_) {
        return IEZETHBalancerRateProvider(_RATE_SOURCE).getRate() * 1e9; // scale to 1e27
    }

    /// @inheritdoc IEZETHBalancerRateProvider
    function getRate() external view override returns (uint256) {
        return _rate / 1e9; // scale to 1e18
    }
}
