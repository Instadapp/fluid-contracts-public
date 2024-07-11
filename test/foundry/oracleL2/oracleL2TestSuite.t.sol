//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { FluidOracleL2 } from "../../../contracts/oracle/fluidOracleL2.sol";

import { MockChainlinkSequencerUptimeFeed } from "./mocks/mockChainlinkSequencerUptimeFeed.sol";
import { OracleTestSuite } from "../oracle/oracleTestSuite.t.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";

import "forge-std/console2.sol";

abstract contract OracleL2TestSuite is OracleTestSuite {
    FluidOracleL2 oracleL2;
    MockChainlinkSequencerUptimeFeed mockFeed;

    function test_sequencerL2Data() public {
        (
            address sequencerUptimeFeed_,
            uint256 maxGracePeriod_,
            bool isSequencerUp_,
            uint256 lastUptimeStartedAt_,
            uint256 gracePeriod_,
            bool gracePeriodPassed_,
            uint256 lastOutageStartedAt_,
            bool isSequencerUpAndValid_
        ) = oracleL2.sequencerL2Data();

        assertEq(sequencerUptimeFeed_, address(mockFeed));
        assertEq(maxGracePeriod_, 45 minutes);
        assertEq(isSequencerUp_, true);
        assertEq(lastUptimeStartedAt_, block.timestamp - 400 minutes);
        assertEq(gracePeriod_, 45 minutes);
        assertEq(gracePeriodPassed_, true);
        assertEq(lastOutageStartedAt_, 0);
        assertEq(isSequencerUpAndValid_, true);
    }

    function test_getExchangeRate_sequencerOutage10Min() public {
        // set current feed round to an outage round, see data in constructor in MockChainlinkSequencerUptimeFeed
        mockFeed.setCurrentRoundId(mockFeed.ROUND_ID_DOWN_FOR_10_MINUTES());
        (
            ,
            ,
            bool isSequencerUp_,
            uint256 lastUptimeStartedAt_,
            uint256 gracePeriod_,
            bool gracePeriodPassed_,
            uint256 lastOutageStartedAt_,
            bool isSequencerUpAndValid_
        ) = oracleL2.sequencerL2Data();
        assertEq(isSequencerUp_, false);
        assertEq(lastUptimeStartedAt_, 0);
        assertEq(gracePeriod_, 45 minutes);
        assertEq(gracePeriodPassed_, false);
        assertEq(lastOutageStartedAt_, block.timestamp);
        assertEq(isSequencerUpAndValid_, false);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.FluidOracleL2__SequencerOutage);

        // set to round id where outage was over. grace period should be 10 minutes.
        mockFeed.setCurrentRoundId(mockFeed.ROUND_ID_DOWN_FOR_10_MINUTES_UP_AGAIN());
        (
            ,
            ,
            isSequencerUp_,
            lastUptimeStartedAt_,
            gracePeriod_,
            gracePeriodPassed_,
            lastOutageStartedAt_,
            isSequencerUpAndValid_
        ) = oracleL2.sequencerL2Data();
        assertEq(isSequencerUp_, true);
        assertEq(lastUptimeStartedAt_, block.timestamp);
        assertEq(gracePeriod_, 10 minutes);
        assertEq(gracePeriodPassed_, false);
        assertEq(lastOutageStartedAt_, block.timestamp - 10 minutes);
        assertEq(isSequencerUpAndValid_, false);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.FluidOracleL2__SequencerOutage);

        // simulate 10 minutes passed
        mockFeed.setCurrentTimeMinutesAgo(mockFeed.currentTimeMinutesAgo() - 10 minutes);
        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.FluidOracleL2__SequencerOutage);

        // grace period should be over after 10 minutes + 1 second
        mockFeed.setCurrentTimeMinutesAgo(mockFeed.currentTimeMinutesAgo() - 1);
        (
            ,
            ,
            isSequencerUp_,
            lastUptimeStartedAt_,
            gracePeriod_,
            gracePeriodPassed_,
            lastOutageStartedAt_,
            isSequencerUpAndValid_
        ) = oracleL2.sequencerL2Data();
        assertEq(isSequencerUp_, true);
        assertEq(lastUptimeStartedAt_, block.timestamp - 10 minutes - 1);
        assertEq(gracePeriod_, 10 minutes);
        assertEq(gracePeriodPassed_, true);
        assertEq(lastOutageStartedAt_, block.timestamp - 20 minutes - 1);
        assertEq(isSequencerUpAndValid_, true);

        _assertExchangeRatesAllMethodsNotZero(oracle);
    }

    function test_getExchangeRate_sequencerOutageUpConsecutive() public {
        // set current feed round to an outage round, see data in constructor in MockChainlinkSequencerUptimeFeed
        mockFeed.setCurrentRoundId(mockFeed.ROUND_ID_DOWN_FOR_30_MINUTES());
        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.FluidOracleL2__SequencerOutage);

        // set to round id where outage was over. grace period should be 30 minutes.
        mockFeed.setCurrentRoundId(mockFeed.ROUND_ID_DOWN_FOR_30_MINUTES_UP_AGAIN());
        (
            ,
            ,
            bool isSequencerUp_,
            uint256 lastUptimeStartedAt_,
            uint256 gracePeriod_,
            bool gracePeriodPassed_,
            uint256 lastOutageStartedAt_,
            bool isSequencerUpAndValid_
        ) = oracleL2.sequencerL2Data();
        assertEq(isSequencerUp_, true);
        assertEq(lastUptimeStartedAt_, block.timestamp);
        assertEq(gracePeriod_, 30 minutes);
        assertEq(gracePeriodPassed_, false);
        assertEq(lastOutageStartedAt_, block.timestamp - 30 minutes);
        assertEq(isSequencerUpAndValid_, false);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.FluidOracleL2__SequencerOutage);

        // set to round id where outage was over with consecutive uptime reports. at this round grace period should be over
        mockFeed.setCurrentRoundId(mockFeed.ROUND_ID_DOWN_FOR_30_MINUTES_UP_LAST_CONSECUTIVE());
        mockFeed.setCurrentTimeMinutesAgo(mockFeed.currentTimeMinutesAgo() - 1);

        (
            ,
            ,
            isSequencerUp_,
            lastUptimeStartedAt_,
            gracePeriod_,
            gracePeriodPassed_,
            lastOutageStartedAt_,
            isSequencerUpAndValid_
        ) = oracleL2.sequencerL2Data();
        assertEq(isSequencerUp_, true);
        assertEq(lastUptimeStartedAt_, block.timestamp - 30 minutes - 1);
        assertEq(gracePeriod_, 30 minutes);
        assertEq(gracePeriodPassed_, true);
        assertEq(lastOutageStartedAt_, block.timestamp - 60 minutes - 1);
        assertEq(isSequencerUpAndValid_, true);

        _assertExchangeRatesAllMethodsNotZero(oracle);
    }

    function test_getExchangeRate_sequencerOutageDownConsecutive() public {
        // set current feed round to an outage round, see data in constructor in MockChainlinkSequencerUptimeFeed
        mockFeed.setCurrentRoundId(mockFeed.ROUND_ID_DOWN_FOR_80_MINUTES_FIRST());
        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.FluidOracleL2__SequencerOutage);

        mockFeed.setCurrentRoundId(mockFeed.ROUND_ID_DOWN_FOR_80_MINUTES_LAST_CONSECUTIVE());
        (
            ,
            ,
            bool isSequencerUp_,
            uint256 lastUptimeStartedAt_,
            uint256 gracePeriod_,
            bool gracePeriodPassed_,
            uint256 lastOutageStartedAt_,
            bool isSequencerUpAndValid_
        ) = oracleL2.sequencerL2Data();
        assertEq(isSequencerUp_, false);
        assertEq(lastUptimeStartedAt_, 0);
        assertEq(gracePeriod_, 45 minutes);
        assertEq(gracePeriodPassed_, false);
        assertEq(lastOutageStartedAt_, block.timestamp - 70 minutes);
        assertEq(isSequencerUpAndValid_, false);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.FluidOracleL2__SequencerOutage);

        // set to round id where outage was over. grace period should be 45 minutes.
        mockFeed.setCurrentRoundId(mockFeed.ROUND_ID_DOWN_FOR_80_MINUTES_UP_AGAIN());
        (
            ,
            ,
            isSequencerUp_,
            lastUptimeStartedAt_,
            gracePeriod_,
            gracePeriodPassed_,
            lastOutageStartedAt_,
            isSequencerUpAndValid_
        ) = oracleL2.sequencerL2Data();
        assertEq(isSequencerUp_, true);
        assertEq(lastUptimeStartedAt_, block.timestamp);
        assertEq(gracePeriod_, 45 minutes);
        assertEq(gracePeriodPassed_, false);
        assertEq(lastOutageStartedAt_, block.timestamp - 80 minutes);
        assertEq(isSequencerUpAndValid_, false);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.FluidOracleL2__SequencerOutage);

        // set time to after grace period
        mockFeed.setCurrentTimeMinutesAgo(mockFeed.currentTimeMinutesAgo() - 45 minutes - 1);

        (
            ,
            ,
            isSequencerUp_,
            lastUptimeStartedAt_,
            gracePeriod_,
            gracePeriodPassed_,
            lastOutageStartedAt_,
            isSequencerUpAndValid_
        ) = oracleL2.sequencerL2Data();
        assertEq(isSequencerUp_, true);
        assertEq(lastUptimeStartedAt_, block.timestamp - 45 minutes - 1);
        assertEq(gracePeriod_, 45 minutes);
        assertEq(gracePeriodPassed_, true);
        assertEq(lastOutageStartedAt_, 0);
        assertEq(isSequencerUpAndValid_, true);

        _assertExchangeRatesAllMethodsNotZero(oracle);

        mockFeed.setCurrentRoundId(mockFeed.ROUND_ID_DOWN_FOR_80_MINUTES_UP_LAST_CONSECUTIVE());
        mockFeed.setCurrentTimeMinutesAgo(0);
        (
            ,
            ,
            isSequencerUp_,
            lastUptimeStartedAt_,
            gracePeriod_,
            gracePeriodPassed_,
            lastOutageStartedAt_,
            isSequencerUpAndValid_
        ) = oracleL2.sequencerL2Data();
        assertEq(isSequencerUp_, true);
        assertEq(lastUptimeStartedAt_, block.timestamp - 400 minutes);
        assertEq(gracePeriod_, 45 minutes);
        assertEq(gracePeriodPassed_, true);
        assertEq(lastOutageStartedAt_, 0);
        assertEq(isSequencerUpAndValid_, true);

        _assertExchangeRatesAllMethodsNotZero(oracle);
    }
}
