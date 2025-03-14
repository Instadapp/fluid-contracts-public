//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

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

import { FluidOracleL2 } from "../../../contracts/oracle/fluidOracleL2.sol";
import { OracleL2TestSuite } from "./oracleL2TestSuite.t.sol";
import { OracleTestSuite } from "../oracle/oracleTestSuite.t.sol";
import { MockChainlinkSequencerUptimeFeed } from "./mocks/mockChainlinkSequencerUptimeFeed.sol";

import { UniV3CheckCLRSOracleL2 } from "../../../contracts/oracle/oraclesL2/uniV3CheckCLRSOracleL2.sol";
import { UniV3CheckCLRSOracleTest } from "../oracle/uniV3CheckCLRSOracle.t.sol";

import "forge-std/console2.sol";

contract UniV3CheckCLRSOracleL2Test is UniV3CheckCLRSOracleTest, OracleL2TestSuite {
    function setUp() public virtual override(UniV3CheckCLRSOracleTest, OracleTestSuite) {
        super.setUp();

        mockFeed = new MockChainlinkSequencerUptimeFeed();

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

        oracleL2 = FluidOracleL2(address(oracle));
    }

    function _createOracle(
        UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams memory params
    ) internal virtual override returns (IFluidOracle) {
        return new UniV3CheckCLRSOracleL2(infoName, SAMPLE_TARGET_DECIMALS, params, address(mockFeed));
    }
}
