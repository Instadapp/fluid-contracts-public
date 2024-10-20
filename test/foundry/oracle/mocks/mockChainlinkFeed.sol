//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { IChainlinkAggregatorV3 } from "../../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";

contract MockChainlinkFeed is IChainlinkAggregatorV3 {
    IChainlinkAggregatorV3 chainlinkFeed;
    int256 exchangeRate;

    constructor(IChainlinkAggregatorV3 originalChainLinkFeed) {
        chainlinkFeed = originalChainLinkFeed;
        (, int256 exchangeRate_, , , ) = chainlinkFeed.latestRoundData();
        exchangeRate = exchangeRate_;
    }

    function setExchangeRate(int256 newExchangeRate_) external {
        exchangeRate = newExchangeRate_;
    }

    function decimals() external view returns (uint8) {
        return chainlinkFeed.decimals();
    }

    function description() external view returns (string memory) {
        return chainlinkFeed.description();
    }

    function version() external view returns (uint256) {
        return chainlinkFeed.version();
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return chainlinkFeed.getRoundData(_roundId);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (uint80 roundIdOrg, , uint256 startedAtOrg, uint256 updatedAtOrg, uint80 answeredInRoundOrg) = chainlinkFeed
            .latestRoundData();
        return (roundIdOrg, exchangeRate, startedAtOrg, updatedAtOrg, answeredInRoundOrg);
    }
}
