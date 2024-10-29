//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { IUniswapV3Pool } from "../../../../contracts/oracle/interfaces/external/IUniswapV3Pool.sol";

//
contract MockUniswapPool is IUniswapV3Pool {
    IUniswapV3Pool uniPool;
    int56[] mockedTickCumulatives;

    constructor(IUniswapV3Pool originalUniswap_, uint32[] memory secondsAgos_) {
        uniPool = originalUniswap_;
        (mockedTickCumulatives, ) = originalUniswap_.observe(secondsAgos_);
    }

    function setTickCumulative(int56[] calldata mockedTickCumulatives_) external {
        mockedTickCumulatives = mockedTickCumulatives_;
    }

    function factory() external view returns (address) {
        return uniPool.factory();
    }

    function token0() external view returns (address) {
        return uniPool.token0();
    }

    function token1() external view returns (address) {
        return uniPool.token1();
    }

    function fee() external view returns (uint24) {
        return uniPool.fee();
    }

    function tickSpacing() external view returns (int24) {
        return uniPool.tickSpacing();
    }

    function maxLiquidityPerTick() external view returns (uint128) {
        return uniPool.maxLiquidityPerTick();
    }

    function observe(
        uint32[] calldata secondsAgos
    ) external view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
        tickCumulatives = mockedTickCumulatives;
        return (tickCumulatives, secondsPerLiquidityCumulativeX128s);
    }

    function snapshotCumulativesInside(
        int24 tickLower,
        int24 tickUpper
    ) external view returns (int56 tickCumulativeInside, uint160 secondsPerLiquidityInsideX128, uint32 secondsInside) {
        return uniPool.snapshotCumulativesInside(tickLower, tickUpper);
    }

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return uniPool.slot0();
    }

    function feeGrowthGlobal0X128() external view returns (uint256) {
        return uniPool.feeGrowthGlobal0X128();
    }

    function feeGrowthGlobal1X128() external view returns (uint256) {
        return uniPool.feeGrowthGlobal1X128();
    }

    function protocolFees() external view returns (uint128 token0, uint128 token1) {
        return uniPool.protocolFees();
    }

    function liquidity() external view returns (uint128) {
        return uniPool.liquidity();
    }

    function ticks(
        int24 tick
    )
        external
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        )
    {
        return uniPool.ticks(tick);
    }

    function tickBitmap(int16 wordPosition) external view returns (uint256) {
        return uniPool.tickBitmap(wordPosition);
    }

    function positions(
        bytes32 key
    )
        external
        view
        returns (
            uint128 _liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        return uniPool.positions(key);
    }

    function observations(
        uint256 index
    )
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        )
    {
        return uniPool.observations(index);
    }
}
