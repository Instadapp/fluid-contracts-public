//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsdOracleSequencerL2 } from "../../../contracts/oracleV2/usdOracle/mainL2.sol";
import { ErrorTypes as UsdOracleErrorTypes } from "../../../contracts/oracleV2/usdOracle/errorTypes.sol";
import { Error } from "../../../contracts/oracleV2/usdOracle/error.sol";

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

contract SequencerL2Harness is FluidUsdOracleSequencerL2 {
    constructor(address sequencerUptimeFeed_) FluidUsdOracleSequencerL2(sequencerUptimeFeed_) {}
}

contract FluidUsdOracleSequencerL2ConstructorTest is Test {
    function test_sequencerL2_constructor_RevertsOnZeroSequencerFeed() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__AddressZero)
        );
        new SequencerL2Harness(address(0));
    }

    function test_sequencerL2_constructor_RevertsOnEOASequencerFeed() public {
        address eoa_ = makeAddr("sequencer-eoa");

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidParams)
        );
        new SequencerL2Harness(eoa_);
    }

    function test_sequencerL2_constructor_AcceptsContractSequencerFeed() public {
        SequencerUptimeFeedMock feed_ = new SequencerUptimeFeedMock();
        SequencerL2Harness oracle_ = new SequencerL2Harness(address(feed_));

        (address sequencerUptimeFeed_, , , , , , , ) = oracle_.sequencerL2Data();
        assertEq(sequencerUptimeFeed_, address(feed_));
    }
}
