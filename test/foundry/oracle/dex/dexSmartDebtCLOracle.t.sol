//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { DexSmartColCLOracle } from "../../../../contracts/oracle/oracles/dex/dexSmartColCLOracle.sol";
import { DexSmartDebtCLOracle } from "../../../../contracts/oracle/oracles/dex/dexSmartDebtCLOracle.sol";
import { ErrorTypes } from "../../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../../contracts/oracle/error.sol";
import { IFluidOracle } from "../../../../contracts/oracle/fluidOracle.sol";

import { ChainlinkOracleImpl } from "../../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { ChainlinkStructs } from "../../../../contracts/oracle/implementations/structs.sol";
import { IChainlinkAggregatorV3 } from "../../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";

import { MockChainlinkFeed } from "../mocks/mockChainlinkFeed.sol";

import "forge-std/console2.sol";

contract DexSmartDebtCLOracleTest is Test {
    uint8 public constant SAMPLE_TARGET_DECIMALS = 20; // sample target decimals - doesn't matter in test

    address internal constant DEX_USDC_ETH = 0x2886a01a0645390872a9eb99dAe1283664b0c524;
    address internal constant UniV3CheckCLRSOracle_ETH_USDC = 0x5b2860C6D6F888319C752aaCDaf8165C21095E3a;

    // USDC / ETH feed
    IChainlinkAggregatorV3 CHAINLINK_FEED = IChainlinkAggregatorV3(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);

    DexSmartDebtCLOracle oracle;

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

    function test_getExchangeRate_USDC() public {
        oracle = new DexSmartDebtCLOracle(
            DexSmartDebtCLOracle.DexSmartDebtCLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                IFluidOracle(address(0)),
                false,
                clParams,
                1,
                1e12,
                1,
                1
            )
        );

        (uint256 chainlinkExchangeRate, , , , , , , , , ) = oracle.chainlinkOracleData();
        console2.log("Chainlink Exchange Rate:", chainlinkExchangeRate);
        assertEq(chainlinkExchangeRate, 329939312955999000000000000000000000);

        // "token0RealReserves": "66_719549",
        // "token1RealReserves": "0_052423385833000000",

        // new col reserves at this price
        // got newDebtReserves_ token0Reserves_ 134_442661779238
        // got newDebtReserves_ token1Reserves_   0_026029189432

        // got combined reserves 224_793373 USDC

        // = ~134.44$ + 0.02603 ETH * 3030.86 $ / ETH = ~224.8$
        // @ totalBorrowShares 100e18
        // so ~2.248$ per share, inverted -> it should be ~0.44484e27 debt shares per 1 USDC

        (uint256 operateRate, uint256 liquidateRate) = oracle.dexSmartDebtSharesRates();
        console2.log("Operate shares Rate:", operateRate);
        console2.log("Liquidate shares Rate:", liquidateRate);

        assertEq(oracle.getExchangeRateOperate(), 444852971711047727372283345);
    }

    function test_getExchangeRate_ETH() public {
        oracle = new DexSmartDebtCLOracle(
            DexSmartDebtCLOracle.DexSmartDebtCLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                false, // quote in ETH (token1)
                IFluidOracle(address(0)),
                false,
                clParams,
                1,
                1e12,
                1,
                1
            )
        );

        (uint256 chainlinkExchangeRate, , , , , , , , , ) = oracle.chainlinkOracleData();
        console2.log("Chainlink Exchange Rate:", chainlinkExchangeRate);
        assertEq(chainlinkExchangeRate, 329939312955999000000000000000000000);

        // got combined reserves 0_074168171339000000 ETH

        // = ~0_074168171339000000 ETH * 3030.86 $ / ETH = ~224.8$
        // @ totalBorrowShares 100e18
        // so ~2.248$ per share, inverted -> it should be ~0.44484e27 debt shares per 1$
        // so 0.44484e27 * 3030.86 = ~1348_247762400000000000000000000 debt shares per 1 ETH

        assertEq(oracle.getExchangeRateOperate(), 1348287253071544951657851470922);
    }
}

contract DexSmartDebtCLCombinedOracleTest is Test {
    uint8 public constant SAMPLE_TARGET_DECIMALS = 20; // sample target decimals - doesn't matter in test

    address internal constant DEX_USDC_ETH = 0x2886a01a0645390872a9eb99dAe1283664b0c524;
    address internal constant UniV3CheckCLRSOracle_ETH_USDC = 0x5b2860C6D6F888319C752aaCDaf8165C21095E3a;

    // USDC / ETH feed
    IChainlinkAggregatorV3 CHAINLINK_FEED = IChainlinkAggregatorV3(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);

    DexSmartDebtCLOracle oracle;

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

    function test_getExchangeRate_CombinedSmartCol_DefaultState() public {
        //  USDC / ETH Dex amounts at block 21148750:
        //   "totalBorrowShares": "100000000000000000000",
        //   "totalSupplyShares": "100000000000000000000"
        //   "poolReserves_": {
        //     "pool": "0x2886a01a0645390872a9eb99dae1283664b0c524",
        //     "token0": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        //     "token1": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        //     "fee": "500",
        //     "collateralReserves": {
        //       "token0RealReserves": "145091098000000",
        //       "token1RealReserves": "20376157484",
        //       "token0ImaginaryReserves": "2032850239216709",
        //       "token1ImaginaryReserves": "660984405916"
        //     },
        //     "debtReserves": {
        //       "token0Debt": "66719549000000",
        //       "token1Debt": "52423385833",
        //       "token0RealReserves": "149720381080886",
        //       "token1RealReserves": "21025181551",
        //       "token0ImaginaryReserves": "2097679753435509",
        //       "token1ImaginaryReserves": "682062288559"
        //     },
        //     "balanceToken0": "7099430886666",
        //     "balanceToken1": "9553938075658850756061"
        //   }

        DexSmartColCLOracle smartColOracle = new DexSmartColCLOracle(
            DexSmartColCLOracle.DexSmartColCLOracleParams(
                "USDC per 1 USDC/ETH col share",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                IFluidOracle(address(0)),
                false,
                clParams,
                1,
                1e12,
                1,
                1e12
            )
        );
        assertEq(smartColOracle.getExchangeRateOperate(), 2067405880000000);

        oracle = new DexSmartDebtCLOracle(
            DexSmartDebtCLOracle.DexSmartDebtCLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                IFluidOracle(address(smartColOracle)),
                false,
                clParams,
                1,
                1e12,
                1e12,
                1
            )
        );

        // "token0Debt": "66719549000000", ~66.72$
        // "token1Debt": "52423385833", ~158.88$
        // sum should be ~225.6$

        // new debt reserves at this price
        // got newDebtReserves_ token0Debt 83228885467063
        // got newDebtReserves_ token1Debt 46707690050

        // total debt reserves = 46707690050 * 1e6 * 3030860405935798293 / 1e27 + 83228885467063 / 1e6 = 224793373
        // 224793373 USDC / 100000000000000000000 shares = 2247933 USDC / SHARE
        // scaled to 1e27 -> 2247933730000000

        // so there should be < 1 debt shares needed per col share
        // ~ 206740588 / 224793373 = 0,919691649450893732530095538

        // so 1e54 / 2247933730000000 * 2067405880000000 / 1e27 = 919691649450893732530095538

        assertEq(oracle.getExchangeRateOperate(), 919691649450893732530095536);
    }

    function test_getExchangeRate_CombinedSmartCol_MatchInternalPricing() public {
        //       "centerPrice": "339348508210503532675072", // scaled 3393485082105035326
        //       "lastStoredPrice": "325151118254488344854528", // 1e54 / x = 325151118254488344854528
        // so x = x≈3075493036494258240657324033916, scaled = x ≈ 3075493036494258240

        // set 3075_493036494258240 USDC per ETH as price, CL oracle must always set token1/token0, so ETH per USDC.
        // ChainlinkOracleImpl scales to ETH / USDC scaled to 1e27, result is 329939312955999000000000000000000000.
        // adjust decimals to be in expected rate as used internally in Fluid Dex, e.g. 325151118254488344854528.
        // so set via multiplier & divisor to divide 1e12.
        // 1e54/3075493036494258240/1e21 = 325151118254488
        MOCK_CHAINLINK_FEED.setExchangeRate(int256(325151118254488));

        DexSmartColCLOracle smartColOracle = new DexSmartColCLOracle(
            DexSmartColCLOracle.DexSmartColCLOracleParams(
                "USDC per 1 USDC/ETH col share",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                IFluidOracle(address(0)),
                false,
                clParams,
                1,
                1e12,
                1,
                1e12
            )
        );

        //  total col reserves =
        // combine reserves into token0 (USDC), scaled to token decimals and multiplied by external oracle price
        // token1Reserves * 1e6 * 1e54 / 325151118254488344854528 / 1e12 / 1e27 + token0Reserves / 1e6
        // 20376157484 * 1e6 * (1e54 / 325151118254488344854528 / 1e12) / 1e27 + 145091098000000 / 1e6 = 207757828
        assertEq(smartColOracle.getExchangeRateOperate(), 2077578280000000);

        oracle = new DexSmartDebtCLOracle(
            DexSmartDebtCLOracle.DexSmartDebtCLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                IFluidOracle(address(smartColOracle)),
                false,
                clParams,
                1,
                1e12,
                1e12,
                1
            )
        );

        // total debt reserves = 52423385833 * 1e6 * 3075493036494258240 / 1e27 + 66719549000000 / 1e6 = 227947307
        // so 1e54 / 2279473070000000 * 2077578280000000 / 1e27 = 911429183938549447307135767

        // result here slightly different as new reserves are slightly different (used actual in manual calculation here)

        assertEq(oracle.getExchangeRateOperate(), 911429551793383393607155936);
    }

    function test_getExchangeRate_CombinedSmartCol_DiffPricing() public {
        // mock external oracle price to be 2880860405935798293 USDC per ETH
        // 1e54/2880860405935798293/1e21 = 347118519848991
        MOCK_CHAINLINK_FEED.setExchangeRate(int256(347118519848991));

        // new col reserves at this price
        // ├─ [0] console::log("got newCollateralReserves_ token0Reserves_", 79716693035328 [7.971e13]) [staticcall]
        // ├─ [0] console::log("got newCollateralReserves_ token1Reserves_", 42339050992 [4.233e10]) [staticcall]

        DexSmartColCLOracle smartColOracle = new DexSmartColCLOracle(
            DexSmartColCLOracle.DexSmartColCLOracleParams(
                "USDC per 1 USDC/ETH col share",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                IFluidOracle(address(0)),
                false,
                clParams,
                1,
                1e12,
                1,
                1e12
            )
        );

        // total col reserves = 42339050992 * 1e6 * 2880860405935798293 / 1e27 + 79716693035328 / 1e6 = 201689588

        assertEq(smartColOracle.getExchangeRateOperate(), 2016895880000000);

        // new debt reserves at this price
        // │   ├─ [0] console::log("got newDebtReserves_ token0Debt", 143561858297223 [1.435e14]) [staticcall]
        // │   ├─ [0] console::log("got newDebtReserves_ token1Debt", 27838181587 [2.783e10]) [staticcall]

        oracle = new DexSmartDebtCLOracle(
            DexSmartDebtCLOracle.DexSmartDebtCLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                IFluidOracle(address(smartColOracle)),
                false,
                clParams,
                1,
                1e12,
                1e12,
                1
            )
        );

        // total debt reserves = 27838181587 * 1e6 * 2880860405935798293 / 1e27 + 143561858297223 / 1e6 = 223759773
        // so 1e54 / 2237597730000000 * 2016895880000000 / 1e27 = 901366609806133473329900097

        assertEq(oracle.getExchangeRateOperate(), 901366609806133473329900096);
    }

    function test_getExchangeRate_CombinedSmartCol_OutsideRangeColAllToken0() public {
        // mock external oracle price to be 4030860405935798293 USDC per ETH
        // 1e54/4030860405935798293/1e21 = 248085991399605
        MOCK_CHAINLINK_FEED.setExchangeRate(int256(248085991399605));

        // new col reserves at this price
        // got newCollateralReserves_ token0Reserves_ 209751015690809
        // got newCollateralReserves_ token1Reserves_ 0

        DexSmartColCLOracle smartColOracle = new DexSmartColCLOracle(
            DexSmartColCLOracle.DexSmartColCLOracleParams(
                "USDC per 1 USDC/ETH col share",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                IFluidOracle(address(0)),
                false,
                clParams,
                1,
                1e12,
                1,
                1e12
            )
        );

        // total col reserves = 0 * 1e6 * 4030860405935798293 / 1e27 + 209751015690809 / 1e6 = 209751015

        assertEq(smartColOracle.getExchangeRateOperate(), 2097510150000000);

        // new debt reserves at this price
        // got newDebtReserves_ token0Debt 0
        // got newDebtReserves_ token1Debt 78472458542

        oracle = new DexSmartDebtCLOracle(
            DexSmartDebtCLOracle.DexSmartDebtCLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                IFluidOracle(address(smartColOracle)),
                false,
                clParams,
                1,
                1e12,
                1e12,
                1
            )
        );

        // total debt reserves = 78472458542 * 1e6 * 4030860405935798293 / 1e27 + 0 / 1e6 = 316311526
        // so 1e54 / 3163115260000000 * 2097510150000000 / 1e27 = 663115308039707664652093645

        // as price of ETH increased, debt share value should increase as it has more ETH than supply share

        assertEq(oracle.getExchangeRateOperate(), 663115308039707664652093643);
    }

    function test_getExchangeRate_CombinedSmartCol_OutsideRangeColAllToken1() public {
        // mock external oracle price to be 2030860405935798293 USDC per ETH
        // 1e54/2030860405935798293/1e21 = 492402135113373
        MOCK_CHAINLINK_FEED.setExchangeRate(int256(492402135113373));

        // new col reserves at this price
        // got newCollateralReserves_ token0Reserves_ 0
        // got newCollateralReserves_ token1Reserves_ 71178694270

        DexSmartColCLOracle smartColOracle = new DexSmartColCLOracle(
            DexSmartColCLOracle.DexSmartColCLOracleParams(
                "USDC per 1 USDC/ETH col share",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                IFluidOracle(address(0)),
                false,
                clParams,
                1,
                1e12,
                1,
                1e12
            )
        );

        // total col reserves = 71178694270 * 1e6 * 2030860405935798293 / 1e27 + 0 / 1e6 = 144553991

        assertEq(smartColOracle.getExchangeRateOperate(), 1445539910000000);

        // new debt reserves at this price
        // got newDebtReserves_ token0Debt 253151658198662
        // got newDebtReserves_ token1Debt 0

        oracle = new DexSmartDebtCLOracle(
            DexSmartDebtCLOracle.DexSmartDebtCLOracleParams(
                "USDC/ETH debt sh. per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in USDC (token0)
                IFluidOracle(address(smartColOracle)),
                false,
                clParams,
                1,
                1e12,
                1e12,
                1
            )
        );

        // total debt reserves = 0 * 1e6 * 2030860405935798293 / 1e27 + 253151658198662 / 1e6 = 253151658
        // so 1e54 / 2531516580000000 * 1445539910000000 / 1e27 = 571017358298320921919460626

        // value of col should be ~ 144553991/253151658 ~ 0.57

        assertEq(oracle.getExchangeRateOperate(), 571017358298320921919460625);
    }
}

// // DEX entire data at that block:
// // {
// //   "data_": {
// //     "colReserves": {
// //       "token0ImaginaryReserves": "2032850239",
// //       "token0RealReserves": "145091098",
// //       "token1ImaginaryReserves": "660984405916000000",
// //       "token1RealReserves": "20376157484000000"
// //     },
// //     "configs": {
// //       "centerPriceAddress": "0x0000000000000000000000000000000000000000",
// //       "fee": "500",
// //       "hookAddress": "0x0000000000000000000000000000000000000000",
// //       "isSmartCollateralEnabled": true,
// //       "isSmartDebtEnabled": true,
// //       "lowerRange": "100000",
// //       "lowerShiftThreshold": "500",
// //       "maxBorrowShares": "340282366920938463463374607431768211455",
// //       "maxCenterPrice": "500000031135565524286570496",
// //       "maxSupplyShares": "340282366920938463463374607431768211455",
// //       "minCenterPrice": "499999763729834049536",
// //       "revenueCut": "0",
// //       "shiftingTime": "10800",
// //       "upperRange": "100000",
// //       "upperShiftThreshold": "500",
// //       "utilizationLimitToken0": "1000",
// //       "utilizationLimitToken1": "1000"
// //     },
// //     "constantViews": {
// //       "borrowToken0Slot": "0x764dbe9e8685866a5a91d0015b16c53a58d13b39327fccd3f5bea24d51fed158",
// //       "borrowToken1Slot": "0x98a1c91ce75047f1f4622fecdc1f30e6d9646c84b99e457d62a8096b0f8b45b0",
// //       "deployerContract": "0x4ec7b668baf70d4a4b0fc7941a7708a07b6d45be",
// //       "dexId": "5",
// //       "exchangePriceToken0Slot": "0xa8e1248eddf82e10c0adc6c737b6d8da17674abf51801ea5a4549f41c2dfdf21",
// //       "exchangePriceToken1Slot": "0xa1829a9003092132f585b6ccdd167c19fe9774dbdea4260287e8a8e8ca8185d7",
// //       "factory": "0x91716c4eda1fb55e84bf8b4c7085f84285c19085",
// //       "implementations": {
// //         "admin": "0x331d549d23b408eefaa12b44365c7c0c3a81d46e",
// //         "colOperations": "0x4697eb7c234469ace7eae4c1c5d5ad08c8104bdc",
// //         "debtOperations": "0x05fed1069a92ed377e1521050b7954bfa8fa7b00",
// //         "perfectOperationsAndOracle": "0x45316860c990de706a87ca25106ea45ffd10b146",
// //         "shift": "0xf9eaabaf2f706abeb83fff9f33b6fddbf027efae"
// //       },
// //       "liquidity": "0x52aa899454998be5b000ad077a46bbe360f4e497",
// //       "oracleMapping": "1024",
// //       "supplyToken0Slot": "0x8e44a2662876df089e34290b64db5ecf0e76caff5e6add48d9b14f0d4846971e",
// //       "supplyToken1Slot": "0xff7da29f5cd718ff61fd9f57337f6eca66938c79889347f303b245aa6b6df97f",
// //       "token0": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
// //       "token1": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
// //     },
// //     "constantViews2": {
// //       "token0DenominatorPrecision": "1",
// //       "token0NumeratorPrecision": "1000000",
// //       "token1DenominatorPrecision": "1000000",
// //       "token1NumeratorPrecision": "1"
// //     },
// //     "debtReserves": {
// //       "token0Debt": "66719549",
// //       "token0ImaginaryReserves": "2097679753",
// //       "token0RealReserves": "149720381",
// //       "token1Debt": "52423385833000000",
// //       "token1ImaginaryReserves": "682062288559000000",
// //       "token1RealReserves": "21025181551000000"
// //     },
// //     "dex": "0x2886a01a0645390872a9eb99dae1283664b0c524",
// //     "dexState": {
// //       "centerPrice": "617271340591",
// //       "isSwapAndArbitragePaused": false,
// //       "lastPricesTimeDiff": "60",
// //       "lastStoredPrice": "591446438703",
// //       "lastToLastStoredPrice": "606964639023",
// //       "lastUpdateTimestamp": "1731135887",
// //       "oracleCheckPoint": "7",
// //       "oracleMapping": "0",
// //       "shifts": {
// //         "centerPriceShift": {
// //           "duration": "0",
// //           "shiftPercentage": "0",
// //           "startTimestamp": "0"
// //         },
// //         "isCenterPriceShiftActive": false,
// //         "isRangeChangeActive": false,
// //         "isThresholdChangeActive": false,
// //         "rangeShift": {
// //           "duration": "0",
// //           "oldLower": "0",
// //           "oldTime": "0",
// //           "oldUpper": "0",
// //           "startTimestamp": "0"
// //         },
// //         "thresholdShift": {
// //           "duration": "0",
// //           "oldLower": "0",
// //           "oldTime": "0",
// //           "oldUpper": "0",
// //           "startTimestamp": "0"
// //         }
// //       },
// //       "token0PerBorrowShare": "667195",
// //       "token0PerSupplyShare": "1450910",
// //       "token1PerBorrowShare": "524233858330000",
// //       "token1PerSupplyShare": "203761574840000",
// //       "totalBorrowShares": "100000000000000000000",
// //       "totalSupplyShares": "100000000000000000000"
// //     },
// //     "limitsAndAvailability": {
// //       "borrowableUntilUtilizationLimitToken0": "7053657207338",
// //       "borrowableUntilUtilizationLimitToken1": "9544352053714676494384",
// //       "liquidityBorrowToken0": "94862401408236",
// //       "liquidityBorrowToken1": "42057192093949154815057",
// //       "liquidityBorrowableToken0": "39893735056",
// //       "liquidityBorrowableToken1": "15932119368254541883",
// //       "liquiditySupplyToken0": "101916058615574",
// //       "liquiditySupplyToken1": "51601544147663831309441",
// //       "liquidityTokenData0": {
// //         "borrowExchangePrice": "1082649409910",
// //         "borrowInterestFree": "0",
// //         "borrowRate": "767",
// //         "borrowRawInterest": "87620609719006",
// //         "fee": "1000",
// //         "lastStoredUtilization": "9307",
// //         "lastUpdateTimestamp": "1731138083",
// //         "maxUtilization": "10000",
// //         "rateData": {
// //           "rateDataV1": {
// //             "kink": "9300",
// //             "rateAtUtilizationKink": "750",
// //             "rateAtUtilizationMax": "2500",
// //             "rateAtUtilizationZero": "0",
// //             "token": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
// //           },
// //           "rateDataV2": {
// //             "kink1": "0",
// //             "kink2": "0",
// //             "rateAtUtilizationKink1": "0",
// //             "rateAtUtilizationKink2": "0",
// //             "rateAtUtilizationMax": "0",
// //             "rateAtUtilizationZero": "0",
// //             "token": "0x0000000000000000000000000000000000000000"
// //           },
// //           "version": "1"
// //         },
// //         "revenue": "45773679328",
// //         "storageUpdateThreshold": "30",
// //         "supplyExchangePrice": "1063393896172",
// //         "supplyInterestFree": "0",
// //         "supplyRate": "642",
// //         "supplyRawInterest": "95840364499412",
// //         "totalBorrow": "94862401408236",
// //         "totalSupply": "101916058615574"
// //       },
// //       "liquidityTokenData1": {
// //         "borrowExchangePrice": "1052574579104",
// //         "borrowInterestFree": "0",
// //         "borrowRate": "269",
// //         "borrowRawInterest": "39956496127571478446080",
// //         "fee": "1000",
// //         "lastStoredUtilization": "8160",
// //         "lastUpdateTimestamp": "1731117539",
// //         "maxUtilization": "10000",
// //         "rateData": {
// //           "rateDataV1": {
// //             "kink": "0",
// //             "rateAtUtilizationKink": "0",
// //             "rateAtUtilizationMax": "0",
// //             "rateAtUtilizationZero": "0",
// //             "token": "0x0000000000000000000000000000000000000000"
// //           },
// //           "rateDataV2": {
// //             "kink1": "5000",
// //             "kink2": "9000",
// //             "rateAtUtilizationKink1": "230",
// //             "rateAtUtilizationKink2": "280",
// //             "rateAtUtilizationMax": "10000",
// //             "rateAtUtilizationZero": "0",
// //             "token": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
// //           },
// //           "version": "2"
// //         },
// //         "revenue": "9586021944174261677",
// //         "storageUpdateThreshold": "30",
// //         "supplyExchangePrice": "1040958819451",
// //         "supplyInterestFree": "0",
// //         "supplyRate": "197",
// //         "supplyRawInterest": "49571167642230460514304",
// //         "totalBorrow": "42057192093949154815057",
// //         "totalSupply": "51601544147663831309441"
// //       },
// //       "liquidityUserBorrowDataToken0": {
// //         "baseBorrowLimit": "39960454605",
// //         "borrow": "66719549",
// //         "borrowLimit": "39960454605",
// //         "borrowLimitUtilization": "101916058615574",
// //         "borrowable": "39893735056",
// //         "borrowableUntilLimit": "39893735056",
// //         "expandDuration": "3600",
// //         "expandPercent": "5000",
// //         "lastUpdateTimestamp": "1731135887",
// //         "maxBorrowLimit": "49986895942",
// //         "modeWithInterest": true
// //       },
// //       "liquidityUserBorrowDataToken1": {
// //         "baseBorrowLimit": "15984542754087757552",
// //         "borrow": "52423385833215669",
// //         "borrowLimit": "15984542754087757552",
// //         "borrowLimitUtilization": "51601544147663831309441",
// //         "borrowable": "15932119368254541883",
// //         "borrowableUntilLimit": "15932119368254541883",
// //         "expandDuration": "3600",
// //         "expandPercent": "5000",
// //         "lastUpdateTimestamp": "1731135887",
// //         "maxBorrowLimit": "19985418817091929372",
// //         "modeWithInterest": true
// //       },
// //       "liquidityUserSupplyDataToken0": {
// //         "baseWithdrawalLimit": "49954209449",
// //         "expandDuration": "3600",
// //         "expandPercent": "5000",
// //         "lastUpdateTimestamp": "1731135887",
// //         "modeWithInterest": true,
// //         "supply": "145091098",
// //         "withdrawable": "145091098",
// //         "withdrawableUntilLimit": "145091098",
// //         "withdrawalLimit": "0"
// //       },
// //       "liquidityUserSupplyDataToken1": {
// //         "baseWithdrawalLimit": "19989895307916534620",
// //         "expandDuration": "3600",
// //         "expandPercent": "5000",
// //         "lastUpdateTimestamp": "1731135887",
// //         "modeWithInterest": true,
// //         "supply": "20376157484395192",
// //         "withdrawable": "20376157484395192",
// //         "withdrawableUntilLimit": "20376157484395192",
// //         "withdrawalLimit": "0"
// //       },
// //       "liquidityWithdrawableToken0": "145091098",
// //       "liquidityWithdrawableToken1": "20376157484395192",
// //       "utilizationLimitToken0": "101916058615574",
// //       "utilizationLimitToken1": "51601544147663831309441",
// //       "withdrawableUntilUtilizationLimitToken0": "7053657207338",
// //       "withdrawableUntilUtilizationLimitToken1": "9544352053714676494384"
// //     },
// //     "pex": {
// //       "borrowToken0ExchangePrice": "1082649409910",
// //       "borrowToken1ExchangePrice": "1052574579104",
// //       "centerPrice": "339348508210503532675072",
// //       "geometricMean": "339348508210503532675071",
// //       "lastStoredPrice": "325151118254488344854528",
// //       "lowerRange": "305413657389453179407564",
// //       "supplyToken0ExchangePrice": "1063393896172",
// //       "supplyToken1ExchangePrice": "1040958819451",
// //       "upperRange": "377053898011670591861191"
// //     }
// //   }
// // }
