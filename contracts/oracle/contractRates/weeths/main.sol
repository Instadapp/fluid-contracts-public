// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWeETHsAccountant } from "../../interfaces/external/IWeETHsAccountant.sol";
import { FluidContractRate } from "../../fluidContractRate.sol";

/// @notice This contract stores the rate of ETH for 1 weETHs in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
/// @dev WEETHS accountant contract; 0xbe16605B22a7faCEf247363312121670DFe5afBE
contract WeETHsContractRate is IWeETHsAccountant, FluidContractRate {
    constructor(
        string memory infoName_,
        address rateSource_,
        uint256 minUpdateDiffPercent_,
        uint256 minHeartBeat_
    ) FluidContractRate(infoName_, rateSource_, minUpdateDiffPercent_, minHeartBeat_) {}

    function _getNewRate1e27() internal view virtual override returns (uint256 exchangeRate_) {
        return IWeETHsAccountant(_RATE_SOURCE).getRate() * 1e9; // scale to 1e27
    }

    /// @inheritdoc IWeETHsAccountant
    function vault() external view override returns (address) {
        return IWeETHsAccountant(_RATE_SOURCE).vault();
    }

    /// @inheritdoc IWeETHsAccountant
    function getRate() external view override returns (uint256) {
        return _rate / 1e9; // scale to 1e18
    }

    /// @inheritdoc IWeETHsAccountant
    function getRateSafe() external view override returns (uint256) {
        IWeETHsAccountant(_RATE_SOURCE).getRateSafe(); // will revert if paused
        // return actual rate of this contract to keep equivalency with getRate() and other methods.
        return _rate / 1e9; // scale to 1e18
    }
}
