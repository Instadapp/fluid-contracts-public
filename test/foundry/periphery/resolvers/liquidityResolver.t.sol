//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

contract FluidLiquidityResolverRobustnessTest is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);

    // address that is not listed as token, user or anything
    address internal constant UNUSED_ADDRESS = 0x9aA2B2aba70EEF169a8ad6949C0B2F68e3C6e63F;
    address internal constant UNUSED_TOKEN = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant Vault_wstETH_USDC = 0x51197586F6A9e2571868b6ffaef308f3bdfEd3aE;

    FluidLiquidityResolver liquidityResolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19927377);

        liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
    }

    function test_allMethodsWithoutReverts() public {
        // this test ensures there are no reverts for any method available on the resolver

        address user_ = UNUSED_ADDRESS;
        liquidityResolver.isAuth(user_);
        liquidityResolver.isGuardian(user_);
        liquidityResolver.listedTokens();
        liquidityResolver.getRevenueCollector();
        liquidityResolver.getStatus();
        liquidityResolver.getAllOverallTokensData();

        // for listed token and configured user
        address token_ = USDC;
        user_ = Vault_wstETH_USDC;

        address[] memory tokens_ = new address[](2);
        tokens_[0] = USDC;
        tokens_[1] = WSTETH;
        address[] memory supplyTokens_ = new address[](1);
        supplyTokens_[0] = WSTETH;
        address[] memory borrowTokens_ = new address[](1);
        borrowTokens_[0] = USDC;

        _runAllResolverMethods(token_, user_, tokens_, supplyTokens_, borrowTokens_);

        // for listed token but not configured user
        user_ = UNUSED_ADDRESS;
        _runAllResolverMethods(token_, user_, tokens_, supplyTokens_, borrowTokens_);

        // for unlisted token AND not configured user
        token_ = UNUSED_TOKEN;
        user_ = UNUSED_ADDRESS;
        supplyTokens_[0] = UNUSED_TOKEN;
        borrowTokens_[0] = UNUSED_TOKEN;
        tokens_ = supplyTokens_;
        _runAllResolverMethods(token_, user_, tokens_, supplyTokens_, borrowTokens_);
    }

    function _runAllResolverMethods(
        address token_,
        address user_,
        address[] memory tokens_,
        address[] memory supplyTokens_,
        address[] memory borrowTokens_
    ) internal {
        liquidityResolver.getExchangePricesAndConfig(token_);
        liquidityResolver.getOverallTokenData(token_);
        liquidityResolver.getOverallTokensData(tokens_);
        liquidityResolver.getRateConfig(token_);
        liquidityResolver.getRevenue(token_);
        liquidityResolver.getTokenRateData(token_);
        liquidityResolver.getTokensRateData(tokens_);
        liquidityResolver.getTotalAmounts(token_);
        liquidityResolver.getUserBorrow(user_, token_);
        liquidityResolver.getUserBorrowData(user_, token_);
        liquidityResolver.getUserClass(user_);
        liquidityResolver.getUserMultipleBorrowData(user_, tokens_);
        liquidityResolver.getUserMultipleBorrowSupplyData(user_, supplyTokens_, borrowTokens_);
        liquidityResolver.getUserMultipleSupplyData(user_, tokens_);
        liquidityResolver.getUserSupply(user_, token_);
        liquidityResolver.getUserSupplyData(user_, token_);
    }
}
