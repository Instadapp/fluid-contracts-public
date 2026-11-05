// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { FluidCenterPriceL2 } from "../../../contracts/oracleV1_DEPRECATED/fluidCenterPriceL2.sol";
import { Error } from "../../../contracts/oracleV1_DEPRECATED/error.sol";
import { ErrorTypes } from "../../../contracts/oracleV1_DEPRECATED/errorTypes.sol";
import { MockChainlinkSequencerUptimeFeed } from "./mocks/mockChainlinkSequencerUptimeFeed.sol";

contract CenterPriceL2Harness is FluidCenterPriceL2 {
    uint256 internal immutable _price;

    constructor(
        string memory infoName_,
        address sequencerUptimeFeed_,
        uint256 price_
    ) FluidCenterPriceL2(infoName_, sequencerUptimeFeed_) {
        _price = price_;
    }

    function centerPrice() external view override returns (uint256 price_) {
        _ensureSequencerUpAndValid();
        return _price;
    }
}

contract CenterPriceL2SequencerFeedTest is Test {
    function test_constructor_RevertsOnZeroSequencerFeed() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidOracleError.selector,
                ErrorTypes.FluidOracleL2__InvalidSequencerUptimeFeed
            )
        );
        new CenterPriceL2Harness("L2", address(0), 1e27);
    }

    function test_constructor_RevertsOnEOASequencerFeed() public {
        address eoa_ = makeAddr("sequencer-eoa");

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidOracleError.selector,
                ErrorTypes.FluidOracleL2__InvalidSequencerUptimeFeed
            )
        );
        new CenterPriceL2Harness("L2", eoa_, 1e27);
    }

    function test_constructor_AcceptsSequencerFeedContract() public {
        vm.warp(1_000_000);
        MockChainlinkSequencerUptimeFeed feed_ = new MockChainlinkSequencerUptimeFeed();
        CenterPriceL2Harness center_ = new CenterPriceL2Harness("L2", address(feed_), 1e27);

        (address sequencerUptimeFeed_, , , , , , , ) = center_.sequencerL2Data();
        assertEq(sequencerUptimeFeed_, address(feed_));
    }
}
