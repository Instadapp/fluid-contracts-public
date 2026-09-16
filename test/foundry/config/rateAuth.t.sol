//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { LiquidityUserModuleBaseTest } from "../liquidity/userModule/liquidityUserModuleBaseTest.t.sol";
import { Structs as ResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { IFluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidRatesAuth, Events, Constants, Structs } from "../../../contracts/config/ratesAuth/main.sol";
import { BigMathMinified } from "../../../contracts/libraries/bigMathMinified.sol";
import { Error } from "../../../contracts/config/error.sol";
import { ErrorTypes } from "../../../contracts/config/errorTypes.sol";
import { IFluidReserveContract } from "../../../contracts/reserve/interfaces/iReserveContract.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";

contract RateAuthTest is Test, Events {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidReserveContract internal constant RESERVE_CONTRACT =
        IFluidReserveContract(0x264786EF916af64a1DB19F513F24a3681734ce92);

    IFluidLiquidityResolver liquidityResolver;

    address internal constant REBALANCER = 0x3BE5C671b20649DCA5D916b5698328D54BdAAf88;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    address bob = makeAddr("bob");

    FluidRatesAuth handler;

    uint256 percentRateChangeAllowed = 1500; // 15%
    uint256 cooldown = 1 days;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19876268);

        liquidityResolver = IFluidLiquidityResolver(address(new FluidLiquidityResolver(LIQUIDITY)));

        _deployNewHandler();
    }

    function test_deploy_revertOnInvalidParams() public {
        // revert if cooldown is zero
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__InvalidParams));
        new FluidRatesAuth(address(LIQUIDITY), 1500, 0);

        // revert if percentRateChangeAllowed is zero
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__InvalidParams));
        new FluidRatesAuth(address(LIQUIDITY), 0, 1 days);

        // revert if percentRateChangeAllowed is more than 100%
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__InvalidParams));
        new FluidRatesAuth(address(LIQUIDITY), 10200, 1 days); // 10200 > 10000
    }

    function test_deployment() public {
        assertEq(address(handler.LIQUIDITY()), address(LIQUIDITY));
        assertEq(handler.PERCENT_RATE_CHANGE_ALLOWED(), percentRateChangeAllowed);
        assertEq(handler.COOLDOWN(), cooldown);
    }

    function _deployNewHandler() internal {
        // constructor params
        // uint256 percentRateChangeAllowed_,
        // uint256 cooldown_
        handler = new FluidRatesAuth(address(LIQUIDITY), percentRateChangeAllowed, cooldown);

        // authorize handler at liquidity
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(handler), true);

        vm.prank(GOVERNANCE);
        LIQUIDITY.updateAuths(updateAuthsParams);
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
        // ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);

        // setting up the rateStruct with valid params(under max rate change allowed)
        FluidRatesAuth.RateAtKinkV2 memory rateStruct;
        rateStruct.token = ETH;
        rateStruct.rateAtUtilizationKink1 = 1300; // 1200 > 1500 - 15%(1500) = 1275
        rateStruct.rateAtUtilizationKink2 = 2400; // 2200 < 2000 + 15%(2000) = 2300

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__Unauthorized));
        handler.updateRateDataV2(rateStruct);
    }

    function test_updateRateDataV2_revertWhenCalledWithExcessRateChange() public {
        // ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);

        // setting up the rateStruct with excess rate change at kink1 (positive direction)
        FluidRatesAuth.RateAtKinkV2 memory rateStruct;
        rateStruct.token = ETH;
        rateStruct.rateAtUtilizationKink1 = 1800; // 1800 > 1500 + 15%(1500) = 1725 (out of bound)
        rateStruct.rateAtUtilizationKink2 = 2200; // 2200 < 2000 + 15%(2000) = 2300

        vm.startPrank(handler.TEAM_MULTISIG2());
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__NoUpdate));
        handler.updateRateDataV2(rateStruct);

        // setting up the rateStruct with excess rate change at kink1 (negative direction)
        rateStruct.rateAtUtilizationKink1 = 1200; // 1200 < 1500 - 15%(1500) = 1275 (out of bound)

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__NoUpdate));
        handler.updateRateDataV2(rateStruct);

        // setting up the rateStruct with excess rate change at kink2 (positive direction)
        rateStruct.rateAtUtilizationKink1 = 1200; // 1700 < 1500 + 15%(1500) = 1725
        rateStruct.rateAtUtilizationKink2 = 2400; // 2400 > 2000 + 15%(2000) = 2300 (out of bound)

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__NoUpdate));
        handler.updateRateDataV2(rateStruct);

        // setting up the rateStruct with excess rate change at kink2 (negative direction)
        rateStruct.rateAtUtilizationKink2 = 1600; // 1600 < 2000 - 15%(2000) = 1700 (out of bound)

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__NoUpdate));
        handler.updateRateDataV2(rateStruct);
    }

    function test_updateRateDataV2_revertIfCooldownNotPassed() public {
        // setting up the rateStruct with valid params(under max rate change allowed)
        FluidRatesAuth.RateAtKinkV2 memory rateStruct;
        rateStruct.token = ETH;
        rateStruct.rateAtUtilizationKink1 = 1600; // 1600 < 1500 + 15%(1500) = 1725
        rateStruct.rateAtUtilizationKink2 = 2200; // 2200 < 2000 + 15%(2000) = 2300

        vm.startPrank(handler.TEAM_MULTISIG());
        handler.updateRateDataV2(rateStruct);

        // try to update rate data before cooldown period
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__CooldownLeft));
        rateStruct.rateAtUtilizationKink1 = 1700; // 1700 < 1600 + 15%(1600) = 1840
        rateStruct.rateAtUtilizationKink2 = 2300; // 2300 < 2200 + 15%(2200) = 2530
        handler.updateRateDataV2(rateStruct);

        // try to update rate data after cooldown period
        uint256 lastTimestamp = vm.getBlockTimestamp();
        vm.warp(lastTimestamp + 1 days + 1); // 10000 blocks passed (more than a day(cooldown period))
        rateStruct.rateAtUtilizationKink1 = 1700; // 1700 < 1600 + 15%(1600) = 1840
        rateStruct.rateAtUtilizationKink2 = 2300; // 2300 < 2200 + 15%(2200) = 2530
        handler.updateRateDataV2(rateStruct);
    }

    function test_updateRateDataV2() public {
        // setting up the rateStruct with valid params(under max rate change allowed)
        FluidRatesAuth.RateAtKinkV2 memory rateStruct;
        rateStruct.token = ETH;
        rateStruct.rateAtUtilizationKink1 = 1600; // 1600 < 1500 + 15%(1500) = 1725
        rateStruct.rateAtUtilizationKink2 = 2200; // 2200 < 2000 + 15%(2000) = 2300

        vm.prank(handler.TEAM_MULTISIG());
        handler.updateRateDataV2(rateStruct);

        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink1, 1600);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink2, 2200);
    }
}

contract FluidRateAuthTestsRateV1 is RateAuthTest {
    function setUp() public virtual override {
        super.setUp();

        // update borrow token rate data to v1 at Liquidity
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

        percentRateChangeAllowed = 1500;

        _deployNewHandler();
    }

    function test_checkRateValues() public {
        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        assertEq(currentRateData.version, 1);
        assertEq(currentRateData.rateDataV1.rateAtUtilizationKink, 1000);
    }

    function test_updateRateDataV1_revertWhenUnauthorized() public {
        // setting up the rateStruct with valid params(under max rate change allowed)
        FluidRatesAuth.RateAtKinkV1 memory rateStruct;
        rateStruct.token = ETH;
        rateStruct.rateAtUtilizationKink = 1100; // 1100 < 1000 + 15%(1000) = 1150

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__Unauthorized));
        handler.updateRateDataV1(rateStruct);
    }

    function test_updateRateDataV1_revertWhenCalledWithExcessRateChange() public {
        // setting up the rateStruct with excess rate change in positive direction
        FluidRatesAuth.RateAtKinkV1 memory rateStruct;
        rateStruct.token = ETH;
        rateStruct.rateAtUtilizationKink = 1200; // 1200 > 1000 + 15%(1000) = 1150

        vm.startPrank(handler.TEAM_MULTISIG());
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__NoUpdate));
        handler.updateRateDataV1(rateStruct);

        // setting up the rateStruct with excess rate change in negative direction
        rateStruct.rateAtUtilizationKink = 800; // 800 < 1000 - 15%(1000) = 850

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__NoUpdate));
        handler.updateRateDataV1(rateStruct);
    }

    function test_updateRateDataV1_revertIfCooldownNotPassed() public {
        // setting up the rateStruct with valid params(under max rate change allowed)
        FluidRatesAuth.RateAtKinkV1 memory rateStruct;
        rateStruct.token = ETH;
        rateStruct.rateAtUtilizationKink = 1100; // 1100 < 1000 + 15%(1000) = 1150

        vm.startPrank(handler.TEAM_MULTISIG());
        handler.updateRateDataV1(rateStruct);

        // try to update rate data before cooldown period
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RatesAuth__CooldownLeft));
        rateStruct.rateAtUtilizationKink = 1200; // 1200 < 1100 + 15%(1100) = 1265
        handler.updateRateDataV1(rateStruct);

        // try to update rate data after cooldown period
        uint256 lastTimestamp = vm.getBlockTimestamp();
        vm.warp(lastTimestamp + 1 days + 1);
        rateStruct.rateAtUtilizationKink = 1200; // 1200 < 1100 + 15%(1100) = 1265
        handler.updateRateDataV1(rateStruct);
    }

    function test_updateRateDataV1() public {
        // setting up the rateStruct with excess rate change
        FluidRatesAuth.RateAtKinkV1 memory rateStruct;
        rateStruct.token = ETH;
        rateStruct.rateAtUtilizationKink = 900; // 900 > 1000 - 15%(1000) = 850

        vm.prank(handler.TEAM_MULTISIG());
        handler.updateRateDataV1(rateStruct);

        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        assertEq(currentRateData.rateDataV1.rateAtUtilizationKink, 900);
    }
}
