//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { BasicValidations } from "contracts/libraries/utils/basicValidations.sol";
import { LibsErrorTypes } from "contracts/libraries/errorTypes.sol";

import { Structs as ResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { IFluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidRatesAuth, Events } from "../../../contracts/config/ratesAuth/main.sol";
import { IFluidAuthGate, FluidAuthLevels } from "../../../contracts/config/authGate/interfaces/iAuthGate.sol";
import { Error } from "../../../contracts/config/error.sol";
import { ErrorTypes } from "../../../contracts/config/errorTypes.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";

error Access__Unauthorized();

contract RateAuthTest is Test, Events, FluidAuthLevels {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    address internal constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address internal constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;
    /// @dev team MS TimelockController (proposer = TEAM_MULTISIG), distinct from mainnet governance
    address internal constant TEAM_MULTISIG_TIMELOCK = 0x4d6CE4F4498d59Eed397bCbC687805a07f9b2346;

    address internal authGate;

    IFluidLiquidityResolver liquidityResolver;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    address bob = makeAddr("bob");

    FluidRatesAuth handler;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19876268);

        liquidityResolver = IFluidLiquidityResolver(address(new FluidLiquidityResolver(LIQUIDITY)));

        _deployNewHandler();
    }

    function test_deploy_revertOnInvalidParams() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidRatesAuth(address(0), authGate);
    }

    function test_constructor_RevertIfAuthGateForOtherLiquidity() public {
        address otherLiquidity_ = makeAddr("otherLiquidity");
        address otherAuthGate_ = deployCode(
            "contracts/config/authGate/main.sol:FluidAuthGate",
            abi.encode(otherLiquidity_, TEAM_MULTISIG, TEAM_MULTISIG2, TEAM_MULTISIG_TIMELOCK)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__InvalidParams));
        new FluidRatesAuth(address(LIQUIDITY), otherAuthGate_);
    }

    function test_deployment() public {
        assertEq(address(handler.LIQUIDITY()), address(LIQUIDITY));
        assertEq(handler.RATE_RELATIVE_MAX_DELTA(), 3000);
        assertEq(handler.COOLDOWN(), 1 days);
    }

    function test_authLevel_ladderIsFourDistinctRungs() public {
        IFluidAuthGate gate = IFluidAuthGate(authGate);

        assertEq(gate.governance(), GOVERNANCE);
        assertEq(gate.authLevel(GOVERNANCE), SECURITY_LEVEL_MAX);
        assertEq(gate.authLevel(TEAM_MULTISIG_TIMELOCK), SECURITY_LEVEL_CRITICAL);
        assertEq(gate.authLevel(TEAM_MULTISIG), SECURITY_LEVEL_HIGH);
        assertEq(gate.authLevel(TEAM_MULTISIG2), SECURITY_LEVEL_MID);
        assertEq(gate.authLevel(bob), 0);

        // the timelock must not shadow to governance, else the CRITICAL rung is never exercised
        assertTrue(TEAM_MULTISIG_TIMELOCK != GOVERNANCE);
        assertFalse(gate.isGovernance(TEAM_MULTISIG_TIMELOCK));
    }

    function _deployNewHandler() internal {
        authGate = deployCode(
            "contracts/config/authGate/main.sol:FluidAuthGate",
            abi.encode(address(LIQUIDITY), TEAM_MULTISIG, TEAM_MULTISIG2, TEAM_MULTISIG_TIMELOCK)
        );
        handler = new FluidRatesAuth(address(LIQUIDITY), authGate);

        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(handler), true);

        vm.prank(GOVERNANCE);
        LIQUIDITY.updateAuths(updateAuthsParams);
    }

    function _ethRateV2() internal view returns (AdminModuleStructs.RateDataV2Params memory) {
        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        return currentRateData.rateDataV2;
    }
}

contract FluidRateAuthTestsRateV2 is RateAuthTest {
    function test_checkRateValues() public {
        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        assertEq(currentRateData.version, 2);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink1, 1500);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink2, 2000);
    }

    function test_updateRateDataV2_revertWhenUnauthorized() public {
        AdminModuleStructs.RateDataV2Params memory rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationKink1 = 1600;
        rateStruct.rateAtUtilizationKink2 = 2200;

        vm.startPrank(bob);
        vm.expectRevert(Access__Unauthorized.selector);
        handler.updateRateDataV2(rateStruct);
    }

    function test_updateRateDataV2_revertWhenCalledWithExcessRateChange() public {
        AdminModuleStructs.RateDataV2Params memory rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationKink1 = 2300;
        rateStruct.rateAtUtilizationKink2 = 2200;

        vm.startPrank(TEAM_MULTISIG2);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV2(rateStruct);

        rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationKink1 = 740;
        rateStruct.rateAtUtilizationKink2 = 2200;

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV2(rateStruct);

        rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationKink1 = 1600;
        rateStruct.rateAtUtilizationKink2 = 3100;

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV2(rateStruct);

        rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationKink1 = 1600;
        rateStruct.rateAtUtilizationKink2 = 900;

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV2(rateStruct);
    }

    /// @dev kink moves are capped by absolute delta 1000 on the 10_000 = 100% utilization scale
    function test_updateRateDataV2_revertWhenKinkShiftExceedsAbsoluteCap() public {
        AdminModuleStructs.RateDataV2Params memory rateStruct = _ethRateV2();
        if (rateStruct.kink1 + 1001 < rateStruct.kink2) {
            rateStruct.kink1 = rateStruct.kink1 + 1001;
        } else {
            assertGt(rateStruct.kink2, 1001);
            rateStruct.kink2 = rateStruct.kink2 - 1001;
        }

        vm.startPrank(TEAM_MULTISIG2);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV2(rateStruct);
    }

    /// @dev calldata `0` for a non-`rateAtUtilizationZero` field means leave previous value
    function test_updateRateDataV2_zeroCalldataSkipsRateAtKink1() public {
        AdminModuleStructs.RateDataV2Params memory rateStruct = _ethRateV2();
        uint256 expectKink1Rate = rateStruct.rateAtUtilizationKink1;
        rateStruct.rateAtUtilizationKink1 = 0;
        rateStruct.rateAtUtilizationKink2 = 2100;

        vm.prank(TEAM_MULTISIG);
        handler.updateRateDataV2(rateStruct);

        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink1, expectKink1Rate);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink2, 2100);
    }

    function test_updateRateDataV2_revertIfCooldownNotPassed() public {
        AdminModuleStructs.RateDataV2Params memory rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationKink1 = 1600;
        rateStruct.rateAtUtilizationKink2 = 2200;

        vm.startPrank(TEAM_MULTISIG);
        handler.updateRateDataV2(rateStruct);

        rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationKink1 = 1700;
        rateStruct.rateAtUtilizationKink2 = 2300;

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__CooldownLeft));
        handler.updateRateDataV2(rateStruct);

        uint256 lastTimestamp = vm.getBlockTimestamp();
        vm.warp(lastTimestamp + 1 days + 1);
        rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationKink1 = 1700;
        rateStruct.rateAtUtilizationKink2 = 2300;
        handler.updateRateDataV2(rateStruct);
    }

    /// @dev a no-op would otherwise stamp the cooldown and lock the token for a day for everyone
    function test_updateRateDataV2_revertIfNoChange() public {
        vm.startPrank(TEAM_MULTISIG);

        // write a config this test knows exactly, so the replay below is a true no-op
        AdminModuleStructs.RateDataV2Params memory applied_ = _ethRateV2();
        applied_.rateAtUtilizationKink1 = 1600;
        handler.updateRateDataV2(applied_);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__NoChange));
        handler.updateRateDataV2(applied_);

        // the refused replay did not burn the cooldown
        applied_.rateAtUtilizationKink1 = 1700;
        handler.updateRateDataV2(applied_);
    }

    function test_updateRateDataV2() public {
        AdminModuleStructs.RateDataV2Params memory rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationKink1 = 1600;
        rateStruct.rateAtUtilizationKink2 = 2200;

        vm.prank(TEAM_MULTISIG);
        handler.updateRateDataV2(rateStruct);

        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink1, 1600);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink2, 2200);
    }

    /// @dev CRITICAL clears the MID gate on `onlyAuthLevelMid`
    function test_updateRateDataV2_teamMultisigTimelock() public {
        assertEq(IFluidAuthGate(authGate).authLevel(TEAM_MULTISIG_TIMELOCK), SECURITY_LEVEL_CRITICAL);

        AdminModuleStructs.RateDataV2Params memory rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationKink1 = 1600;

        vm.prank(TEAM_MULTISIG_TIMELOCK);
        handler.updateRateDataV2(rateStruct);

        assertEq(liquidityResolver.getTokenRateData(ETH).rateDataV2.rateAtUtilizationKink1, 1600);
    }

    function test_updateRateDataV2_rateAtUtilizationZero_revertBeyondCap() public {
        uint256 oldZero = liquidityResolver.getTokenRateData(ETH).rateDataV2.rateAtUtilizationZero;
        // allowed |Δ| = max(30% of old, 1% absolute)
        uint256 rel = (oldZero * handler.RATE_RELATIVE_MAX_DELTA()) / 1e4;
        uint256 maxDelta = rel > 100 ? rel : 100;

        AdminModuleStructs.RateDataV2Params memory rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationZero = oldZero + maxDelta + 1;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV2(rateStruct);
    }

    /// @dev Kink moves are capped at absolute 1000 on the 10_000 utilization scale — exact boundary succeeds.
    function test_updateRateDataV2_kink1_shift_exactAbsoluteCap_succeeds() public {
        AdminModuleStructs.RateDataV2Params memory rateStruct = _ethRateV2();
        uint256 oldK1 = rateStruct.kink1;
        uint256 oldK2 = rateStruct.kink2;
        assertGt(oldK2, oldK1 + 1000);
        rateStruct.kink1 = oldK1 + 1000;
        rateStruct.kink2 = 0;
        rateStruct.rateAtUtilizationKink1 = 0;
        rateStruct.rateAtUtilizationKink2 = 0;
        rateStruct.rateAtUtilizationMax = 0;

        vm.prank(TEAM_MULTISIG2);
        handler.updateRateDataV2(rateStruct);
        assertEq(liquidityResolver.getTokenRateData(ETH).rateDataV2.kink1, oldK1 + 1000);
        assertEq(liquidityResolver.getTokenRateData(ETH).rateDataV2.kink2, oldK2);
    }

    /// @dev rateAtUtilizationKink1: allowed |Δ| = max(30% relative, 100 absolute) — 1500 -> 1950 is exactly at relative cap.
    function test_updateRateDataV2_rateAtKink1_exactRelativeCap_succeeds() public {
        AdminModuleStructs.RateDataV2Params memory rateStruct = _ethRateV2();
        assertEq(rateStruct.rateAtUtilizationKink1, 1500);
        rateStruct.rateAtUtilizationKink1 = 1950;
        rateStruct.rateAtUtilizationKink2 = 0;
        rateStruct.rateAtUtilizationMax = 0;

        vm.prank(TEAM_MULTISIG2);
        handler.updateRateDataV2(rateStruct);
        assertEq(liquidityResolver.getTokenRateData(ETH).rateDataV2.rateAtUtilizationKink1, 1950);
    }

    function test_updateRateDataV2_rateAtKink1_oneOverRelativeCap_reverts() public {
        AdminModuleStructs.RateDataV2Params memory rateStruct = _ethRateV2();
        rateStruct.rateAtUtilizationKink1 = 1951;
        rateStruct.rateAtUtilizationKink2 = 0;
        rateStruct.rateAtUtilizationMax = 0;

        vm.startPrank(TEAM_MULTISIG2);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV2(rateStruct);
    }

    function test_updateRateDataV2_revertIfAllSentinelsNoChange() public {
        AdminModuleStructs.RateDataV2Params memory rateStruct_;
        rateStruct_.token = ETH;
        rateStruct_.rateAtUtilizationZero = _ethRateV2().rateAtUtilizationZero;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__NoChange));
        handler.updateRateDataV2(rateStruct_);
    }

    function test_updateRateDataV2_rateAtUtilizationZero_fromZeroOnlyAbsoluteCapApplies() public {
        AdminModuleStructs.RateDataV2Params[] memory params_ = new AdminModuleStructs.RateDataV2Params[](1);
        params_[0] = _ethRateV2();
        params_[0].rateAtUtilizationZero = 0;
        vm.prank(GOVERNANCE);
        LIQUIDITY.updateRateDataV2s(params_);

        AdminModuleStructs.RateDataV2Params memory rateStruct_ = _ethRateV2();
        rateStruct_.rateAtUtilizationZero = 101;
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV2(rateStruct_);

        rateStruct_.rateAtUtilizationZero = 100;
        vm.prank(TEAM_MULTISIG);
        handler.updateRateDataV2(rateStruct_);
        assertEq(_ethRateV2().rateAtUtilizationZero, 100);
    }
}

contract FluidRateAuthTestsRateV1 is RateAuthTest {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(GOVERNANCE);
        AdminModuleStructs.RateDataV1Params[] memory params = new AdminModuleStructs.RateDataV1Params[](1);
        params[0] = AdminModuleStructs.RateDataV1Params({
            token: ETH,
            kink: 7000,
            rateAtUtilizationZero: 400,
            rateAtUtilizationKink: 1000,
            rateAtUtilizationMax: 3000
        });
        LIQUIDITY.updateRateDataV1s(params);

        _deployNewHandler();
    }

    function test_checkRateValues() public {
        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        assertEq(currentRateData.version, 1);
        assertEq(currentRateData.rateDataV1.rateAtUtilizationKink, 1000);
    }

    function test_updateRateDataV1_revertWhenKinkAbsoluteDeltaExceeds1000() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.kink = 8200; // was 7000, +1200 > 1000

        vm.startPrank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV1(rateStruct);
        vm.stopPrank();
    }

    function test_updateRateDataV1_revertWhenUnauthorized() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.rateAtUtilizationKink = 1100;

        vm.startPrank(bob);
        vm.expectRevert(Access__Unauthorized.selector);
        handler.updateRateDataV1(rateStruct);
    }

    function test_updateRateDataV1_revertWhenCalledWithExcessRateChange() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.rateAtUtilizationKink = 1600;

        vm.startPrank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV1(rateStruct);

        rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.rateAtUtilizationKink = 400;

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV1(rateStruct);
    }

    function test_updateRateDataV1_revertIfCooldownNotPassed() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.rateAtUtilizationKink = 1100;

        vm.startPrank(TEAM_MULTISIG);
        handler.updateRateDataV1(rateStruct);

        rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.rateAtUtilizationKink = 1200;

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__CooldownLeft));
        handler.updateRateDataV1(rateStruct);

        uint256 lastTimestamp = vm.getBlockTimestamp();
        vm.warp(lastTimestamp + 1 days + 1);
        rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.rateAtUtilizationKink = 1200;
        handler.updateRateDataV1(rateStruct);
    }

    function test_updateRateDataV1() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.rateAtUtilizationKink = 900;

        vm.prank(TEAM_MULTISIG);
        handler.updateRateDataV1(rateStruct);

        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        assertEq(currentRateData.rateDataV1.rateAtUtilizationKink, 900);
    }

    function test_updateRateDataV1_zeroCalldataSkipsMaxRate() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        uint256 expectMax = rateStruct.rateAtUtilizationMax;
        rateStruct.rateAtUtilizationMax = 0;
        rateStruct.rateAtUtilizationKink = 1100;

        vm.prank(TEAM_MULTISIG);
        handler.updateRateDataV1(rateStruct);

        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        assertEq(currentRateData.rateDataV1.rateAtUtilizationMax, expectMax);
        assertEq(currentRateData.rateDataV1.rateAtUtilizationKink, 1100);
    }

    /// @dev rate at 0% util: old=400, max |Δ| = max(30% of 400, 100) = max(120,100) = 120; 400+120=520 allowed
    function test_updateRateDataV1_rateAtUtilizationZero_allowedWithinCap() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.rateAtUtilizationZero = 520;

        vm.prank(TEAM_MULTISIG);
        handler.updateRateDataV1(rateStruct);

        assertEq(liquidityResolver.getTokenRateData(ETH).rateDataV1.rateAtUtilizationZero, 520);
    }

    /// @dev old=400, maxDelta=120; 400+121=521 exceeds
    function test_updateRateDataV1_rateAtUtilizationZero_revertBeyondCap() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.rateAtUtilizationZero = 521;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV1(rateStruct);
    }

    /// @dev with old=150, 30% relative = 45 < 100 absolute floor, so floor applies: 150+101=251 exceeds
    function test_updateRateDataV1_rateAtUtilizationZero_usesOnePercentAbsoluteWhenBiggerThanThirtyPercentRel() public {
        vm.prank(GOVERNANCE);
        AdminModuleStructs.RateDataV1Params[] memory params = new AdminModuleStructs.RateDataV1Params[](1);
        params[0] = AdminModuleStructs.RateDataV1Params({
            token: ETH,
            kink: 7000,
            rateAtUtilizationZero: 150,
            rateAtUtilizationKink: 1000,
            rateAtUtilizationMax: 3000
        });
        LIQUIDITY.updateRateDataV1s(params);

        vm.warp(block.timestamp + 1 days + 1);

        // old=150: max(30% of 150, 100) = max(45, 100) = 100 → 150+100=250 allowed
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.rateAtUtilizationZero = 250;
        vm.prank(TEAM_MULTISIG);
        handler.updateRateDataV1(rateStruct);
        assertEq(liquidityResolver.getTokenRateData(ETH).rateDataV1.rateAtUtilizationZero, 250);

        vm.warp(block.timestamp + 1 days + 1);
        rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        // old=250: max(30% of 250, 100) = max(75, 100) = 100 → 250+101=351 exceeds (test uses 376 > 100)
        rateStruct.rateAtUtilizationZero = 376;
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV1(rateStruct);
    }

    function test_updateRateDataV1_kink_exactAbsoluteCap_succeeds() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        assertEq(rateStruct.kink, 7000);
        rateStruct.kink = 8000;
        vm.prank(TEAM_MULTISIG);
        handler.updateRateDataV1(rateStruct);
        assertEq(liquidityResolver.getTokenRateData(ETH).rateDataV1.kink, 8000);
    }

    function test_updateRateDataV1_kink_oneOverAbsoluteCap_reverts() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.kink = 8001; // +1001 from default 7000
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV1(rateStruct);
    }

    /// @dev rateAtUtilizationKink 1000 -> 1300: |Δ|=300, relative 30% exactly on boundary.
    function test_updateRateDataV1_rateAtUtilizationKink_exactRelativeCap_succeeds() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        assertEq(rateStruct.rateAtUtilizationKink, 1000);
        rateStruct.rateAtUtilizationKink = 1300;
        vm.prank(TEAM_MULTISIG);
        handler.updateRateDataV1(rateStruct);
        assertEq(liquidityResolver.getTokenRateData(ETH).rateDataV1.rateAtUtilizationKink, 1300);
    }

    function test_updateRateDataV1_rateAtUtilizationKink_oneOverRelativeCap_reverts() public {
        AdminModuleStructs.RateDataV1Params memory rateStruct = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        rateStruct.rateAtUtilizationKink = 1301;
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__AllowedDeltaExceeded)
        );
        handler.updateRateDataV1(rateStruct);
    }

    function test_updateRateDataV1_revertIfNoChange() public {
        AdminModuleStructs.RateDataV1Params memory applied_ = liquidityResolver.getTokenRateData(ETH).rateDataV1;
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__NoChange));
        handler.updateRateDataV1(applied_);

        applied_.rateAtUtilizationKink = 1100;
        vm.prank(TEAM_MULTISIG);
        handler.updateRateDataV1(applied_);
    }
}
