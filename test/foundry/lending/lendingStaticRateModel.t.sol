// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IFTokenAdmin } from "../../../contracts/protocols/lending/interfaces/iFToken.sol";
import "../../../contracts/protocols/lending/lendingStaticRateModel/main.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";
import { Error } from "../../../contracts/protocols/lending/error.sol";

// To test run: forge test --match-path test/foundry/lending/lendingStaticRateModel.t.sol -vvv
contract FluidLendingStaticRateModelTest is Test {
    FluidLendingStaticRateModel public model;

    address public configurator = address(this);
    address public fToken = address(0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33);

    uint256 constant RATE_PRECISION = 1e12;
    uint256 constant MAX_RATE = 50 * RATE_PRECISION;
    uint256 constant DEFAULT_DURATION = 365 days;

    function setUp() public {
        model = new FluidLendingStaticRateModel(configurator, fToken, address(0), address(0), 0, DEFAULT_DURATION);
        vm.mockCall(fToken, abi.encodeWithSelector(IFTokenAdmin.updateStaticRewards.selector), "");
        vm.mockCall(
            fToken,
            abi.encodeWithSelector(IFTokenAdmin.updateRates.selector),
            abi.encode(uint256(1e12), uint256(1e12))
        );
    }

    function testConstructorRevert() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__InvalidParams)
        );
        new FluidLendingStaticRateModel(address(0), fToken, address(0), address(0), 0, DEFAULT_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__InvalidParams)
        );
        new FluidLendingStaticRateModel(configurator, address(0), address(0), address(0), 0, DEFAULT_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__InvalidParams)
        );
        new FluidLendingStaticRateModel(configurator, fToken, address(0), address(0), 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__InvalidParams)
        );
        new FluidLendingStaticRateModel(
            configurator,
            fToken,
            address(0),
            address(0),
            int256(MAX_RATE + 1),
            DEFAULT_DURATION
        );
    }

    function testConstructorAndGetConfig() public {
        FluidLendingStaticRateModel modelAt3Pct = new FluidLendingStaticRateModel(
            configurator,
            fToken,
            address(0),
            address(0),
            int256(3 * RATE_PRECISION),
            DEFAULT_DURATION
        );

        (int256 staticRate, uint256 duration, uint256 startTime, address configurator_, uint256 maxRate_) = modelAt3Pct
            .getStaticConfig();
        assertEq(staticRate, int256(3 * RATE_PRECISION));
        assertEq(duration, DEFAULT_DURATION);
        assertEq(startTime, block.timestamp);
        assertEq(configurator_, configurator);
        assertEq(maxRate_, MAX_RATE);
    }

    function testGetStaticRate_active() public {
        FluidLendingStaticRateModel modelAt3Pct = new FluidLendingStaticRateModel(
            configurator,
            fToken,
            address(0),
            address(0),
            int256(3 * RATE_PRECISION),
            DEFAULT_DURATION
        );

        (int256 rate, bool ended, uint256 startTime, uint256 endTime) = modelAt3Pct.getRateV2(0);
        assertEq(rate, int256(3 * RATE_PRECISION));
        assertFalse(ended);
        assertEq(startTime, block.timestamp);
        assertEq(endTime, block.timestamp + DEFAULT_DURATION);
    }

    function testGetStaticRate_zeroRateStillActive() public {
        (int256 rate, bool ended, , ) = model.getRateV2(0);
        assertEq(rate, int256(0));
        assertFalse(ended, "0% within duration is active, not ended");
    }

    function testGetStaticRate_endedAfterDuration() public {
        FluidLendingStaticRateModel modelAt3Pct = new FluidLendingStaticRateModel(
            configurator,
            fToken,
            address(0),
            address(0),
            int256(3 * RATE_PRECISION),
            DEFAULT_DURATION
        );

        vm.warp(block.timestamp + DEFAULT_DURATION + 1);

        (int256 rate, bool ended, uint256 startTime, uint256 endTime) = modelAt3Pct.getRateV2(0);
        assertEq(rate, int256(3 * RATE_PRECISION), "rate stays the actual rate when ended (for exact tail accrual)");
        assertTrue(ended);
        assertEq(startTime, block.timestamp - DEFAULT_DURATION - 1);
        assertEq(endTime, startTime + DEFAULT_DURATION);
    }

    function testSetStaticRate_ValidRates() public {
        (, , uint256 startBefore_, , ) = model.getStaticConfig();

        model.setStaticRate(int256(0), DEFAULT_DURATION);
        (int256 rate, bool ended, uint256 startTime, ) = model.getRateV2(0);
        assertEq(rate, int256(0));
        assertFalse(ended);

        vm.warp(block.timestamp + 1 days);
        model.setStaticRate(int256(3 * RATE_PRECISION), DEFAULT_DURATION * 2);
        (rate, ended, startTime, ) = model.getRateV2(0);
        assertEq(rate, int256(3 * RATE_PRECISION));
        assertFalse(ended);
        assertGt(startTime, startBefore_);

        (, uint256 duration, , , ) = model.getStaticConfig();
        assertEq(duration, DEFAULT_DURATION * 2);

        model.setStaticRate(int256(MAX_RATE), DEFAULT_DURATION);
        (rate, ended, , ) = model.getRateV2(0);
        assertEq(rate, int256(MAX_RATE));
        assertFalse(ended);

        model.setStaticRate(-int256(MAX_RATE), DEFAULT_DURATION);
        (rate, ended, , ) = model.getRateV2(0);
        assertEq(rate, -int256(MAX_RATE));
        assertFalse(ended);

        model.setStaticRate(-int256(3 * RATE_PRECISION), DEFAULT_DURATION);
        (rate, ended, , ) = model.getRateV2(0);
        assertEq(rate, -int256(3 * RATE_PRECISION));
        assertFalse(ended);
    }

    function testSetStaticRate_RevertMaxRate() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__MaxRate)
        );
        model.setStaticRate(int256(MAX_RATE + 1), DEFAULT_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__MaxRate)
        );
        model.setStaticRate(-int256(MAX_RATE) - 1, DEFAULT_DURATION);
    }

    function testConstructorRevert_negativeOutsideMaxRate() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__InvalidParams)
        );
        new FluidLendingStaticRateModel(
            configurator,
            fToken,
            address(0),
            address(0),
            -int256(MAX_RATE) - 1,
            DEFAULT_DURATION
        );
    }

    function testSetStaticRate_RevertZeroDuration() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__InvalidParams)
        );
        model.setStaticRate(int256(3 * RATE_PRECISION), 0);
    }

    function testSetStaticRate_callsUpdateStaticRewards() public {
        vm.expectCall(fToken, abi.encodeWithSelector(IFTokenAdmin.updateStaticRewards.selector, address(model)));
        model.setStaticRate(int256(3 * RATE_PRECISION), DEFAULT_DURATION);
    }

    function testStopStaticRate() public {
        FluidLendingStaticRateModel modelAt3Pct = new FluidLendingStaticRateModel(
            configurator,
            fToken,
            address(0),
            address(0),
            int256(3 * RATE_PRECISION),
            DEFAULT_DURATION
        );

        vm.warp(block.timestamp + 1 days);
        vm.expectCall(fToken, abi.encodeWithSelector(IFTokenAdmin.updateRates.selector));
        modelAt3Pct.stopStaticRate();

        (int256 rate, bool ended, , uint256 endTime) = modelAt3Pct.getRateV2(0);
        assertEq(rate, int256(3 * RATE_PRECISION), "rate stays the actual rate when ended (for exact tail accrual)");
        assertTrue(ended);
        assertLt(endTime, block.timestamp, "endTime is in the past after stop");
    }

    function testStopStaticRate_RevertAlreadyStopped() public {
        vm.warp(block.timestamp + 1 days);
        model.stopStaticRate();
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__AlreadyStopped)
        );
        model.stopStaticRate();
    }

    function testOnlyConfiguratorModifier() public {
        address nonConfigurator = address(0x123);
        vm.prank(nonConfigurator);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__Unauthorized)
        );
        model.setStaticRate(int256(3 * RATE_PRECISION), DEFAULT_DURATION);
    }

    function testConstructor_revertsDurationExceedsUint32Max() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__InvalidParams)
        );
        new FluidLendingStaticRateModel(
            configurator,
            fToken,
            address(0),
            address(0),
            int256(3 * RATE_PRECISION),
            uint256(type(uint32).max) + 1
        );
    }

    function testSetStaticRate_revertsDurationExceedsUint32Max() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingStaticRateModel__InvalidParams)
        );
        model.setStaticRate(int256(3 * RATE_PRECISION), uint256(type(uint32).max) + 1);
    }

    function testSetStaticRate_acceptsMaxUint32Duration() public {
        model.setStaticRate(int256(3 * RATE_PRECISION), type(uint32).max);
        (, uint256 duration_, , , ) = model.getStaticConfig();
        assertEq(duration_, type(uint32).max);
    }

    function testLegacyGetRateAndGetConfig_returnZeros() public {
        (uint256 rate_, bool ended_, uint256 startTime_) = model.getRate(1e18);
        assertEq(rate_, 0);
        assertFalse(ended_);
        assertEq(startTime_, 0);

        (
            uint256 duration_,
            uint256 startTimeCfg_,
            uint256 endTime_,
            uint256 startTvl_,
            uint256 maxRate_,
            uint256 rewardAmount_,
            address configurator_
        ) = model.getConfig();
        assertEq(duration_, 0);
        assertEq(startTimeCfg_, 0);
        assertEq(endTime_, 0);
        assertEq(startTvl_, 0);
        assertEq(maxRate_, 0);
        assertEq(rewardAmount_, 0);
        assertEq(configurator_, address(0));
    }

    function testSetStaticRate_callsUpdateStaticRewardsOnFToken2And3() public {
        address fToken2_ = address(0x2222);
        address fToken3_ = address(0x3333);
        FluidLendingStaticRateModel multiModel_ = new FluidLendingStaticRateModel(
            configurator,
            fToken,
            fToken2_,
            fToken3_,
            int256(3 * RATE_PRECISION),
            DEFAULT_DURATION
        );
        vm.mockCall(fToken2_, abi.encodeWithSelector(IFTokenAdmin.updateStaticRewards.selector), "");
        vm.mockCall(fToken3_, abi.encodeWithSelector(IFTokenAdmin.updateStaticRewards.selector), "");

        vm.expectCall(fToken, abi.encodeWithSelector(IFTokenAdmin.updateStaticRewards.selector, address(multiModel_)));
        vm.expectCall(
            fToken2_,
            abi.encodeWithSelector(IFTokenAdmin.updateStaticRewards.selector, address(multiModel_))
        );
        vm.expectCall(
            fToken3_,
            abi.encodeWithSelector(IFTokenAdmin.updateStaticRewards.selector, address(multiModel_))
        );
        multiModel_.setStaticRate(int256(5 * RATE_PRECISION), DEFAULT_DURATION);
    }

    function testStopStaticRate_callsUpdateRatesOnFToken2And3() public {
        address fToken2_ = address(0x2222);
        address fToken3_ = address(0x3333);
        FluidLendingStaticRateModel multiModel_ = new FluidLendingStaticRateModel(
            configurator,
            fToken,
            fToken2_,
            fToken3_,
            int256(3 * RATE_PRECISION),
            DEFAULT_DURATION
        );
        vm.mockCall(
            fToken2_,
            abi.encodeWithSelector(IFTokenAdmin.updateRates.selector),
            abi.encode(uint256(1e12), uint256(1e12))
        );
        vm.mockCall(
            fToken3_,
            abi.encodeWithSelector(IFTokenAdmin.updateRates.selector),
            abi.encode(uint256(1e12), uint256(1e12))
        );

        vm.warp(block.timestamp + 1 days);
        vm.expectCall(fToken, abi.encodeWithSelector(IFTokenAdmin.updateRates.selector));
        vm.expectCall(fToken2_, abi.encodeWithSelector(IFTokenAdmin.updateRates.selector));
        vm.expectCall(fToken3_, abi.encodeWithSelector(IFTokenAdmin.updateRates.selector));
        multiModel_.stopStaticRate();
    }
}
