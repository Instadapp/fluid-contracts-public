//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { PendleOracle } from "../../../contracts/oracle/oracles/pendleOracle.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";
import { IPendleMarketV3 } from "../../../contracts/oracle/interfaces/external/IPendleMarketV3.sol";
import { IPendlePYLpOracle } from "../../../contracts/oracle/interfaces/external/IPendlePYLpOracle.sol";
import { IFluidOracle } from "../../../contracts/oracle/fluidOracle.sol";

import { OracleTestSuite } from "./oracleTestSuite.t.sol";

import "forge-std/console2.sol";

contract PendleOracleTest is OracleTestSuite {
    IPendleMarketV3 internal constant PENDLE_MARKET = IPendleMarketV3(0xd1D7D99764f8a52Aff007b7831cc02748b2013b5);

    IPendlePYLpOracle internal constant PENDLE_PYLP_ORACLE =
        IPendlePYLpOracle(0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2);

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 20118615);

        // PENDLE_MARKET.increaseObservationsCardinalityNext(150); // 150 blocks = 1800 seconds
        // vm.roll(block.number + 151);

        // create PendleOracle. constructor:
        // IPendlePYLpOracle pendleOracle_,
        // IPendleMarketV3 pendleMarket_,
        // uint32 twapDuration_,
        // uint256 maxExpectedBorrowRate_,
        // uint256 minYieldRate_,
        // uint256 maxYieldRate_
        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            75 * 1e2, // 75%
            6 // test with a debt token with 6 decimals, e.g. USDC
        );
    }

    function test_constructor_InvalidPendleOracle() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidParams)
        );

        oracle = new PendleOracle(
            infoName,
            IPendlePYLpOracle(address(0)),
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            75 * 1e2, // 75%
            6 // test with a debt token with 6 decimals, e.g. USDC
        );
    }

    function test_constructor_InvalidPendleMarket() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidParams)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            IPendleMarketV3(address(0)),
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            75 * 1e2, // 75%
            6 // test with a debt token with 6 decimals, e.g. USDC
        );
    }

    function test_constructor_InvalidTWAPDuration() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidParams)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            0,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            75 * 1e2, // 75%
            6 // test with a debt token with 6 decimals, e.g. USDC
        );
    }

    function test_constructor_InvalidMaxBorrowRate() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidParams)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            0,
            4 * 1e2, // 4%
            75 * 1e2, // 75%
            6 // test with a debt token with 6 decimals, e.g. USDC
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidParams)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            300 * 1e2 + 1,
            4 * 1e2, // 4%
            75 * 1e2, // 75%
            6 // test with a debt token with 6 decimals, e.g. USDC
        );
    }

    function test_constructor_InvalidMinYieldRate() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidParams)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            0,
            75 * 1e2, // 75%
            6 // test with a debt token with 6 decimals, e.g. USDC
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidParams)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            100 * 1e2 + 1,
            75 * 1e2, // 75%
            6 // test with a debt token with 6 decimals, e.g. USDC
        );

        // min yield rate > max yield rate
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidParams)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            99 * 1e2, // 99%
            75 * 1e2, // 75%
            6 // test with a debt token with 6 decimals, e.g. USDC
        );
    }

    function test_constructor_InvalidMaxYieldRate() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidParams)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            0,
            6 // test with a debt token with 6 decimals, e.g. USDC
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidParams)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            300 * 1e2 + 1,
            6 // test with a debt token with 6 decimals, e.g. USDC
        );
    }

    function test_constructor_InvalidDebtTokenDecimals() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidParams)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            75 * 1e2,
            5
        );
    }

    function test_constructor_InvalidPendleMarketDecimals() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__MarketInvalidDecimals)
        );

        vm.mockCall(address(PENDLE_MARKET), abi.encodeWithSelector(PENDLE_MARKET.decimals.selector), abi.encode(17));

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            75 * 1e2,
            6
        );
    }

    function test_constructor_InvalidPendleOracleState() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__MarketNotInitialized)
        );

        vm.mockCall(
            address(PENDLE_PYLP_ORACLE),
            abi.encodeWithSelector(PENDLE_PYLP_ORACLE.getOracleState.selector),
            abi.encode(true, 0, true)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            75 * 1e2,
            6
        );

        vm.clearMockedCalls();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__MarketNotInitialized)
        );

        vm.mockCall(
            address(PENDLE_PYLP_ORACLE),
            abi.encodeWithSelector(PENDLE_PYLP_ORACLE.getOracleState.selector),
            abi.encode(false, 0, false)
        );

        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            75 * 1e2,
            6
        );
    }

    function test_pendleOracleData() public {
        (
            IPendlePYLpOracle pendleOracle_,
            IPendleMarketV3 pendleMarket_,
            uint256 expiry_,
            uint32 twapDuration_,
            uint256 maxExpectedBorrowRate_,
            uint256 minYieldRate_,
            uint256 maxYieldRate_,
            uint8 debtTokenDecimals_,
            uint256 exchangeRateOperate_,
            uint256 exchangeRateLiquidate_,
            uint256 ptToAssetRateTWAP_
        ) = PendleOracle(address(oracle)).pendleOracleData();

        assertEq(address(pendleOracle_), address(PENDLE_PYLP_ORACLE));
        assertEq(address(pendleMarket_), address(PENDLE_MARKET));
        assertEq(expiry_, 1727308800);
        assertEq(twapDuration_, 15 minutes);
        assertEq(maxExpectedBorrowRate_, 50 * 1e2);
        assertEq(minYieldRate_, 4 * 1e2);
        assertEq(maxYieldRate_, 75 * 1e2);
        assertEq(debtTokenDecimals_, 6);
        assertEq(exchangeRateOperate_, 880065155407224);
        assertEq(exchangeRateLiquidate_, 1e15);
        assertEq(ptToAssetRateTWAP_, 931693352351794835);
    }

    function test_getExchangeRate() public {
        assertEq(oracle.getExchangeRateOperate(), oracle.getExchangeRate());
    }

    function test_getExchangeRateLiquidate_6DebtDecimals() public {
        assertEq(oracle.getExchangeRateLiquidate(), 1e15);
    }

    function test_getExchangeRateLiquidate_18DebtDecimals() public {
        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            75 * 1e2,
            18
        );

        assertEq(oracle.getExchangeRateLiquidate(), 1e27);
    }

    function test_getExchangeRateLiquidate_AfterMaturity() public {
        vm.warp(PENDLE_MARKET.expiry());
        assertEq(oracle.getExchangeRateLiquidate(), 1e15);
        vm.warp(PENDLE_MARKET.expiry() + 1);
        assertEq(oracle.getExchangeRateLiquidate(), 1e15);
        vm.warp(PENDLE_MARKET.expiry() + 100000);
        assertEq(oracle.getExchangeRateLiquidate(), 1e15);
    }

    function test_getExchangeRateOperate_6DebtDecimals() public {
        vm.warp(PENDLE_MARKET.expiry() - 365 days / 10);
        // at 10% of a year to maturity, and given a max borrow rate of 50%,
        // it should be x * 1.05 = 1 -> ~1 / 1.05 = 0,95238095238095238095238095238

        assertEq(oracle.getExchangeRateOperate(), 952380952380952);
    }

    function test_getExchangeRateOperate_18DebtDecimals() public {
        oracle = new PendleOracle(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            75 * 1e2,
            18
        );

        vm.warp(PENDLE_MARKET.expiry() - 365 days / 10);
        // at 10% of a year to maturity, and given a max borrow rate of 50%,
        // it should be x * 1.05 = 1 -> ~1 / 1.05 = 0,95238095238095238095238095238

        assertEq(oracle.getExchangeRateOperate(), 952380952380952380952380952);
    }

    function test_getExchangeRateOperate_AfterMaturity() public {
        vm.warp(PENDLE_MARKET.expiry());
        assertEq(oracle.getExchangeRateOperate(), 1e15);
        vm.warp(PENDLE_MARKET.expiry() + 1);
        assertEq(oracle.getExchangeRateOperate(), 1e15);
        vm.warp(PENDLE_MARKET.expiry() + 100000);
        assertEq(oracle.getExchangeRateOperate(), 1e15);
    }

    function test_getExchangeRateOperate_RevertPriceBiggerThan1e18() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidPrice));

        vm.mockCall(
            address(PENDLE_PYLP_ORACLE),
            abi.encodeWithSelector(PENDLE_PYLP_ORACLE.getPtToAssetRate.selector),
            abi.encode(1e18 + 1)
        );

        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertPriceBelowMaxYield() public {
        // min expected price at time 830275664039362585715848972
        // tests to confirm calculate priceAtRateToMaturity() below separately

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidPrice));

        vm.mockCall(
            address(PENDLE_PYLP_ORACLE),
            abi.encodeWithSelector(PENDLE_PYLP_ORACLE.getPtToAssetRate.selector),
            abi.encode(830275664039362584)
        );

        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertPriceAboveMinYield() public {
        // max expected price at time 989215219092206051713989106
        // tests to confirm calculate priceAtRateToMaturity() below separately

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.PendleOracle__InvalidPrice));

        vm.mockCall(
            address(PENDLE_PYLP_ORACLE),
            abi.encodeWithSelector(PENDLE_PYLP_ORACLE.getPtToAssetRate.selector),
            abi.encode(989215219092206052)
        );

        oracle.getExchangeRateOperate();
    }
}

contract PendleOracleHarness is PendleOracle {
    constructor(
        string memory infoName_,
        IPendlePYLpOracle pendleOracle_,
        IPendleMarketV3 pendleMarket_,
        uint32 twapDuration_,
        uint256 maxExpectedBorrowRate_,
        uint256 minYieldRate_,
        uint256 maxYieldRate_,
        uint8 debtTokenDecimals_
    )
        PendleOracle(
            infoName_,
            pendleOracle_,
            pendleMarket_,
            twapDuration_,
            maxExpectedBorrowRate_,
            minYieldRate_,
            maxYieldRate_,
            debtTokenDecimals_
        )
    {}

    function exposed_priceAtRateToMaturity(
        uint256 yearlyRatePercent_,
        uint256 timeToMaturity_
    ) external pure returns (uint256 price_) {
        return _priceAtRateToMaturity(yearlyRatePercent_, timeToMaturity_);
    }
}

contract PendleOracleTestPriceAtRateToMaturity is Test {
    PendleOracleHarness oracle;

    string internal constant infoName = "SomeName / SomeToken";

    IPendleMarketV3 internal constant PENDLE_MARKET = IPendleMarketV3(0xd1D7D99764f8a52Aff007b7831cc02748b2013b5);

    IPendlePYLpOracle internal constant PENDLE_PYLP_ORACLE =
        IPendlePYLpOracle(0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 20118615);

        oracle = new PendleOracleHarness(
            infoName,
            PENDLE_PYLP_ORACLE,
            PENDLE_MARKET,
            15 minutes,
            50 * 1e2, // 50%
            4 * 1e2, // 4%
            75 * 1e2, // 75%
            6 // test with a debt token with 6 decimals, e.g. USDC
        );
    }

    function test_priceAtRateToMaturity() public {
        uint256 maxBorrowRate = 50 * 1e2; // 50%
        uint256 timeToMaturity = 365 days / 5;

        // at 20% of a year to maturity, and given a max borrow rate of 50%,
        // it should be x * 1.10 = 1 -> ~1 / 1.10 = 0,95238095238095238095238095238
        assertEq(oracle.exposed_priceAtRateToMaturity(maxBorrowRate, timeToMaturity), 909090909090909090909090909);

        timeToMaturity = 365 days * 2;
        // at 200% of a year to maturity, and given a max borrow rate of 50%,
        // it should be x * 2 = 1 -> ~1 / 2 = 0,50000000000000000000000000000000000
        assertEq(oracle.exposed_priceAtRateToMaturity(maxBorrowRate, timeToMaturity), 500000000000000000000000000);

        maxBorrowRate = 1 * 1e2; // 1%
        timeToMaturity = 365 days / 365; // 86400
        // at 1 day to maturity, and given a max yearly borrow rate of 1%,
        // in 1 day the rate is 0,00273972602739726027397260274% so
        // it should be x * 1.0000273972602739726027397260274 = 1 -> ~1 / 1.0000273972602739726027397260274 = 0,9999726034903153338264431118982085336
        // minor diff because of precision loss
        assertEq(oracle.exposed_priceAtRateToMaturity(maxBorrowRate, timeToMaturity), 999972603490315333829210083);
    }

    function testFuzz_priceAtRateToMaturity(uint256 rate, uint32 timeToMaturity) public {
        vm.assume(rate > 0);
        vm.assume(rate <= 300 * 1e2);

        uint256 result = oracle.exposed_priceAtRateToMaturity(rate, timeToMaturity);

        // result should never be 0 or > 1e27
        assertLt(result, 1e27 + 1);
        assertGt(result, 0);
    }
}
