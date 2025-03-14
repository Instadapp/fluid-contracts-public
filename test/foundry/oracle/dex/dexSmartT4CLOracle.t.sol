//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { DexSmartT4CLOracle } from "../../../../contracts/oracle/oracles/dex/dexSmartT4CLOracle.sol";
import { ErrorTypes } from "../../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../../contracts/oracle/error.sol";
import { IFluidOracle } from "../../../../contracts/oracle/fluidOracle.sol";

import { ChainlinkOracleImpl } from "../../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { ChainlinkStructs } from "../../../../contracts/oracle/implementations/structs.sol";
import { IChainlinkAggregatorV3 } from "../../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";

import { MockChainlinkFeed } from "../mocks/mockChainlinkFeed.sol";

import "forge-std/console2.sol";

contract DexSmartT4CLOracleTest is Test {
    uint8 public constant SAMPLE_TARGET_DECIMALS = 20; // sample target decimals - doesn't matter in test

    address internal constant DEX_USDC_ETH = 0x2886a01a0645390872a9eb99dAe1283664b0c524;
    address internal constant UniV3CheckCLRSOracle_ETH_USDC = 0x5b2860C6D6F888319C752aaCDaf8165C21095E3a;

    // USDC / ETH feed
    IChainlinkAggregatorV3 CHAINLINK_FEED = IChainlinkAggregatorV3(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);

    DexSmartT4CLOracle oracle;

    ChainlinkStructs.ChainlinkConstructorParams clParams;

    MockChainlinkFeed internal MOCK_CHAINLINK_FEED;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21148750);

        MOCK_CHAINLINK_FEED = new MockChainlinkFeed(CHAINLINK_FEED);

        clParams = ChainlinkStructs.ChainlinkConstructorParams({
            hops: 1,
            feed1: ChainlinkStructs.ChainlinkFeedData({
                feed: MOCK_CHAINLINK_FEED, // simulate USDC ETH feed
                invertRate: false,
                token0Decimals: 6
            }),
            feed2: ChainlinkStructs.ChainlinkFeedData({
                feed: IChainlinkAggregatorV3(address(0)),
                invertRate: false,
                token0Decimals: 0
            }),
            feed3: ChainlinkStructs.ChainlinkFeedData({
                feed: IChainlinkAggregatorV3(address(0)),
                invertRate: false,
                token0Decimals: 0
            })
        });

        // set 3030_860405935798293 USDC per ETH as price, CL oracle must always set token1/token0, so ETH per USDC.
        // ChainlinkOracleImpl scales to ETH / USDC scaled to 1e27, result is 329939312955999000000000000000000000.
        // adjust decimals to be in expected rate as used internally in Fluid Dex, e.g. 325151118254488344854528.
        // so set via multiplier & divisor to divide 1e12
        MOCK_CHAINLINK_FEED.setExchangeRate(int256(329939312955999));
    }

    function test_getExchangeRate_USDC_ETH_RealFeed() public {
        clParams = ChainlinkStructs.ChainlinkConstructorParams({
            hops: 1,
            feed1: ChainlinkStructs.ChainlinkFeedData({ feed: CHAINLINK_FEED, invertRate: false, token0Decimals: 6 }),
            feed2: ChainlinkStructs.ChainlinkFeedData({
                feed: IChainlinkAggregatorV3(address(0)),
                invertRate: false,
                token0Decimals: 0
            }),
            feed3: ChainlinkStructs.ChainlinkFeedData({
                feed: IChainlinkAggregatorV3(address(0)),
                invertRate: false,
                token0Decimals: 0
            })
        });

        oracle = new DexSmartT4CLOracle(
            DexSmartT4CLOracle.DexSmartT4CLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                clParams,
                1,
                1e12, // diff between USDC and ETH decimals
                1,
                1
            )
        );

        // see same expectation as in DexSmartDebtCLOracle test

        uint256 gasleft_ = gasleft();
        assertEq(oracle.getExchangeRateOperate(), 918006497562199283167547559);
        console2.log("gas used", gasleft_ - gasleft());
    }

    function test_getExchangeRate_USDC_ETH_Default() public {
        oracle = new DexSmartT4CLOracle(
            DexSmartT4CLOracle.DexSmartT4CLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                clParams,
                1,
                1e12,
                1,
                1
            )
        );

        // see same expectation as in DexSmartDebtCLOracle test

        assertEq(oracle.getExchangeRateOperate(), 919691649450893732530095536);
    }

    function test_getExchangeRate_USDC_ETH_IN_ETH() public {
        oracle = new DexSmartT4CLOracle(
            DexSmartT4CLOracle.DexSmartT4CLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                false, // quote in ETH (token1)
                clParams,
                1,
                1e12,
                1,
                1
            )
        );

        assertEq(oracle.getExchangeRateOperate(), 919691649780935419376364193);
    }

    function test_getExchangeRate_USDC_ETH_MatchInternalPricing() public {
        MOCK_CHAINLINK_FEED.setExchangeRate(int256(325151118254488));

        oracle = new DexSmartT4CLOracle(
            DexSmartT4CLOracle.DexSmartT4CLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                clParams,
                1,
                1e12,
                1,
                1
            )
        );

        assertEq(oracle.getExchangeRateOperate(), 911429551793383393607155936);
    }

    function test_getExchangeRate_USDC_ETH_DiffPricing() public {
        MOCK_CHAINLINK_FEED.setExchangeRate(int256(347118519848991));

        oracle = new DexSmartT4CLOracle(
            DexSmartT4CLOracle.DexSmartT4CLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                clParams,
                1,
                1e12,
                1,
                1
            )
        );
        assertEq(oracle.getExchangeRateOperate(), 901366609806133473329900096);
    }

    function test_getExchangeRate_USDC_ETH_OutsideRangeColAllToken0() public {
        MOCK_CHAINLINK_FEED.setExchangeRate(int256(248085991399605));

        oracle = new DexSmartT4CLOracle(
            DexSmartT4CLOracle.DexSmartT4CLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                clParams,
                1,
                1e12,
                1,
                1
            )
        );
        assertEq(oracle.getExchangeRateOperate(), 663115308039707664652093643);
    }

    function test_getExchangeRate_USDC_ETH_OutsideRangeColAllToken1() public {
        MOCK_CHAINLINK_FEED.setExchangeRate(int256(492402135113373));

        oracle = new DexSmartT4CLOracle(
            DexSmartT4CLOracle.DexSmartT4CLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                clParams,
                1,
                1e12,
                1,
                1
            )
        );
        assertEq(oracle.getExchangeRateOperate(), 571017358298320921919460625);
    }
}
