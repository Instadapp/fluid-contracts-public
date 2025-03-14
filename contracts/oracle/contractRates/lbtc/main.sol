// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IChainlinkAggregatorV3 } from "../../interfaces/external/IChainlinkAggregatorV3.sol";
import { FluidContractRate } from "../../fluidContractRate.sol";

/// @notice This contract stores the rate of BTC for 1 LBTC in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
/// @dev rate source is Redstone LBTC fundamental oracle, https://etherscan.io/address/0xb415eAA355D8440ac7eCB602D3fb67ccC1f0bc81
/// also see https://docs.redstone.finance/docs/get-started/price-feeds/types-of-feeds/lombard/
contract LBTCContractRate is FluidContractRate {
    constructor(
        string memory infoName_,
        address rateSource_,
        uint256 minUpdateDiffPercent_,
        uint256 minHeartBeat_
    ) FluidContractRate(infoName_, rateSource_, minUpdateDiffPercent_, minHeartBeat_) {}

    function _getNewRate1e27() internal view virtual override returns (uint256 exchangeRate_) {
        // answer is in 1e8, e.g. 100500000
        (, int256 answer_, , , ) = IChainlinkAggregatorV3(_RATE_SOURCE).latestRoundData();
        return uint256(answer_) * 1e19; // scale to 1e27
    }
}
