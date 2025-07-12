//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IRedstoneOracle } from "../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";
import { IUniswapV3Pool } from "../../../contracts/oracle/interfaces/external/IUniswapV3Pool.sol";
import { UniV3CheckCLRSOracle } from "../../../contracts/oracle/oracles/uniV3CheckCLRSOracle.sol";
import { ChainlinkStructs, RedstoneStructs } from "../../../contracts/oracle/implementations/structs.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";
import { UniV3OracleImpl } from "../../../contracts/oracle/implementations/uniV3OracleImpl.sol";
import { ChainlinkOracleImpl } from "../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { RedstoneOracleImpl } from "../../../contracts/oracle/implementations/redstoneOracleImpl.sol";
import { TickMath } from "../../../contracts/oracle/libraries/TickMath.sol";
import { IFluidOracle } from "../../../contracts/oracle/fluidOracle.sol";

import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";

import { OracleTestSuite } from "./oracleTestSuite.t.sol";
import { MockChainlinkFeed } from "./mocks/mockChainlinkFeed.sol";
import { MockRedstoneFeed } from "./mocks/mockRedstoneFeed.sol";
import { MockUniswapPool } from "./mocks/mockUniswapPool.sol";

import "forge-std/console2.sol";

// @dev All cases for Oracles at initial Fluid launch:
// UniV3 main with Chainlink only: rateSource == 2, fallback source == 1.
// - uniV3 ok, chainlink ok. Delta ok. -> uniV3
// - uniV3 ok, chainlink ok. Delta fail. -> Chainlink
// - uniV3 ok, chainlink fails. -> uniV3 (skip check)
// - uniV3 fails, chainlink ok. -> Chainlink
// - univ3 fails, chainlink fails -> revert.
// all these are covered with tests.

contract UniV3CheckCLRSOracleTest is OracleTestSuite {
    function setUp() public virtual override {
        super.setUp();
    }

    function _createOracle(
        UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams memory params
    ) internal virtual returns (IFluidOracle) {
        return new UniV3CheckCLRSOracle(infoName, SAMPLE_TARGET_DECIMALS, params);
    }

    function test_constructor_RateSourceShouldBeBetweenOneAndThree() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.UniV3CheckCLRSOracle__InvalidParams)
        );
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: UNIV3_POOL,
                    invertRate: true,
                    tWAPMaxDeltaPercents: _getDefaultUniswapTwapDeltasFixed(),
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: true,
                        token0Decimals: 6 // USDC has 6 decimals
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED)),
                    invertRate: false,
                    token0Decimals: 1
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 0, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 1, // which oracle to use as CL/RS main source <- in this case doesnt metter as fallback is not used
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.FallbackOracle__InvalidParams)
        );
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: UNIV3_POOL,
                    invertRate: true,
                    tWAPMaxDeltaPercents: _getDefaultUniswapTwapDeltasFixed(),
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: true,
                        token0Decimals: 6 // USDC has 6 decimals
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED)),
                    invertRate: false,
                    token0Decimals: 1
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 1, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 4, // which oracle to use as CL/RS main source <- in this case doesnt metter as fallback is not used
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
    }

    function test_constructor_DeltaMoreThan100Percent() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.UniV3CheckCLRSOracle__InvalidParams)
        );
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: UNIV3_POOL,
                    invertRate: true,
                    tWAPMaxDeltaPercents: _getDefaultUniswapTwapDeltasFixed(),
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: true,
                        token0Decimals: 6 // USDC has 6 decimals
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED)),
                    invertRate: false,
                    token0Decimals: 1
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 3, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 2, // which oracle to use as CL/RS main source <- in this case doesnt metter as fallback is not used
                rateCheckMaxDeltaPercent: 10_001 // invalid 101%
            })
        );
    }

    function test_getExchangeRate_UniswapOnly() public {
        MockUniswapPool mockUniswapPool = new MockUniswapPool(UNIV3_POOL, _getDefaultSecondAgos());
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: mockUniswapPool,
                    invertRate: true,
                    tWAPMaxDeltaPercents: [uint256(9_999), 9_998, 9_997], // <= in this test we dont care. Please look at test_getExchangeRate_UniswapCheckTWAPDeltaChecks test
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: true,
                        token0Decimals: 6 // USDC has 6 decimals
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED)),
                    invertRate: false,
                    token0Decimals: 1
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 1, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 1, // which oracle to use as CL/RS main source <- in this case doesnt metter as fallback is not used
                rateCheckMaxDeltaPercent: 100 // 1% max delta
            })
        );
        runOracleDataAsserts(100, 1, 1);
        uint32[] memory uniswapTwapDeltas_ = new uint32[](3);
        uniswapTwapDeltas_[0] = 9999;
        uniswapTwapDeltas_[1] = 9998;
        uniswapTwapDeltas_[2] = 9997;
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(mockUniswapPool),
            true,
            _getDefaultSecondAgos(),
            uniswapTwapDeltas_
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(CHAINLINK_FEED)),
            false
        );
        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);

        (, int256 expectedChainlinkExchangeRate, , , ) = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED))
            .latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
            invertRate: true,
            exchangeRate: 10 ** (27 + 6) / uint256(expectedChainlinkExchangeRate)
        });

        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: true,
            exchangeRate: 0
        });

        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: true,
            exchangeRate: 0
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);

        // default uniswap exchange rate -> 495906977500261

        MOCK_CHAINLINK_FEED.setExchangeRate(int256(495906977500261) / 2); // change chainlink price drasticly, it shouldn't impact final result because in this case test takes only uniswap rate and doesnt check other sources

        (int56[] memory tickCumulativesDefault, ) = IUniswapV3Pool(mockUniswapPool).observe(_getDefaultSecondAgos());
        // tick(imprecise as it's an integer) to price
        int256 twapInterval = 1; // <- prev last (seconds ago) - last (seconds ago), looking at default values its 1 - 0
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulativesDefault[4] - tickCumulativesDefault[3]) / int56(twapInterval))
        );
        uint256 expectedRate = _invertUniV3Price(_getPriceFromSqrtPriceX96(sqrtPriceX96));
        _assertExchangeRatesAllMethods(oracle, expectedRate);

        uint256 notInvertedChainlinkExchangePrice = 10 ** (27 + 6) / uint256(expectedChainlinkExchangeRate);

        int256 product = (tickCumulativesDefault[4] - tickCumulativesDefault[3]) / int256(1 - 0);
        uint256 lastPrice = _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(product)));
        int256 productTemp;
        int56 addValue;
        uint256 chainlinkPricePlus5Percent = (uint256(notInvertedChainlinkExchangePrice) +
            ((uint256(notInvertedChainlinkExchangePrice) * 500) / 10_000));

        // now check if even if uniswap price is out of delta (1%) from chainlink its still return uniswap price, proof that chainlink has no impact here
        int56[] memory tickCumulatives = new int56[](tickCumulativesDefault.length);
        for (uint256 i = 0; i < tickCumulativesDefault.length; i++) {
            int56 temp = tickCumulativesDefault[i];
            tickCumulatives[i] = temp;
        }

        // price above delta +5%
        while (expectedRate < chainlinkPricePlus5Percent) {
            addValue += 100;
            productTemp = (tickCumulativesDefault[4] - (tickCumulativesDefault[3] + addValue)) / int256(1 - 0);
            expectedRate = _invertUniV3Price(
                _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(productTemp)))
            );
        }
        tickCumulatives[3] += addValue;
        mockUniswapPool.setTickCumulative(tickCumulatives);

        addValue = 0;

        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }

    function test_getExchangeRate_UniswapWithChainLinkFallback() public {
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: UNIV3_POOL,
                    invertRate: true,
                    tWAPMaxDeltaPercents: _getDefaultUniswapTwapDeltasFixed(),
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED,
                        invertRate: true,
                        token0Decimals: 6 // USDC has 6 decimals
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED)),
                    invertRate: false,
                    token0Decimals: 1
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 2, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 1, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 2, 1);
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(UNIV3_POOL),
            true,
            _getDefaultSecondAgos(),
            _getDefaultUniswapTwapDeltas()
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(CHAINLINK_FEED)),
            false
        );

        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
        (, int256 expectedExchangeRate, , , ) = IChainlinkAggregatorV3(address(CHAINLINK_FEED)).latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(CHAINLINK_FEED)),
            invertRate: true,
            exchangeRate: 10 ** (27 + 6) / uint256(expectedExchangeRate)
        });

        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: true,
            exchangeRate: 0
        });

        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: true,
            exchangeRate: 0
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(UNIV3_POOL).observe(_getDefaultSecondAgos());
        // tick(imprecise as it's an integer) to price
        int256 twapInterval = 1; // <- prev last (seconds ago) - last (seconds ago), looking at default values its 1 - 0
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[4] - tickCumulatives[3]) / int56(twapInterval))
        );
        uint256 expectedRate = _invertUniV3Price(_getPriceFromSqrtPriceX96(sqrtPriceX96));
        console2.log("expectedRate", expectedRate);
        // case: uniV3 ok, chainlink ok. Delta ok. -> uniV3
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }

    function test_getExchangeRate_UniswapWithChainLinkFallback_WhenChainlinkReturnsZeroThenTakeUniswapRateDirectly()
        public
    {
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: UNIV3_POOL,
                    invertRate: true,
                    tWAPMaxDeltaPercents: _getDefaultUniswapTwapDeltasFixed(),
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: false,
                        token0Decimals: 6 // USDC has 6 decimals
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(IRedstoneOracle(address(MOCK_CHAINLINK_FEED))),
                    invertRate: false,
                    token0Decimals: 1
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 2, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 1, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 2, 1);
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(UNIV3_POOL),
            true,
            _getDefaultSecondAgos(),
            _getDefaultUniswapTwapDeltas()
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(MOCK_CHAINLINK_FEED)),
            false
        );
        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
        (, int256 expectedExchangeRate, , , ) = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)).latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
            invertRate: false,
            exchangeRate: uint256(expectedExchangeRate) * 10 ** (27 - 6)
        });

        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: true,
            exchangeRate: 0
        });

        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: true,
            exchangeRate: 0
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);

        MOCK_CHAINLINK_FEED.setExchangeRate(0);

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(UNIV3_POOL).observe(_getDefaultSecondAgos());
        // tick(imprecise as it's an integer) to price
        int256 twapInterval = 1; // <- prev last (seconds ago) - last (seconds ago), looking at default values its 1 - 0
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[4] - tickCumulatives[3]) / int56(twapInterval))
        );
        uint256 expectedRate = _invertUniV3Price(_getPriceFromSqrtPriceX96(sqrtPriceX96));
        // case: uniV3 ok, chainlink fails. -> uniV3 (skip check)
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }

    function test_getExchangeRate_UniswapWithChainLinkFallback_ChainlinkRateOutOfDelta() public {
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: UNIV3_POOL,
                    invertRate: true,
                    tWAPMaxDeltaPercents: _getDefaultUniswapTwapDeltasFixed(),
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED, // <- MOCKED
                        invertRate: true,
                        token0Decimals: 6 // USDC has 6 decimals
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(MOCK_CHAINLINK_FEED)),
                    invertRate: false,
                    token0Decimals: 1
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 2, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 1, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 2, 1);
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(UNIV3_POOL),
            true,
            _getDefaultSecondAgos(),
            _getDefaultUniswapTwapDeltas()
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(MOCK_CHAINLINK_FEED)),
            false
        );
        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
        (, int256 expectedExchangeRate, , , ) = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)).latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
            invertRate: true,
            exchangeRate: 10 ** (27 + 6) / uint256(expectedExchangeRate)
        });

        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: true,
            exchangeRate: 0
        });

        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: true,
            exchangeRate: 0
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);

        // calculate uniswap exchange rate
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(UNIV3_POOL).observe(_getDefaultSecondAgos());
        // tick(imprecise as it's an integer) to price
        int256 twapInterval = 1; // <- prev last (seconds ago) - last (seconds ago), looking at default values its 1 - 0
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[4] - tickCumulatives[3]) / int56(twapInterval))
        );
        uint256 uniswapExchangeRate = _invertUniV3Price(_getPriceFromSqrtPriceX96(sqrtPriceX96));
        // uint256 invertedUniswapExchangeRate = 10 ** (27 * 2) / uniswapExchangeRate;
        // uint256 scaledInvertedUniswapExchangeRate = invertedUniswapExchangeRate / 1e21; // to have the same decimals as the chainlink output
        // default chainlink exchange rate -> 495374475436994
        // default uniswap exchange rate -> 495906977500261
        // this is price difference

        // case: uniV3 ok, chainlink ok. Delta fail. -> Chainlink

        // expected delta 3%
        int256 newChainlinkExchangeRate = (int256(495906977500261) * 10299999) / 10000000;
        MOCK_CHAINLINK_FEED.setExchangeRate(newChainlinkExchangeRate); // change exchange rate from chainlink to right BELOW uniswap exchange rate +3% (default delta)
        _assertExchangeRatesAllMethods(oracle, uniswapExchangeRate);

        newChainlinkExchangeRate = (int256(495906977500261) * 10300001) / 10000000;
        MOCK_CHAINLINK_FEED.setExchangeRate(newChainlinkExchangeRate); // change exchange rate from chainlink to right ABOVE uniswap exchange rate +3% (default delta)
        // when delta out of range, should return chainlink price instead of uniV3 price
        // scaled & inverted chainlink rate 10 ** (27 * 2) / (495906977500261 * 10300001 / 10000000) / 1e21 = 1957773808793957228
        _assertExchangeRatesAllMethods(oracle, 1957773808793959451); // minor imprecision doesn't matter for test verify goals

        newChainlinkExchangeRate = (int256(495906977500261) * 9699999) / 10000000;
        MOCK_CHAINLINK_FEED.setExchangeRate(newChainlinkExchangeRate); // change exchange rate from chainlink to right BELOW uniswap exchange rate -3% (default delta)
        // when delta out of range, should return chainlink price instead of uniV3 price
        // scaled & inverted chainlink rate 10 ** (27 * 2) / (495906977500261 * 9699999 / 10000000) / 1e21 = 2078873635796412787
        _assertExchangeRatesAllMethods(oracle, 2078873635796414602); // minor imprecision doesn't matter for test verify goals

        newChainlinkExchangeRate = (int256(495906977500261) * 9700001) / 10000000;
        MOCK_CHAINLINK_FEED.setExchangeRate(newChainlinkExchangeRate); // change exchange rate from chainlink to right ABOVE uniswap exchange rate -3% (default delta)
        _assertExchangeRatesAllMethods(oracle, uniswapExchangeRate); // should return uniV3 price again
    }

    function test_getExchangeRate_UniswapWithChainLinkFallback_WhenUniV3Fails() public {
        MockUniswapPool mockUniswapPool = new MockUniswapPool(UNIV3_POOL, _getDefaultSecondAgos());
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: mockUniswapPool,
                    invertRate: false,
                    tWAPMaxDeltaPercents: [uint256(9_999), 9_998, 100], // last delta small will make uniV3 fail when wanted
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: false,
                        token0Decimals: 6 // USDC has 6 decimals
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
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED)),
                    invertRate: false,
                    token0Decimals: 1
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 2, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 1, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 2, 1);
        uint32[] memory uniswapTwapDeltas_ = new uint32[](3);
        uniswapTwapDeltas_[0] = 9999;
        uniswapTwapDeltas_[1] = 9998;
        uniswapTwapDeltas_[2] = 100;
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(mockUniswapPool),
            false,
            _getDefaultSecondAgos(),
            uniswapTwapDeltas_
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(CHAINLINK_FEED)),
            false
        );

        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
        (, int256 expectedExchangeRate, , , ) = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)).latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
            invertRate: false,
            exchangeRate: uint256(expectedExchangeRate) * 10 ** (27 - 6)
        });

        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(UNIV3_POOL).observe(_getDefaultSecondAgos());
        // tick(imprecise as it's an integer) to price
        int256 twapInterval = 1; // <- prev last (seconds ago) - last (seconds ago), looking at default values its 1 - 0
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[4] - tickCumulatives[3]) / int56(twapInterval))
        );
        uint256 expectedRate = _getPriceFromSqrtPriceX96(sqrtPriceX96);
        _assertExchangeRatesAllMethods(oracle, expectedRate); // checks rate with chainlink oracle

        // when uniV3 fails, Chainlink rate should be used.
        // case: uniV3 fails, chainlink ok. -> Chainlink
        changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(
            mockUniswapPool,
            expectedRate,
            uint256(expectedExchangeRate) * 10 ** (27 - 6)
        );

        // case: univ3 fails, chainlink fails -> revert.
        MOCK_CHAINLINK_FEED.setExchangeRate(0);
        changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(mockUniswapPool, expectedRate, 0);
    }

    function test_getExchangeRate_UniswapWithChainLinkCheckAndRedStoneFallback() public {
        MockUniswapPool mockUniswapPool = new MockUniswapPool(UNIV3_POOL, _getDefaultSecondAgos());
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: mockUniswapPool,
                    invertRate: false,
                    tWAPMaxDeltaPercents: [uint256(9_999), 9_998, 100], // last delta small will make uniV3 fail when wanted
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: false,
                        token0Decimals: 6 // USDC has 6 decimals
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
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
                    invertRate: false,
                    token0Decimals: 6
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 2, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 2, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 2, 2);
        uint32[] memory uniswapTwapDeltas_ = new uint32[](3);
        uniswapTwapDeltas_[0] = 9999;
        uniswapTwapDeltas_[1] = 9998;
        uniswapTwapDeltas_[2] = 100;
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(mockUniswapPool),
            false,
            _getDefaultSecondAgos(),
            uniswapTwapDeltas_
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            MOCK_REDSTONE_FEED.getExchangeRate(),
            IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
            false
        );
        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
        (, int256 expectedExchangeRate, , , ) = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)).latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
            invertRate: false,
            exchangeRate: uint256(expectedExchangeRate) * 10 ** (27 - 6)
        });

        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(UNIV3_POOL).observe(_getDefaultSecondAgos());
        // tick(imprecise as it's an integer) to price
        int256 twapInterval = 1; // <- prev last (seconds ago) - last (seconds ago), looking at default values its 1 - 0
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[4] - tickCumulatives[3]) / int56(twapInterval))
        );
        uint256 expectedRate = _getPriceFromSqrtPriceX96(sqrtPriceX96);
        _assertExchangeRatesAllMethods(oracle, expectedRate); // checks rate with chainlink oracle

        // when uniV3 fails, Chainlink rate should be used.
        changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(
            mockUniswapPool,
            expectedRate,
            uint256(expectedExchangeRate) * 10 ** (27 - 6)
        );

        uint256 newRedstoneExchangeRate = 495906977500261; // -> current difference in scaler multiplier
        MOCK_REDSTONE_FEED.setExchangeRate(newRedstoneExchangeRate); // set exchange price the same as uniswap for redstone oracle
        MOCK_CHAINLINK_FEED.setExchangeRate(0); // return bad exchange rate from chainlink to get exchange rate from redstone
        _assertExchangeRatesAllMethods(oracle, expectedRate); // checks rate with redstone oracle, passes, should use uniV3 price.

        // when uniV3 fails, and Chainlink fails, Redstone rate should be used.
        changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(
            mockUniswapPool,
            expectedRate,
            newRedstoneExchangeRate * 10 ** (27 - 6)
        );

        newRedstoneExchangeRate = uint256(495906977500261 * 1031) / 1000;
        MOCK_REDSTONE_FEED.setExchangeRate(newRedstoneExchangeRate); // change exchange rate from chainlink to right ABOVE uniswap exchange rate +3% (default delta)

        // delta check uniV3 <> Chainlink fails. Redstone fallback will be used. Redstone fails too, so revert should happen
        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.UniV3CheckCLRSOracle__InvalidPrice);
    }

    function test_getExchangeRate_UniswapWithRedStoneCheckAndChainLinkFallback() public {
        MockUniswapPool mockUniswapPool = new MockUniswapPool(UNIV3_POOL, _getDefaultSecondAgos());
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: mockUniswapPool,
                    invertRate: false,
                    tWAPMaxDeltaPercents: [uint256(9_999), 9_998, 100], // last delta small will make uniV3 fail when wanted
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: false,
                        token0Decimals: 6 // USDC has 6 decimals
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
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
                    invertRate: false,
                    token0Decimals: 6
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 2, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 3, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 2, 3);
        uint32[] memory uniswapTwapDeltas_ = new uint32[](3);
        uniswapTwapDeltas_[0] = 9999;
        uniswapTwapDeltas_[1] = 9998;
        uniswapTwapDeltas_[2] = 100;
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(mockUniswapPool),
            false,
            _getDefaultSecondAgos(),
            uniswapTwapDeltas_
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
            false
        );
        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
        (, int256 expectedExchangeRate, , , ) = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)).latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
            invertRate: false,
            exchangeRate: uint256(expectedExchangeRate) * 10 ** (27 - 6)
        });

        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(UNIV3_POOL).observe(_getDefaultSecondAgos());
        // tick(imprecise as it's an integer) to price
        int256 twapInterval = 1; // <- prev last (seconds ago) - last (seconds ago), looking at default values its 1 - 0
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[4] - tickCumulatives[3]) / int56(twapInterval))
        );
        uint256 expectedRate = _getPriceFromSqrtPriceX96(sqrtPriceX96);
        _assertExchangeRatesAllMethods(oracle, expectedRate); // checks rate with chainlink oracle

        // when uniV3 fails, Chainlink rate should be used, even when Redstone would be configured first
        changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(
            mockUniswapPool,
            expectedRate,
            uint256(expectedExchangeRate) * 10 ** (27 - 6)
        );

        // when uniV3 fails, and fetching Chainlink fails, Redstone should be used
        MOCK_CHAINLINK_FEED.setExchangeRate(0);
        MOCK_REDSTONE_FEED.setExchangeRate(495906977500777);
        changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(
            mockUniswapPool,
            expectedRate,
            495906977500777 * 10 ** (27 - 6)
        );
        MOCK_CHAINLINK_FEED.setExchangeRate(495906977500261); // reset

        uint256 newRedstoneExchangeRate = uint256(495906977500261 * 1031) / 1000;
        MOCK_REDSTONE_FEED.setExchangeRate(newRedstoneExchangeRate); // change exchange rate from Redstone to right ABOVE uniswap exchange rate +3% (default delta)

        // check against redstone should fail but check against Chainlink passes
        _assertExchangeRatesAllMethods(oracle, expectedRate);

        // check against Chainlink fails too -> use Chainlink price
        int256 newChainlinkExchangeRate = int256(495906977500261 * 9699999) / 10000000;
        MOCK_CHAINLINK_FEED.setExchangeRate(newChainlinkExchangeRate);
        // scaled chainlink rate (495906977500261 * 9699999 / 10000000) * 1e12 = ~481029718584555000000000000000000000
        _assertExchangeRatesAllMethods(oracle, 481029718584555000000000000000000000);

        MOCK_REDSTONE_FEED.setExchangeRate(0); // set exchange price to 0 in order to ignore exchange rate from redstone and take directly from chainlink
        _assertExchangeRatesAllMethods(oracle, 481029718584555000000000000000000000);

        // when Chainlink delta passes, should return uniV3 price
        MOCK_CHAINLINK_FEED.setExchangeRate(495906977500261);
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }

    function test_getExchangeRate_ChainlinkWithUniswapCheck() public {
        MockUniswapPool mockUniswapPool = new MockUniswapPool(UNIV3_POOL, _getDefaultSecondAgos());
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: mockUniswapPool,
                    invertRate: false,
                    tWAPMaxDeltaPercents: [uint256(9_999), 9_998, 9_997], // <= in this test we dont care. Please look at test_getExchangeRate_UniswapCheckTWAPDeltaChecks test
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: false,
                        token0Decimals: 6 // USDC has 6 decimals
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
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
                    invertRate: false,
                    token0Decimals: 6
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 3, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 2, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 3, 2);
        uint32[] memory uniswapTwapDeltas_ = new uint32[](3);
        uniswapTwapDeltas_[0] = 9999;
        uniswapTwapDeltas_[1] = 9998;
        uniswapTwapDeltas_[2] = 9997;
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(mockUniswapPool),
            false,
            _getDefaultSecondAgos(),
            uniswapTwapDeltas_
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
            false
        );
        uint256 priceMultiplier = 10 ** (27 - 6);

        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
        (, int256 expectedExchangeRate, , , ) = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)).latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
            invertRate: false,
            exchangeRate: uint256(expectedExchangeRate) * priceMultiplier
        });

        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);

        (
            uint80 roundId,
            int256 exchangeRate,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = MOCK_CHAINLINK_FEED.latestRoundData();
        uint256 chainlinkExchangePrice = uint256(exchangeRate) * priceMultiplier;
        _assertExchangeRatesAllMethods(oracle, chainlinkExchangePrice); // rate from chainlink

        changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(
            mockUniswapPool,
            chainlinkExchangePrice,
            chainlinkExchangePrice
        );
    }

    function test_getExchangeRate_ChainlinkAndRedstoneFallbackWithUniswapCheck() public {
        MockUniswapPool mockUniswapPool = new MockUniswapPool(UNIV3_POOL, _getDefaultSecondAgos());
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: mockUniswapPool,
                    invertRate: false,
                    tWAPMaxDeltaPercents: [uint256(9_999), 9_998, 9_997], // <= in this test we dont care. Please look at test_getExchangeRate_UniswapCheckTWAPDeltaChecks test
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: false,
                        token0Decimals: 6 // USDC has 6 decimals
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
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
                    invertRate: false,
                    token0Decimals: 6
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 3, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 2, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 3, 2);
        uint32[] memory uniswapTwapDeltas_ = new uint32[](3);
        uniswapTwapDeltas_[0] = 9999;
        uniswapTwapDeltas_[1] = 9998;
        uniswapTwapDeltas_[2] = 9997;
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(mockUniswapPool),
            false,
            _getDefaultSecondAgos(),
            uniswapTwapDeltas_
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
            false
        );
        uint256 priceMultiplier = 10 ** (27 - 6);
        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
        (, int256 expectedExchangeRate, , , ) = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)).latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
            invertRate: false,
            exchangeRate: uint256(expectedExchangeRate) * priceMultiplier
        });

        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);

        (
            uint80 roundId,
            int256 exchangeRate,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = MOCK_CHAINLINK_FEED.latestRoundData();
        uint256 chainlinkExchangePrice = uint256(exchangeRate) * priceMultiplier;
        _assertExchangeRatesAllMethods(oracle, chainlinkExchangePrice); // rate from chainlink

        // change uniswap exchange rate out of delta to get invalid price in order to prove check price with uniswap against price from chainlink
        changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(
            mockUniswapPool,
            chainlinkExchangePrice,
            chainlinkExchangePrice
        );
        MOCK_CHAINLINK_FEED.setExchangeRate(0);
        uint256 newRedstoneExchangeRate = uint256(495906977500261 * 1029) / 1000; // => price still in valid range, right BELOW uniswap exchange rate +3% (default exchange check delta)
        MOCK_REDSTONE_FEED.setExchangeRate(newRedstoneExchangeRate);
        exchangeRate = int256(MOCK_REDSTONE_FEED.getExchangeRate());
        uint256 expectedRate = uint256(exchangeRate) * priceMultiplier;
        _assertExchangeRatesAllMethods(oracle, expectedRate); // proof that exchange rate was taken from redstone
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            newRedstoneExchangeRate * priceMultiplier,
            IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
            false
        );
        // ===========================================
        // change uniswap exchange rate out of delta to get invalid price in order to prove check price with uniswap against price from redstone
        changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(
            mockUniswapPool,
            newRedstoneExchangeRate * priceMultiplier,
            0
        );
    }

    function test_getExchangeRate_RedstoneAndChainlinkFallbackWithUniswapCheck() public {
        MockUniswapPool mockUniswapPool = new MockUniswapPool(UNIV3_POOL, _getDefaultSecondAgos());
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: mockUniswapPool,
                    invertRate: false,
                    tWAPMaxDeltaPercents: [uint256(9_999), 9_998, 9_997], // <= in this test we dont care. Please look at test_getExchangeRate_UniswapCheckTWAPDeltaChecks test
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: false,
                        token0Decimals: 6 // USDC has 6 decimals
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
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
                    invertRate: false,
                    token0Decimals: 6
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 3, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 3, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 3, 3);
        uint32[] memory uniswapTwapDeltas_ = new uint32[](3);
        uniswapTwapDeltas_[0] = 9999;
        uniswapTwapDeltas_[1] = 9998;
        uniswapTwapDeltas_[2] = 9997;
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(mockUniswapPool),
            false,
            _getDefaultSecondAgos(),
            uniswapTwapDeltas_
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
            false
        );
        uint256 priceMultiplier = 10 ** (27 - 6);
        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
        (, int256 expectedExchangeRate, , , ) = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)).latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
            invertRate: false,
            exchangeRate: uint256(expectedExchangeRate) * priceMultiplier
        });

        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);

        uint256 newRedstoneExchangeRate = uint256(495906977500261 * 1029) / 1000; // => price still in valid range, right BELOW uniswap exchange rate +3% (default exchange check delta)
        MOCK_REDSTONE_FEED.setExchangeRate(newRedstoneExchangeRate);
        int256 exchangeRate = int256(MOCK_REDSTONE_FEED.getExchangeRate());
        uint256 expectedRate = uint256(exchangeRate) * priceMultiplier;
        _assertExchangeRatesAllMethods(oracle, expectedRate); // proof that exchange rate was taken from redstone
        // change uniswap exchange rate out of delta to get invalid price in order to prove check price with uniswap against price from redstone
        changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(
            mockUniswapPool,
            uint256(expectedExchangeRate),
            // when uniswap fails to fetch for checking, check is skipped and Redstone price should be returned
            expectedRate
        );

        MOCK_REDSTONE_FEED.setExchangeRate(0);
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
            false
        );
        (, exchangeRate, , , ) = MOCK_CHAINLINK_FEED.latestRoundData();
        expectedRate = uint256(exchangeRate) * priceMultiplier;
        _assertExchangeRatesAllMethods(oracle, expectedRate); // rate from chainlink

        // change uniswap exchange rate out of delta to get invalid price in order to prove check price with uniswap against price from chainlink
        changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(
            mockUniswapPool,
            uint256(expectedExchangeRate),
            uint256(expectedExchangeRate) * priceMultiplier
        );
    }

    function test_getExchangeRate_RedstoneAndChainlinkFallbackWithUniswapCheck_BothRedstoneAndChainlinkHaveInvalidPrices()
        public
    {
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: UNIV3_POOL,
                    invertRate: false,
                    tWAPMaxDeltaPercents: _getDefaultUniswapTwapDeltasFixed(),
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: false,
                        token0Decimals: 6 // USDC has 6 decimals
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
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
                    invertRate: false,
                    token0Decimals: 6
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 3, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 3, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 3, 3);
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(UNIV3_POOL),
            false,
            _getDefaultSecondAgos(),
            _getDefaultUniswapTwapDeltas()
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
            false
        );
        uint256 priceMultiplier = 10 ** (27 - 6);
        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
        (, int256 expectedExchangeRate, , , ) = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)).latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
            invertRate: false,
            exchangeRate: uint256(expectedExchangeRate) * priceMultiplier
        });

        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(0)),
            invertRate: false,
            exchangeRate: 0
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);

        MOCK_CHAINLINK_FEED.setExchangeRate(0);
        MOCK_REDSTONE_FEED.setExchangeRate(0);

        _assertExchangeRatesAllMethods(oracle, 495906977500261371200612336690714056); // expect standard uniV3 rate
    }

    function test_getExchangeRate_MultiHopCase() public {
        UNIV3_POOL = IUniswapV3Pool(0x9a772018FbD77fcD2d25657e5C547BAfF3Fd7D16); // WBTC - USDC

        IChainlinkAggregatorV3 CHAINLINK_FEED_WBTC_BTC = IChainlinkAggregatorV3(
            0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23
        );

        IChainlinkAggregatorV3 CHAINLINK_FEED_BTC_USD = IChainlinkAggregatorV3(
            0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c
        );

        IChainlinkAggregatorV3 CHAINLINK_FEED_USDC_USD = IChainlinkAggregatorV3(
            0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6
        );

        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: UNIV3_POOL,
                    invertRate: false,
                    tWAPMaxDeltaPercents: _getDefaultUniswapTwapDeltasFixed(),
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 3,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED_WBTC_BTC,
                        invertRate: false,
                        token0Decimals: 8
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED_BTC_USD,
                        invertRate: false,
                        token0Decimals: 8
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED_USDC_USD,
                        invertRate: true,
                        token0Decimals: 6
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED_USDC_USD)),
                    invertRate: false,
                    token0Decimals: 1
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 3, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 3, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 3, 3);
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(UNIV3_POOL),
            false,
            _getDefaultSecondAgos(),
            _getDefaultUniswapTwapDeltas()
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(CHAINLINK_FEED_USDC_USD)),
            false
        );
        uint256 priceMultiplier = 10 ** (27 - 8);
        ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
        (, int256 exchangeRateWbtcBtc_, , , ) = IChainlinkAggregatorV3(address(CHAINLINK_FEED_WBTC_BTC))
            .latestRoundData();
        chainlinkDataArray[0] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(CHAINLINK_FEED_WBTC_BTC)),
            invertRate: false,
            exchangeRate: uint256(exchangeRateWbtcBtc_) * priceMultiplier
        });

        (, int256 exchangeRateBtcUsd_, , , ) = IChainlinkAggregatorV3(address(CHAINLINK_FEED_BTC_USD))
            .latestRoundData();
        chainlinkDataArray[1] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(CHAINLINK_FEED_BTC_USD)),
            invertRate: false,
            exchangeRate: uint256(exchangeRateBtcUsd_) * priceMultiplier
        });

        (, int256 exchangeRateUsdcUsd_, , , ) = IChainlinkAggregatorV3(address(CHAINLINK_FEED_USDC_USD))
            .latestRoundData();
        chainlinkDataArray[2] = ChainlinkFeedData({
            feed: IChainlinkAggregatorV3(address(CHAINLINK_FEED_USDC_USD)),
            invertRate: true,
            exchangeRate: 10 ** (27 + 6) / uint256(exchangeRateUsdcUsd_)
        });

        runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);
        MOCK_REDSTONE_FEED.setExchangeRate(0); // ignore redstone check

        //convert WBTC -> BTC (wbtc/btc rate)
        uint256 rateWbtcBtc = (uint256(exchangeRateWbtcBtc_) * (1e27)) / 1e8; // 1e27 -> Oracle precision

        //convert BTC -> USD (btc/usd rate)
        exchangeRateBtcUsd_ = (exchangeRateBtcUsd_ * 1e27) / 1e8;
        uint256 wbtcUsdRate = (rateWbtcBtc * uint256(exchangeRateBtcUsd_)) / 1e27; // 1e8 -> BTC decimals

        assertEq(exchangeRateUsdcUsd_, 99990875);

        //invert USDC/USD rate to get USD to USDC rate
        uint256 usdUsdcRate = (1e27 * 1e6) / uint256(exchangeRateUsdcUsd_); // 1e6 -> USDC decimals

        // WBTC -> USDC rate
        uint256 expectedRate = (wbtcUsdRate * usdUsdcRate) / 1e27; // 1e27 division adjusts for the Oracle's precision and 1e8 division was introduced by BTC's 8 decimal

        assertEq(expectedRate, 369916395986438762537081487906);
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }

    function test_getExchangeRate_UniswapCheckTWAPDeltaChecks() public {
        MockUniswapPool mockUniswapPool = new MockUniswapPool(UNIV3_POOL, _getDefaultSecondAgos());
        oracle = _createOracle(
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: mockUniswapPool,
                    invertRate: false,
                    tWAPMaxDeltaPercents: _getDefaultUniswapTwapDeltasFixed(),
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: MOCK_CHAINLINK_FEED,
                        invertRate: false,
                        token0Decimals: 6 // USDC has 6 decimals
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
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED)),
                    invertRate: false,
                    token0Decimals: 1
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 1, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 1, // which oracle to use as CL/RS main source <- in this case doesnt metter as fallback is not used
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
        runOracleDataAsserts(300, 1, 1);
        runUniV3OracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            address(mockUniswapPool),
            false,
            _getDefaultSecondAgos(),
            _getDefaultUniswapTwapDeltas()
        );
        runRedstoneOracleDataAsserts(
            UniV3CheckCLRSOracle(address(oracle)),
            0,
            IRedstoneOracle(address(CHAINLINK_FEED)),
            false
        );

        {
            ChainlinkFeedData[] memory chainlinkDataArray = new ChainlinkFeedData[](3);
            (, int256 expectedExchangeRate, , , ) = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED))
                .latestRoundData();
            chainlinkDataArray[0] = ChainlinkFeedData({
                feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
                invertRate: false,
                exchangeRate: uint256(expectedExchangeRate) * 10 ** (27 - 6)
            });

            chainlinkDataArray[1] = ChainlinkFeedData({
                feed: IChainlinkAggregatorV3(address(0)),
                invertRate: false,
                exchangeRate: 0
            });

            chainlinkDataArray[2] = ChainlinkFeedData({
                feed: IChainlinkAggregatorV3(address(0)),
                invertRate: false,
                exchangeRate: 0
            });
            runChainlinkOracleDataAsserts(UniV3CheckCLRSOracle(address(oracle)), chainlinkDataArray);
        }

        // default uniswap exchange rate -> 495906977500261 adjusted to scale with higher precision
        uint256 defaultUniV3Rate = 495906977500261371200612336690714056;
        // change chainlink price drasticly, this should be ignored anyway for this test as we use a uniV3 ONLY Oracle
        MOCK_CHAINLINK_FEED.setExchangeRate(int256(495906977500261) / 2);

        (int56[] memory tickCumulativesDefault, ) = IUniswapV3Pool(UNIV3_POOL).observe(_getDefaultSecondAgos());
        int56[] memory tickCumulatives = new int56[](tickCumulativesDefault.length);
        for (uint256 i = 0; i < tickCumulativesDefault.length; i++) {
            int56 temp = tickCumulativesDefault[i];
            tickCumulatives[i] = temp;
        }

        // default values for seconds agos => 240, 60, 15, 1, 0

        // twap one interval (for price between 3-1 minutes ago) = 240 - 60 = 180
        // twap two interval (for price between 1 minutes and 15 seconds ago) = 60 - 15 = 45
        // twap three interval (for price between 15 and 1 seconds ago) = 15 - 1 = 14

        uint256 twap1Interval = uint256(_getDefaultSecondAgos()[0] - _getDefaultSecondAgos()[1]);
        assertEq(twap1Interval, 180);
        uint256 twap2Interval = uint256(_getDefaultSecondAgos()[1] - _getDefaultSecondAgos()[2]);
        assertEq(twap2Interval, 45);
        uint256 twap3Interval = uint256(_getDefaultSecondAgos()[2] - _getDefaultSecondAgos()[3]);
        assertEq(twap3Interval, 14);

        int256 product = (tickCumulativesDefault[4] - tickCumulativesDefault[3]) / int256(1 - 0);
        uint256 lastPrice = _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(product)));
        int256 productTemp;
        uint256 tempPrice;
        int56 addValue;
        uint256 lastPricePlus3Percent = (lastPrice + ((lastPrice * 310) / 10_000));
        uint256 lastPriceMinus3Percent = (lastPrice - ((lastPrice * 310) / 10_000));

        // Case for first interval check
        // price right above +3% (3,1%)
        while (tempPrice < lastPricePlus3Percent) {
            addValue += 100;
            productTemp = (tickCumulativesDefault[1] - (tickCumulativesDefault[0] - addValue)) / int256(twap1Interval);
            tempPrice = _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(productTemp)));
        }
        tickCumulatives[0] -= addValue;
        mockUniswapPool.setTickCumulative(tickCumulatives);

        addValue = 0;

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.UniV3CheckCLRSOracle__ExchangeRateZero);

        mockUniswapPool.setTickCumulative(tickCumulativesDefault);
        _assertExchangeRatesAllMethods(oracle, defaultUniV3Rate);

        resetTickCumulatives(tickCumulatives, tickCumulativesDefault);

        // price right below -3% (3,1%)
        tempPrice = lastPrice;
        while (tempPrice > lastPriceMinus3Percent) {
            addValue += 100;
            productTemp = (tickCumulativesDefault[1] - (tickCumulativesDefault[0] + addValue)) / int256(twap1Interval);
            tempPrice = _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(productTemp)));
        }
        tickCumulatives[0] += addValue;
        mockUniswapPool.setTickCumulative(tickCumulatives);
        addValue = 0;

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.UniV3CheckCLRSOracle__ExchangeRateZero);

        mockUniswapPool.setTickCumulative(tickCumulativesDefault);
        _assertExchangeRatesAllMethods(oracle, defaultUniV3Rate);

        resetTickCumulatives(tickCumulatives, tickCumulativesDefault);

        // Case for second interval check
        // price right above +3% (3,1%)
        while (tempPrice < lastPricePlus3Percent) {
            addValue += 100;
            productTemp = (tickCumulativesDefault[2] - (tickCumulativesDefault[1] - addValue)) / int256(twap2Interval);
            tempPrice = _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(productTemp)));
        }
        tickCumulatives[1] -= addValue;
        mockUniswapPool.setTickCumulative(tickCumulatives);
        addValue = 0;

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.UniV3CheckCLRSOracle__ExchangeRateZero);

        mockUniswapPool.setTickCumulative(tickCumulativesDefault);
        _assertExchangeRatesAllMethods(oracle, defaultUniV3Rate);

        resetTickCumulatives(tickCumulatives, tickCumulativesDefault);

        // price right below -3% (3.1%)
        while (tempPrice > lastPriceMinus3Percent) {
            addValue += 100;
            productTemp = (tickCumulativesDefault[2] - (tickCumulativesDefault[1] + addValue)) / int256(twap2Interval);
            tempPrice = _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(productTemp)));
        }
        tickCumulatives[1] += addValue;
        mockUniswapPool.setTickCumulative(tickCumulatives);
        addValue = 0;

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.UniV3CheckCLRSOracle__ExchangeRateZero);

        mockUniswapPool.setTickCumulative(tickCumulativesDefault);
        _assertExchangeRatesAllMethods(oracle, defaultUniV3Rate);

        resetTickCumulatives(tickCumulatives, tickCumulativesDefault);

        // Case for third interval check
        // price right above +3% (3.1%)
        while (tempPrice < lastPricePlus3Percent) {
            addValue += 100;
            productTemp = (tickCumulativesDefault[3] - (tickCumulativesDefault[2] - addValue)) / int256(twap3Interval);
            tempPrice = _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(productTemp)));
        }
        tickCumulatives[2] += addValue;
        mockUniswapPool.setTickCumulative(tickCumulatives);
        addValue = 0;

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.UniV3CheckCLRSOracle__ExchangeRateZero);

        mockUniswapPool.setTickCumulative(tickCumulativesDefault);
        _assertExchangeRatesAllMethods(oracle, defaultUniV3Rate);

        resetTickCumulatives(tickCumulatives, tickCumulativesDefault);
        // price right below -3% (3.1%)
        while (tempPrice > lastPriceMinus3Percent) {
            addValue += 100;
            productTemp = (tickCumulativesDefault[3] - (tickCumulativesDefault[2] + addValue)) / int256(twap3Interval);
            tempPrice = _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(productTemp)));
        }
        tickCumulatives[2] += addValue;
        mockUniswapPool.setTickCumulative(tickCumulatives);
        addValue = 0;

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.UniV3CheckCLRSOracle__ExchangeRateZero);

        mockUniswapPool.setTickCumulative(tickCumulativesDefault);
        _assertExchangeRatesAllMethods(oracle, defaultUniV3Rate);
    }

    function changeUniPricePlus5PercentAndCheckIfFallbackOrInvalidPriceErrorWasThrown(
        MockUniswapPool mockUniswapPool,
        uint256 exchangePrice,
        uint256 chainlinkOrRedstonePrice // if uniV3 fails, it should always use the chainlink or redstone price directly. in exception cases (when Redstone price is left to use only) a revert can be expected. Set to 0 for that.
    ) private {
        // change uniswap exchange rate out of delta to get invalid price in order to prove check price with uniswap against price from chainlink
        (int56[] memory tickCumulativesDefault, ) = IUniswapV3Pool(mockUniswapPool).observe(_getDefaultSecondAgos());
        // tick(imprecise as it's an integer) to price
        uint256 expectedRate;

        int256 productTemp;
        int56 addValue;
        uint256 exchangePricePlus5Percent = exchangePrice + (exchangePrice * 500) / 10_000;

        int56[] memory tickCumulatives = new int56[](tickCumulativesDefault.length);
        for (uint256 i = 0; i < tickCumulativesDefault.length; i++) {
            int56 temp = tickCumulativesDefault[i];
            tickCumulatives[i] = temp;
        }

        // price above delta +5%
        while (expectedRate < exchangePricePlus5Percent) {
            addValue += 100;
            productTemp = (tickCumulativesDefault[4] - (tickCumulativesDefault[3] - addValue)) / int256(1 - 0);
            expectedRate = _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(productTemp)));
        }
        tickCumulatives[3] -= addValue;
        mockUniswapPool.setTickCumulative(tickCumulatives);

        addValue = 0;

        if (chainlinkOrRedstonePrice == 0) {
            vm.expectRevert();
            // can be either
            // abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.UniV3CheckCLRSOracle__ExchangeRateZero)
            // abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.UniV3CheckCLRSOracle__InvalidPrice)
            oracle.getExchangeRateOperate();
            vm.expectRevert();
            oracle.getExchangeRateLiquidate();
            vm.expectRevert();
            oracle.getExchangeRate();
        } else {
            _assertExchangeRatesAllMethods(oracle, chainlinkOrRedstonePrice);
        }
        mockUniswapPool.setTickCumulative(tickCumulativesDefault); // reset ticks
    }

    function resetTickCumulatives(int56[] memory tickCumulatives, int56[] memory tickCumulativesDefault) private {
        for (uint256 i = 0; i < tickCumulativesDefault.length; i++) {
            int56 temp = tickCumulativesDefault[i];
            tickCumulatives[i] = temp;
        }
    }
}
