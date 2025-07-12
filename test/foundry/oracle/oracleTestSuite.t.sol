//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IRedstoneOracle } from "../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";
import { IUniswapV3Pool } from "../../../contracts/oracle/interfaces/external/IUniswapV3Pool.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";
import { IWstETH } from "../../../contracts/oracle/interfaces/external/IWstETH.sol";
import { IWeETH } from "../../../contracts/oracle/interfaces/external/IWeETH.sol";
import { IVedaAccountant } from "../../../contracts/oracle/interfaces/external/IVedaAccountant.sol";
import { UniV3CheckCLRSOracle } from "../../../contracts/oracle/oracles/uniV3CheckCLRSOracle.sol";
import { IFluidOracle } from "../../../contracts/oracle/fluidOracle.sol";
import { UniV3OracleImpl } from "../../../contracts/oracle/implementations/uniV3OracleImpl.sol";
import { ChainlinkOracleImpl } from "../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { RedstoneOracleImpl } from "../../../contracts/oracle/implementations/redstoneOracleImpl.sol";
import { Error } from "../../../contracts/oracle/error.sol";

import { FullMath } from "../../../contracts/oracle/libraries/FullMath.sol";
import { TickMath } from "../../../contracts/oracle/libraries/TickMath.sol";

import { MockChainlinkFeed } from "./mocks/mockChainlinkFeed.sol";
import { MockRedstoneFeed } from "./mocks/mockRedstoneFeed.sol";

contract OracleTestSuite is Test {
    IFluidOracle oracle;

    string infoName = "SomeName / SomeToken";

    uint8 public constant SAMPLE_TARGET_DECIMALS = 20; // sample target decimals - doesn't matter in test

    uint32[] secondsAgos_ = new uint32[](5);

    uint256[] uniswapTwapDeltas_ = new uint256[](3);

    address payable internal bob = payable(makeAddr("bob"));

    IUniswapV3Pool UNIV3_POOL = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    // USDC / ETH feed
    IChainlinkAggregatorV3 CHAINLINK_FEED = IChainlinkAggregatorV3(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);

    IChainlinkAggregatorV3 internal constant CHAINLINK_FEED_ETH_USD =
        IChainlinkAggregatorV3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    IChainlinkAggregatorV3 internal constant CHAINLINK_FEED_USDC_USD =
        IChainlinkAggregatorV3(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    IChainlinkAggregatorV3 internal constant CHAINLINK_FEED_WBTC_BTC =
        IChainlinkAggregatorV3(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23);

    IChainlinkAggregatorV3 internal constant CHAINLINK_FEED_BTC_USD =
        IChainlinkAggregatorV3(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);

    IChainlinkAggregatorV3 internal constant CHAINLINK_FEED_CRV_USD =
        IChainlinkAggregatorV3(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);

    IChainlinkAggregatorV3 internal constant CHAINLINK_FEED_SXP_USD =
        IChainlinkAggregatorV3(0xFb0CfD6c19e25DB4a08D8a204a387cEa48Cc138f);

    IChainlinkAggregatorV3 internal constant CHAINLINK_FEED_STETH_ETH =
        IChainlinkAggregatorV3(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);

    IWstETH internal constant WSTETH_TOKEN = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    IWeETH internal constant WEETH_TOKEN = IWeETH(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);

    address internal constant WEETHS_TOKEN = 0x917ceE801a67f933F2e6b33fC0cD1ED2d5909D88;
    IVedaAccountant internal constant WEETHS_ACCOUNTANT = IVedaAccountant(0xbe16605B22a7faCEf247363312121670DFe5afBE);

    // MOCKS
    MockChainlinkFeed internal MOCK_CHAINLINK_FEED;
    MockRedstoneFeed internal MOCK_REDSTONE_FEED = new MockRedstoneFeed();

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(18664561);

        MOCK_CHAINLINK_FEED = new MockChainlinkFeed(CHAINLINK_FEED);
        MOCK_REDSTONE_FEED = new MockRedstoneFeed();
    }

    function _getDefaultSecondAgosFixed() internal pure returns (uint32[5] memory) {
        uint32[5] memory secondsAgos_ = [uint32(240), 60, 15, 1, 0];
        return secondsAgos_;
    }

    function _getDefaultSecondAgos() internal pure returns (uint32[] memory) {
        uint32[] memory secondsAgos_ = new uint32[](5);
        secondsAgos_[0] = 240;
        secondsAgos_[1] = 60;
        secondsAgos_[2] = 15;
        secondsAgos_[3] = 1;
        secondsAgos_[4] = 0;
        return secondsAgos_;
    }

    function _getDefaultUniswapTwapDeltasFixed() internal pure returns (uint256[3] memory) {
        uint256[3] memory uniswapTwapDeltas_ = [uint256(300), 100, 20];
        return uniswapTwapDeltas_;
    }

    function _getDefaultUniswapTwapDeltas() internal pure returns (uint32[] memory) {
        uint32[] memory uniswapTwapDeltas_ = new uint32[](3);
        uniswapTwapDeltas_[0] = 300;
        uniswapTwapDeltas_[1] = 100;
        uniswapTwapDeltas_[2] = 20;
        return uniswapTwapDeltas_;
    }

    function _assertExchangeRatesAllMethodsNotZero(IFluidOracle oracle) internal {
        uint256 rate = oracle.getExchangeRateOperate();
        assertNotEq(rate, 0);
        rate = oracle.getExchangeRateLiquidate();
        assertNotEq(rate, 0);
        rate = oracle.getExchangeRate();
        assertNotEq(rate, 0);
    }

    function _assertExchangeRatesAllMethods(IFluidOracle oracle, uint256 expectedRate) internal {
        uint256 rate = oracle.getExchangeRateOperate();
        assertEq(rate, expectedRate);
        rate = oracle.getExchangeRateLiquidate();
        assertEq(rate, expectedRate);
        rate = oracle.getExchangeRate();
        assertEq(rate, expectedRate);
    }

    function _assertExchangeRatesAllMethodsReverts(IFluidOracle oracle, uint256 errorType) internal {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, errorType));
        oracle.getExchangeRateOperate();

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, errorType));
        oracle.getExchangeRateLiquidate();

        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, errorType));
        oracle.getExchangeRate();
    }

    function runUniV3OracleDataAsserts(
        UniV3CheckCLRSOracle oracle,
        address uniV3Pool,
        bool uniV3InvertRate,
        uint32[] memory uniV3secondsAgos,
        uint32[] memory uniV3TwapDeltas
    ) public {
        (
            IUniswapV3Pool uniV3Pool_,
            bool uniV3InvertRate_,
            uint32[] memory uniV3secondsAgos_,
            uint256[] memory uniV3TwapDeltas_,
            uint256 uniV3exchangeRateUnsafe_,
            uint256 uniV3exchangeRate_
        ) = oracle.uniV3OracleData();
        assertEq(address(uniV3Pool_), address(uniV3Pool));
        assertEq(uniV3InvertRate_, uniV3InvertRate);
        for (uint256 i = 0; i < uniV3secondsAgos_.length; i++) {
            assertEq(uniV3secondsAgos_[i], uniV3secondsAgos[i]);
        }
        for (uint256 i = 0; i < uniV3TwapDeltas_.length; i++) {
            assertEq(uniV3TwapDeltas_[i], uniV3TwapDeltas[i]);
        }
        (uint160 sqrtPriceX96_, , , , , , ) = IUniswapV3Pool(uniV3Pool).slot0();
        uint256 expectedUniV3exchangeRateUnsafe_ = uniV3InvertRate
            ? _invertUniV3Price(_getPriceFromSqrtPriceX96(sqrtPriceX96_))
            : _getPriceFromSqrtPriceX96(sqrtPriceX96_);

        assertEq(uniV3exchangeRateUnsafe_, expectedUniV3exchangeRateUnsafe_);
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(uniV3Pool).observe(uniV3secondsAgos);
        int24 product = int24(
            (tickCumulatives[uniV3TwapDeltas_.length + 1] - tickCumulatives[uniV3TwapDeltas_.length]) /
                int256(uint256(uniV3secondsAgos[3] - uniV3secondsAgos[4]))
        );
        uint256 expectedUniV3exchangeRate_ = uniV3InvertRate
            ? _invertUniV3Price(_getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(product))))
            : _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(int24(product)));
        assertEq(uniV3exchangeRate_, expectedUniV3exchangeRate_);
    }

    function runRedstoneOracleDataAsserts(
        UniV3CheckCLRSOracle oracle,
        uint256 redstoneExchangeRate,
        IRedstoneOracle redstoneOracle,
        bool redstoneInvertRate
    ) public {
        (uint256 redstoneExchangeRate_, IRedstoneOracle redstoneOracle_, bool redstoneInvertRate_) = oracle
            .redstoneOracleData();
        assertEq(redstoneExchangeRate_, redstoneExchangeRate);
        assertEq(address(redstoneOracle_), address(redstoneOracle));
        assertEq(redstoneInvertRate_, redstoneInvertRate_);
    }

    struct ChainlinkFeedData {
        IChainlinkAggregatorV3 feed;
        bool invertRate;
        uint256 exchangeRate;
    }

    function runChainlinkOracleDataAsserts(
        UniV3CheckCLRSOracle oracle,
        ChainlinkFeedData[] memory expectedData
    ) public {
        (
            uint256 chainlinkExchangeRate_,
            IChainlinkAggregatorV3 chainlinkFeed1_,
            bool chainlinkInvertRate1_,
            uint256 chainlinkExchangeRate1_,
            IChainlinkAggregatorV3 chainlinkFeed2_,
            bool chainlinkInvertRate2_,
            uint256 chainlinkExchangeRate2_,
            IChainlinkAggregatorV3 chainlinkFeed3_,
            bool chainlinkInvertRate3_,
            uint256 chainlinkExchangeRate3_
        ) = oracle.chainlinkOracleData();

        assertEq(address(expectedData[0].feed), address(chainlinkFeed1_));
        assertEq(expectedData[0].invertRate, chainlinkInvertRate1_);
        assertEq(expectedData[0].exchangeRate, chainlinkExchangeRate1_);
        assertEq(address(expectedData[1].feed), address(chainlinkFeed2_));
        assertEq(expectedData[1].invertRate, chainlinkInvertRate2_);
        assertEq(expectedData[1].exchangeRate, chainlinkExchangeRate2_);
        assertEq(address(expectedData[2].feed), address(chainlinkFeed3_));
        assertEq(expectedData[2].invertRate, chainlinkInvertRate3_);
        assertEq(expectedData[2].exchangeRate, chainlinkExchangeRate3_);
    }

    function runOracleDataAsserts(uint256 rateCheckMaxDelta, uint256 rateSource, uint256 falbackMainSource) public {
        (uint256 rateCheckMaxDelta_, uint256 rateSource_, uint256 falbackMainSource_) = UniV3CheckCLRSOracle(
            address(oracle)
        ).uniV3CheckOracleData();
        assertEq(rateCheckMaxDelta, rateCheckMaxDelta_);
        assertEq(rateSource, rateSource_);
        assertEq(falbackMainSource, falbackMainSource_);
    }

    /// @dev                  Get the price from the sqrt price in `OracleUtils.RATE_OUTPUT_DECIMALS`
    ///                       (see https://blog.uniswap.org/uniswap-v3-math-primer)
    /// @param sqrtPriceX96_  The sqrt price to convert
    // TODO: Create modular absctract contract for _getPriceFromSqrtPriceX96 and _invertUniV3Price that will be also used in uniV3OracleImpl.sol
    function _getPriceFromSqrtPriceX96(uint160 sqrtPriceX96_) internal view returns (uint256 priceX96_) {
        return
            FullMath.mulDiv(
                uint256(sqrtPriceX96_) * uint256(sqrtPriceX96_),
                10 ** 27,
                1 << 192 // 2^96 * 2
            );
    }

    /// @dev                     Invert the price
    /// @param price_            The price to invert
    /// @return invertedPrice_   The inverted price in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _invertUniV3Price(uint256 price_) internal view returns (uint256 invertedPrice_) {
        return 10 ** (27 * 2) / price_;
    }
}
