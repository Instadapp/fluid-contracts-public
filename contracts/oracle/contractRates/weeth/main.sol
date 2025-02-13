// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWeETH } from "../../interfaces/external/IWeETH.sol";
import { FluidContractRate } from "../../fluidContractRate.sol";

/// @notice This contract stores the rate of eETH for 1 wEETH in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
/// @dev WEETH contract; on mainnet 0xcd5fe23c85820f7b72d0926fc9b05b43e359b7ee
contract WEETHContractRate is IWeETH, FluidContractRate {
    constructor(
        string memory infoName_,
        address rateSource_,
        uint256 minUpdateDiffPercent_,
        uint256 minHeartBeat_
    ) FluidContractRate(infoName_, rateSource_, minUpdateDiffPercent_, minHeartBeat_) {}

    function _getNewRate1e27() internal view virtual override returns (uint256 exchangeRate_) {
        return IWeETH(_RATE_SOURCE).getEETHByWeETH(1e27); // scale to 1e27
    }

    /// @inheritdoc IWeETH
    function getEETHByWeETH(uint256 _weETHAmount) external view override returns (uint256) {
        return (_rate * _weETHAmount) / 1e27;
    }

    /// @inheritdoc IWeETH
    function getWeETHByeETH(uint256 _eETHAmount) external view override returns (uint256) {
        return (1e27 * _eETHAmount) / _rate;
    }
}
