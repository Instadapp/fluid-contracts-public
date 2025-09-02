//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IAllowanceTransfer } from "../../../../contracts/protocols/lending/interfaces/permit2/iAllowanceTransfer.sol";
import { MockERC20Permit } from "../../utils/mocks/MockERC20Permit.sol";
import { fToken } from "../../../../contracts/protocols/lending/fToken/main.sol";
import { fTokenNativeUnderlying } from "../../../../contracts/protocols/lending/fToken/nativeUnderlying/fTokenNativeUnderlying.sol";
import { fTokenWithInterestTestBase } from "../../lending/fTokenWithInterest.t.sol";
import { FluidLendingResolver } from "../../../../contracts/periphery/resolvers/lending/main.sol";
import { IFluidLendingFactory } from "../../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { IFluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { IFToken } from "../../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { Structs as FluidLendingResolverStructs } from "../../../../contracts/periphery/resolvers/lending/structs.sol";
import { Structs as FluidLiquidityResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { LendingRewardsRateMockModel } from "../../lending/mocks/rewardsMock.sol";

abstract contract FluidLendingResolverTestBase is fTokenWithInterestTestBase {
    FluidLendingResolver lendingResolver;

    function setUp() public virtual override {
        // native underlying tests must run in fork for WETH support
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        super.setUp();
        FluidLiquidityResolver liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(address(liquidity)));
        lendingResolver = new FluidLendingResolver(
            IFluidLendingFactory(address(factory)),
            IFluidLiquidityResolver(address(liquidityResolver))
        );

        // setting configs in order to make LiquidityCalcs working

        _setDefaultRateDataV2(address(liquidity), admin, address(USDC));
        _setDefaultRateDataV2(address(liquidity), admin, address(WETH_ADDRESS));
        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](2);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 1000, // 10%
            threshold: 100, // 1%
            maxUtilization: 1e4 // 100%
        });
        tokenConfigs_[1] = AdminModuleStructs.TokenConfig({
            token: address(WETH_ADDRESS),
            fee: 1000, // 10%
            threshold: 100, // 1%
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs_);

        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);
        vm.prank(admin);
        factory.setFTokenCreationCode("NativeUnderlying", type(fTokenNativeUnderlying).creationCode);

        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(lendingFToken));
        _setUserAllowancesDefault(address(liquidity), admin, address(WETH_ADDRESS), address(lendingFToken));
    }
}

contract FluidLendingResolverTest is FluidLendingResolverTestBase {
    function test_deployment() public {
        assertEq(address(lendingResolver.LENDING_FACTORY()), address(factory));
    }

    function test_getAllFTokens() public {
        address[] memory fTokens_ = lendingResolver.getAllFTokens();

        assertEq(fTokens_.length, 1);
        assertEq(fTokens_[0], address(lendingFToken));
    }

    function test_getAllFTokensMultiple() public {
        address token1 = address(lendingFToken);
        vm.prank(admin);
        address token2 = factory.createToken(address(WETH_ADDRESS), "NativeUnderlying", true);

        address[2] memory createdTokens = [token1, token2];
        address[] memory allTokens = lendingResolver.getAllFTokens();

        assertEq(createdTokens.length, allTokens.length);

        for (uint256 i = 0; i < createdTokens.length; i++) {
            assertEq(createdTokens[i], allTokens[i]);
        }
    }

    function test_computeFToken() public {
        address underlying = lendingFToken.asset();
        address expectedAddress = lendingResolver.computeFToken(underlying, "fToken");

        assertEq(expectedAddress, address(lendingFToken));
    }

    function test_getFTokenDetails() public {
        FluidLendingResolverStructs.FTokenDetails memory details = lendingResolver.getFTokenDetails(lendingFToken);
        (, uint256 rewardsRate_) = lendingResolver.getFTokenRewards(lendingFToken);

        FluidLendingResolverStructs.FTokenDetails memory expectedDetails = FluidLendingResolverStructs.FTokenDetails({
            eip2612Deposits: false,
            isNativeUnderlying: false,
            name: "Fluid USDC",
            symbol: "fUSDC",
            decimals: 6,
            asset: address(USDC),
            totalAssets: 0,
            totalSupply: 0,
            convertToShares: 1e6,
            convertToAssets: 1e6,
            tokenAddress: address(lendingFToken),
            rewardsRate: rewardsRate_,
            supplyRate: 0,
            rebalanceDifference: 0,
            liquidityUserSupplyData: FluidLiquidityResolverStructs.UserSupplyData({
                modeWithInterest: true,
                supply: 0,
                withdrawalLimit: 0,
                withdrawableUntilLimit: 0,
                withdrawable: 0,
                expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
                expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
                baseWithdrawalLimit: DEFAULT_BASE_WITHDRAWAL_LIMIT_AFTER_BIGMATH,
                lastUpdateTimestamp: 0
            })
        });

        assertFTokenDetails(details, expectedDetails);

        // do a deposit to get total supply up etc.
        uint256 usdcBalanceBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        assertEqDecimal(shares, DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEq(usdcBalanceBefore - underlying.balanceOf(alice), DEFAULT_AMOUNT);

        // assert values change as expected
        details = lendingResolver.getFTokenDetails(lendingFToken);
        FluidLendingResolverStructs.FTokenDetails memory expectedDetailsAfterDeposit = FluidLendingResolverStructs
            .FTokenDetails({
                eip2612Deposits: false,
                isNativeUnderlying: false,
                name: "Fluid USDC",
                symbol: "fUSDC",
                decimals: 6,
                asset: address(USDC),
                totalAssets: DEFAULT_AMOUNT,
                totalSupply: DEFAULT_AMOUNT,
                convertToShares: 1e6,
                convertToAssets: 1e6,
                tokenAddress: address(lendingFToken),
                rewardsRate: rewardsRate_,
                supplyRate: 0,
                rebalanceDifference: 0,
                liquidityUserSupplyData: FluidLiquidityResolverStructs.UserSupplyData({
                    modeWithInterest: true,
                    supply: DEFAULT_AMOUNT,
                    withdrawalLimit: 0,
                    withdrawableUntilLimit: DEFAULT_AMOUNT,
                    withdrawable: DEFAULT_AMOUNT,
                    expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
                    expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
                    baseWithdrawalLimit: DEFAULT_BASE_WITHDRAWAL_LIMIT_AFTER_BIGMATH,
                    lastUpdateTimestamp: block.timestamp
                })
            });

        assertFTokenDetails(details, expectedDetailsAfterDeposit);
    }

    function test_getFTokenInternalData() public {
        (
            IFluidLiquidity liquidity_,
            IFluidLendingFactory lendingFactory_,
            IFluidLendingRewardsRateModel lendingRewardsRateModel_,
            IAllowanceTransfer permit2_,
            address rebalancer_,
            bool rewardsActive_,
            uint256 liquidityBalance_,
            uint256 liquidityExchangePrice_,
            uint256 tokenExchangePrice_
        ) = lendingResolver.getFTokenInternalData(lendingFToken);

        assertEq(address(liquidity_), address(liquidity));
        assertEq(address(lendingFactory_), address(factory));
        assertEq(address(lendingRewardsRateModel_), address(rewards));
        assertEq(address(permit2_), address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
        assertEq(address(rebalancer_), admin);
        assertEq(rewardsActive_, true);
        assertEq(liquidityBalance_, 0);
        assertEq(liquidityExchangePrice_, EXCHANGE_PRICES_PRECISION);
        assertEq(tokenExchangePrice_, EXCHANGE_PRICES_PRECISION);

        {
            // do a deposit to get total supply up etc.
            uint256 usdcBalanceBefore = underlying.balanceOf(alice);
            vm.prank(alice);
            uint256 shares = lendingFToken.deposit(DEFAULT_AMOUNT, alice);
            assertEqDecimal(shares, DEFAULT_AMOUNT, DEFAULT_DECIMALS);
            assertEqDecimal(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT, DEFAULT_DECIMALS);
            assertEq(usdcBalanceBefore - underlying.balanceOf(alice), DEFAULT_AMOUNT);
        }

        // assert values change as expected
        (
            ,
            ,
            ,
            ,
            rebalancer_,
            rewardsActive_,
            liquidityBalance_,
            liquidityExchangePrice_,
            tokenExchangePrice_
        ) = lendingResolver.getFTokenInternalData(lendingFToken);

        assertEq(address(rebalancer_), admin);
        assertEq(rewardsActive_, true);
        assertEq(liquidityBalance_, DEFAULT_AMOUNT);
        assertEq(liquidityExchangePrice_, EXCHANGE_PRICES_PRECISION);
        assertEq(tokenExchangePrice_, EXCHANGE_PRICES_PRECISION);

        vm.prank(alice);
        lendingFToken.withdraw(DEFAULT_AMOUNT, alice, alice);
    }

    function test_getFTokenDetailsTypeNativeUnderlying() public {
        vm.prank(admin);
        address token = factory.createToken(address(WETH_ADDRESS), "NativeUnderlying", true);

        FluidLendingResolverStructs.FTokenDetails memory details = lendingResolver.getFTokenDetails(IFToken(token));

        assertEq(details.eip2612Deposits, false);
        assertEq(details.isNativeUnderlying, true);
    }

    function test_getFTokenDetailsWithYield() public {
        // todo
    }

    function test_getFTokensEntireData() public {
        vm.prank(admin);
        factory.createToken(address(WETH_ADDRESS), "NativeUnderlying", true);
        vm.prank(admin);
        factory.createToken(address(DAI), "fToken", false);

        FluidLendingResolverStructs.FTokenDetails[] memory allDetails = lendingResolver.getFTokensEntireData();

        address[] memory allTokens = lendingResolver.getAllFTokens();
        assertEq(allTokens.length, allDetails.length);

        for (uint256 i = 0; i < allDetails.length; i++) {
            FluidLendingResolverStructs.FTokenDetails memory tokenDetails = lendingResolver.getFTokenDetails(
                IFToken(allTokens[i])
            );
            FluidLendingResolverStructs.FTokenDetails memory expectedTokenDetails = FluidLendingResolverStructs
                .FTokenDetails({
                    eip2612Deposits: allDetails[i].eip2612Deposits,
                    isNativeUnderlying: allDetails[i].isNativeUnderlying,
                    name: allDetails[i].name,
                    symbol: allDetails[i].symbol,
                    decimals: allDetails[i].decimals,
                    asset: allDetails[i].asset,
                    totalAssets: allDetails[i].totalAssets,
                    totalSupply: allDetails[i].totalSupply,
                    convertToShares: allDetails[i].convertToShares,
                    convertToAssets: allDetails[i].convertToAssets,
                    tokenAddress: allDetails[i].tokenAddress,
                    rewardsRate: allDetails[i].rewardsRate,
                    supplyRate: allDetails[i].supplyRate,
                    rebalanceDifference: allDetails[i].rebalanceDifference,
                    liquidityUserSupplyData: allDetails[i].liquidityUserSupplyData
                });

            assertFTokenDetails(tokenDetails, expectedTokenDetails);
        }
    }

    function test_getFTokenRewards() public {
        (IFluidLendingRewardsRateModel rewardsRateModel_, uint256 rewardsRate_) = lendingResolver.getFTokenRewards(
            lendingFToken
        );
        assertEq(address(rewardsRateModel_), address(rewards));
        assertEq(rewardsRate_, 20 * 1e12); // 20%
    }

    function test_getFTokenRewardsRateModelConfig() public {
        uint256 startTime_ = block.timestamp + 10 days;
        uint256 endTime_ = startTime_ + 73 days;

        FluidLendingRewardsRateModel rateModel = new FluidLendingRewardsRateModel(
            alice,
            address(lendingFToken),
            address(0),
            address(0),
            10,
            1 ether,
            73 days,
            startTime_
        );
        vm.warp(startTime_);

        vm.prank(admin);
        factory.setAuth(alice, true);
        vm.prank(alice);
        lendingFToken.updateRewards(rateModel);

        (
            uint256 actualDuration_,
            uint256 actualStartTime_,
            uint256 actualEndTime_,
            uint256 actualStartTvl_,
            uint256 actualMaxRate_,
            uint256 actualRewardAmount_,
            address actualInitiator_
        ) = lendingResolver.getFTokenRewardsRateModelConfig(lendingFToken);

        assertEq(actualDuration_, 73 days);
        assertEq(actualStartTime_, startTime_);
        assertEq(actualEndTime_, endTime_);
        assertEq(actualStartTvl_, 10);
        assertEq(actualRewardAmount_, 1 ether);
        assertEq(actualMaxRate_, 50 * 1e12);
        assertEq(actualInitiator_, alice);
    }

    function test_getUserPosition() public {
        FluidLendingResolverStructs.UserPosition memory userPosition = lendingResolver.getUserPosition(
            lendingFToken,
            alice
        );

        // alice expected balance after executing actions in setup (we are minting twice 1e50 and supplying once 1000 * 1e6)
        uint256 aliceBalance = 199999999999999999999999999999999999999999999999999999999999000000000;
        FluidLendingResolverStructs.UserPosition memory expectedPosition = FluidLendingResolverStructs.UserPosition({
            fTokenShares: 0,
            underlyingAssets: 0,
            underlyingBalance: aliceBalance,
            allowance: type(uint256).max
        });

        assertUserPosition(userPosition, expectedPosition);

        // do a deposit to get supply of alice up etc.
        uint256 usdcBalanceBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        assertEqDecimal(shares, DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEq(usdcBalanceBefore - underlying.balanceOf(alice), DEFAULT_AMOUNT);

        // assert values change as expected
        userPosition = lendingResolver.getUserPosition(lendingFToken, alice);

        FluidLendingResolverStructs.UserPosition memory expectedPositionAfter = FluidLendingResolverStructs
            .UserPosition({
                fTokenShares: shares,
                underlyingAssets: DEFAULT_AMOUNT,
                underlyingBalance: aliceBalance - DEFAULT_AMOUNT,
                allowance: type(uint256).max
            });

        assertUserPosition(userPosition, expectedPositionAfter);
    }

    function test_getUserPositions() public {
        address user = address(alice);
        address[] memory allTokens = lendingResolver.getAllFTokens();
        FluidLendingResolverStructs.FTokenDetailsUserPosition[] memory positions = lendingResolver.getUserPositions(
            address(alice)
        );
        FluidLendingResolverStructs.FTokenDetails[] memory allDetails = lendingResolver.getFTokensEntireData();

        assertEq(allTokens.length, allDetails.length);
        assertEq(positions.length, allDetails.length);

        for (uint256 i = 0; i < allDetails.length; i++) {
            FluidLendingResolverStructs.UserPosition memory userPosition = lendingResolver.getUserPosition(
                IFToken(allTokens[i]),
                user
            );

            FluidLendingResolverStructs.FTokenDetails memory expectedTokenDetails = FluidLendingResolverStructs
                .FTokenDetails({
                    eip2612Deposits: allDetails[i].eip2612Deposits,
                    isNativeUnderlying: allDetails[i].isNativeUnderlying,
                    name: allDetails[i].name,
                    symbol: allDetails[i].symbol,
                    decimals: allDetails[i].decimals,
                    asset: allDetails[i].asset,
                    totalAssets: allDetails[i].totalAssets,
                    totalSupply: allDetails[i].totalSupply,
                    convertToShares: allDetails[i].convertToShares,
                    convertToAssets: allDetails[i].convertToAssets,
                    tokenAddress: allDetails[i].tokenAddress,
                    rewardsRate: allDetails[i].rewardsRate,
                    supplyRate: allDetails[i].supplyRate,
                    rebalanceDifference: allDetails[i].rebalanceDifference,
                    liquidityUserSupplyData: allDetails[i].liquidityUserSupplyData
                });

            assertFTokenDetails(positions[i].fTokenDetails, expectedTokenDetails);

            assertUserPosition(positions[i].userPosition, userPosition);
        }
    }

    function test_getPreviews() public {
        (
            uint256 previewDeposit_,
            uint256 previewMint_,
            uint256 previewWithdraw_,
            uint256 previewRedeem_
        ) = lendingResolver.getPreviews(lendingFToken, DEFAULT_AMOUNT, DEFAULT_AMOUNT);

        assertEq(previewDeposit_, DEFAULT_AMOUNT);
        assertEq(previewMint_, DEFAULT_AMOUNT);
        assertEq(previewWithdraw_, DEFAULT_AMOUNT);
        assertEq(previewRedeem_, DEFAULT_AMOUNT);

        // do a deposit to get rates to change
        uint256 usdcBalanceBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        assertEqDecimal(shares, DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEq(usdcBalanceBefore - underlying.balanceOf(alice), DEFAULT_AMOUNT);

        // warp 1 year time to get rewards to increase value of shares
        // shares will be worth 1.2 times now because rewards rate is 20%
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // assert values change as expected
        (previewDeposit_, previewMint_, previewWithdraw_, previewRedeem_) = lendingResolver.getPreviews(
            lendingFToken,
            DEFAULT_AMOUNT,
            DEFAULT_AMOUNT
        );
        assertEq(previewMint_, (DEFAULT_AMOUNT * 12) / 10);
        assertEq(previewRedeem_, (DEFAULT_AMOUNT * 12) / 10);

        // token deposit is worth 20% less in shares. so DEFAULT_AMOUNT = 120% of x
        // so x = 1000000000 / 120% = 833333333
        assertEq(previewDeposit_, 833333333);
        assertEq(previewWithdraw_, 833333334); // rounded up
    }

    // Utility function to assert FTokenDetails

    function assertFTokenDetails(
        FluidLendingResolverStructs.FTokenDetails memory details,
        FluidLendingResolverStructs.FTokenDetails memory expectedDetails
    ) internal {
        assertEq(details.eip2612Deposits, expectedDetails.eip2612Deposits);
        assertEq(details.isNativeUnderlying, expectedDetails.isNativeUnderlying);
        assertEq(details.name, expectedDetails.name);
        assertEq(details.symbol, expectedDetails.symbol);
        assertEq(details.decimals, expectedDetails.decimals);
        assertEq(details.asset, expectedDetails.asset);
        assertEq(details.totalAssets, expectedDetails.totalAssets);
        assertEq(details.totalSupply, expectedDetails.totalSupply);
        assertEq(details.convertToShares, expectedDetails.convertToShares);
        assertEq(details.convertToAssets, expectedDetails.convertToAssets);
        assertEq(details.tokenAddress, expectedDetails.tokenAddress);
        assertEq(details.rewardsRate, expectedDetails.rewardsRate);
        assertEq(details.supplyRate, expectedDetails.supplyRate);
        assertEq(details.rebalanceDifference, expectedDetails.rebalanceDifference);
        assertEq(details.liquidityUserSupplyData.supply, expectedDetails.liquidityUserSupplyData.supply);
        assertEq(
            details.liquidityUserSupplyData.withdrawalLimit,
            expectedDetails.liquidityUserSupplyData.withdrawalLimit
        );
        assertEq(details.liquidityUserSupplyData.withdrawable, expectedDetails.liquidityUserSupplyData.withdrawable);
        assertEq(details.liquidityUserSupplyData.expandPercent, expectedDetails.liquidityUserSupplyData.expandPercent);
        assertEq(
            details.liquidityUserSupplyData.expandDuration,
            expectedDetails.liquidityUserSupplyData.expandDuration
        );
        assertEq(
            details.liquidityUserSupplyData.baseWithdrawalLimit,
            expectedDetails.liquidityUserSupplyData.baseWithdrawalLimit
        );
        assertEq(
            details.liquidityUserSupplyData.lastUpdateTimestamp,
            expectedDetails.liquidityUserSupplyData.lastUpdateTimestamp
        );
    }

    // Utility function to assert UserPosition
    function assertUserPosition(
        FluidLendingResolverStructs.UserPosition memory actualPosition,
        FluidLendingResolverStructs.UserPosition memory expectedPosition
    ) internal {
        assertEq(actualPosition.fTokenShares, expectedPosition.fTokenShares);
        assertEq(actualPosition.underlyingAssets, expectedPosition.underlyingAssets);
        assertEq(actualPosition.underlyingBalance, expectedPosition.underlyingBalance);
        assertEq(actualPosition.allowance, expectedPosition.allowance);
    }
}

contract FluidLendingResolverEIP2612Test is FluidLendingResolverTestBase {
    function _createUnderlying() internal virtual override returns (address) {
        MockERC20Permit mockERC20 = new MockERC20Permit("TestPermitToken", "TestPRM");

        return address(mockERC20);
    }

    function test_getFTokenDetailsTypeEIP2612Deposits() public {
        FluidLendingResolverStructs.FTokenDetails memory details = lendingResolver.getFTokenDetails(lendingFToken);

        assertEq(details.eip2612Deposits, true);
    }
}

contract FluidLendingResolverRobustnessTest is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidLendingFactory internal constant LENDING_FACTORY =
        IFluidLendingFactory(0x54B91A0D94cb471F37f949c60F7Fa7935b551D03);

    address internal constant ALLOWED_DEPLOYER = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e; // team multisig is an allowed deployer

    address internal constant weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant FUSDC = 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33;
    address newfToken;

    FluidLendingResolver lendingResolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19927377);

        // deploy the lending resolver
        FluidLiquidityResolver liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
        lendingResolver = new FluidLendingResolver(
            LENDING_FACTORY,
            IFluidLiquidityResolver(address(liquidityResolver))
        );

        // create a new fToken, without configuring it at Liquidity
        vm.prank(ALLOWED_DEPLOYER);
        newfToken = LENDING_FACTORY.createToken(weETH, "fToken", false);
    }

    function test_allMethodsWithoutReverts_generalMethods() public {
        // this test ensures there are no reverts for any method available on the resolver
        lendingResolver.getFTokensEntireData();

        lendingResolver.computeFToken(weETH, "fToken");
        lendingResolver.getAllFTokens();
        lendingResolver.getAllFTokenTypes();
        lendingResolver.getFTokensEntireData();
        lendingResolver.isLendingFactoryAuth(ALLOWED_DEPLOYER);
        lendingResolver.isLendingFactoryDeployer(ALLOWED_DEPLOYER);
    }

    function test_allMethodsWithoutReverts_existingToken() public {
        _runAllResolverMethods(IFToken(FUSDC), 1e10, ALLOWED_DEPLOYER);
    }

    function test_allMethodsWithoutReverts_newToken() public {
        _runAllResolverMethods(IFToken(newfToken), 1e18, ALLOWED_DEPLOYER);
    }

    function _runAllResolverMethods(IFToken fToken_, uint256 previewsAmount_, address user_) internal {
        lendingResolver.getFTokenDetails(fToken_);
        lendingResolver.getFTokenInternalData(fToken_);
        lendingResolver.getFTokenRewards(fToken_);
        lendingResolver.getFTokenRewardsRateModelConfig(fToken_);
        lendingResolver.getPreviews(fToken_, previewsAmount_, previewsAmount_);
        lendingResolver.getUserPosition(fToken_, user_);
        lendingResolver.getUserPositions(user_);
    }
}
