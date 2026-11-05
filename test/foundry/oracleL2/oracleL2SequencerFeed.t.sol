// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { FluidOracleL2 } from "../../../contracts/oracleV1_DEPRECATED/fluidOracleL2.sol";
import { Error } from "../../../contracts/oracleV1_DEPRECATED/error.sol";
import { ErrorTypes } from "../../../contracts/oracleV1_DEPRECATED/errorTypes.sol";
import { MockChainlinkSequencerUptimeFeed } from "./mocks/mockChainlinkSequencerUptimeFeed.sol";

contract FluidOracleL2Harness is FluidOracleL2 {
    constructor(address sequencerUptimeFeed_) FluidOracleL2(sequencerUptimeFeed_) {}

    function getExchangeRate() external pure override returns (uint256) {
        return 1;
    }

    function getExchangeRateOperate() external pure override returns (uint256) {
        return 1;
    }

    function getExchangeRateLiquidate() external pure override returns (uint256) {
        return 1;
    }

    function infoName() external pure override returns (string memory) {
        return "FluidOracleL2Harness";
    }

    function targetDecimals() external pure override returns (uint8) {
        return 18;
    }
}

contract FluidOracleL2InvalidSequencerFeedTest is Test {
    function test_constructor_RevertsOnZeroSequencerFeed() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidOracleError.selector,
                ErrorTypes.FluidOracleL2__InvalidSequencerUptimeFeed
            )
        );
        new FluidOracleL2Harness(address(0));
    }

    function test_constructor_RevertsOnEOASequencerFeed() public {
        address eoa = makeAddr("sequencer-eoa");

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidOracleError.selector,
                ErrorTypes.FluidOracleL2__InvalidSequencerUptimeFeed
            )
        );
        new FluidOracleL2Harness(eoa);
    }

    function test_constructor_AcceptsSequencerFeedContract() public {
        vm.warp(1_000_000);
        MockChainlinkSequencerUptimeFeed feed = new MockChainlinkSequencerUptimeFeed();
        FluidOracleL2Harness oracle = new FluidOracleL2Harness(address(feed));

        (address sequencerUptimeFeed_, , , , , , , ) = oracle.sequencerL2Data();
        assertEq(sequencerUptimeFeed_, address(feed));
    }
}
