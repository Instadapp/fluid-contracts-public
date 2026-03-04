//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { DexSmartColCLOracle } from "../../../../contracts/oracle/oracles/dex/dexSmartColCLOracle.sol";
import { ErrorTypes } from "../../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../../contracts/oracle/error.sol";
import { IFluidOracle } from "../../../../contracts/oracle/fluidOracle.sol";

import { ChainlinkOracleImpl } from "../../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { ChainlinkStructs } from "../../../../contracts/oracle/implementations/structs.sol";
import { IChainlinkAggregatorV3 } from "../../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";

import { MockChainlinkFeed } from "../mocks/mockChainlinkFeed.sol";

import "forge-std/console2.sol";

contract DexSmartColCLOracleTest is Test {
    uint8 public constant SAMPLE_TARGET_DECIMALS = 20; // sample target decimals - doesn't matter in test

    address internal constant DEX_USDC_ETH = 0x2886a01a0645390872a9eb99dAe1283664b0c524;
    address internal constant UniV3CheckCLRSOracle_ETH_USDC = 0x5b2860C6D6F888319C752aaCDaf8165C21095E3a;

    // USDC / ETH feed
    IChainlinkAggregatorV3 CHAINLINK_FEED = IChainlinkAggregatorV3(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);

    DexSmartColCLOracle oracle;

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
    }

    function test_getExchangeRate_USDC() public {
        oracle = new DexSmartColCLOracle(
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

        // set 3030_860405935798293 USDC per ETH as price, CL oracle must always set token1/token0, so ETH per USDC.
        // ChainlinkOracleImpl scales to ETH / USDC scaled to 1e27, result is 329939312955999000000000000000000000.
        // adjust decimals to be in expected rate as used internally in Fluid Dex, e.g. 325151118254488344854528.
        // so set via multiplier & divisor to divide 1e12
        MOCK_CHAINLINK_FEED.setExchangeRate(int256(329939312955999));

        (uint256 chainlinkExchangeRate, , , , , , , , , ) = oracle.chainlinkOracleData();
        console2.log("Chainlink Exchange Rate:", chainlinkExchangeRate);
        assertEq(chainlinkExchangeRate, 329939312955999000000000000000000000); // 1e54/329939312955999000000000000000000000 = 3030860405935805802

        // new col reserves at this price
        // got newCollateralReserves_ token0Reserves_ 130287811784749
        // got newCollateralReserves_ token1Reserves_ 25224776754

        // "token0RealReserves": "145091098000000", ~145.09$
        // "token1RealReserves": "20376157484", ~61.74$
        // sum should be ~206.82$ (for old reserves)

        // total col reserves = 25224776754 * 1e6 * 3030860405935798293 / 1e27 + 130287811784749 / 1e6 = 206740588
        // 206740588 USDC / 100000000000000000000 shares = 2067405 USDC / SHARE
        // scaled to 1e27 -> 2067405880000000

        (uint256 operateRate, uint256 liquidateRate) = oracle.dexSmartColSharesRates();
        console2.log("Operate shares Rate:", operateRate);
        console2.log("Liquidate shares Rate:", liquidateRate);

        assertEq(oracle.getExchangeRateOperate(), 2067405880000000);
    }
}
