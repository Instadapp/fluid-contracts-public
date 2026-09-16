// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IChainlinkAggregatorV3 } from "../../../contracts/oracleV2/interfaces/external/IChainlinkAggregatorV3.sol";
import { FluidCenterPrice } from "../../../contracts/oracleV2/centerPrices/fluidCenterPrice.sol";
import { FluidCenterPriceL2 } from "../../../contracts/oracleV2/centerPrices/fluidCenterPriceL2.sol";
import { StaticCenterPrice } from "../../../contracts/oracleV2/centerPrices/implementations/staticCenterPrice.sol";
import { FluidCappedRateInvertCenterPrice } from "../../../contracts/oracleV2/centerPrices/implementations/cappedRateInvertCenterPrice.sol";
import { CenterPriceError as CenterError } from "../../../contracts/oracleV2/centerPrices/error.sol";
import { ErrorTypes as CenterErrorTypes } from "../../../contracts/oracleV2/centerPrices/errorTypes.sol";

contract MockCenterRateSource {
    uint256 internal _rate;

    function setRate(uint256 rate_) external {
        _rate = rate_;
    }

    function centerPrice() external view returns (uint256) {
        return _rate;
    }
}

contract MockSequencerUptimeFeedForCenter is IChainlinkAggregatorV3 {
    struct Round {
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    mapping(uint80 => Round) internal _rounds;
    uint80 internal _latestRoundId;

    function setRound(uint80 roundId_, int256 answer_, uint256 startedAt_, uint256 updatedAt_) external {
        _rounds[roundId_] = Round({
            answer: answer_,
            startedAt: startedAt_,
            updatedAt: updatedAt_,
            answeredInRound: roundId_
        });
        if (roundId_ > _latestRoundId) {
            _latestRoundId = roundId_;
        }
    }

    function decimals() external pure returns (uint8) {
        return 0;
    }

    function description() external pure returns (string memory) {
        return "mock sequencer";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80 roundId_
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        Round memory r_ = _rounds[roundId_];
        return (roundId_, r_.answer, r_.startedAt, r_.updatedAt, r_.answeredInRound);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        Round memory r_ = _rounds[_latestRoundId];
        return (_latestRoundId, r_.answer, r_.startedAt, r_.updatedAt, r_.answeredInRound);
    }
}

contract TestCenterPrice is FluidCenterPrice {
    uint256 internal _price;

    constructor(string memory infoName_, uint256 price_) FluidCenterPrice(infoName_) {
        _price = price_;
    }

    function centerPrice() external view override returns (uint256 price_) {
        return _price;
    }
}

contract TestCenterPriceL2 is FluidCenterPriceL2 {
    uint256 internal _price;

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

contract CenterPricesSupplementaryTest is Test {
    function test_fluidCenterPrice_constructor_revertsForInvalidInfoName() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                CenterError.FluidCenterPriceError.selector,
                CenterErrorTypes.FluidOracle__InvalidInfoName
            )
        );
        new TestCenterPrice("", 1e27);

        string memory longName_ = "012345678901234567890123456789012";
        vm.expectRevert(
            abi.encodeWithSelector(
                CenterError.FluidCenterPriceError.selector,
                CenterErrorTypes.FluidOracle__InvalidInfoName
            )
        );
        new TestCenterPrice(longName_, 1e27);
    }

    function test_fluidCenterPrice_infoNameAndTargetDecimals() public {
        TestCenterPrice center_ = new TestCenterPrice("ETH per BTC", 2e27);
        assertEq(center_.infoName(), "ETH per BTC");
        assertEq(center_.targetDecimals(), 27);
        assertEq(center_.centerPrice(), 2e27);
    }

    function test_staticCenterPrice_constructor_revertsOnZeroPrice() public {
        vm.expectRevert(bytes("static price 0"));
        new StaticCenterPrice("static", 0);
    }

    function test_fluidCappedRateInvertCenterPrice_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                CenterError.FluidCenterPriceError.selector,
                CenterErrorTypes.CenterPrice__InvalidParams
            )
        );
        new FluidCappedRateInvertCenterPrice("inv", address(0));
    }

    function test_fluidCappedRateInvertCenterPrice_revertsOnZeroRate() public {
        MockCenterRateSource rateSource_ = new MockCenterRateSource();
        FluidCappedRateInvertCenterPrice invert_ = new FluidCappedRateInvertCenterPrice("inv", address(rateSource_));

        rateSource_.setRate(0);
        vm.expectRevert(
            abi.encodeWithSelector(CenterError.FluidCenterPriceError.selector, CenterErrorTypes.CenterPrice__RateZero)
        );
        invert_.centerPrice();
    }

    function test_fluidCappedRateInvertCenterPrice_returnsInvertedRate() public {
        MockCenterRateSource rateSource_ = new MockCenterRateSource();
        FluidCappedRateInvertCenterPrice invert_ = new FluidCappedRateInvertCenterPrice("inv", address(rateSource_));

        rateSource_.setRate(2e27);
        assertEq(invert_.centerPrice(), 5e26);
    }

    function test_fluidCenterPriceL2_constructor_revertsForInvalidInfoName() public {
        MockSequencerUptimeFeedForCenter feed_ = new MockSequencerUptimeFeedForCenter();

        vm.expectRevert(
            abi.encodeWithSelector(
                CenterError.FluidCenterPriceError.selector,
                CenterErrorTypes.FluidOracle__InvalidInfoName
            )
        );
        new TestCenterPriceL2("", address(feed_), 1e27);
    }

    function test_fluidCenterPriceL2_centerPrice_revertsWhenSequencerDown() public {
        vm.warp(2 days);
        MockSequencerUptimeFeedForCenter feed_ = new MockSequencerUptimeFeedForCenter();
        feed_.setRound(1, 1, block.timestamp - 1 hours, block.timestamp - 1 hours);
        TestCenterPriceL2 center_ = new TestCenterPriceL2("L2", address(feed_), 1e27);

        vm.expectRevert(
            abi.encodeWithSelector(
                CenterError.FluidCenterPriceError.selector,
                CenterErrorTypes.FluidOracleL2__SequencerOutage
            )
        );
        center_.centerPrice();
    }

    function test_fluidCenterPriceL2_centerPrice_revertsInsideGracePeriod() public {
        vm.warp(2 days);
        MockSequencerUptimeFeedForCenter feed_ = new MockSequencerUptimeFeedForCenter();
        uint256 outageStart_ = block.timestamp - 20 minutes;
        uint256 uptimeStart_ = block.timestamp - 5 minutes;
        feed_.setRound(0, 0, 0, 0);
        feed_.setRound(1, 1, outageStart_, outageStart_);
        feed_.setRound(2, 0, uptimeStart_, uptimeStart_);
        TestCenterPriceL2 center_ = new TestCenterPriceL2("L2", address(feed_), 1e27);

        vm.expectRevert(
            abi.encodeWithSelector(
                CenterError.FluidCenterPriceError.selector,
                CenterErrorTypes.FluidOracleL2__SequencerOutage
            )
        );
        center_.centerPrice();
    }

    function test_fluidCenterPriceL2_centerPrice_succeedsAfterGracePeriod() public {
        vm.warp(2 days);
        MockSequencerUptimeFeedForCenter feed_ = new MockSequencerUptimeFeedForCenter();
        uint256 outageStart_ = block.timestamp - 15 minutes;
        uint256 uptimeStart_ = block.timestamp - 10 minutes;
        feed_.setRound(0, 0, 0, 0);
        feed_.setRound(1, 1, outageStart_, outageStart_);
        feed_.setRound(2, 0, uptimeStart_, uptimeStart_);
        TestCenterPriceL2 center_ = new TestCenterPriceL2("L2", address(feed_), 7e27);

        assertEq(center_.centerPrice(), 7e27);
        (
            address sequencer_,
            uint256 maxGrace_,
            bool isUp_,
            uint256 lastUptimeStartedAt_,
            uint256 grace_,
            bool gracePassed_,
            uint256 lastOutageStartedAt_,
            bool isValid_
        ) = center_.sequencerL2Data();

        assertEq(sequencer_, address(feed_));
        assertEq(maxGrace_, 45 minutes);
        assertTrue(isUp_);
        assertEq(lastUptimeStartedAt_, uptimeStart_);
        assertEq(grace_, uptimeStart_ - outageStart_);
        assertTrue(gracePassed_);
        assertEq(lastOutageStartedAt_, outageStart_);
        assertTrue(isValid_);
    }
}
