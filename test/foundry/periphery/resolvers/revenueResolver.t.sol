//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidRevenueResolver } from "../../../../contracts/periphery/resolvers/revenue/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";

contract FluidRevenueResolverRobustnessTest is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);

    // address that is not listed as token, user or anything
    address internal constant UNUSED_TOKEN = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal constant VAULT_FACTORY = 0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d;

    address internal constant VAULT_WEETH_WSTETH = 0x40D9b8417E6E1DcD358f04E3328bCEd061018A82;

    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    FluidLiquidityResolver liquidityResolver;
    FluidRevenueResolver resolver;
    FluidVaultResolver vaultResolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19927377);

        resolver = new FluidRevenueResolver(LIQUIDITY);
        liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);

        vaultResolver = new FluidVaultResolver(VAULT_FACTORY, address(liquidityResolver));
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
        uint256 simulatedTimestamp_ = block.timestamp;

        {
            uint256 liquidityTokenBalance_ = IERC20(token_).balanceOf(address(LIQUIDITY));
            resolver.getRevenue(token_);
            resolver.calcRevenue(totalAmounts_, exchangePricesAndConfig_, liquidityTokenBalance_);
            resolver.calcRevenueSimulatedTime(
                totalAmounts_,
                exchangePricesAndConfig_,
                liquidityTokenBalance_,
                simulatedTimestamp_
            );
            resolver.calcLiquidityExchangePricesSimulatedTime(exchangePricesAndConfig_, simulatedTimestamp_);
        }

        {
            uint256 vaultVariables2_ = vaultResolver.getVaultVariables2Raw(VAULT_WEETH_WSTETH);
            uint256 vaultRates_ = vaultResolver.getRateRaw(VAULT_WEETH_WSTETH);
            uint256 liquiditySupplyExchangePricesAndConfig_ = liquidityResolver.getExchangePricesAndConfig(WEETH);
            uint256 liquidityBorrowExchangePricesAndConfig_ = liquidityResolver.getExchangePricesAndConfig(WSTETH);
            resolver.calcVaultExchangePricesSimulatedTime(
                vaultVariables2_,
                vaultRates_,
                liquiditySupplyExchangePricesAndConfig_,
                liquidityBorrowExchangePricesAndConfig_,
                simulatedTimestamp_
            );
        }

        resolver.calcLiquidityTotalAmountsSimulatedTime(totalAmounts_, exchangePricesAndConfig_, simulatedTimestamp_);

        {
            uint256 userSupplyData_ = liquidityResolver.getUserSupply(VAULT_WEETH_WSTETH, WEETH);
            uint256 userBorrowData_ = liquidityResolver.getUserBorrow(VAULT_WEETH_WSTETH, WSTETH);
            uint256 liquiditySupplyExchangePricesAndConfig_ = liquidityResolver.getExchangePricesAndConfig(WEETH);
            uint256 liquidityBorrowExchangePricesAndConfig_ = liquidityResolver.getExchangePricesAndConfig(WSTETH);
            resolver.calcLiquidityUserAmountsSimulatedTime(
                userSupplyData_,
                userBorrowData_,
                liquiditySupplyExchangePricesAndConfig_,
                liquidityBorrowExchangePricesAndConfig_,
                simulatedTimestamp_
            );
        }
    }
}
