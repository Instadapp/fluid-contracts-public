//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { LiquidityUserModuleBaseTest } from "../liquidity/userModule/liquidityUserModuleBaseTest.t.sol";
import { Structs as ResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { IFluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidBufferRateHandler, Events } from "../../../contracts/config/bufferRateHandler/main.sol";
import { BigMathMinified } from "../../../contracts/libraries/bigMathMinified.sol";
import { Error } from "../../../contracts/config/error.sol";
import { ErrorTypes } from "../../../contracts/config/errorTypes.sol";
import { IFluidReserveContract } from "../../../contracts/reserve/interfaces/iReserveContract.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";

abstract contract FluidBufferRateBaseTest is Test, Events {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidReserveContract internal constant RESERVE_CONTRACT =
        IFluidReserveContract(0x264786EF916af64a1DB19F513F24a3681734ce92);

    IFluidLiquidityResolver liquidityResolver;

    address internal constant REBALANCER = 0x3BE5C671b20649DCA5D916b5698328D54BdAAf88;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    address bob = makeAddr("bob");

    FluidBufferRateHandler handler;

    int256 rateBufferKink1 = 400; // +4%
    int256 rateBufferKink2 = -200; // -2%

    uint256 minUpdateDiff = 100; // 1%

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19876268);

        liquidityResolver = IFluidLiquidityResolver(address(new FluidLiquidityResolver(LIQUIDITY)));

        _deployNewHandler();
    }

    function test_deployment() public {
        assertEq(address(handler.LIQUIDITY()), address(LIQUIDITY));
        assertEq(address(handler.RESERVE_CONTRACT()), address(RESERVE_CONTRACT));
        assertEq(address(handler.SUPPLY_TOKEN()), WSTETH);
        assertEq(address(handler.BORROW_TOKEN()), ETH);
        assertEq(handler.RATE_BUFFER_KINK1(), rateBufferKink1);
        assertEq(handler.RATE_BUFFER_KINK2(), rateBufferKink2);
        assertEq(handler.MIN_UPDATE_DIFF(), minUpdateDiff);
    }

    function test_rebalance_RevertWhenUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.BufferRateConfigHandler__Unauthorized)
        );
        vm.prank(bob);
        handler.rebalance();
    }

    function _deployNewHandler() internal {
        // constructor params
        // IFluidReserveContract reserveContract_,
        // IFluidLiquidity liquidity_,
        // address supplyToken_,
        // address borrowToken_,
        // int256 rateBufferKink1_,
        // int256 rateBufferKink2_,
        // uint256 minUpdateDiff_
        handler = new FluidBufferRateHandler(
            RESERVE_CONTRACT,
            LIQUIDITY,
            WSTETH,
            ETH,
            rateBufferKink1,
            rateBufferKink2,
            minUpdateDiff
        );

        // authorize handler at liquidity
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(handler), true);

        vm.prank(GOVERNANCE);
        LIQUIDITY.updateAuths(updateAuthsParams);
    }
}

contract FluidBufferRateTestsRateV2 is FluidBufferRateBaseTest {
    function test_supplyTokenLendingRate() public {
        assertEq(handler.supplyTokenLendingRate(), 1027);

        ResolverStructs.OverallTokenData memory overallTokenData = liquidityResolver.getOverallTokenData(WSTETH);
        assertEq(overallTokenData.supplyRate, 1027);
    }

    function test_calcBorrowRates() public {
        // supply rate at test block is 1027
        // at kink1, rate should be 1027 + 4% = 1427
        // at kink2, rate should be 1027 - 2% = 827
        (uint256 newRateKink1, uint256 newRateKink2) = handler.calcBorrowRates();
        assertEq(newRateKink1, 1427);
        assertEq(newRateKink2, 827);
    }

    function test_configPercentDiff() public {
        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        assertEq(currentRateData.version, 2);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink1, 1500);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink2, 2000);

        // supply rate at test block is 1027
        // at kink1, rate should be 1027 + 4% = 1427
        // at kink2, rate should be 1027 - 2% = 827

        // percent diff at kink1 is: 1500 - 1427 = 73. 73 * 1e4 / 1500 = 486. so 4.86%
        // percent diff at kink2 is: 2000 - 827 = 1173. 1173 * 1e4 / 2000 = 5865. so 58.65%
        assertEq(handler.configPercentDiff(), 5865);
    }

    function test_rebalance() public {
        rateBufferKink1 = 200; // +2%
        rateBufferKink2 = 400; // +4%
        _deployNewHandler();

        ResolverStructs.RateData memory rateDataBefore = liquidityResolver.getTokenRateData(ETH);

        // uint256 supplyRate,
        // uint256 oldRateKink1,
        // uint256 newRateKink1,
        // uint256 oldRateKink2,
        // uint256 newRateKink2
        vm.expectEmit(true, true, true, true);
        emit LogUpdateRate(1027, 1500, 1227, 2000, 1427);

        vm.prank(REBALANCER);
        handler.rebalance();

        ResolverStructs.RateData memory rateDataAfter = liquidityResolver.getTokenRateData(ETH);
        // assert new rates at kinks are set
        assertEq(rateDataAfter.rateDataV2.rateAtUtilizationKink1, 1227);
        assertEq(rateDataAfter.rateDataV2.rateAtUtilizationKink2, 1427);
        // assert all other values are same as before
        assertEq(rateDataAfter.version, 2);
        assertEq(rateDataAfter.rateDataV2.kink1, rateDataBefore.rateDataV2.kink1);
        assertEq(rateDataAfter.rateDataV2.kink2, rateDataBefore.rateDataV2.kink2);
        assertEq(rateDataAfter.rateDataV2.rateAtUtilizationZero, rateDataBefore.rateDataV2.rateAtUtilizationZero);
        assertEq(rateDataAfter.rateDataV2.rateAtUtilizationMax, rateDataBefore.rateDataV2.rateAtUtilizationMax);

        // should revert when no update needed
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.BufferRateConfigHandler__NoUpdate)
        );
        vm.prank(REBALANCER);
        handler.rebalance();
    }

    function test_rebalance_BelowZeroRateCap() public {
        rateBufferKink1 = -2000; // -20%
        rateBufferKink2 = 400; // +4%
        _deployNewHandler();

        vm.prank(REBALANCER);
        handler.rebalance();

        ResolverStructs.RateData memory rateDataAfter = liquidityResolver.getTokenRateData(ETH);
        // assert new rates at kinks are set
        assertEq(rateDataAfter.rateDataV2.rateAtUtilizationKink1, 0);
        assertEq(rateDataAfter.rateDataV2.rateAtUtilizationKink2, 1427);
    }

    function test_rebalance_lastKinkRateCapAtMaxUtilizationRate() public {
        // update rate data at Liquidity
        ResolverStructs.RateData memory rateData = liquidityResolver.getTokenRateData(ETH);
        rateData.rateDataV2.token = ETH;
        rateData.rateDataV2.rateAtUtilizationKink1 = 100; // 1%;
        rateData.rateDataV2.rateAtUtilizationKink2 = 200; // 2%
        rateData.rateDataV2.rateAtUtilizationMax = 1500; // 15%
        vm.prank(GOVERNANCE);
        AdminModuleStructs.RateDataV2Params[] memory params = new AdminModuleStructs.RateDataV2Params[](1);
        params[0] = rateData.rateDataV2;
        LIQUIDITY.updateRateDataV2s(params);

        rateBufferKink1 = 2000; // +20%
        rateBufferKink2 = 10000; // +100%
        _deployNewHandler();

        vm.prank(REBALANCER);
        handler.rebalance();

        ResolverStructs.RateData memory rateDataAfter = liquidityResolver.getTokenRateData(ETH);
        // assert new rates at kinks are set
        assertEq(rateDataAfter.rateDataV2.rateAtUtilizationKink1, 1500); // capped at max rate 15%
        assertEq(rateDataAfter.rateDataV2.rateAtUtilizationKink2, 1500); // capped at max rate 15%
    }
}

contract FluidBufferRateTestsRateV1 is FluidBufferRateBaseTest {
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

        rateBufferKink1 = 800; // 8%
        rateBufferKink2 = 0;
        _deployNewHandler();
    }

    function test_calcBorrowRates() public {
        // supply rate at test block is 1027
        // at kink1, rate should be 1027 + 8% = 1827
        (uint256 newRateKink1, uint256 newRateKink2) = handler.calcBorrowRates();
        assertEq(newRateKink1, 1827);
        assertEq(newRateKink2, 0);
    }

    function test_configPercentDiff() public {
        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(ETH);
        assertEq(currentRateData.version, 1);
        assertEq(currentRateData.rateDataV1.rateAtUtilizationKink, 1000);

        // supply rate at test block is 1027
        // at kink1, rate should be 1027 + 8% = 1827

        // percent diff at kink1 is: 1827 - 1000 = 827. 827 * 1e4 / 1000 = 8270. so 82.7%
        assertEq(handler.configPercentDiff(), 8270);
    }

    function test_rebalance() public {
        ResolverStructs.RateData memory rateDataBefore = liquidityResolver.getTokenRateData(ETH);

        // uint256 supplyRate,
        // uint256 oldRateKink1,
        // uint256 newRateKink1,
        // uint256 oldRateKink2,
        // uint256 newRateKink2
        vm.expectEmit(true, true, true, true);
        emit LogUpdateRate(1027, 1000, 1827, 0, 0);

        vm.prank(REBALANCER);
        handler.rebalance();

        ResolverStructs.RateData memory rateDataAfter = liquidityResolver.getTokenRateData(ETH);
        // assert new rates at kinks are set
        assertEq(rateDataAfter.rateDataV1.rateAtUtilizationKink, 1827);
        // assert all other values are same as before
        assertEq(rateDataAfter.version, 1);
        assertEq(rateDataAfter.rateDataV1.kink, rateDataBefore.rateDataV1.kink);
        assertEq(rateDataAfter.rateDataV1.rateAtUtilizationZero, rateDataBefore.rateDataV1.rateAtUtilizationZero);
        assertEq(rateDataAfter.rateDataV1.rateAtUtilizationMax, rateDataBefore.rateDataV1.rateAtUtilizationMax);

        // should revert when no update needed
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.BufferRateConfigHandler__NoUpdate)
        );
        vm.prank(REBALANCER);
        handler.rebalance();
    }

    function test_rebalance_BelowZeroRateCap() public {
        // update borrow token rate data to v1 at Liquidity
        vm.prank(GOVERNANCE);
        AdminModuleStructs.RateDataV1Params[] memory params = new AdminModuleStructs.RateDataV1Params[](1);
        params[0] = AdminModuleStructs.RateDataV1Params({
            token: ETH,
            kink: 7000,
            rateAtUtilizationZero: 0,
            rateAtUtilizationKink: 800,
            rateAtUtilizationMax: 1500
        });
        LIQUIDITY.updateRateDataV1s(params);

        rateBufferKink1 = -2000; // -20%
        _deployNewHandler();

        vm.prank(REBALANCER);
        handler.rebalance();

        ResolverStructs.RateData memory rateDataAfter = liquidityResolver.getTokenRateData(ETH);
        assertEq(rateDataAfter.rateDataV1.rateAtUtilizationKink, 0);
    }

    function test_rebalance_lastKinkRateCapAtMaxUtilizationRate() public {
        // update rate data at Liquidity
        vm.prank(GOVERNANCE);
        AdminModuleStructs.RateDataV1Params[] memory params = new AdminModuleStructs.RateDataV1Params[](1);
        params[0] = AdminModuleStructs.RateDataV1Params({
            token: ETH,
            kink: 7000,
            rateAtUtilizationZero: 0,
            rateAtUtilizationKink: 800,
            rateAtUtilizationMax: 1200
        });
        LIQUIDITY.updateRateDataV1s(params);

        vm.prank(REBALANCER);
        handler.rebalance();

        ResolverStructs.RateData memory rateDataAfter = liquidityResolver.getTokenRateData(ETH);
        // assert new rates at kinks are set
        assertEq(rateDataAfter.rateDataV1.rateAtUtilizationKink, 1200); // capped at max rate 12%
    }
}
