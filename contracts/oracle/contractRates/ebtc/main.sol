// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWeETHsAccountant } from "../../interfaces/external/IWeETHsAccountant.sol";
import { FluidContractRate } from "../../fluidContractRate.sol";

/// @notice This contract stores the rate of BTC for 1 eBTC in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
/// @dev EBTC accountant contract; 0x1b293DC39F94157fA0D1D36d7e0090C8B8B8c13F
contract EBTCContractRate is IWeETHsAccountant, FluidContractRate {
    constructor(
        string memory infoName_,
        address rateSource_,
        uint256 minUpdateDiffPercent_,
        uint256 minHeartBeat_
    ) FluidContractRate(infoName_, rateSource_, minUpdateDiffPercent_, minHeartBeat_) {}

    function _getNewRate1e27() internal view virtual override returns (uint256 exchangeRate_) {
        // rate is in 1e8 e.g. 100000000
        return IWeETHsAccountant(_RATE_SOURCE).getRate() * 1e19; // scale to 1e27
    }

    /// @inheritdoc IWeETHsAccountant
    function vault() external view override returns (address) {
        return IWeETHsAccountant(_RATE_SOURCE).vault();
    }

    /// @inheritdoc IWeETHsAccountant
    function getRate() external view override returns (uint256) {
        return _rate / 1e19; // scale to 1e8
    }

    /// @inheritdoc IWeETHsAccountant
    function getRateSafe() external view override returns (uint256) {
        IWeETHsAccountant(_RATE_SOURCE).getRateSafe(); // will revert if paused
        // return actual rate of this contract to keep equivalency with getRate() and other methods.
        return _rate / 1e19; // scale to 1e8
    }
}
