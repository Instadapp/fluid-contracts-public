//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { FluidCappedRate, FluidCappedRateBase } from "../../../contracts/oracle/fluidCappedRate.sol";
import { FluidWSTETHCappedRate, IWstETH } from "../../../contracts/oracle/cappedRates/wstethCappedRate.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";

contract FluidCappedRateTest is Test {
    FluidWSTETHCappedRate cappedRate;

    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;
    address constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    address constant alice = address(0xABCD);

    uint256 constant _SIX_DECIMALS = 1e6;

    uint256 constant MAX_APR_PERCENT = 10e4;
    uint256 constant MAX_DOWN_PERCENT_COL = 20e4;
    uint256 constant MAX_DOWN_PERCENT_DEBT = 2e4;
    uint256 constant MAX_UP_CAP_PERCENT_DEBT = 5e4;

    uint256 WSTETH_RATE_START;

    FluidCappedRateBase.CappedRateConstructorParams constructorParams;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(22245957);

        WSTETH_RATE_START = IWstETH(WSTETH).stEthPerToken();

        constructorParams = FluidCappedRateBase.CappedRateConstructorParams({
            infoName: "ETH per 1 WSTETH",
            liquidity: LIQUIDITY,
            rateSource: WSTETH,
            rateMultiplier: 1e9,
            minUpdateDiffPercent: 100, // 0.01%
            minHeartbeat: 7 days,
            avoidForcedLiquidationsCol: false,
            avoidForcedLiquidationsDebt: false,
            maxAPRPercent: MAX_APR_PERCENT, // 10%
            maxDownFromMaxReachedPercentCol: MAX_DOWN_PERCENT_COL, // 20%
            maxDownFromMaxReachedPercentDebt: MAX_DOWN_PERCENT_DEBT, // 2%
            maxDebtUpCapPercent: MAX_UP_CAP_PERCENT_DEBT // 5%
        });

        cappedRate = new FluidWSTETHCappedRate(constructorParams);
    }

    function _assertAllRates(uint256 expectedRate) internal view {
        assertEq(cappedRate.getExchangeRate(), expectedRate);
        assertEq(cappedRate.getExchangeRateOperate(), expectedRate);
        assertEq(cappedRate.getExchangeRateLiquidate(), expectedRate);
        assertEq(cappedRate.getExchangeRateOperateDebt(), expectedRate);
        assertEq(cappedRate.getExchangeRateLiquidateDebt(), expectedRate);
    }

    function _assertStorageSyncNeeded() internal view {
        assertGt(cappedRate.configPercentDiff(), 0);
    }

    function _assertStorageSynced() internal view {
        assertEq(cappedRate.configPercentDiff(), 0);
    }

    function test_deploys() public view {
        _assertAllRates(WSTETH_RATE_START * 1e9);

        (
            address liquidity_,
            uint16 minUpdateDiffPercent_,
            uint24 minHeartbeat_,
            uint40 lastUpdateTime_,
            address rateSource_,
            bool avoidForcedLiquidationsCol_,
            bool avoidForcedLiquidationsDebt_,
            uint256 maxAPRPercent_,
            uint24 maxDownFromMaxReachedPercentCol_,
            uint24 maxDownFromMaxReachedPercentDebt_,
            uint256 maxDebtUpCapPercent_
        ) = cappedRate.configData();

        assertEq(liquidity_, constructorParams.liquidity);
        assertEq(minUpdateDiffPercent_, constructorParams.minUpdateDiffPercent);
        assertEq(minHeartbeat_, constructorParams.minHeartbeat);
        assertEq(rateSource_, constructorParams.rateSource);
        assertEq(avoidForcedLiquidationsCol_, constructorParams.avoidForcedLiquidationsCol);
        assertEq(avoidForcedLiquidationsDebt_, constructorParams.avoidForcedLiquidationsDebt);
        assertEq(maxAPRPercent_, constructorParams.maxAPRPercent);
        assertEq(maxDownFromMaxReachedPercentCol_, constructorParams.maxDownFromMaxReachedPercentCol);
        assertEq(maxDownFromMaxReachedPercentDebt_, constructorParams.maxDownFromMaxReachedPercentDebt);
        assertEq(maxDebtUpCapPercent_, constructorParams.maxDebtUpCapPercent);
    }

    struct TestFlags {
        bool isRateBelowMaxReached;
        bool isUpMaxAPRCapped;
        bool isDownCappedCol;
        bool isDownCappedDebt;
        bool isUpCapped;
    }

    function test_getRatesAndCaps() public {
        (
            uint256 rate_,
            uint256 maxReachedRate_,
            uint256 maxUpCappedRateDebt_,
            ,
            ,
            uint256 downCappedRateCol_,
            uint256 downCappedRateDebt_,
            ,
            ,

        ) = cappedRate.getRatesAndCaps();

        TestFlags memory tf;
        (
            ,
            ,
            ,
            tf.isRateBelowMaxReached,
            tf.isUpMaxAPRCapped,
            ,
            ,
            tf.isDownCappedCol,
            tf.isDownCappedDebt,
            tf.isUpCapped
        ) = cappedRate.getRatesAndCaps();

        assertEq(rate_, WSTETH_RATE_START * 1e9);
        assertEq(maxReachedRate_, WSTETH_RATE_START * 1e9);
        assertEq(maxUpCappedRateDebt_, (WSTETH_RATE_START * 1e9 * 105) / 100);

        assertEq(tf.isRateBelowMaxReached, false);
        assertEq(tf.isUpMaxAPRCapped, false);

        assertEq(
            downCappedRateCol_,
            (WSTETH_RATE_START * 1e9 * (_SIX_DECIMALS - MAX_DOWN_PERCENT_COL)) / _SIX_DECIMALS
        );
        assertEq(
            downCappedRateDebt_,
            (WSTETH_RATE_START * 1e9 * (_SIX_DECIMALS - MAX_DOWN_PERCENT_DEBT)) / _SIX_DECIMALS
        );

        assertEq(tf.isDownCappedCol, false);
        assertEq(tf.isDownCappedDebt, false);
        assertEq(tf.isUpCapped, false);

        uint256 newRate = (WSTETH_RATE_START * 110) / 100;
        vm.warp(block.timestamp + 10 days); // after heartbeat
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));

        (rate_, maxReachedRate_, maxUpCappedRateDebt_, , , downCappedRateCol_, downCappedRateDebt_, , , ) = cappedRate
            .getRatesAndCaps();
        (
            ,
            ,
            ,
            tf.isRateBelowMaxReached,
            tf.isUpMaxAPRCapped,
            ,
            ,
            tf.isDownCappedCol,
            tf.isDownCappedDebt,
            tf.isUpCapped
        ) = cappedRate.getRatesAndCaps();

        assertEq(rate_, newRate * 1e9);

        assertApproxEqRel(
            maxReachedRate_,
            WSTETH_RATE_START *
                1e9 +
                (((WSTETH_RATE_START * 1e9 * 10 days) / 365 days) * MAX_APR_PERCENT) /
                _SIX_DECIMALS, // max yield rate
            1e12
        ); // 0.0001% diff

        assertEq(maxUpCappedRateDebt_, (maxReachedRate_ * 105) / 100);

        assertEq(tf.isRateBelowMaxReached, false);
        assertEq(tf.isUpMaxAPRCapped, true);

        assertApproxEqRel(
            downCappedRateCol_,
            (maxReachedRate_ * (_SIX_DECIMALS - MAX_DOWN_PERCENT_COL)) / _SIX_DECIMALS,
            1e12
        ); // 0.0001% diff
        assertApproxEqRel(
            downCappedRateDebt_,
            (maxReachedRate_ * (_SIX_DECIMALS - MAX_DOWN_PERCENT_DEBT)) / _SIX_DECIMALS,
            1e12
        ); // 0.0001% diff

        assertEq(tf.isDownCappedCol, false);
        assertEq(tf.isDownCappedDebt, false);
        assertEq(tf.isUpCapped, true);

        // decrease rate by 10x
        newRate = newRate / 10;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));

        (rate_, maxReachedRate_, maxUpCappedRateDebt_, , , downCappedRateCol_, downCappedRateDebt_, , , ) = cappedRate
            .getRatesAndCaps();
        (
            ,
            ,
            ,
            tf.isRateBelowMaxReached,
            tf.isUpMaxAPRCapped,
            ,
            ,
            tf.isDownCappedCol,
            tf.isDownCappedDebt,
            tf.isUpCapped
        ) = cappedRate.getRatesAndCaps();

        assertEq(rate_, newRate * 1e9);
        assertEq(maxReachedRate_, WSTETH_RATE_START * 1e9);
        assertEq(maxUpCappedRateDebt_, (WSTETH_RATE_START * 1e9 * 105) / 100);

        assertEq(tf.isRateBelowMaxReached, true);
        assertEq(tf.isUpMaxAPRCapped, false);

        assertApproxEqRel(
            downCappedRateCol_,
            (WSTETH_RATE_START * 1e9 * (_SIX_DECIMALS - MAX_DOWN_PERCENT_COL)) / _SIX_DECIMALS,
            1e12
        ); // 0.0001% diff
        assertApproxEqRel(
            downCappedRateDebt_,
            (WSTETH_RATE_START * 1e9 * (_SIX_DECIMALS - MAX_DOWN_PERCENT_DEBT)) / _SIX_DECIMALS,
            1e12
        ); // 0.0001% diff

        assertEq(tf.isDownCappedCol, true);
        assertEq(tf.isDownCappedDebt, true);
        assertEq(tf.isUpCapped, false);
    }

    function test_updateRates() public {
        // sync with rebalance
        vm.warp(block.timestamp + 2 days);
        assertEq(cappedRate.isHeartbeatTrigger(), false);
        // simulate rate increased by 0.001%, not enough for min update diff
        uint256 newRate = (WSTETH_RATE_START * 100_001) / 100_000;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        assertEq(IWstETH(WSTETH).stEthPerToken(), newRate);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__MinUpdateDiffNotReached)
        );
        cappedRate.rebalance();

        // after heartbeat, min update diff should be ignored
        vm.warp(block.timestamp + 6 days);
        assertEq(cappedRate.isHeartbeatTrigger(), true);
        cappedRate.rebalance();
        _assertAllRates(newRate * 1e9);

        // simulate rate increased by 0.02%
        vm.warp(block.timestamp + 2 days);
        newRate = (newRate * 100_02) / 100_00;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        cappedRate.rebalance();
        _assertAllRates(newRate * 1e9);

        // sync via centerPrice if heartbeat passed
        newRate = (newRate * 100_02) / 100_00;
        vm.warp(block.timestamp + 7 days + 1);
        assertEq(cappedRate.isHeartbeatTrigger(), true);
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();
        uint256 centerPrice = cappedRate.centerPrice();
        assertEq(centerPrice, newRate * 1e9);
        _assertAllRates(newRate * 1e9);
        _assertStorageSynced();
        assertEq(cappedRate.isHeartbeatTrigger(), false);
    }

    function test_updateAvoidForcedLiquidationsCol() public {
        vm.prank(TEAM_MULTISIG);
        cappedRate.updateAvoidForcedLiquidationsCol(true);
        (, , , , , bool avoidForcedLiquidationsCol_, , , , , ) = cappedRate.configData();
        assertTrue(avoidForcedLiquidationsCol_);

        vm.prank(GOVERNANCE);
        cappedRate.updateAvoidForcedLiquidationsCol(false);
        (, , , , , avoidForcedLiquidationsCol_, , , , , ) = cappedRate.configData();
        assertFalse(avoidForcedLiquidationsCol_);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__Unauthorized));
        cappedRate.updateAvoidForcedLiquidationsCol(true);
    }

    function test_updateAvoidForcedLiquidationsDebt() public {
        vm.prank(TEAM_MULTISIG);
        cappedRate.updateAvoidForcedLiquidationsDebt(true);
        (, , , , , , bool avoidForcedLiquidationsDebt_, , , , ) = cappedRate.configData();
        assertTrue(avoidForcedLiquidationsDebt_);

        vm.prank(GOVERNANCE);
        cappedRate.updateAvoidForcedLiquidationsDebt(false);
        (, , , , , , avoidForcedLiquidationsDebt_, , , , ) = cappedRate.configData();
        assertFalse(avoidForcedLiquidationsDebt_);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__Unauthorized));
        cappedRate.updateAvoidForcedLiquidationsDebt(true);
    }

    function test_forceResetMaxRate() public {
        // Simulate setting maxReachedAPRCappedRate to 2e20 without overwriting the full slot
        uint256 slot1 = uint256(keccak256(abi.encodePacked(uint256(1))));
        bytes32 currentSlotValue = vm.load(address(cappedRate), bytes32(slot1));
        bytes32 newMaxReachedAPRCappedRate = bytes32(uint256(2e20) & ((1 << 168) - 1));
        bytes32 updatedSlotValue = (currentSlotValue & ~bytes32(uint256((1 << 168) - 1))) | newMaxReachedAPRCappedRate;
        vm.store(address(cappedRate), bytes32(slot1), updatedSlotValue);

        vm.prank(TEAM_MULTISIG);
        cappedRate.forceResetMaxRate();
        (, uint256 maxReachedRate_, , , , , , , , ) = cappedRate.getRatesAndCaps();
        assertEq(maxReachedRate_, WSTETH_RATE_START * 1e9);

        vm.prank(GOVERNANCE);
        cappedRate.forceResetMaxRate();

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__Unauthorized));
        cappedRate.forceResetMaxRate();
    }

    function test_updateMaxAPRPercent() public {
        uint256 newMaxAPRPercent = 50000; // 5%
        vm.prank(TEAM_MULTISIG);
        cappedRate.updateMaxAPRPercent(newMaxAPRPercent);
        (, , , , , , , uint256 maxAPRPercent_, , , ) = cappedRate.configData();
        assertEq(maxAPRPercent_, newMaxAPRPercent);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__InvalidParams));
        vm.prank(GOVERNANCE);
        cappedRate.updateMaxAPRPercent(type(uint24).max * uint256(101));

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__Unauthorized));
        cappedRate.updateMaxAPRPercent(newMaxAPRPercent);
    }

    function test_updateMaxDownFromMaxReachedPercentCol() public {
        uint256 newMaxDownPercent = 500000; // 50%
        vm.prank(TEAM_MULTISIG);
        cappedRate.updateMaxDownFromMaxReachedPercentCol(newMaxDownPercent);
        (, , , , , , , , uint24 maxDownFromMaxReachedPercentCol_, , ) = cappedRate.configData();
        assertEq(maxDownFromMaxReachedPercentCol_, newMaxDownPercent);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__InvalidParams));
        vm.prank(GOVERNANCE);
        cappedRate.updateMaxDownFromMaxReachedPercentCol(_SIX_DECIMALS + 1);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__Unauthorized));
        cappedRate.updateMaxDownFromMaxReachedPercentCol(newMaxDownPercent);
    }

    function test_updateMaxDownFromMaxReachedPercentDebt() public {
        uint256 newMaxDownPercent = 500000; // 50%
        vm.prank(TEAM_MULTISIG);
        cappedRate.updateMaxDownFromMaxReachedPercentDebt(newMaxDownPercent);
        (, , , , , , , , , uint24 maxDownFromMaxReachedPercentDebt_, ) = cappedRate.configData();
        assertEq(maxDownFromMaxReachedPercentDebt_, newMaxDownPercent);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__InvalidParams));
        vm.prank(GOVERNANCE);
        cappedRate.updateMaxDownFromMaxReachedPercentDebt(_SIX_DECIMALS + 1);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__Unauthorized));
        cappedRate.updateMaxDownFromMaxReachedPercentDebt(newMaxDownPercent);
    }

    function test_updateMaxDebtUpCapPercent() public {
        uint256 newMaxDebtUpCapPercent = 50_0000; // 50%
        vm.prank(TEAM_MULTISIG);
        cappedRate.updateMaxDebtUpCapPercent(newMaxDebtUpCapPercent);
        (, , , , , , , , , , uint256 maxDebtUpCapPercent_) = cappedRate.configData();
        assertEq(maxDebtUpCapPercent_, newMaxDebtUpCapPercent);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__InvalidParams));
        vm.prank(GOVERNANCE);
        cappedRate.updateMaxDebtUpCapPercent(type(uint16).max * uint256(101));

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__Unauthorized));
        cappedRate.updateMaxDebtUpCapPercent(newMaxDebtUpCapPercent);
    }

    function test_updateMinHeartbeat() public {
        uint256 newMinHeartbeat = 100000; // arbitrary value
        vm.prank(GOVERNANCE);
        cappedRate.updateMinHeartbeat(newMinHeartbeat);
        (, , uint24 minHeartbeat_, , , , , , , , ) = cappedRate.configData();
        assertEq(minHeartbeat_, newMinHeartbeat);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__InvalidParams));
        vm.prank(GOVERNANCE);
        cappedRate.updateMinHeartbeat(type(uint24).max + uint256(1));

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__InvalidParams));
        vm.prank(GOVERNANCE);
        cappedRate.updateMinHeartbeat(0);

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__Unauthorized));
        cappedRate.updateMinHeartbeat(newMinHeartbeat);
    }

    function test_updateMinUpdateDiffPercent() public {
        uint256 newMinUpdateDiffPercent = 5000; // 0.5%
        vm.prank(GOVERNANCE);
        cappedRate.updateMinUpdateDiffPercent(newMinUpdateDiffPercent);
        (, uint16 minUpdateDiffPercent_, , , , , , , , , ) = cappedRate.configData();
        assertEq(minUpdateDiffPercent_, newMinUpdateDiffPercent);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__InvalidParams));
        vm.prank(GOVERNANCE);
        cappedRate.updateMinUpdateDiffPercent(type(uint16).max + uint256(1));

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__InvalidParams));
        vm.prank(GOVERNANCE);
        cappedRate.updateMinUpdateDiffPercent(0);

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.CappedRate__Unauthorized));
        cappedRate.updateMinUpdateDiffPercent(newMinUpdateDiffPercent);
    }

    function test_ratesFetchDirectlyAfterHeartbeat() public {
        uint256 newRate = (WSTETH_RATE_START * 100_02) / 100_00;
        vm.warp(block.timestamp + 7 days + 1);
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        _assertAllRates(newRate * 1e9);

        _assertStorageSyncNeeded();
        assertEq(cappedRate.centerPrice(), newRate * 1e9);
    }

    function test_maxYieldCap() public {
        // case rate increases faster than maxAPR yield
        uint256 newRate = (WSTETH_RATE_START * 110) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.warp(block.timestamp + 3 days);
        // max yield increased rate in 3 days
        uint256 maxYieldRate = WSTETH_RATE_START +
            (((WSTETH_RATE_START * 3 days) / 365 days) * MAX_APR_PERCENT) /
            _SIX_DECIMALS;

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();

        (, uint256 maxReachedRate_, , , , , , , , ) = cappedRate.getRatesAndCaps();
        assertApproxEqRel(maxReachedRate_, maxYieldRate * 1e9, 1e12); // 0.0001% diff
    }

    function test_configPercentDiff() public {
        // checks min update diff when only max reached rate increases
        uint256 newRate = (WSTETH_RATE_START * 101) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        assertApproxEqAbs(cappedRate.configPercentDiff(), 1e4, 1);

        // rate is 10% per 365 days, so per 10 days increase is capped at 0,27397260%
        vm.warp(block.timestamp + 10 days);

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();

        assertApproxEqAbs(cappedRate.configPercentDiff(), 0, 1);
        (uint256 rate, uint256 maxReachedRate, , , , , , , , ) = cappedRate.getRatesAndCaps();

        // rate stays the same, but max rate still increases
        vm.warp(block.timestamp + 10 days);
        assertApproxEqAbs(cappedRate.configPercentDiff(), 2738, 1);

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();

        (uint256 rate2, uint256 maxReachedRate2, , , , , , , , ) = cappedRate.getRatesAndCaps();

        assertApproxEqAbs(cappedRate.configPercentDiff(), 0, 1);
        assertEq(rate, rate2);
        assertGt(maxReachedRate2, maxReachedRate);
    }

    function test_centerPrice() public {
        // for centerPrice -> no up cap, no down cap
        uint256 newRate = (WSTETH_RATE_START * 110) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.warp(block.timestamp + 3 days);
        // max yield increased rate in 3 days
        uint256 maxYieldRate = WSTETH_RATE_START +
            (((WSTETH_RATE_START * 3 days) / 365 days) * MAX_APR_PERCENT) /
            _SIX_DECIMALS;

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();

        (uint256 rate, uint256 maxReachedRate, , , , , , , , ) = cappedRate.getRatesAndCaps();
        assertEq(rate, newRate * 1e9);
        assertApproxEqRel(maxReachedRate, maxYieldRate * 1e9, 1e12); // 0.0001% diff

        // center price should have no up cap
        assertEq(rate, cappedRate.centerPrice());

        // decrease rate by 10x
        newRate = newRate / 10;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();
        (uint256 rate2, uint256 maxReachedRate2, , , , , , , , ) = cappedRate.getRatesAndCaps();
        assertEq(rate2, newRate * 1e9);
        assertEq(maxReachedRate, maxReachedRate2);

        // center price should have no down cap
        assertEq(rate2, cappedRate.centerPrice());
    }

    function test_getExchangeRate() public {
        // for exchangeRate -> no up cap, no down cap
        uint256 newRate = (WSTETH_RATE_START * 110) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.warp(block.timestamp + 3 days);
        // max yield increased rate in 3 days
        uint256 maxYieldRate = WSTETH_RATE_START +
            (((WSTETH_RATE_START * 3 days) / 365 days) * MAX_APR_PERCENT) /
            _SIX_DECIMALS;

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();

        (uint256 rate, uint256 maxReachedRate, , , , , , , , ) = cappedRate.getRatesAndCaps();
        assertEq(rate, newRate * 1e9);
        assertApproxEqRel(maxReachedRate, maxYieldRate * 1e9, 1e12); // 0.0001% diff

        // should have no up cap
        assertEq(rate, cappedRate.getExchangeRate());

        // decrease rate by 10x
        newRate = newRate / 10;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();
        (uint256 rate2, uint256 maxReachedRate2, , , , , , , , ) = cappedRate.getRatesAndCaps();

        // should have no down cap
        assertEq(rate2, cappedRate.getExchangeRate());
    }

    function test_getExchangeRateOperate() public {
        // for col -> up APR capped (avoid overpricing exploit), down no cap
        uint256 newRate = (WSTETH_RATE_START * 110) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.warp(block.timestamp + 3 days);
        // max yield increased rate in 3 days
        uint256 maxYieldRate = WSTETH_RATE_START +
            (((WSTETH_RATE_START * 3 days) / 365 days) * MAX_APR_PERCENT) /
            _SIX_DECIMALS;

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();

        (uint256 rate, uint256 maxReachedRate, , , , , , , , ) = cappedRate.getRatesAndCaps();
        assertEq(rate, newRate * 1e9);
        assertApproxEqRel(maxReachedRate, maxYieldRate * 1e9, 1e12); // 0.0001% diff

        // should have up cap
        assertEq(maxReachedRate, cappedRate.getExchangeRateOperate());

        // decrease rate by 10x
        newRate = newRate / 10;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();
        (uint256 rate2, uint256 maxReachedRate2, , , , , , , , ) = cappedRate.getRatesAndCaps();

        // should have no down cap
        assertEq(rate2, cappedRate.getExchangeRateOperate());

        // increase rate by 20x
        newRate = newRate * 20;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.warp(block.timestamp + 30 days);

        maxYieldRate = maxReachedRate + (((maxReachedRate * 30 days) / 365 days) * MAX_APR_PERCENT) / _SIX_DECIMALS;

        (rate, maxReachedRate, , , , , , , , ) = cappedRate.getRatesAndCaps();
        assertEq(rate, newRate * 1e9);
        assertApproxEqRel(maxReachedRate, maxYieldRate, 1e12); // 0.0001% diff

        // should have up cap
        assertEq(maxReachedRate, cappedRate.getExchangeRateOperate());
    }

    function test_getExchangeRateLiquidate() public {
        // for col -> up max APR cap, down capped (avoid forced liquidations attack)
        uint256 newRate = (WSTETH_RATE_START * 110) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.warp(block.timestamp + 3 days);
        // max yield increased rate in 3 days
        uint256 maxYieldRate = WSTETH_RATE_START +
            (((WSTETH_RATE_START * 3 days) / 365 days) * MAX_APR_PERCENT) /
            _SIX_DECIMALS;

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();

        (uint256 rate, uint256 maxReachedRate, , , , , , , , ) = cappedRate.getRatesAndCaps();
        assertEq(rate, newRate * 1e9);
        assertApproxEqRel(maxReachedRate, maxYieldRate * 1e9, 1e12); // 0.0001% diff

        // should have up cap
        assertEq(maxReachedRate, cappedRate.getExchangeRateLiquidate());

        // decrease rate by 10x
        newRate = newRate / 10;
        vm.warp(block.timestamp + 1 days);
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();
        (uint256 rate2, uint256 maxReachedRate2, , , , , , , , ) = cappedRate.getRatesAndCaps();

        // should have no down cap
        assertEq(rate2, cappedRate.getExchangeRateLiquidate());

        // switch flag to protect liquidations, down cap should become active
        vm.prank(TEAM_MULTISIG);
        cappedRate.updateAvoidForcedLiquidationsCol(true);
        assertNotEq(rate2, cappedRate.getExchangeRateLiquidate());

        uint256 downCappedRate = (maxReachedRate2 * (_SIX_DECIMALS - MAX_DOWN_PERCENT_COL)) / _SIX_DECIMALS;
        assertApproxEqRel(cappedRate.getExchangeRateLiquidate(), downCappedRate, 1e12); // 0.0001% diff

        newRate = ((maxReachedRate2 * 999) / 1000) / 1e9;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();

        // normal current rate should be higher than down capped rate
        assertEq(newRate * 1e9, cappedRate.getExchangeRateLiquidate());
    }

    function test_getExchangeRateOperateDebt() public {
        // for debt -> up no cap, down capped (avoid underpricing exploit)
        uint256 newRate = (WSTETH_RATE_START * 110) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.warp(block.timestamp + 3 days);
        // max yield increased rate in 3 days
        uint256 maxYieldRate = WSTETH_RATE_START +
            (((WSTETH_RATE_START * 3 days) / 365 days) * MAX_APR_PERCENT) /
            _SIX_DECIMALS;

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();

        (uint256 rate, uint256 maxReachedRate, , , , , , , , ) = cappedRate.getRatesAndCaps();
        assertEq(rate, newRate * 1e9);
        assertApproxEqRel(maxReachedRate, maxYieldRate * 1e9, 1e12); // 0.0001% diff

        // should have no up cap
        assertEq(rate, cappedRate.getExchangeRateOperateDebt());

        // decrease rate by 10x
        newRate = newRate / 10;
        vm.warp(block.timestamp + 1 days);
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();
        (uint256 rate2, uint256 maxReachedRate2, , , , , , , , ) = cappedRate.getRatesAndCaps();

        // should have down cap
        uint256 downCappedRate = (maxReachedRate2 * (_SIX_DECIMALS - MAX_DOWN_PERCENT_DEBT)) / _SIX_DECIMALS;
        assertApproxEqRel(cappedRate.getExchangeRateOperateDebt(), downCappedRate, 1e12); // 0.0001% diff
    }

    function test_getExchangeRateLiquidateDebt() public {
        // for debt -> up max APR capped (avoid forced liquidations attack), down capped
        uint256 newRate = (WSTETH_RATE_START * 110) / 100;
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.warp(block.timestamp + 3 days);
        // max yield increased rate in 3 days
        uint256 maxYieldRate = WSTETH_RATE_START +
            (((WSTETH_RATE_START * 3 days) / 365 days) * MAX_APR_PERCENT) /
            _SIX_DECIMALS;

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();

        (uint256 rate, uint256 maxReachedRate, , , , , , , , ) = cappedRate.getRatesAndCaps();
        assertEq(rate, newRate * 1e9);
        assertApproxEqRel(maxReachedRate, maxYieldRate * 1e9, 1e12); // 0.0001% diff

        // should have no up cap
        assertEq(rate, cappedRate.getExchangeRateLiquidateDebt());
        // switch flag to protect liquidations, up cap should become active
        vm.prank(TEAM_MULTISIG);
        cappedRate.updateAvoidForcedLiquidationsDebt(true);
        assertNotEq(rate, cappedRate.getExchangeRateLiquidateDebt());
        // up cap is at maxReachedRate + up to MAX_UP_CAP_PERCENT_DEBT which is 5% on top
        uint256 maxUpCappedRate = (maxReachedRate * 105) / 100;
        assertEq(maxUpCappedRate, cappedRate.getExchangeRateLiquidateDebt());
        (, , uint256 maxUpCappedRateFetched, , , , , , , ) = cappedRate.getRatesAndCaps();
        assertEq(maxUpCappedRate, maxUpCappedRateFetched);

        // decrease rate by 10x
        newRate = newRate / 10;
        vm.warp(block.timestamp + 1 days);
        vm.mockCall(WSTETH, abi.encodeWithSelector(IWstETH.stEthPerToken.selector), abi.encode(newRate));
        _assertStorageSyncNeeded();

        vm.prank(TEAM_MULTISIG);
        cappedRate.rebalance();
        (uint256 rate2, uint256 maxReachedRate2, , , , , , , , ) = cappedRate.getRatesAndCaps();

        // should have down cap
        uint256 downCappedRate = (maxReachedRate2 * (_SIX_DECIMALS - MAX_DOWN_PERCENT_DEBT)) / _SIX_DECIMALS;
        assertApproxEqRel(cappedRate.getExchangeRateLiquidateDebt(), downCappedRate, 1e12); // 0.0001% diff
    }
}
