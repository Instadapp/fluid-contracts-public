// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsdOracleL2 } from "../../../contracts/oracleV2/usdOracle/mainL2.sol";
import { Error as UsdError } from "../../../contracts/oracleV2/usdOracle/error.sol";
import { ErrorTypes as UsdErrorTypes } from "../../../contracts/oracleV2/usdOracle/errorTypes.sol";
import { Error as CommonError } from "../../../contracts/oracleV2/common/error.sol";
import { ErrorTypes as CommonErrorTypes } from "../../../contracts/oracleV2/common/errorTypes.sol";

import { SequencerUptimeFeedMock } from "./chrStockOracleMocks.sol";

/// @notice Sequencer gate on `FluidUsdOracleL2`'s guarded reads. The gate runs before any token lookup, so no token
///         is configured here.
contract UsdOracleSequencerL2GateTest is Test {
    SequencerUptimeFeedMock feed;
    FluidUsdOracleL2 oracle;

    address constant TOKEN = address(0x7A11);

    function setUp() public {
        vm.warp(1_700_000_000);
        feed = new SequencerUptimeFeedMock();
        feed.setRound(1, 0, block.timestamp - 1 days);
        oracle = new FluidUsdOracleL2(makeAddr("liquidity"), address(feed));
    }

    function _expectCommonErr(uint256 id_) internal {
        vm.expectRevert(abi.encodeWithSelector(CommonError.OracleV2CommonError.selector, id_));
    }

    function test_getPriceView_RevertIfSequencerDown() public {
        feed.setRound(2, 1, block.timestamp);
        _expectCommonErr(CommonErrorTypes.SequencerL2__SequencerDown);
        oracle.getPriceView(TOKEN, 0, true, true);
    }

    function test_getPriceDetailedView_RevertIfSequencerDown() public {
        feed.setRound(2, 1, block.timestamp);
        _expectCommonErr(CommonErrorTypes.SequencerL2__SequencerDown);
        oracle.getPriceDetailedView(TOKEN, 0, true, true);
    }

    function test_getPriceView_RevertIfSequencerGracePeriod() public {
        uint256 t1_ = block.timestamp - 10 minutes;
        feed.setRound(1, 1, t1_ - 30 minutes);
        feed.setRound(2, 0, t1_);
        _expectCommonErr(CommonErrorTypes.SequencerL2__GracePeriod);
        oracle.getPriceView(TOKEN, 0, true, true);
    }

    function test_getPriceDetailedViewRaw_NotGatedBySequencer() public {
        feed.setRound(2, 1, block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(UsdError.FluidUsdOracleError.selector, UsdErrorTypes.UsdOracle__NoConfig)
        );
        oracle.getPriceDetailedViewRaw(TOKEN, 0, true, true);
    }
}
