//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FluidDexReservesResolver } from "../../../../contracts/periphery/resolvers/dexReserves/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidDexFactory } from "../../../../contracts/protocols/dex/interfaces/iDexFactory.sol";
import { IFluidDexT1 } from "../../../../contracts/protocols/dex/interfaces/iDexT1.sol";

contract FluidDexReservesResolverRobustnessTest is Test {
    IFluidDexFactory internal constant DEX_FACTORY = IFluidDexFactory(0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085);

    // address that is not listed as token, user or anything
    address internal constant UNUSED_TOKEN = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;

    address internal constant DEX_WSTETH_ETH = 0x0B1a513ee24972DAEf112bC777a5610d4325C9e7;

    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    FluidDexReservesResolver resolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21051752);

        resolver = new FluidDexReservesResolver(address(DEX_FACTORY));
    }

    function test_allMethodsWithoutReverts() public {
        // this test ensures there are no reverts for any method available on the resolver

        resolver.getPoolAddress(1);
        resolver.estimateSwapIn(DEX_WSTETH_ETH, true, 1e16, 0);
        resolver.estimateSwapOut(DEX_WSTETH_ETH, true, 1e16, 1e25);
        resolver.estimateSwapIn(DEX_WSTETH_ETH, false, 1e16, 0);
        resolver.estimateSwapOut(DEX_WSTETH_ETH, false, 1e16, 1e25);
        uint256 fee = resolver.getPoolFee(DEX_WSTETH_ETH);
        assertEq(fee, 100);
        resolver.getAllPoolAddresses();
        resolver.getAllPools();
        resolver.getAllPoolsReserves();
        resolver.getAllPoolsReservesAdjusted();

        IFluidDexT1.CollateralReserves memory collateralReserves = resolver.getDexCollateralReserves(DEX_WSTETH_ETH);
        console.log("--------------------- getDexCollateralReserves: --------------------- ");
        console.log("token0RealReserves: ", collateralReserves.token0RealReserves);
        console.log("token1RealReserves: ", collateralReserves.token1RealReserves);
        console.log("token0ImaginaryReserves: ", collateralReserves.token0ImaginaryReserves);
        console.log("token1ImaginaryReserves: ", collateralReserves.token1ImaginaryReserves);

        IFluidDexT1.DebtReserves memory debtReserves = resolver.getDexDebtReserves(DEX_WSTETH_ETH);
        console.log("--------------------- getDexDebtReserves: --------------------- ");
        console.log("token0Debt: ", debtReserves.token0Debt);
        console.log("token1Debt: ", debtReserves.token1Debt);
        console.log("token0RealReserves: ", debtReserves.token0RealReserves);
        console.log("token1RealReserves: ", debtReserves.token1RealReserves);
        console.log("token0ImaginaryReserves: ", debtReserves.token0ImaginaryReserves);
        console.log("token1ImaginaryReserves: ", debtReserves.token1ImaginaryReserves);

        collateralReserves = resolver.getDexCollateralReservesAdjusted(DEX_WSTETH_ETH);
        console.log("--------------------- getDexCollateralReservesAdjusted: --------------------- ");
        console.log("token0RealReserves: ", collateralReserves.token0RealReserves);
        console.log("token1RealReserves: ", collateralReserves.token1RealReserves);
        console.log("token0ImaginaryReserves: ", collateralReserves.token0ImaginaryReserves);
        console.log("token1ImaginaryReserves: ", collateralReserves.token1ImaginaryReserves);

        debtReserves = resolver.getDexDebtReservesAdjusted(DEX_WSTETH_ETH);
        console.log("--------------------- getDexDebtReservesAdjusted: --------------------- ");
        console.log("token0Debt: ", debtReserves.token0Debt);
        console.log("token1Debt: ", debtReserves.token1Debt);
        console.log("token0RealReserves: ", debtReserves.token0RealReserves);
        console.log("token1RealReserves: ", debtReserves.token1RealReserves);
        console.log("token0ImaginaryReserves: ", debtReserves.token0ImaginaryReserves);
        console.log("token1ImaginaryReserves: ", debtReserves.token1ImaginaryReserves);

        IFluidDexT1.PricesAndExchangePrice memory pricesAndExchangePrices = resolver.getDexPricesAndExchangePrices(
            DEX_WSTETH_ETH
        );
        console.log("--------------------- getDexPricesAndExchangePrices: --------------------- ");
        console.log("lastStoredPrice: ", pricesAndExchangePrices.lastStoredPrice);
        console.log("centerPrice: ", pricesAndExchangePrices.centerPrice);
        console.log("upperRange: ", pricesAndExchangePrices.upperRange);
        console.log("lowerRange: ", pricesAndExchangePrices.lowerRange);
        console.log("geometricMean: ", pricesAndExchangePrices.geometricMean);
        console.log("supplyToken0ExchangePrice: ", pricesAndExchangePrices.supplyToken0ExchangePrice);
        console.log("borrowToken0ExchangePrice: ", pricesAndExchangePrices.borrowToken0ExchangePrice);
        console.log("supplyToken1ExchangePrice: ", pricesAndExchangePrices.supplyToken1ExchangePrice);
        console.log("borrowToken1ExchangePrice: ", pricesAndExchangePrices.borrowToken1ExchangePrice);
        resolver.getPoolReserves(DEX_WSTETH_ETH);
        resolver.getPoolReservesAdjusted(DEX_WSTETH_ETH);
        address[] memory pools = new address[](1);
        pools[0] = DEX_WSTETH_ETH;
        resolver.getPoolsReserves(pools);
        resolver.getPoolsReservesAdjusted(pools);
    }
}
