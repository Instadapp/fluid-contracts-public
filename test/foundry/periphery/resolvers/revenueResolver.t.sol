//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidRevenueResolver } from "../../../../contracts/periphery/resolvers/revenue/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

contract FluidRevenueResolverRobustnessTest is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);

    // address that is not listed as token, user or anything
    address internal constant UNUSED_TOKEN = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    FluidLiquidityResolver liquidityResolver;
    FluidRevenueResolver resolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19927377);

        resolver = new FluidRevenueResolver(LIQUIDITY);
        liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
    }

    function test_allMethodsWithoutReverts() public {
        // this test ensures there are no reverts for any method available on the resolver

        resolver.getRevenueCollector();
        resolver.getRevenues();

        // for listed token
        _runAllResolverMethods(USDC);
        // for NOT listed token
        _runAllResolverMethods(UNUSED_TOKEN);
    }

    function _runAllResolverMethods(address token_) internal {
        uint256 totalAmounts_ = liquidityResolver.getTotalAmounts(token_);
        uint256 exchangePricesAndConfig_ = liquidityResolver.getExchangePricesAndConfig(token_);
        uint256 liquidityTokenBalance_ = IERC20(token_).balanceOf(address(LIQUIDITY));
        uint256 simulatedTimestamp_ = block.timestamp;

        resolver.getRevenue(token_);
        resolver.calcRevenue(totalAmounts_, exchangePricesAndConfig_, liquidityTokenBalance_);
        resolver.calcRevenueSimulatedTime(
            totalAmounts_,
            exchangePricesAndConfig_,
            liquidityTokenBalance_,
            simulatedTimestamp_
        );
    }
}
