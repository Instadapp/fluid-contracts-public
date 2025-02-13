// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IRsETHLRTOracle } from "../../interfaces/external/IRsETHLRTOracle.sol";
import { FluidContractRate } from "../../fluidContractRate.sol";

/// @notice This contract stores the rate of ETH for 1 rstETH in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
/// @dev RSETH LRT oracle contract; 0x349A73444b1a310BAe67ef67973022020d70020d
contract RsETHContractRate is IRsETHLRTOracle, FluidContractRate {
    constructor(
        string memory infoName_,
        IRsETHLRTOracle rstETHLRTOracle_,
        uint256 minUpdateDiffPercent_,
        uint256 minHeartBeat_
    ) FluidContractRate(infoName_, address(rstETHLRTOracle_), minUpdateDiffPercent_, minHeartBeat_) {}

    function _getNewRate1e27() internal view virtual override returns (uint256 exchangeRate_) {
        return IRsETHLRTOracle(_RATE_SOURCE).rsETHPrice() * 1e9; // scale to 1e27
    }

    /// @inheritdoc IRsETHLRTOracle
    function rsETHPrice() external view override returns (uint256) {
        return _rate / 1e9; // scale to 1e18
    }
}
