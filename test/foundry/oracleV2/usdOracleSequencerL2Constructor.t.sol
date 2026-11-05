//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidSequencerL2 } from "../../../contracts/oracleV2/common/sequencerL2.sol";
import { Error as CommonError } from "../../../contracts/oracleV2/common/error.sol";
import { ErrorTypes as CommonErrorTypes } from "../../../contracts/oracleV2/common/errorTypes.sol";

contract SequencerUptimeFeedMock {
    struct RoundData {
        int256 answer;
        uint256 startedAt;
    }

    mapping(uint80 => RoundData) public rounds;
    uint80 public latestRoundId;

    function setRound(uint80 roundId_, int256 answer_, uint256 startedAt_) external {
        rounds[roundId_] = RoundData(answer_, startedAt_);
        if (roundId_ > latestRoundId) {
            latestRoundId = roundId_;
        }
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt_, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory r = rounds[latestRoundId];
        return (latestRoundId, r.answer, r.startedAt, block.timestamp, latestRoundId);
    }

    function getRoundData(
        uint80 roundId_
    )
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt_, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory r = rounds[roundId_];
        return (roundId_, r.answer, r.startedAt, r.startedAt, roundId_);
    }
}

contract SequencerL2Harness is FluidSequencerL2 {
    constructor(address sequencerUptimeFeed_) FluidSequencerL2(sequencerUptimeFeed_) {}
}

contract FluidSequencerL2ConstructorTest is Test {
    function test_constructor_RevertIfSequencerFeedZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(CommonError.OracleV2CommonError.selector, CommonErrorTypes.SequencerL2__InvalidFeed)
        );
        new SequencerL2Harness(address(0));
    }

    function test_constructor_RevertIfSequencerFeedNoCode() public {
        address eoa_ = makeAddr("sequencer-eoa");

        vm.expectRevert(
            abi.encodeWithSelector(CommonError.OracleV2CommonError.selector, CommonErrorTypes.SequencerL2__InvalidFeed)
        );
        new SequencerL2Harness(eoa_);
    }

    function test_constructor_AcceptsContractSequencerFeed() public {
        SequencerUptimeFeedMock feed_ = new SequencerUptimeFeedMock();
        SequencerL2Harness oracle_ = new SequencerL2Harness(address(feed_));

        (address sequencerUptimeFeed_, , , , , , , ) = oracle_.sequencerL2Data();
        assertEq(sequencerUptimeFeed_, address(feed_));
    }
}
