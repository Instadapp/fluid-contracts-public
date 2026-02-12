// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/// from https://github.com/smartcontractkit/chainlink/blob/master/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol
/// Copyright (c) 2018 SmartContract ChainLink, Ltd.

interface IChainlinkAggregatorV3 {
    /// @notice represents the number of decimals the aggregator responses represent.
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
