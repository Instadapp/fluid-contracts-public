// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWstETH } from "../../interfaces/external/IWstETH.sol";
import { FluidContractRate } from "../../fluidContractRate.sol";

/// @notice This contract stores the rate of stETH for 1 wstETH in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
/// @dev WSTETH contract; on mainnet 0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0
contract WstETHContractRate is IWstETH, FluidContractRate {
    constructor(
        string memory infoName_,
        address rateSource_,
        uint256 minUpdateDiffPercent_,
        uint256 minHeartBeat_
    ) FluidContractRate(infoName_, rateSource_, minUpdateDiffPercent_, minHeartBeat_) {}

    function _getNewRate1e27() internal view virtual override returns (uint256 exchangeRate_) {
        return IWstETH(_RATE_SOURCE).stEthPerToken() * 1e9; // scale to 1e27
    }

    /// @inheritdoc IWstETH
    function stEthPerToken() external view override returns (uint256) {
        return _rate / 1e9; // scale to 1e18
    }

    /// @inheritdoc IWstETH
    function tokensPerStEth() external view override returns (uint256) {
        return 1e45 / _rate; // scale to 1e18
    }
}
