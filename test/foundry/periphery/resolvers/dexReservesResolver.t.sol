//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FluidDexReservesResolver } from "../../../../contracts/periphery/resolvers/dexReserves/main.sol";
import { Structs } from "../../../../contracts/periphery/resolvers/dexReserves/structs.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidDexFactory } from "../../../../contracts/protocols/dex/interfaces/iDexFactory.sol";
import { IFluidDexT1 } from "../../../../contracts/protocols/dex/interfaces/iDexT1.sol";

contract FluidDexReservesResolverRobustnessTest is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidDexFactory internal constant DEX_FACTORY = IFluidDexFactory(0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085);

    // address that is not listed as token, user or anything
    address internal constant UNUSED_TOKEN = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;

    address internal constant DEX_WSTETH_ETH = 0x0B1a513ee24972DAEf112bC777a5610d4325C9e7;

    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    FluidDexReservesResolver resolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21051752);

        FluidLiquidityResolver liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(LIQUIDITY));

        resolver = new FluidDexReservesResolver(address(DEX_FACTORY), address(LIQUIDITY), address(liquidityResolver));
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
        resolver.getPoolReservesAdjusted(DEX_WSTETH_ETH);
        address[] memory pools = new address[](1);
        pools[0] = DEX_WSTETH_ETH;
        resolver.getPoolsReserves(pools);
        resolver.getPoolsReservesAdjusted(pools);
    }

    function test_getPoolReservesWhenBelowBaseLimits() public {
        console.log("--------------------- getPoolReserves (wstETH / ETH): --------------------- ");
        Structs.PoolWithReserves memory poolWithReserves = resolver.getPoolReserves(DEX_WSTETH_ETH);
        console.log("--------------------- getPoolReserves result (all below base limit): --------------------- ");
        console.log("withdrawableToken0 available: ", poolWithReserves.limits.withdrawableToken0.available);
        console.log("withdrawableToken0 expandsTo: ", poolWithReserves.limits.withdrawableToken0.expandsTo);
        console.log("withdrawableToken0 expandDuration: ", poolWithReserves.limits.withdrawableToken0.expandDuration);
        console.log("withdrawableToken1 available: ", poolWithReserves.limits.withdrawableToken1.available);
        console.log("withdrawableToken1 expandsTo: ", poolWithReserves.limits.withdrawableToken1.expandsTo);
        console.log("withdrawableToken1 expandDuration: ", poolWithReserves.limits.withdrawableToken1.expandDuration);
        console.log("borrowableToken0 available: ", poolWithReserves.limits.borrowableToken0.available);
        console.log("borrowableToken0 expandsTo: ", poolWithReserves.limits.borrowableToken0.expandsTo);
        console.log("borrowableToken0 expandDuration: ", poolWithReserves.limits.borrowableToken0.expandDuration);
        console.log("borrowableToken1 available: ", poolWithReserves.limits.borrowableToken1.available);
        console.log("borrowableToken1 expandsTo: ", poolWithReserves.limits.borrowableToken1.expandsTo);
        console.log("borrowableToken1 expandDuration: ", poolWithReserves.limits.borrowableToken1.expandDuration);
    }
}

contract FluidDexReservesResolverRobustnessTestLimitsReached is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidDexFactory internal constant DEX_FACTORY = IFluidDexFactory(0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085);

    address internal constant DEX_WSTETH_ETH = 0x0B1a513ee24972DAEf112bC777a5610d4325C9e7;

    FluidDexReservesResolver resolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21173734);

        FluidLiquidityResolver liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(LIQUIDITY));

        resolver = new FluidDexReservesResolver(address(DEX_FACTORY), address(LIQUIDITY), address(liquidityResolver));
    }

    function test_getPoolReservesWhenLimitsReached() public {
        console.log("--------------------- getPoolReserves (wstETH / ETH): --------------------- ");
        Structs.PoolWithReserves memory poolWithReserves = resolver.getPoolReserves(DEX_WSTETH_ETH);
        console.log("--------------------- getPoolReserves result (at later block): --------------------- ");
        console.log("withdrawableToken0 available: ", poolWithReserves.limits.withdrawableToken0.available);
        console.log("withdrawableToken0 expandsTo: ", poolWithReserves.limits.withdrawableToken0.expandsTo);
        console.log("withdrawableToken0 expandDuration: ", poolWithReserves.limits.withdrawableToken0.expandDuration);
        console.log("withdrawableToken1 available: ", poolWithReserves.limits.withdrawableToken1.available);
        console.log("withdrawableToken1 expandsTo: ", poolWithReserves.limits.withdrawableToken1.expandsTo);
        console.log("withdrawableToken1 expandDuration: ", poolWithReserves.limits.withdrawableToken1.expandDuration);
        console.log("borrowableToken0 available: ", poolWithReserves.limits.borrowableToken0.available);
        console.log("borrowableToken0 expandsTo: ", poolWithReserves.limits.borrowableToken0.expandsTo);
        console.log("borrowableToken0 expandDuration: ", poolWithReserves.limits.borrowableToken0.expandDuration);
        console.log("borrowableToken1 available: ", poolWithReserves.limits.borrowableToken1.available);
        console.log("borrowableToken1 expandsTo: ", poolWithReserves.limits.borrowableToken1.expandsTo);
        console.log("borrowableToken1 expandDuration: ", poolWithReserves.limits.borrowableToken1.expandDuration);
    }
}

contract FluidDexReservesResolverRobustnessTestLimitsAboveBaseBelowMax is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidDexFactory internal constant DEX_FACTORY = IFluidDexFactory(0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085);

    address internal constant DEX_WSTETH_ETH = 0x0B1a513ee24972DAEf112bC777a5610d4325C9e7;

    FluidDexReservesResolver resolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21133007);

        FluidLiquidityResolver liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(LIQUIDITY));

        resolver = new FluidDexReservesResolver(address(DEX_FACTORY), address(LIQUIDITY), address(liquidityResolver));
    }

    function test_getPoolReservesWhenAboveBaseBelowMax() public {
        console.log("--------------------- getPoolReserves (wstETH / ETH): --------------------- ");
        Structs.PoolWithReserves memory poolWithReserves = resolver.getPoolReserves(DEX_WSTETH_ETH);
        console.log("--------------------- getPoolReserves result (above base below max): --------------------- ");
        console.log("withdrawableToken0 available: ", poolWithReserves.limits.withdrawableToken0.available);
        console.log("withdrawableToken0 expandsTo: ", poolWithReserves.limits.withdrawableToken0.expandsTo);
        console.log("withdrawableToken0 expandDuration: ", poolWithReserves.limits.withdrawableToken0.expandDuration);
        console.log("withdrawableToken1 available: ", poolWithReserves.limits.withdrawableToken1.available);
        console.log("withdrawableToken1 expandsTo: ", poolWithReserves.limits.withdrawableToken1.expandsTo);
        console.log("withdrawableToken1 expandDuration: ", poolWithReserves.limits.withdrawableToken1.expandDuration);
        console.log("borrowableToken0 available: ", poolWithReserves.limits.borrowableToken0.available);
        console.log("borrowableToken0 expandsTo: ", poolWithReserves.limits.borrowableToken0.expandsTo);
        console.log("borrowableToken0 expandDuration: ", poolWithReserves.limits.borrowableToken0.expandDuration);
        console.log("borrowableToken1 available: ", poolWithReserves.limits.borrowableToken1.available);
        console.log("borrowableToken1 expandsTo: ", poolWithReserves.limits.borrowableToken1.expandsTo);
        console.log("borrowableToken1 expandDuration: ", poolWithReserves.limits.borrowableToken1.expandDuration);
    }
}

contract FluidDexReservesResolverRobustnessTestLimitsBTCUSD is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidDexFactory internal constant DEX_FACTORY = IFluidDexFactory(0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085);

    address internal constant DEX_USDC_USDT = 0x667701e51B4D1Ca244F17C78F7aB8744B4C99F9B;
    address internal constant DEX_WBTC_CBBTC = 0x3C0441B42195F4aD6aa9a0978E06096ea616CDa7;

    FluidDexReservesResolver resolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21167616);

        FluidLiquidityResolver liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(LIQUIDITY));

        resolver = new FluidDexReservesResolver(address(DEX_FACTORY), address(LIQUIDITY), address(liquidityResolver));
    }

    function test_getPoolReservesWhenAboveBaseLimitsUSDCUSDT() public {
        console.log("--------------------- getPoolReserves (USDC / USDT), only smart debt: --------------------- ");
        Structs.PoolWithReserves memory poolWithReserves = resolver.getPoolReserves(DEX_USDC_USDT);
        console.log("--------------------- getPoolReserves result: --------------------- ");
        console.log("withdrawableToken0 available: ", poolWithReserves.limits.withdrawableToken0.available);
        console.log("withdrawableToken0 expandsTo: ", poolWithReserves.limits.withdrawableToken0.expandsTo);
        console.log("withdrawableToken0 expandDuration: ", poolWithReserves.limits.withdrawableToken0.expandDuration);
        console.log("withdrawableToken1 available: ", poolWithReserves.limits.withdrawableToken1.available);
        console.log("withdrawableToken1 expandsTo: ", poolWithReserves.limits.withdrawableToken1.expandsTo);
        console.log("withdrawableToken1 expandDuration: ", poolWithReserves.limits.withdrawableToken1.expandDuration);
        console.log("borrowableToken0 available: ", poolWithReserves.limits.borrowableToken0.available);
        console.log("borrowableToken0 expandsTo: ", poolWithReserves.limits.borrowableToken0.expandsTo);
        console.log("borrowableToken0 expandDuration: ", poolWithReserves.limits.borrowableToken0.expandDuration);
        console.log("borrowableToken1 available: ", poolWithReserves.limits.borrowableToken1.available);
        console.log("borrowableToken1 expandsTo: ", poolWithReserves.limits.borrowableToken1.expandsTo);
        console.log("borrowableToken1 expandDuration: ", poolWithReserves.limits.borrowableToken1.expandDuration);
    }

    function test_getPoolReservesWhenAboveBaseLimitsWBTCCBBTC() public {
        console.log("--------------------- getPoolReserves (WBTC / CBBTC): --------------------- ");
        Structs.PoolWithReserves memory poolWithReserves = resolver.getPoolReserves(DEX_WBTC_CBBTC);
        console.log("--------------------- getPoolReserves result: --------------------- ");
        console.log("withdrawableToken0 available: ", poolWithReserves.limits.withdrawableToken0.available);
        console.log("withdrawableToken0 expandsTo: ", poolWithReserves.limits.withdrawableToken0.expandsTo);
        console.log("withdrawableToken0 expandDuration: ", poolWithReserves.limits.withdrawableToken0.expandDuration);
        console.log("withdrawableToken1 available: ", poolWithReserves.limits.withdrawableToken1.available);
        console.log("withdrawableToken1 expandsTo: ", poolWithReserves.limits.withdrawableToken1.expandsTo);
        console.log("withdrawableToken1 expandDuration: ", poolWithReserves.limits.withdrawableToken1.expandDuration);
        console.log("borrowableToken0 available: ", poolWithReserves.limits.borrowableToken0.available);
        console.log("borrowableToken0 expandsTo: ", poolWithReserves.limits.borrowableToken0.expandsTo);
        console.log("borrowableToken0 expandDuration: ", poolWithReserves.limits.borrowableToken0.expandDuration);
        console.log("borrowableToken1 available: ", poolWithReserves.limits.borrowableToken1.available);
        console.log("borrowableToken1 expandsTo: ", poolWithReserves.limits.borrowableToken1.expandsTo);
        console.log("borrowableToken1 expandDuration: ", poolWithReserves.limits.borrowableToken1.expandDuration);
    }
}

contract FluidDexReservesResolverEstimatesTest is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidDexFactory internal constant DEX_FACTORY = IFluidDexFactory(0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085);

    address internal constant DEX_USDC_USDT = 0x667701e51B4D1Ca244F17C78F7aB8744B4C99F9B;

    FluidDexReservesResolver resolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21173330);

        FluidLiquidityResolver liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(LIQUIDITY));

        resolver = new FluidDexReservesResolver(address(DEX_FACTORY), address(LIQUIDITY), address(liquidityResolver));
    }

    function test_estimateIn() public {
        uint256 result_ = resolver.estimateSwapIn(DEX_USDC_USDT, true, 1e9, 0);
        console.log("RESULT: estimateSwapIn output amount within limits (1k USDT out):", result_);

        console.log("\n\n ---------------------- \n\n");

        result_ = resolver.estimateSwapIn(DEX_USDC_USDT, true, 4e9, 0);
        console.log("RESULT: estimateSwapIn output amount TOO BIG for limits (4k USDT out):", result_);
    }

    function test_estimateOut() public {
        uint256 result_ = resolver.estimateSwapOut(DEX_USDC_USDT, true, 1e9, 0);
        console.log("RESULT: estimateSwapOut output amount within limits (1k USDT out):", result_);

        console.log("\n\n ---------------------- \n\n");

        result_ = resolver.estimateSwapOut(DEX_USDC_USDT, true, 4e9, 0);
        console.log("RESULT: estimateSwapOut output amount TOO BIG for limits (4k USDT out):", result_);
    }
}
