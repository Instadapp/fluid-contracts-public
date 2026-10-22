//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import "forge-std/console2.sol";

contract MockChainlinkSequencerUptimeFeed {
    struct MockRoundData {
        uint80 roundId;
        int256 answer; // 0 = Sequencer is up
        uint256 startedAtMinutesAgo;
    }

    mapping(uint80 => MockRoundData) public rounds;

    uint80 public currentRoundId;

    uint256 public currentTimeMinutesAgo;

    uint80 public constant ROUND_ID_DOWN_FOR_10_MINUTES = 3;
    uint80 public constant ROUND_ID_DOWN_FOR_10_MINUTES_UP_AGAIN = 4;

    uint80 public constant ROUND_ID_DOWN_FOR_30_MINUTES = 7;
    uint80 public constant ROUND_ID_DOWN_FOR_30_MINUTES_UP_AGAIN = 8;
    uint80 public constant ROUND_ID_DOWN_FOR_30_MINUTES_UP_LAST_CONSECUTIVE = 11;

    uint80 public constant ROUND_ID_DOWN_FOR_80_MINUTES_FIRST = 12;
    uint80 public constant ROUND_ID_DOWN_FOR_80_MINUTES_LAST_CONSECUTIVE = 14;
    uint80 public constant ROUND_ID_DOWN_FOR_80_MINUTES_UP_AGAIN = 15;
    uint80 public constant ROUND_ID_DOWN_FOR_80_MINUTES_UP_LAST_CONSECUTIVE = 16;

    constructor() {
        setRoundData(1, 0, 0); // first round, sequencer up
        setRoundData(2, 0, 800 minutes); // sequencer up
        setRoundData(3, 1, 700 minutes); // sequencer down for 10 minutes
        setRoundData(4, 0, 690 minutes); // sequencer up after 10 minutes
        setRoundData(5, 0, 640 minutes); // sequencer up consecutive report
        setRoundData(6, 0, 600 minutes); // sequencer up consecutive report
        setRoundData(7, 1, 550 minutes); // sequencer down for 30 minutes
        setRoundData(8, 0, 520 minutes); // sequencer up after 30 minutes
        setRoundData(9, 0, 510 minutes); // sequencer up consecutive report
        setRoundData(10, 0, 500 minutes); // sequencer up consecutive report
        setRoundData(11, 0, 490 minutes); // sequencer up consecutive report
        setRoundData(12, 1, 480 minutes); // sequencer down total of 80 minutes
        setRoundData(13, 1, 450 minutes); // sequencer down consecutive report
        setRoundData(14, 1, 410 minutes); // sequencer down consecutive report
        setRoundData(15, 0, 400 minutes); // sequencer up after 80 minutes
        setRoundData(16, 0, 30 minutes); // sequencer up consecutive report

        setCurrentRoundId(16);
        setCurrentTimeMinutesAgo(0);
    }

    function setCurrentTimeMinutesAgo(uint256 currentTimeMinutesAgo_) public {
        currentTimeMinutesAgo = currentTimeMinutesAgo_;
    }

    function setCurrentRoundId(uint80 roundId) public {
        currentRoundId = roundId;
        currentTimeMinutesAgo = rounds[roundId].startedAtMinutesAgo;
    }

    function setRoundData(uint80 roundId, int256 answer, uint256 startedAtMinutesAgo) public {
        rounds[roundId] = MockRoundData(roundId, answer, startedAtMinutesAgo);
    }

    function getRoundData(
        uint80 _roundId
    )
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        MockRoundData memory roundData = rounds[_roundId];
        console2.log("getRoundData block timestamp", block.timestamp);
        console2.log("getRoundData roundData.startedAtMinutesAgo", roundData.startedAtMinutesAgo);
        console2.log("getRoundData currentTimeMinutesAgo", currentTimeMinutesAgo);
        return (
            roundData.roundId,
            roundData.answer,
            roundData.startedAtMinutesAgo == 0
                ? 0
                : block.timestamp - roundData.startedAtMinutesAgo + currentTimeMinutesAgo,
            roundData.startedAtMinutesAgo == 0
                ? 0
                : block.timestamp - roundData.startedAtMinutesAgo + currentTimeMinutesAgo,
            roundData.roundId
        );
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return getRoundData(currentRoundId);
    }
}
