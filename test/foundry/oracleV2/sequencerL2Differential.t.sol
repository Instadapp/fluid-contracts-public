//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { FluidCenterPriceL2 } from "../../../contracts/oracleV1_DEPRECATED/fluidCenterPriceL2.sol";
import { FluidSequencerL2 } from "../../../contracts/oracleV2/common/sequencerL2.sol";
import { Error as CommonError } from "../../../contracts/oracleV2/common/error.sol";
import { ErrorTypes as CommonErrorTypes } from "../../../contracts/oracleV2/common/errorTypes.sol";
import { MockChainlinkSequencerUptimeFeed } from "../oracleL2/mocks/mockChainlinkSequencerUptimeFeed.sol";

contract CenterPriceL2Harness is FluidCenterPriceL2 {
    constructor(address feed_) FluidCenterPriceL2("harness", feed_) {}

    function centerPrice() external pure override returns (uint256) {
        return 0;
    }

    function check() external view {
        _ensureSequencerUpAndValid();
    }
}

contract SequencerL2Harness is FluidSequencerL2 {
    constructor(address feed_) FluidSequencerL2(feed_) {}

    function check() external view {
        _ensureSequencerUpAndValid();
    }
}

/// @dev Pins the shared helper to the pre-extraction algorithm, kept verbatim in the deprecated V1 `FluidCenterPriceL2`.
contract SequencerL2DifferentialTest is Test {
    MockChainlinkSequencerUptimeFeed feed;
    CenterPriceL2Harness centerPriceRef;
    SequencerL2Harness helper;

    function setUp() public {
        vm.warp(100 days);
        feed = new MockChainlinkSequencerUptimeFeed();
        centerPriceRef = new CenterPriceL2Harness(address(feed));
        helper = new SequencerL2Harness(address(feed));
    }

    function test_fuzz_SequencerL2_MatchesCenterPriceL2(uint80 roundId_, uint256 minutesAfterRound_) public {
        roundId_ = uint80(bound(roundId_, 2, 16));
        feed.setCurrentRoundId(roundId_);
        (, , uint256 startedAtMinutesAgo_) = feed.rounds(roundId_);
        minutesAfterRound_ = bound(minutesAfterRound_, 0, startedAtMinutesAgo_);
        feed.setCurrentTimeMinutesAgo(startedAtMinutesAgo_ - minutesAfterRound_);

        _assertSameOutcome();
    }

    function test_sequencerL2Data_MatchesCenterPriceL2AcrossAllRounds() public {
        for (uint80 roundId_ = 2; roundId_ <= 16; roundId_++) {
            feed.setCurrentRoundId(roundId_);
            _assertSameOutcome();
        }
    }

    function test_check_RevertIfSequencerDown() public {
        feed.setCurrentRoundId(feed.ROUND_ID_DOWN_FOR_10_MINUTES());
        vm.expectRevert(
            abi.encodeWithSelector(
                CommonError.OracleV2CommonError.selector,
                CommonErrorTypes.SequencerL2__SequencerDown
            )
        );
        helper.check();
    }

    function test_check_RevertIfGraceRightAfterOutage() public {
        feed.setCurrentRoundId(feed.ROUND_ID_DOWN_FOR_30_MINUTES_UP_AGAIN());
        vm.expectRevert(
            abi.encodeWithSelector(CommonError.OracleV2CommonError.selector, CommonErrorTypes.SequencerL2__GracePeriod)
        );
        helper.check();
    }

    function _assertSameOutcome() internal {
        (bool refOk_, ) = address(centerPriceRef).staticcall(abi.encodeCall(CenterPriceL2Harness.check, ()));
        (bool helperOk_, ) = address(helper).staticcall(abi.encodeCall(SequencerL2Harness.check, ()));
        assertEq(helperOk_, refOk_, "check outcome");

        (bool refDataOk_, bytes memory refData_) = address(centerPriceRef).staticcall(
            abi.encodeCall(FluidCenterPriceL2.sequencerL2Data, ())
        );
        (bool helperDataOk_, bytes memory helperData_) = address(helper).staticcall(
            abi.encodeCall(FluidSequencerL2.sequencerL2Data, ())
        );
        assertEq(helperDataOk_, refDataOk_, "sequencerL2Data outcome");
        assertEq(helperData_, refData_, "sequencerL2Data tuple");
    }
}
