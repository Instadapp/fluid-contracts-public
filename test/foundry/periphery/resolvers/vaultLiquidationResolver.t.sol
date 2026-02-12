//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FluidVaultLiquidationResolver } from "../../../../contracts/periphery/resolvers/vaultLiquidation/main.sol";
import { Structs } from "../../../../contracts/periphery/resolvers/vaultLiquidation/structs.sol";
import { IFluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/iVaultResolver.sol";
import { IFluidVaultFactory } from "../../../../contracts/protocols/vault/interfaces/iVaultFactory.sol";
import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";
import { IFluidVaultT1 } from "../../../../contracts/protocols/vault/interfaces/iVaultT1.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

abstract contract FluidVaultLiquidationResolverBaseTest is Test {
    IFluidVaultFactory internal constant VAULT_FACTORY = IFluidVaultFactory(0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d);

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address internal constant VAULT_ETH_USDC_V1 = 0xeAbBfca72F8a8bf14C4ac59e69ECB2eB69F0811C;
    address internal constant VAULT_ETH_USDC_V2 = 0x0C8C77B7FF4c2aF7F6CEBbe67350A490E3DD6cB3;
    address internal constant VAULT_WSTETH_ETH_V1 = 0xA0F83Fc5885cEBc0420ce7C7b139Adc80c4F4D91;
    address internal constant VAULT_WSTETH_ETH_V2 = 0x82B27fA821419F5689381b565a8B0786aA2548De;
    address internal constant VAULT_WSTETH_USDC_V1 = 0x51197586F6A9e2571868b6ffaef308f3bdfEd3aE;
    address internal constant VAULT_WSTETH_USDC_V2 = 0x1982CC7b1570C2503282d0A0B41F69b3B28fdcc3;
    address internal constant VAULT_WSTETH_USDT_V1 = 0x1c2bB46f36561bc4F05A94BD50916496aa501078;
    address internal constant VAULT_WSTETH_USDT_V2 = 0xb4F3bf2d96139563777C0231899cE06EE95Cc946;
    address internal constant Vault_WBTC_USDC = 0x6F72895Cf6904489Bcd862c941c3D02a3eE4f03e;
    address internal constant Vault_WEETH_WBTC = 0xF74cb9D69ada3559903149CFD60fD57cEAF95F30;
    address internal constant Vault_WEETH_WSTETH_V1 = 0x40D9b8417E6E1DcD358f04E3328bCEd061018A82;

    address internal constant WSTETH_WHALE = 0x5fEC2f34D80ED82370F733043B6A536d7e9D7f8d;
    address internal constant USDC_WHALE = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;

    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);

    FluidVaultResolver vaultResolver;

    address bob = makeAddr("bob");

    FluidVaultLiquidationResolver resolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(20326410);

        // deploy resolver dependencies newest state
        FluidLiquidityResolver liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
        vaultResolver = new FluidVaultResolver(address(VAULT_FACTORY), address(liquidityResolver));

        // constructor params
        // IFluidVaultResolver vaultResolver_
        resolver = new FluidVaultLiquidationResolver(
            IFluidVaultResolver(address(vaultResolver)),
            IFluidLiquidity(address(LIQUIDITY))
        );

        // add some test deposit to WSTETH_USDC vault v2
        vm.startPrank(WSTETH_WHALE);
        IERC20(WSTETH).approve(VAULT_WSTETH_USDC_V2, 140 ether);
        IFluidVaultT1(VAULT_WSTETH_USDC_V2).operate(0, 45 ether, 100_000 * 1e6, WSTETH_WHALE);
        IFluidVaultT1(VAULT_WSTETH_USDC_V2).operate(0, 40 ether, 100_000 * 1e6, WSTETH_WHALE);
        IFluidVaultT1(VAULT_WSTETH_USDC_V2).operate(0, 35 ether, 100_000 * 1e6, WSTETH_WHALE);
        vm.stopPrank();

        // set withdraw limit to very wide
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](3);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(VAULT_WSTETH_USDC_V2),
            token: address(WSTETH),
            mode: 1,
            expandPercent: 10000,
            expandDuration: 10,
            baseWithdrawalLimit: 30 ether
        });
        userSupplyConfigs_[1] = AdminModuleStructs.UserSupplyConfig({
            user: address(VAULT_WSTETH_USDC_V1),
            token: address(WSTETH),
            mode: 1,
            expandPercent: 10000,
            expandDuration: 10,
            baseWithdrawalLimit: 30 ether
        });
        userSupplyConfigs_[2] = AdminModuleStructs.UserSupplyConfig({
            user: address(Vault_WEETH_WSTETH_V1),
            token: address(WEETH),
            mode: 1,
            expandPercent: 10000,
            expandDuration: 10,
            baseWithdrawalLimit: 30 ether
        });
        vm.prank(GOVERNANCE);
        FluidLiquidityAdminModule(address(LIQUIDITY)).updateUserSupplyConfigs(userSupplyConfigs_);
    }

    function _reduceVaultOraclePrice(address vault, uint256 reductionInPercent) internal {
        FluidVaultResolver.VaultEntireData memory vaultData = vaultResolver.getVaultEntireData(vault);

        uint256 currentOraclePrice = vaultData.configs.oraclePriceLiquidate;
        console2.log("current oracle price", currentOraclePrice);

        // set a mockOracle as oracle and move positions into liquidation territory
        MockOracle oracle = new MockOracle();

        vm.prank(GOVERNANCE);
        FluidVaultT1Admin(vault).updateOracle(address(oracle));

        oracle.setPrice((currentOraclePrice * (100 - reductionInPercent)) / 100); // simulate price drop
        vaultData = vaultResolver.getVaultEntireData(vault);
        assertLt(vaultData.configs.oraclePriceLiquidate, currentOraclePrice);
        console2.log("reduced oracle price to", vaultData.configs.oraclePriceLiquidate);
    }

    function _logSwaps(Structs.Swap[] memory swaps) internal {
        console2.log("---------------- LOGGING SWAPS ---------------------");
        for (uint256 i; i < swaps.length; i++) {
            console2.log("______swap ", i);
            console2.log("protocol ", swaps[i].path.protocol);
            console2.log("tokenIn ", swaps[i].path.tokenIn);
            console2.log("tokenOut ", swaps[i].path.tokenOut);
            console2.log("inAmt ", swaps[i].data.inAmt);
            console2.log("outAmt ", swaps[i].data.outAmt);
            console2.log("withAbsorb ", swaps[i].data.withAbsorb);
            console2.log("ratio ", swaps[i].data.ratio);
        }
        console2.log("----------------------------------------------------");
    }

    function _reduceWstethUsdcVaultsOraclePrices() internal {
        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_WSTETH_USDC_V1, 40);

        vm.prank(bob);
        IFluidVaultT1(VAULT_WSTETH_USDC_V1).absorb();

        _reduceVaultOraclePrice(VAULT_WSTETH_USDC_V2, 40);
    }

    function _verifyWeethWstethVaultSwap(Structs.Swap[] memory swaps) internal {
        // there should only be the without absorb swap if both swaps have the same amount.
        // running liquidate() with absorb in that case only costs extra gas.
        assertEq(swaps.length, 1);
        assertEq(swaps[0].path.protocol, Vault_WEETH_WSTETH_V1);
        assertEq(swaps[0].path.tokenIn, WSTETH);
        assertEq(swaps[0].path.tokenOut, WEETH);
        assertEq(swaps[0].data.inAmt, 169195126140259605);
        assertEq(swaps[0].data.outAmt, 192159919887094343);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[0].data.ratio, 1135729641099693097261946426);
    }

    function _verifyWstethUsdcVaultsSwapRawAfterOracleChange(Structs.Swap[] memory swaps) internal {
        assertEq(swaps.length, 4);

        for (uint256 i; i < swaps.length; i++) {
            assertEq(swaps[i].path.tokenIn, USDC);
            assertEq(swaps[i].path.tokenOut, WSTETH);
            if (i < 2) {
                assertEq(swaps[i].path.protocol, VAULT_WSTETH_USDC_V1);
            } else {
                assertEq(swaps[i].path.protocol, VAULT_WSTETH_USDC_V2);
            }
        }

        assertEq(swaps[0].data.inAmt, 17171641401);
        assertEq(swaps[0].data.outAmt, 7239874247595527378);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[0].data.ratio, 421618066585871593580688704949272426);

        assertEq(swaps[1].data.inAmt, 3820174809043);
        assertEq(swaps[1].data.outAmt, 1314649452937157229549);
        assertEq(swaps[1].data.withAbsorb, true);
        assertEq(swaps[1].data.ratio, 344133323382259781987783593432549988);

        assertEq(swaps[2].data.inAmt, 51053932660);
        assertEq(swaps[2].data.outAmt, 21525260378992474409);
        assertEq(swaps[2].data.withAbsorb, false);
        assertEq(swaps[2].data.ratio, 421618066571729489349782834143770345);

        assertEq(swaps[3].data.inAmt, 251312581922);
        assertEq(swaps[3].data.outAmt, 96525260378634413804);
        assertEq(swaps[3].data.withAbsorb, true);
        assertEq(swaps[3].data.ratio, 384084472175742488824964259562409064);
    }

    function _verifyWstethUsdcVaultsSwapAfterOracleChange(Structs.Swap[] memory swaps) internal {
        assertEq(swaps.length, 2);

        for (uint256 i; i < swaps.length; i++) {
            assertEq(swaps[i].path.tokenIn, USDC);
            assertEq(swaps[i].path.tokenOut, WSTETH);
            if (i == 0) {
                assertEq(swaps[i].path.protocol, VAULT_WSTETH_USDC_V1);
            } else {
                assertEq(swaps[i].path.protocol, VAULT_WSTETH_USDC_V2);
            }
        }

        // only the better ratio swap should be returned

        assertEq(swaps[0].data.inAmt, 17171641401);
        assertEq(swaps[0].data.outAmt, 7239874247595527378);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[0].data.ratio, 421618066585871593580688704949272426);

        assertEq(swaps[1].data.inAmt, 51053932660);
        assertEq(swaps[1].data.outAmt, 21525260378992474409);
        assertEq(swaps[1].data.withAbsorb, false);
        assertEq(swaps[1].data.ratio, 421618066571729489349782834143770345);
    }
}

contract FluidVaultLiquidationResolverPathsTest is FluidVaultLiquidationResolverBaseTest {
    function test_deployment() public {
        assertEq(address(resolver.VAULT_RESOLVER()), address(vaultResolver));
        assertEq(address(resolver.LIQUIDITY()), address(LIQUIDITY));
    }

    function test_getAllSwapPaths() public {
        Structs.SwapPath[] memory paths = resolver.getAllSwapPaths();
        assertEq(paths.length, 26);
        assertEq(paths[0].protocol, VAULT_ETH_USDC_V1);
        assertEq(paths[0].tokenIn, USDC);
        assertEq(paths[0].tokenOut, ETH);

        assertEq(paths[2].protocol, VAULT_WSTETH_ETH_V1);
        assertEq(paths[2].tokenIn, ETH);
        assertEq(paths[2].tokenOut, WSTETH);

        assertEq(paths[4].protocol, VAULT_WSTETH_USDT_V1);
        assertEq(paths[4].tokenIn, USDT);
        assertEq(paths[4].tokenOut, WSTETH);

        assertEq(paths[14].protocol, VAULT_WSTETH_USDT_V2);
        assertEq(paths[14].tokenIn, USDT);
        assertEq(paths[14].tokenOut, WSTETH);

        assertEq(paths[20].protocol, Vault_WBTC_USDC);
        assertEq(paths[20].tokenIn, USDC);
        assertEq(paths[20].tokenOut, WBTC);

        assertEq(paths[25].protocol, Vault_WEETH_WBTC);
        assertEq(paths[25].tokenIn, WBTC);
        assertEq(paths[25].tokenOut, WEETH);
    }

    function test_getSwapPaths() public {
        Structs.SwapPath[] memory paths = resolver.getSwapPaths(USDC, ETH);
        assertEq(paths.length, 2);
        assertEq(paths[0].protocol, VAULT_ETH_USDC_V1);
        assertEq(paths[0].tokenIn, USDC);
        assertEq(paths[0].tokenOut, ETH);
        assertEq(paths[1].protocol, VAULT_ETH_USDC_V2);
        assertEq(paths[1].tokenIn, USDC);
        assertEq(paths[1].tokenOut, ETH);

        paths = resolver.getSwapPaths(ETH, WSTETH);
        assertEq(paths.length, 2);
        assertEq(paths[0].protocol, VAULT_WSTETH_ETH_V1);
        assertEq(paths[0].tokenIn, ETH);
        assertEq(paths[0].tokenOut, WSTETH);
        assertEq(paths[1].protocol, VAULT_WSTETH_ETH_V2);
        assertEq(paths[1].tokenIn, ETH);
        assertEq(paths[1].tokenOut, WSTETH);

        paths = resolver.getSwapPaths(USDT, WSTETH);
        assertEq(paths.length, 2);
        assertEq(paths[0].protocol, VAULT_WSTETH_USDT_V1);
        assertEq(paths[0].tokenIn, USDT);
        assertEq(paths[0].tokenOut, WSTETH);
        assertEq(paths[1].protocol, VAULT_WSTETH_USDT_V2);
        assertEq(paths[1].tokenIn, USDT);
        assertEq(paths[1].tokenOut, WSTETH);

        paths = resolver.getSwapPaths(USDC, WBTC);
        assertEq(paths.length, 1);
        assertEq(paths[0].protocol, Vault_WBTC_USDC);
        assertEq(paths[0].tokenIn, USDC);
        assertEq(paths[0].tokenOut, WBTC);

        paths = resolver.getSwapPaths(WSTETH, USDC);
        assertEq(paths.length, 0);
    }

    function test_getAnySwapPaths() public {
        address[] memory tokensIn = new address[](3);
        tokensIn[0] = ETH;
        tokensIn[1] = WSTETH;
        tokensIn[2] = USDC;
        address[] memory tokensOut = new address[](3);
        tokensOut[0] = ETH;
        tokensOut[1] = WSTETH;
        tokensOut[2] = USDC;
        // should find routes: USDC -> ETH, USDC -> WSTETH, ETH -> WSTETH
        Structs.SwapPath[] memory paths = resolver.getAnySwapPaths(tokensIn, tokensOut);
        assertEq(paths.length, 6);
        assertEq(paths[0].protocol, VAULT_ETH_USDC_V1);
        assertEq(paths[0].tokenIn, USDC);
        assertEq(paths[0].tokenOut, ETH);
        assertEq(paths[1].protocol, VAULT_WSTETH_ETH_V1);
        assertEq(paths[1].tokenIn, ETH);
        assertEq(paths[1].tokenOut, WSTETH);
        assertEq(paths[2].protocol, VAULT_WSTETH_USDC_V1);
        assertEq(paths[2].tokenIn, USDC);
        assertEq(paths[2].tokenOut, WSTETH);
        assertEq(paths[3].protocol, VAULT_ETH_USDC_V2);
        assertEq(paths[3].tokenIn, USDC);
        assertEq(paths[3].tokenOut, ETH);
        assertEq(paths[4].protocol, VAULT_WSTETH_ETH_V2);
        assertEq(paths[4].tokenIn, ETH);
        assertEq(paths[4].tokenOut, WSTETH);
        assertEq(paths[5].protocol, VAULT_WSTETH_USDC_V2);
        assertEq(paths[5].tokenIn, USDC);
        assertEq(paths[5].tokenOut, WSTETH);
    }
}

contract FluidVaultLiquidationResolverSwapDataTest is FluidVaultLiquidationResolverBaseTest {
    function test_getVaultSwapData() public {
        // assert initially no swap available
        (Structs.SwapData memory withoutAbsorb, Structs.SwapData memory withAbsorb) = resolver.getVaultSwapData(
            VAULT_ETH_USDC_V1
        );
        assertEq(withoutAbsorb.inAmt, 0);
        assertEq(withoutAbsorb.outAmt, 0);
        assertEq(withoutAbsorb.withAbsorb, false);
        assertEq(withoutAbsorb.ratio, 0);
        assertEq(withAbsorb.inAmt, 0);
        assertEq(withAbsorb.outAmt, 0);
        assertEq(withAbsorb.withAbsorb, true);
        assertEq(withAbsorb.ratio, 0);

        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_ETH_USDC_V1, 32);
        vm.prank(bob);
        IFluidVaultT1(VAULT_ETH_USDC_V1).absorb();

        (withoutAbsorb, withAbsorb) = resolver.getVaultSwapData(VAULT_ETH_USDC_V1);
        assertEq(withoutAbsorb.inAmt, 51205646760); // 51_205,646760 USDC
        assertEq(withoutAbsorb.outAmt, 22014968952384651082); // 22,014968952384651082 ETH
        assertEq(withoutAbsorb.withAbsorb, false);
        assertEq(withoutAbsorb.ratio, 429932445840757330608121392274354704);
        assertEq(withAbsorb.inAmt, 4641172548729); // 4_641_172,548729 USDC
        assertEq(withAbsorb.outAmt, 1666692729041985099641); // 1666,692729041985099641 ETH
        assertEq(withAbsorb.withAbsorb, true);
        assertEq(withAbsorb.ratio, 359110270420438096692909385775085614);
    }

    function test_getVaultsSwapData() public {
        address[] memory vaults = new address[](2);
        vaults[0] = VAULT_ETH_USDC_V1;
        vaults[1] = VAULT_WSTETH_USDC_V2;

        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_ETH_USDC_V1, 32);
        vm.prank(bob);
        IFluidVaultT1(VAULT_ETH_USDC_V1).absorb();

        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_WSTETH_USDC_V2, 40);

        (Structs.SwapData[] memory withoutAbsorb, Structs.SwapData[] memory withAbsorb) = resolver.getVaultsSwapData(
            vaults
        );
        assertEq(withoutAbsorb[0].inAmt, 51205646760); // 51_205,646760 USDC
        assertEq(withoutAbsorb[0].outAmt, 22014968952384651082); // 22,014968952384651082 ETH
        assertEq(withoutAbsorb[0].withAbsorb, false);
        assertEq(withoutAbsorb[0].ratio, 429932445840757330608121392274354704);
        assertEq(withAbsorb[0].inAmt, 4641172548729); // 4_641_172,548729 USDC
        assertEq(withAbsorb[0].outAmt, 1666692729041985099641); // 1666,692729041985099641 ETH
        assertEq(withAbsorb[0].withAbsorb, true);
        assertEq(withAbsorb[0].ratio, 359110270420438096692909385775085614);

        assertEq(withoutAbsorb[1].inAmt, 51053932660);
        assertEq(withoutAbsorb[1].outAmt, 21525260378992474409);
        assertEq(withoutAbsorb[1].withAbsorb, false);
        assertEq(withoutAbsorb[1].ratio, 421618066571729489349782834143770345);
        assertEq(withAbsorb[1].inAmt, 251312581922);
        assertEq(withAbsorb[1].outAmt, 96525260378634413804);
        assertEq(withAbsorb[1].withAbsorb, true);
        assertEq(withAbsorb[1].ratio, 384084472175742488824964259562409064);
    }

    function test_getAllVaultsSwapData() public {
        (Structs.SwapData[] memory withoutAbsorb, Structs.SwapData[] memory withAbsorb) = resolver
            .getAllVaultsSwapData();
        assertEq(withoutAbsorb.length, 26);
        assertEq(withAbsorb.length, 26);
        for (uint256 i; i < withoutAbsorb.length; i++) {
            if (i == 5) {
                assertEq(withoutAbsorb[i].inAmt, 169195126140259605);
                assertEq(withoutAbsorb[i].outAmt, 192159919887094343);
                assertEq(withoutAbsorb[i].withAbsorb, false);
                assertEq(withoutAbsorb[i].ratio, 1135729641099693097261946426);
            } else {
                assertEq(withoutAbsorb[i].inAmt, 0);
                assertEq(withoutAbsorb[i].outAmt, 0);
                assertEq(withoutAbsorb[i].withAbsorb, false);
                assertEq(withoutAbsorb[i].ratio, 0);
            }
        }
        for (uint256 i; i < withAbsorb.length; i++) {
            if (i == 5) {
                assertEq(withAbsorb[i].inAmt, 169195126140259605);
                assertEq(withAbsorb[i].outAmt, 192159919887094343);
                assertEq(withAbsorb[i].withAbsorb, true);
                assertEq(withAbsorb[i].ratio, 1135729641099693097261946426);
            } else {
                assertEq(withAbsorb[i].inAmt, 0);
                assertEq(withAbsorb[i].outAmt, 0);
                assertEq(withAbsorb[i].withAbsorb, true);
                assertEq(withAbsorb[i].ratio, 0);
            }
        }

        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_ETH_USDC_V1, 32);
        vm.prank(bob);
        IFluidVaultT1(VAULT_ETH_USDC_V1).absorb();

        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_WSTETH_USDC_V2, 40);

        (withoutAbsorb, withAbsorb) = resolver.getAllVaultsSwapData();
        assertEq(withoutAbsorb.length, 26);
        assertEq(withAbsorb.length, 26);
        uint256 nonZeroSwaps;
        for (uint256 i; i < withoutAbsorb.length; i++) {
            if (withoutAbsorb[i].inAmt > 0) {
                nonZeroSwaps++;
            }
        }
        assertEq(nonZeroSwaps, 3);

        nonZeroSwaps = 0;
        for (uint256 i; i < withAbsorb.length; i++) {
            if (withAbsorb[i].inAmt > 0) {
                nonZeroSwaps++;
            }
        }
        assertEq(nonZeroSwaps, 3);
    }
}

contract FluidVaultLiquidationResolverSwapsTest is FluidVaultLiquidationResolverBaseTest {
    function test_getSwapForProtocol() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        // assert initially no swap available
        Structs.Swap memory swap = resolver.getSwapForProtocol(VAULT_WSTETH_USDC_V1);
        assertEq(swap.data.inAmt, 0);
        swap = resolver.getSwapForProtocol(VAULT_WSTETH_USDC_V2);
        assertEq(swap.data.inAmt, 0);

        _reduceWstethUsdcVaultsOraclePrices();

        Structs.Swap memory swap1 = resolver.getSwapForProtocol(VAULT_WSTETH_USDC_V1);
        assertGt(swap1.data.inAmt, 0);
        Structs.Swap memory swap2 = resolver.getSwapForProtocol(VAULT_WSTETH_USDC_V2);
        assertGt(swap2.data.inAmt, 0);

        Structs.Swap[] memory swaps = new Structs.Swap[](2);
        swaps[0] = swap1;
        swaps[1] = swap2;

        _verifyWstethUsdcVaultsSwapAfterOracleChange(swaps);
    }

    function test_getSwapForProtocol_WhenWithAbsorbLiquidityZero() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        Structs.Swap memory swap = resolver.getSwapForProtocol(Vault_WEETH_WSTETH_V1);
        Structs.Swap[] memory swaps = new Structs.Swap[](1);
        swaps[0] = swap;
        _verifyWeethWstethVaultSwap(swaps);
    }

    function test_getVaultsSwapRaw() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        address[] memory vaults = new address[](2);
        vaults[0] = VAULT_WSTETH_USDC_V1;
        vaults[1] = VAULT_WSTETH_USDC_V2;

        // assert initially no swap available
        Structs.Swap[] memory swaps = resolver.getVaultsSwapRaw(vaults);
        assertEq(swaps.length, 0);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getVaultsSwapRaw(vaults);
        _verifyWstethUsdcVaultsSwapRawAfterOracleChange(swaps);
    }

    function test_getVaultsSwap() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        address[] memory vaults = new address[](2);
        vaults[0] = VAULT_WSTETH_USDC_V1;
        vaults[1] = VAULT_WSTETH_USDC_V2;

        // assert initially no swap available
        Structs.Swap[] memory swaps = resolver.getVaultsSwap(vaults);
        assertEq(swaps.length, 0);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getVaultsSwap(vaults);
        _verifyWstethUsdcVaultsSwapAfterOracleChange(swaps);
    }

    function test_test_getVaultsSwapRaw_WhenWithAbsorbLiquidityZero() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        address[] memory vaults = new address[](3);
        vaults[0] = VAULT_WSTETH_USDC_V1;
        vaults[1] = VAULT_WSTETH_USDC_V2;
        vaults[2] = Vault_WEETH_WSTETH_V1;

        Structs.Swap[] memory swaps = resolver.getVaultsSwapRaw(vaults);
        _verifyWeethWstethVaultSwap(swaps);
    }

    function test_test_getVaultsSwap_WhenWithAbsorbLiquidityZero() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        address[] memory vaults = new address[](3);
        vaults[0] = VAULT_WSTETH_USDC_V1;
        vaults[1] = VAULT_WSTETH_USDC_V2;
        vaults[2] = Vault_WEETH_WSTETH_V1;

        Structs.Swap[] memory swaps = resolver.getVaultsSwap(vaults);
        _verifyWeethWstethVaultSwap(swaps);
    }

    function test_getAllVaultsSwapRaw() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        Structs.Swap[] memory swaps = resolver.getAllVaultsSwapRaw();
        _verifyWeethWstethVaultSwap(swaps);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getAllVaultsSwapRaw();
        assertEq(swaps.length, 5);

        Structs.Swap[] memory weethWstethSwaps = new Structs.Swap[](1);
        weethWstethSwaps[0] = swaps[2];
        _verifyWeethWstethVaultSwap(weethWstethSwaps);

        Structs.Swap[] memory wstethUsdcSwaps = new Structs.Swap[](4);
        wstethUsdcSwaps = new Structs.Swap[](4);
        wstethUsdcSwaps[0] = swaps[0];
        wstethUsdcSwaps[1] = swaps[1];
        wstethUsdcSwaps[2] = swaps[3];
        wstethUsdcSwaps[3] = swaps[4];
        _verifyWstethUsdcVaultsSwapRawAfterOracleChange(wstethUsdcSwaps);
    }

    function test_getAllVaultsSwap() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        Structs.Swap[] memory swaps = resolver.getAllVaultsSwap();
        _verifyWeethWstethVaultSwap(swaps);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getAllVaultsSwap();
        assertEq(swaps.length, 3);

        Structs.Swap[] memory weethWstethSwaps = new Structs.Swap[](1);
        weethWstethSwaps[0] = swaps[1];
        _verifyWeethWstethVaultSwap(weethWstethSwaps);

        Structs.Swap[] memory wstethUsdcSwaps = new Structs.Swap[](2);
        wstethUsdcSwaps[0] = swaps[0];
        wstethUsdcSwaps[1] = swaps[2];
        _verifyWstethUsdcVaultsSwapAfterOracleChange(wstethUsdcSwaps);
    }

    function test_getSwapsForPathsRaw_all() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        Structs.SwapPath[] memory paths = resolver.getAllSwapPaths();
        Structs.Swap[] memory swaps = resolver.getSwapsForPathsRaw(paths);
        _verifyWeethWstethVaultSwap(swaps);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getSwapsForPathsRaw(paths);
        assertEq(swaps.length, 5);

        Structs.Swap[] memory weethWstethSwaps = new Structs.Swap[](1);
        weethWstethSwaps[0] = swaps[2];
        _verifyWeethWstethVaultSwap(weethWstethSwaps);

        Structs.Swap[] memory wstethUsdcSwaps = new Structs.Swap[](4);
        wstethUsdcSwaps = new Structs.Swap[](4);
        wstethUsdcSwaps[0] = swaps[0];
        wstethUsdcSwaps[1] = swaps[1];
        wstethUsdcSwaps[2] = swaps[3];
        wstethUsdcSwaps[3] = swaps[4];
        _verifyWstethUsdcVaultsSwapRawAfterOracleChange(wstethUsdcSwaps);
    }

    function test_getSwapsForPaths_all() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        Structs.SwapPath[] memory paths = resolver.getAllSwapPaths();
        Structs.Swap[] memory swaps = resolver.getSwapsForPaths(paths);
        _verifyWeethWstethVaultSwap(swaps);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getSwapsForPaths(paths);
        assertEq(swaps.length, 3);

        Structs.Swap[] memory weethWstethSwaps = new Structs.Swap[](1);
        weethWstethSwaps[0] = swaps[1];
        _verifyWeethWstethVaultSwap(weethWstethSwaps);

        Structs.Swap[] memory wstethUsdcSwaps = new Structs.Swap[](2);
        wstethUsdcSwaps[0] = swaps[0];
        wstethUsdcSwaps[1] = swaps[2];
        _verifyWstethUsdcVaultsSwapAfterOracleChange(wstethUsdcSwaps);
    }

    function test_getSwapsForPathsRaw_specific() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        Structs.SwapPath[] memory paths = resolver.getSwapPaths(WSTETH, WEETH);
        Structs.Swap[] memory swaps = resolver.getSwapsForPathsRaw(paths);
        _verifyWeethWstethVaultSwap(swaps);

        _reduceWstethUsdcVaultsOraclePrices();

        paths = resolver.getSwapPaths(USDC, WSTETH);
        swaps = resolver.getSwapsForPathsRaw(paths);
        _verifyWstethUsdcVaultsSwapRawAfterOracleChange(swaps);
    }

    function test_getSwapsForPaths_specific() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        Structs.SwapPath[] memory paths = resolver.getSwapPaths(WSTETH, WEETH);
        Structs.Swap[] memory swaps = resolver.getSwapsForPaths(paths);
        _verifyWeethWstethVaultSwap(swaps);

        _reduceWstethUsdcVaultsOraclePrices();

        paths = resolver.getSwapPaths(USDC, WSTETH);
        swaps = resolver.getSwapsForPaths(paths);
        _verifyWstethUsdcVaultsSwapAfterOracleChange(swaps);
    }

    function test_getSwapsForPathsRaw_any() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        address[] memory tokensIn = new address[](3);
        tokensIn[0] = ETH;
        tokensIn[1] = WSTETH;
        tokensIn[2] = USDC;
        address[] memory tokensOut = new address[](4);
        tokensOut[0] = ETH;
        tokensOut[1] = WSTETH;
        tokensOut[2] = USDC;
        tokensOut[3] = WEETH;

        Structs.SwapPath[] memory paths = resolver.getAnySwapPaths(tokensIn, tokensOut);
        Structs.Swap[] memory swaps = resolver.getSwapsForPathsRaw(paths);
        _verifyWeethWstethVaultSwap(swaps);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getSwapsForPathsRaw(paths);
        assertEq(swaps.length, 5);

        Structs.Swap[] memory weethWstethSwaps = new Structs.Swap[](1);
        weethWstethSwaps[0] = swaps[2];
        _verifyWeethWstethVaultSwap(weethWstethSwaps);

        Structs.Swap[] memory wstethUsdcSwaps = new Structs.Swap[](4);
        wstethUsdcSwaps = new Structs.Swap[](4);
        wstethUsdcSwaps[0] = swaps[0];
        wstethUsdcSwaps[1] = swaps[1];
        wstethUsdcSwaps[2] = swaps[3];
        wstethUsdcSwaps[3] = swaps[4];
        _verifyWstethUsdcVaultsSwapRawAfterOracleChange(wstethUsdcSwaps);
    }

    function test_getSwapsForPaths_any() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        address[] memory tokensIn = new address[](3);
        tokensIn[0] = ETH;
        tokensIn[1] = WSTETH;
        tokensIn[2] = USDC;
        address[] memory tokensOut = new address[](4);
        tokensOut[0] = ETH;
        tokensOut[1] = WSTETH;
        tokensOut[2] = USDC;
        tokensOut[3] = WEETH;

        Structs.SwapPath[] memory paths = resolver.getAnySwapPaths(tokensIn, tokensOut);
        Structs.Swap[] memory swaps = resolver.getSwapsForPaths(paths);
        _verifyWeethWstethVaultSwap(swaps);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getSwapsForPaths(paths);
        assertEq(swaps.length, 3);

        Structs.Swap[] memory weethWstethSwaps = new Structs.Swap[](1);
        weethWstethSwaps[0] = swaps[1];
        _verifyWeethWstethVaultSwap(weethWstethSwaps);

        Structs.Swap[] memory wstethUsdcSwaps = new Structs.Swap[](2);
        wstethUsdcSwaps[0] = swaps[0];
        wstethUsdcSwaps[1] = swaps[2];
        _verifyWstethUsdcVaultsSwapAfterOracleChange(wstethUsdcSwaps);
    }

    function test_getSwapsRaw() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        Structs.Swap[] memory swaps = resolver.getSwapsRaw(WSTETH, WEETH);
        _verifyWeethWstethVaultSwap(swaps);

        // assert initially no swap available for USDC -> WSTETH
        swaps = resolver.getSwapsRaw(USDC, WSTETH);
        assertEq(swaps.length, 0);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getSwapsRaw(USDC, WSTETH);
        _verifyWstethUsdcVaultsSwapRawAfterOracleChange(swaps);
    }

    function test_getSwaps() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        Structs.Swap[] memory swaps = resolver.getSwaps(WSTETH, WEETH);
        _verifyWeethWstethVaultSwap(swaps);

        // assert initially no swap available for USDC -> WSTETH
        swaps = resolver.getSwaps(USDC, WSTETH);
        assertEq(swaps.length, 0);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getSwaps(USDC, WSTETH);
        _verifyWstethUsdcVaultsSwapAfterOracleChange(swaps);
    }

    function test_getSwapsRaw_USDC_ETH() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        // assert initially no swap available
        Structs.Swap[] memory swaps = resolver.getSwapsRaw(USDC, WSTETH);
        assertEq(swaps.length, 0);

        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_WSTETH_USDC_V1, 10);

        // check that liquidation is now available and swap data is as expected.
        // should have only without absorb swap here
        swaps = resolver.getSwapsRaw(USDC, WSTETH);
        assertEq(swaps.length, 1);
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[0].path.tokenIn, USDC);
        assertEq(swaps[0].path.tokenOut, WSTETH);
        assertEq(swaps[0].data.inAmt, 651750586205);
        assertEq(swaps[0].data.outAmt, 183193214693624384067);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[0].data.ratio, 281078711045460031704030862966763290);

        // reduce oracle price more, into absorb territory, run absorb and check again
        _reduceVaultOraclePrice(VAULT_WSTETH_USDC_V1, 10);
        vm.prank(bob);
        IFluidVaultT1(VAULT_WSTETH_USDC_V1).absorb();

        swaps = resolver.getSwapsRaw(USDC, WSTETH);
        assertEq(swaps.length, 2);
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[0].path.tokenIn, USDC);
        assertEq(swaps[0].path.tokenOut, WSTETH);
        assertEq(swaps[0].data.inAmt, 245956959);
        assertEq(swaps[0].data.outAmt, 76814739131248572);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[0].data.ratio, 312309679886912945610130104104921869);
        assertEq(swaps[1].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[1].path.tokenIn, USDC);
        assertEq(swaps[1].path.tokenOut, WSTETH);
        assertEq(swaps[1].data.inAmt, 2641577709844);
        assertEq(swaps[1].data.outAmt, 818530880010480801203);
        assertEq(swaps[1].data.withAbsorb, true);
        assertEq(swaps[1].data.ratio, 309864395418001784580552157367562787);
    }

    function test_getSwaps_USDC_ETH() public {
        // assert initially no swap available
        Structs.Swap[] memory swaps = resolver.getSwaps(USDC, WSTETH);
        assertEq(swaps.length, 0);

        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_WSTETH_USDC_V1, 10);

        // check that liquidation is now available and swap data is as expected.
        // should have only without absorb swap here
        swaps = resolver.getSwaps(USDC, WSTETH);
        assertEq(swaps.length, 1);
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[0].path.tokenIn, USDC);
        assertEq(swaps[0].path.tokenOut, WSTETH);
        assertEq(swaps[0].data.inAmt, 651750586205);
        assertEq(swaps[0].data.outAmt, 183193214693624384067);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[0].data.ratio, 281078711045460031704030862966763290);

        // reduce oracle price more, into absorb territory, run absorb and check again
        _reduceVaultOraclePrice(VAULT_WSTETH_USDC_V1, 10);
        vm.prank(bob);
        IFluidVaultT1(VAULT_WSTETH_USDC_V1).absorb();

        // should only return the better ratio swap
        swaps = resolver.getSwaps(USDC, WSTETH);
        assertEq(swaps.length, 1);
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[0].path.tokenIn, USDC);
        assertEq(swaps[0].path.tokenOut, WSTETH);
        assertEq(swaps[0].data.inAmt, 245956959);
        assertEq(swaps[0].data.outAmt, 76814739131248572);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[0].data.ratio, 312309679886912945610130104104921869);
    }

    function test_getAnySwapsRaw() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        address[] memory tokensIn = new address[](3);
        tokensIn[0] = ETH;
        tokensIn[1] = WSTETH;
        tokensIn[2] = USDC;
        address[] memory tokensOut = new address[](4);
        tokensOut[0] = ETH;
        tokensOut[1] = WSTETH;
        tokensOut[2] = USDC;
        tokensOut[3] = WEETH;

        Structs.Swap[] memory swaps = resolver.getAnySwapsRaw(tokensIn, tokensOut);
        _verifyWeethWstethVaultSwap(swaps);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getAnySwapsRaw(tokensIn, tokensOut);
        assertEq(swaps.length, 5);

        Structs.Swap[] memory weethWstethSwaps = new Structs.Swap[](1);
        weethWstethSwaps[0] = swaps[2];
        _verifyWeethWstethVaultSwap(weethWstethSwaps);

        Structs.Swap[] memory wstethUsdcSwaps = new Structs.Swap[](4);
        wstethUsdcSwaps = new Structs.Swap[](4);
        wstethUsdcSwaps[0] = swaps[0];
        wstethUsdcSwaps[1] = swaps[1];
        wstethUsdcSwaps[2] = swaps[3];
        wstethUsdcSwaps[3] = swaps[4];
        _verifyWstethUsdcVaultsSwapRawAfterOracleChange(wstethUsdcSwaps);
    }

    function test_getAnySwaps() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        address[] memory tokensIn = new address[](3);
        tokensIn[0] = ETH;
        tokensIn[1] = WSTETH;
        tokensIn[2] = USDC;
        address[] memory tokensOut = new address[](4);
        tokensOut[0] = ETH;
        tokensOut[1] = WSTETH;
        tokensOut[2] = USDC;
        tokensOut[3] = WEETH;

        Structs.Swap[] memory swaps = resolver.getAnySwaps(tokensIn, tokensOut);
        _verifyWeethWstethVaultSwap(swaps);

        _reduceWstethUsdcVaultsOraclePrices();

        swaps = resolver.getAnySwaps(tokensIn, tokensOut);
        assertEq(swaps.length, 3);

        Structs.Swap[] memory weethWstethSwaps = new Structs.Swap[](1);
        weethWstethSwaps[0] = swaps[1];
        _verifyWeethWstethVaultSwap(weethWstethSwaps);

        Structs.Swap[] memory wstethUsdcSwaps = new Structs.Swap[](2);
        wstethUsdcSwaps[0] = swaps[0];
        wstethUsdcSwaps[1] = swaps[2];
        _verifyWstethUsdcVaultsSwapAfterOracleChange(wstethUsdcSwaps);
    }
}

contract FluidVaultLiquidationResolverSwapTxTest is FluidVaultLiquidationResolverBaseTest {
    function test_getSwapTx() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        Structs.Swap[] memory swaps = resolver.getSwapsRaw(WSTETH, WEETH);
        _verifyWeethWstethVaultSwap(swaps);

        (address target, bytes memory liquidateCalldata) = resolver.getSwapTx(
            swaps[0],
            bob,
            10000 // 1% slippage
        );

        // executing the received calldata should trigger the liquidation and result in desired swap
        address alice = WSTETH_WHALE;
        vm.prank(alice);
        IERC20(WSTETH).approve(Vault_WEETH_WSTETH_V1, type(uint256).max);

        uint256 aliceBalanceBefore = IERC20(WSTETH).balanceOf(alice);
        uint256 bobBalanceBefore = IERC20(WEETH).balanceOf(bob);

        vm.expectCall(
            Vault_WEETH_WSTETH_V1,
            abi.encodeCall(IFluidVaultT1.liquidate, (swaps[0].data.inAmt, 1124372344688696166, bob, false))
        );
        vm.prank(alice);
        (bool success, ) = target.call(liquidateCalldata);
        assertTrue(success);

        assertApproxEqAbs(aliceBalanceBefore - IERC20(WSTETH).balanceOf(alice), swaps[0].data.inAmt, 1);
        assertApproxEqAbs(IERC20(WEETH).balanceOf(bob) - bobBalanceBefore, swaps[0].data.outAmt, 1e9); // output amount might be a bit less
        assertLt(IERC20(WEETH).balanceOf(bob) - bobBalanceBefore, swaps[0].data.outAmt); // output should be LESS not more
    }

    function test_getSwapTxs() public {
        _reduceWstethUsdcVaultsOraclePrices();
        Structs.Swap[] memory swaps = resolver.getSwapsRaw(USDC, WSTETH);

        Structs.Swap[] memory executeSwaps = new Structs.Swap[](2);
        executeSwaps[0] = swaps[0];
        executeSwaps[1] = swaps[3];

        // execute the without absorb swap on VAULT_WSTETH_USDC_V1
        assertEq(executeSwaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(executeSwaps[0].data.withAbsorb, false);
        // execute the with asborb swap on VAULT_WSTETH_USDC_V2
        assertEq(executeSwaps[1].path.protocol, VAULT_WSTETH_USDC_V2);
        assertEq(executeSwaps[1].data.withAbsorb, true);

        (address[] memory targets, bytes[] memory liquidateCalldatas) = resolver.getSwapTxs(
            executeSwaps,
            bob,
            10000 // 1% slippage
        );
        assertEq(targets.length, 2);
        assertEq(liquidateCalldatas.length, 2);

        // executing the received calldata should trigger the liquidation and result in desired swap
        address alice = USDC_WHALE;
        vm.prank(alice);
        IERC20(USDC).approve(VAULT_WSTETH_USDC_V1, type(uint256).max);
        vm.prank(alice);
        IERC20(USDC).approve(VAULT_WSTETH_USDC_V2, type(uint256).max);

        uint256 aliceBalanceBefore = IERC20(USDC).balanceOf(alice);
        uint256 bobBalanceBefore = IERC20(WSTETH).balanceOf(bob);

        vm.expectCall(
            VAULT_WSTETH_USDC_V1,
            abi.encodeCall(
                IFluidVaultT1.liquidate,
                (executeSwaps[0].data.inAmt, 417401885920012877644881816, bob, false)
            )
        );
        vm.prank(alice);
        (bool success, ) = targets[0].call(liquidateCalldatas[0]);
        assertTrue(success);

        vm.expectCall(
            VAULT_WSTETH_USDC_V2,
            abi.encodeCall(
                IFluidVaultT1.liquidate,
                (executeSwaps[1].data.inAmt, 380243627453985063936714616, bob, true)
            )
        );
        vm.prank(alice);
        (success, ) = targets[1].call(liquidateCalldatas[1]);
        assertTrue(success);

        assertApproxEqAbs(
            aliceBalanceBefore - IERC20(USDC).balanceOf(alice),
            executeSwaps[0].data.inAmt + executeSwaps[1].data.inAmt,
            2
        );
        assertApproxEqAbs(
            IERC20(WSTETH).balanceOf(bob) - bobBalanceBefore,
            executeSwaps[0].data.outAmt + executeSwaps[1].data.outAmt,
            1e9
        ); // output amount might be a bit less
        assertLt(
            IERC20(WSTETH).balanceOf(bob) - bobBalanceBefore,
            executeSwaps[0].data.outAmt + executeSwaps[1].data.outAmt
        ); // output should be LESS not more
    }
}

contract FluidVaultLiquidationResolverSwapsWithLimitLimitedTest is FluidVaultLiquidationResolverBaseTest {
    address internal constant Vault_ETH_WBTC = 0x991416539E9DA46db233bCcbaEA38C4f852776D4;
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    FluidLiquidityResolver liquidityResolver;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21765181);

        // deploy resolver dependencies newest state
        liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
        vaultResolver = new FluidVaultResolver(address(VAULT_FACTORY), address(liquidityResolver));

        // constructor params
        // IFluidVaultResolver vaultResolver_
        resolver = new FluidVaultLiquidationResolver(
            IFluidVaultResolver(address(vaultResolver)),
            IFluidLiquidity(address(LIQUIDITY))
        );
    }

    function test_getSwapForProtocolWhenWithdrawLimit_Limited() public {
        Structs.Swap memory swap = resolver.getSwapForProtocol(Vault_ETH_WBTC);
        assertEq(swap.data.inAmt, 1195);
        assertEq(swap.data.outAmt, 460525933448233);

        (FluidLiquidityResolver.UserSupplyData memory vaultData, ) = liquidityResolver.getUserSupplyData(
            Vault_ETH_WBTC,
            NATIVE_TOKEN_ADDRESS
        );
        assertEq(vaultData.withdrawable, swap.data.outAmt);
    }
}

contract FluidVaultLiquidationResolverSwapsWithLimitAvailableTest is FluidVaultLiquidationResolverBaseTest {
    address internal constant Vault_ETH_WBTC = 0x991416539E9DA46db233bCcbaEA38C4f852776D4;
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    FluidLiquidityResolver liquidityResolver;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21766528);

        // deploy resolver dependencies newest state
        liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
        vaultResolver = new FluidVaultResolver(address(VAULT_FACTORY), address(liquidityResolver));

        // constructor params
        // IFluidVaultResolver vaultResolver_
        resolver = new FluidVaultLiquidationResolver(
            IFluidVaultResolver(address(vaultResolver)),
            IFluidLiquidity(address(LIQUIDITY))
        );
    }

    function test_getSwapForProtocolWhenWithdrawLimit_Available() public {
        // at block when instant expansion was executed, liquidation should be available now
        Structs.Swap memory swap = resolver.getSwapForProtocol(Vault_ETH_WBTC);
        assertEq(swap.data.inAmt, 799324406);
        assertEq(swap.data.outAmt, 307941712764882225863);

        (FluidLiquidityResolver.UserSupplyData memory vaultData, ) = liquidityResolver.getUserSupplyData(
            Vault_ETH_WBTC,
            NATIVE_TOKEN_ADDRESS
        );
        assertGe(vaultData.withdrawableUntilLimit, swap.data.outAmt);
    }
}

contract FluidVaultLiquidationResolverSwapsWithLimitAvailableFullTest is FluidVaultLiquidationResolverBaseTest {
    address internal constant Vault_ETH_WBTC = 0x991416539E9DA46db233bCcbaEA38C4f852776D4;
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    FluidLiquidityResolver liquidityResolver;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21766529);

        // deploy resolver dependencies newest state
        liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
        vaultResolver = new FluidVaultResolver(address(VAULT_FACTORY), address(liquidityResolver));

        // constructor params
        // IFluidVaultResolver vaultResolver_
        resolver = new FluidVaultLiquidationResolver(
            IFluidVaultResolver(address(vaultResolver)),
            IFluidLiquidity(address(LIQUIDITY))
        );
    }

    function test_getSwapForProtocolWhenWithdrawLimit_AvailableFull() public {
        // at block after when instant expansion was executed and liquidation already triggered to below base limit, FULL liquidation should be available now
        Structs.Swap memory swap = resolver.getSwapForProtocol(Vault_ETH_WBTC);
        assertEq(swap.data.inAmt, 689);
        assertEq(swap.data.outAmt, 265488431040374);

        (FluidLiquidityResolver.UserSupplyData memory vaultData, ) = liquidityResolver.getUserSupplyData(
            Vault_ETH_WBTC,
            NATIVE_TOKEN_ADDRESS
        );
        assertGt(vaultData.withdrawableUntilLimit, swap.data.outAmt);
    }
}

contract FluidVaultLiquidationResolverExactTest is FluidVaultLiquidationResolverBaseTest {
    function test_exactInput() public {
        // assert initially no swap available
        (Structs.Swap[] memory swaps, uint256 actualInAmt, uint256 outAmt) = resolver.exactInput(
            USDC,
            WSTETH,
            type(uint256).max
        );
        assertEq(swaps.length, 0);
        assertEq(actualInAmt, 0);
        assertEq(outAmt, 0);

        _reduceWstethUsdcVaultsOraclePrices();

        (swaps, actualInAmt, outAmt) = resolver.exactInput(USDC, WSTETH, type(uint256).max);
        assertEq(swaps.length, 2); // should have only the with absorb swaps
        assertEq(actualInAmt, 4071487390965);
        // should have the best ratio swap first
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V2);
        assertEq(swaps[0].data.withAbsorb, true);
        assertEq(swaps[1].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[1].data.withAbsorb, true);
        assertGt(swaps[0].data.ratio, swaps[1].data.ratio);

        uint256 targetInAmt = 1e11;
        (swaps, actualInAmt, outAmt) = resolver.exactInput(USDC, WSTETH, targetInAmt);
        assertEq(swaps.length, 2);
        assertEq(swaps[0].data.inAmt + swaps[1].data.inAmt, targetInAmt);
        assertEq(actualInAmt, targetInAmt);
        // should have the best ratio swap first
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[1].path.protocol, VAULT_WSTETH_USDC_V2);
        assertEq(swaps[1].data.withAbsorb, true);
        assertGt(swaps[0].data.ratio, swaps[1].data.ratio);

        targetInAmt = 1e8;
        (swaps, actualInAmt, outAmt) = resolver.exactInput(USDC, WSTETH, targetInAmt);
        assertEq(swaps.length, 1);
        assertEq(swaps[0].data.inAmt, targetInAmt);
        assertEq(actualInAmt, targetInAmt);
        // should have the best ratio swap first. without absorb swap
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[0].data.withAbsorb, false);
    }

    function test_exactInput_WhenNoAbsorbLiquidity() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        (Structs.Swap[] memory swaps, uint256 actualInAmt, uint256 outAmt) = resolver.exactInput(
            WSTETH,
            WEETH,
            type(uint256).max
        );

        _verifyWeethWstethVaultSwap(swaps);
        assertEq(actualInAmt, 169195126140259605);
        assertEq(outAmt, 192159919887094343);

        uint256 targetInAmt = 1e16;
        (swaps, actualInAmt, outAmt) = resolver.exactInput(WSTETH, WEETH, targetInAmt);
        assertEq(swaps[0].data.inAmt, targetInAmt);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(actualInAmt, targetInAmt);
        assertEq(swaps.length, 1);
    }

    function test_exactInput_execute() public {
        _reduceWstethUsdcVaultsOraclePrices();

        uint256 targetInAmt = 1e11;
        (Structs.Swap[] memory swaps, uint256 actualInAmt, uint256 outAmt) = resolver.exactInput(
            USDC,
            WSTETH,
            targetInAmt
        );

        (address[] memory targets, bytes[] memory liquidateCalldatas) = resolver.getSwapTxs(
            swaps,
            bob,
            10000 // 1% slippage
        );
        assertEq(targets.length, 2);
        assertEq(liquidateCalldatas.length, 2);

        // executing the received calldata should trigger the liquidation and result in desired swap
        address alice = USDC_WHALE;
        vm.prank(alice);
        IERC20(USDC).approve(VAULT_WSTETH_USDC_V1, type(uint256).max);
        vm.prank(alice);
        IERC20(USDC).approve(VAULT_WSTETH_USDC_V2, type(uint256).max);

        uint256 aliceBalanceBefore = IERC20(USDC).balanceOf(alice);
        uint256 bobBalanceBefore = IERC20(WSTETH).balanceOf(bob);

        vm.expectCall(
            VAULT_WSTETH_USDC_V1,
            abi.encodeCall(IFluidVaultT1.liquidate, (swaps[0].data.inAmt, 417401885920012877644881816, bob, false))
        );
        vm.prank(alice);
        (bool success, ) = targets[0].call(liquidateCalldatas[0]);
        assertTrue(success);

        vm.expectCall(
            VAULT_WSTETH_USDC_V2,
            abi.encodeCall(IFluidVaultT1.liquidate, (swaps[1].data.inAmt, 370770502417430432049964954, bob, true))
        );
        vm.prank(alice);
        (success, ) = targets[1].call(liquidateCalldatas[1]);
        assertTrue(success);

        assertApproxEqAbs(aliceBalanceBefore - IERC20(USDC).balanceOf(alice), targetInAmt, 2);
        assertApproxEqAbs(
            aliceBalanceBefore - IERC20(USDC).balanceOf(alice),
            swaps[0].data.inAmt + swaps[1].data.inAmt,
            2
        );
        assertApproxEqAbs(
            IERC20(WSTETH).balanceOf(bob) - bobBalanceBefore,
            swaps[0].data.outAmt + swaps[1].data.outAmt,
            1e9
        ); // output amount might be a bit less
        assertLt(IERC20(WSTETH).balanceOf(bob) - bobBalanceBefore, swaps[0].data.outAmt + swaps[1].data.outAmt); // output should be LESS not more
    }

    function test_approxOutput() public {
        // assert initially no swap available
        (Structs.Swap[] memory swaps, uint256 inAmt, uint256 actualOutAmt) = resolver.approxOutput(
            USDC,
            WSTETH,
            type(uint256).max
        );
        assertEq(swaps.length, 0);
        assertEq(inAmt, 0);
        assertEq(actualOutAmt, 0);

        _reduceWstethUsdcVaultsOraclePrices();

        (swaps, inAmt, actualOutAmt) = resolver.approxOutput(USDC, WSTETH, type(uint256).max);
        assertEq(swaps.length, 2); // should have only the with absorb swaps
        assertEq(inAmt, 4071487390965);
        assertEq(actualOutAmt, 1411174713315791643353);
        // should have the best ratio swap first
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V2);
        assertEq(swaps[0].data.withAbsorb, true);
        assertEq(swaps[1].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[1].data.withAbsorb, true);
        assertGt(swaps[0].data.ratio, swaps[1].data.ratio);

        uint256 targetOutAmt = 1e20;
        (swaps, inAmt, actualOutAmt) = resolver.approxOutput(USDC, WSTETH, targetOutAmt);
        assertEq(swaps.length, 2);
        assertApproxEqAbs(swaps[0].data.outAmt + swaps[1].data.outAmt, targetOutAmt, 1e8);
        assertApproxEqAbs(actualOutAmt, targetOutAmt, 1e8);
        // should have the best ratio swap first
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[1].path.protocol, VAULT_WSTETH_USDC_V2);
        assertEq(swaps[1].data.withAbsorb, true);
        assertGt(swaps[0].data.ratio, swaps[1].data.ratio);

        targetOutAmt = 1e17;
        (swaps, inAmt, actualOutAmt) = resolver.approxOutput(USDC, WSTETH, targetOutAmt);
        assertEq(swaps.length, 1);
        assertApproxEqAbs(swaps[0].data.outAmt, targetOutAmt, 1e8);
        assertApproxEqAbs(actualOutAmt, targetOutAmt, 1e8);
        // should have the best ratio swap first. without absorb swap
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[0].data.withAbsorb, false);
    }

    function test_approxOutput_WhenNoAbsorbLiquidity() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        (Structs.Swap[] memory swaps, uint256 inAmt, uint256 actualOutAmt) = resolver.approxOutput(
            WSTETH,
            WEETH,
            type(uint256).max
        );

        _verifyWeethWstethVaultSwap(swaps);
        assertEq(inAmt, 169195126140259605);
        assertEq(actualOutAmt, 192159919887094343);

        uint256 targetOutAmt = 1e16;
        (swaps, inAmt, actualOutAmt) = resolver.approxOutput(WSTETH, WEETH, targetOutAmt);
        assertApproxEqAbs(swaps[0].data.outAmt, targetOutAmt, 1);
        assertEq(swaps[0].data.withAbsorb, false);
        assertApproxEqAbs(actualOutAmt, targetOutAmt, 1);
        assertEq(swaps.length, 1);
    }

    function test_approxOutput_execute() public {
        _reduceWstethUsdcVaultsOraclePrices();

        uint256 targetOutAmt = 1e20;
        (Structs.Swap[] memory swaps, uint256 inAmt, uint256 actualOutAmt) = resolver.approxOutput(
            USDC,
            WSTETH,
            targetOutAmt
        );

        (address[] memory targets, bytes[] memory liquidateCalldatas) = resolver.getSwapTxs(
            swaps,
            bob,
            10000 // 1% slippage
        );
        assertEq(targets.length, 2);
        assertEq(liquidateCalldatas.length, 2);

        // executing the received calldata should trigger the liquidation and result in desired swap
        address alice = USDC_WHALE;
        vm.prank(alice);
        IERC20(USDC).approve(VAULT_WSTETH_USDC_V1, type(uint256).max);
        vm.prank(alice);
        IERC20(USDC).approve(VAULT_WSTETH_USDC_V2, type(uint256).max);

        uint256 aliceBalanceBefore = IERC20(USDC).balanceOf(alice);
        uint256 bobBalanceBefore = IERC20(WSTETH).balanceOf(bob);

        vm.expectCall(
            VAULT_WSTETH_USDC_V1,
            abi.encodeCall(IFluidVaultT1.liquidate, (swaps[0].data.inAmt, 417401885920012877644881816, bob, false))
        );
        vm.prank(alice);
        (bool success, ) = targets[0].call(liquidateCalldatas[0]);
        assertTrue(success);

        vm.expectCall(
            VAULT_WSTETH_USDC_V2,
            abi.encodeCall(IFluidVaultT1.liquidate, (swaps[1].data.inAmt, 378874589137426031698456528, bob, true))
        );
        vm.prank(alice);
        (success, ) = targets[1].call(liquidateCalldatas[1]);
        assertTrue(success);

        assertApproxEqAbs(IERC20(WSTETH).balanceOf(bob) - bobBalanceBefore, targetOutAmt, 1e9);
        assertApproxEqAbs(
            aliceBalanceBefore - IERC20(USDC).balanceOf(alice),
            swaps[0].data.inAmt + swaps[1].data.inAmt,
            2
        );
        assertApproxEqAbs(
            IERC20(WSTETH).balanceOf(bob) - bobBalanceBefore,
            swaps[0].data.outAmt + swaps[1].data.outAmt,
            1e9
        ); // output amount might be a bit less
        assertLt(IERC20(WSTETH).balanceOf(bob) - bobBalanceBefore, swaps[0].data.outAmt + swaps[1].data.outAmt); // output should be LESS not more
    }
}

contract FluidVaultLiquidationResolverHelpersTest is FluidVaultLiquidationResolverBaseTest {
    function setUp() public virtual override {
        super.setUp();
        _reduceWstethUsdcVaultsOraclePrices();
    }

    function test_filterToTargetInAmt() public {
        uint256 targetInAmt = 1e11;

        Structs.Swap[] memory swaps = resolver.getSwapsRaw(USDC, WSTETH);
        uint256 actualInAmt;
        uint256 actualOutAmt;
        (swaps, actualInAmt, actualOutAmt) = resolver.filterToTargetInAmt(swaps, targetInAmt);
        assertEq(swaps.length, 2);
        assertEq(swaps[0].data.inAmt + swaps[1].data.inAmt, targetInAmt);
    }

    function test_filterToTargetInAmt_oneSwap() public {
        uint256 targetInAmt = 1e8;

        Structs.Swap[] memory swaps = resolver.getSwapsRaw(USDC, WSTETH);
        uint256 actualInAmt;
        uint256 actualOutAmt;
        (swaps, actualInAmt, actualOutAmt) = resolver.filterToTargetInAmt(swaps, targetInAmt);
        assertEq(swaps.length, 1);
        assertEq(swaps[0].data.inAmt, targetInAmt);
    }

    function test_filterToApproxOutAmt() public {
        uint256 targetOutAmt = 1e20;

        Structs.Swap[] memory swaps = resolver.getSwapsRaw(USDC, WSTETH);
        uint256 actualInAmt;
        uint256 actualOutAmt;
        (swaps, actualInAmt, actualOutAmt) = resolver.filterToApproxOutAmt(swaps, targetOutAmt);
        assertEq(swaps.length, 2);

        // out amt is never perfect as liquidate() takes an in amount
        assertApproxEqAbs(swaps[0].data.outAmt + swaps[1].data.outAmt, targetOutAmt, 1e8);
    }
}

contract FluidVaultLiquidationResolverCombiTest is FluidVaultLiquidationResolverBaseTest {
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function test_combinationActions() public {
        vm.skip(true); // This will skip the tests, they are targeted for with Zircuit and SUSDS rehypo logic. To execute
        // on the main-mainnet branch

        // assert initially only weETH / Wsteth swap available
        Structs.Swap[] memory swaps = resolver.getAllVaultsSwapRaw();
        _verifyWeethWstethVaultSwap(swaps);
        swaps = resolver.getAllVaultsSwap();
        _verifyWeethWstethVaultSwap(swaps);

        uint256 actualInAmt;
        uint256 outAmt;
        // assert initially no swap available for USDC -> wstETH
        (swaps, actualInAmt, outAmt) = resolver.exactInput(USDC, WSTETH, type(uint256).max);
        assertEq(swaps.length, 0);
        assertEq(actualInAmt, 0);
        assertEq(outAmt, 0);

        // partial swap for weETH / wstETH
        uint256 swapAmount = 1e15;
        (swaps, actualInAmt, outAmt) = resolver.exactInput(WSTETH, WEETH, swapAmount);
        (address[] memory targets, bytes[] memory liquidateCalldatas) = resolver.getSwapTxs(
            swaps,
            bob,
            10000 // 1% slippage
        );
        assertEq(targets.length, 1);
        assertEq(targets[0], Vault_WEETH_WSTETH_V1);
        assertEq(liquidateCalldatas.length, 1);

        // executing the received calldata should trigger the liquidation and result in desired swap
        address alice = WSTETH_WHALE;
        vm.prank(alice);
        IERC20(WSTETH).approve(Vault_WEETH_WSTETH_V1, type(uint256).max);

        uint256 aliceBalanceBefore = IERC20(WSTETH).balanceOf(alice);
        uint256 bobBalanceBefore = IERC20(WEETH).balanceOf(bob);

        uint256 sumSwapsIn;
        for (uint256 i; i < targets.length; i++) {
            vm.prank(alice);
            (bool success, ) = targets[i].call{
                value: swaps[i].path.tokenIn == NATIVE_TOKEN_ADDRESS ? swaps[i].data.inAmt : 0
            }(liquidateCalldatas[i]);
            assertTrue(success);
            sumSwapsIn += swaps[i].data.inAmt;
        }
        assertEq(sumSwapsIn, swapAmount);
        assertEq(actualInAmt, swapAmount);

        assertApproxEqAbs(IERC20(WEETH).balanceOf(bob) - bobBalanceBefore, outAmt, 1e9);
        assertApproxEqAbs(aliceBalanceBefore - IERC20(WSTETH).balanceOf(alice), actualInAmt, 2);

        // assert reduced liquidity is still available for weETH / wstETH
        swaps = resolver.getAllVaultsSwap();
        assertEq(swaps.length, 1);
        assertEq(swaps[0].data.withAbsorb, false);
        // original available in and out amts:
        // assertEq(swaps[0].data.inAmt, 169195126140259605);
        // assertEq(swaps[0].data.outAmt, 192159919887094343);
        assertApproxEqAbs(swaps[0].data.inAmt, 169195126140259605 - actualInAmt, 1e9);
        assertApproxEqAbs(swaps[0].data.outAmt, 192159919887094343 - outAmt, 1e9);

        // reduce oracle prices for wsteth
        _reduceWstethUsdcVaultsOraclePrices();

        // assert reduced liquidity is still available for weETH / wstETH
        swaps = resolver.getAllVaultsSwap();
        assertEq(swaps.length, 3);
        assertEq(swaps[1].path.protocol, Vault_WEETH_WSTETH_V1);
        assertEq(swaps[1].data.withAbsorb, false);
        assertApproxEqAbs(swaps[1].data.inAmt, 169195126140259605 - actualInAmt, 1e9);
        assertApproxEqAbs(swaps[1].data.outAmt, 192159919887094343 - outAmt, 1e9);
        assertEq(swaps[1].data.inAmt, 168195126042305794);
        assertEq(swaps[1].data.outAmt, 191024190134745604);

        // assert USDC -> wstETH swaps are available now too
        Structs.Swap[] memory checkSwaps = new Structs.Swap[](2);
        checkSwaps[0] = swaps[0];
        checkSwaps[1] = swaps[2];
        _verifyWstethUsdcVaultsSwapAfterOracleChange(checkSwaps);

        // expected raw swaps here, sorted by ratio
        swaps = resolver.getSwapsRaw(USDC, WSTETH);
        assertEq(swaps[0].data.inAmt, 17171641401); // VAULT_WSTETH_USDC_V1
        assertEq(swaps[0].data.outAmt, 7239874247595527378);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[0].data.ratio, 421618066585871593580688704949272426);

        assertEq(swaps[2].data.inAmt, 51053932660); // VAULT_WSTETH_USDC_V2
        assertEq(swaps[2].data.outAmt, 21525260378992474409);
        assertEq(swaps[2].data.withAbsorb, false);
        assertEq(swaps[2].data.ratio, 421618066571729489349782834143770345);

        assertEq(swaps[3].data.inAmt, 251312581922); // VAULT_WSTETH_USDC_V2
        assertEq(swaps[3].data.outAmt, 96525260378634413804);
        assertEq(swaps[3].data.withAbsorb, true);
        assertEq(swaps[3].data.ratio, 384084472175742488824964259562409064);

        assertEq(swaps[1].data.inAmt, 3820174809043); // VAULT_WSTETH_USDC_V1
        assertEq(swaps[1].data.outAmt, 1314649452937157229549);
        assertEq(swaps[1].data.withAbsorb, true);
        assertEq(swaps[1].data.ratio, 344133323382259781987783593432549988);

        // partial swap for USDC -> wstETH, using up the whole with absorb liquidity
        swapAmount = 17171641401 + 200_259 * 1e6; // whole without absorb of V1 and whole with absorb (only) of V2
        (swaps, actualInAmt, outAmt) = resolver.exactInput(USDC, WSTETH, swapAmount);

        // swap 1 should be VAULT_WSTETH_USDC_V1 without absorb. using up the whole available 17171641401
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[0].data.inAmt, 17171641401);
        // swap 2 should be VAULT_WSTETH_USDC_V2 with absorb. using up the whole available with absorb liquidity (only)
        // which is 251312581922 - 51053932660 = 200258,649262
        assertEq(swaps[1].path.protocol, VAULT_WSTETH_USDC_V2);
        assertEq(swaps[1].data.withAbsorb, true);
        assertEq(swaps[1].data.inAmt, 200_259 * 1e6);

        (targets, liquidateCalldatas) = resolver.getSwapTxs(
            swaps,
            bob,
            10000 // 1% slippage
        );
        assertEq(targets.length, 2);
        assertEq(targets[0], VAULT_WSTETH_USDC_V1);
        assertEq(targets[1], VAULT_WSTETH_USDC_V2);
        assertEq(liquidateCalldatas.length, 2);

        // execute swaps
        alice = USDC_WHALE;
        vm.prank(alice);
        IERC20(USDC).approve(VAULT_WSTETH_USDC_V1, type(uint256).max);
        vm.prank(alice);
        IERC20(USDC).approve(VAULT_WSTETH_USDC_V2, type(uint256).max);

        aliceBalanceBefore = IERC20(USDC).balanceOf(alice);
        bobBalanceBefore = IERC20(WSTETH).balanceOf(bob);
        sumSwapsIn = 0;
        for (uint256 i; i < targets.length; i++) {
            vm.prank(alice);
            (bool success, ) = targets[i].call{
                value: swaps[i].path.tokenIn == NATIVE_TOKEN_ADDRESS ? swaps[i].data.inAmt : 0
            }(liquidateCalldatas[i]);
            assertTrue(success);
            sumSwapsIn += swaps[i].data.inAmt;
        }
        assertEq(sumSwapsIn, swapAmount);
        assertEq(actualInAmt, swapAmount);

        assertApproxEqAbs(IERC20(WSTETH).balanceOf(bob) - bobBalanceBefore, outAmt, 1e9);
        assertApproxEqAbs(aliceBalanceBefore - IERC20(USDC).balanceOf(alice), actualInAmt, 2);

        // increase oracle prices for V1 by 20%
        // with absorb liquidity should stay the same.
        {
            FluidVaultResolver.VaultEntireData memory vaultData = vaultResolver.getVaultEntireData(
                VAULT_WSTETH_USDC_V1
            );
            uint256 currentOraclePrice = vaultData.configs.oraclePriceLiquidate;
            // set a mockOracle as oracle and move positions into liquidation territory
            MockOracle oracle = new MockOracle();
            vm.prank(GOVERNANCE);
            FluidVaultT1Admin(VAULT_WSTETH_USDC_V1).updateOracle(address(oracle));

            oracle.setPrice((currentOraclePrice * (100 + 20)) / 100); // simulate price increase
            vaultData = vaultResolver.getVaultEntireData(VAULT_WSTETH_USDC_V1);
            assertGt(vaultData.configs.oraclePriceLiquidate, currentOraclePrice);
        }

        vm.prank(bob);
        IFluidVaultT1(VAULT_WSTETH_USDC_V1).absorb();

        // expected raw swaps USDC -> WSTETH here, sorted by ratio
        swaps = resolver.getSwapsRaw(USDC, WSTETH);
        // VAULT_WSTETH_USDC_V2, around the same as before without absorb left over. only with absorb was used up.
        assertEq(swaps[1].path.protocol, VAULT_WSTETH_USDC_V2);
        assertEq(swaps[1].data.inAmt, 51053581925);
        assertEq(swaps[1].data.outAmt, 21525112502630383022);
        assertEq(swaps[1].data.withAbsorb, false);
        assertEq(swaps[1].data.ratio, 421618066568800951413361580701665919);

        // VAULT_WSTETH_USDC_V1,should still have the without absorb liquidity. only without absorb was used up.
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[0].data.inAmt, 3803003167641);
        assertEq(swaps[0].data.outAmt, 1307409578689561702171);
        assertEq(swaps[0].data.withAbsorb, true);
        assertEq(swaps[0].data.ratio, 343783457719428321941454340533692163);

        // assert total available swaps after
        swaps = resolver.getAllVaultsSwap();
        assertEq(swaps.length, 3);
        // weeth wsteth approx unchanged
        assertEq(swaps[1].path.protocol, Vault_WEETH_WSTETH_V1);
        assertEq(swaps[1].data.withAbsorb, false);
        assertEq(swaps[1].data.inAmt, 168195126042305794);
        assertEq(swaps[1].data.outAmt, 191024190134745604);
        // VAULT_WSTETH_USDC_V1
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[0].data.inAmt, 3803003167641);
        // VAULT_WSTETH_USDC_V2
        assertEq(swaps[2].path.protocol, VAULT_WSTETH_USDC_V2);
        assertEq(swaps[2].data.inAmt, 51053581925);

        // assert new expected exact swaps
        swapAmount = 51043581925; // less than best ratio swap
        (swaps, actualInAmt, outAmt) = resolver.exactInput(USDC, WSTETH, swapAmount);
        assertEq(swaps.length, 1);
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V2);
        assertEq(swaps[0].data.inAmt, 51043581925);
        assertEq(swaps[0].data.withAbsorb, false);

        swapAmount = 51083581925; // more than best ratio swap
        (swaps, actualInAmt, outAmt) = resolver.exactInput(USDC, WSTETH, swapAmount);
        assertEq(swaps.length, 2);
        assertEq(swaps[0].path.protocol, VAULT_WSTETH_USDC_V2);
        assertEq(swaps[0].data.inAmt, 51053581925); // all available
        assertEq(swaps[0].data.withAbsorb, false);
        // rest from second available swap
        assertEq(swaps[1].path.protocol, VAULT_WSTETH_USDC_V1);
        assertEq(swaps[1].data.inAmt, uint256(51083581925 - 51053581925));
        assertEq(swaps[1].data.withAbsorb, true);

        swapAmount = type(uint256).max; // max possible
        (swaps, actualInAmt, outAmt) = resolver.exactInput(USDC, WSTETH, swapAmount);
        assertEq(swaps[0].data.inAmt, 51053581925); // all available
        assertEq(swaps[1].data.inAmt, 3803003167641); // all available
        assertEq(actualInAmt, 51053581925 + 3803003167641); // all available

        // increase in amt at last swap by 1 to make sure it is used up fully
        swaps[1].data.inAmt++;

        // execute max possible swaps, should use up all USDC -> WSTETH swaps
        (targets, liquidateCalldatas) = resolver.getSwapTxs(
            swaps,
            bob,
            10000 // 1% slippage
        );
        assertEq(targets.length, 2);
        assertEq(targets[0], VAULT_WSTETH_USDC_V2);
        assertEq(targets[1], VAULT_WSTETH_USDC_V1);
        assertEq(liquidateCalldatas.length, 2);

        aliceBalanceBefore = IERC20(USDC).balanceOf(alice);
        bobBalanceBefore = IERC20(WSTETH).balanceOf(bob);
        sumSwapsIn = 0;
        for (uint256 i; i < targets.length; i++) {
            vm.prank(alice);
            (bool success, ) = targets[i].call{
                value: swaps[i].path.tokenIn == NATIVE_TOKEN_ADDRESS ? swaps[i].data.inAmt : 0
            }(liquidateCalldatas[i]);
            assertTrue(success);
            sumSwapsIn += swaps[i].data.inAmt;
        }
        assertApproxEqAbs(sumSwapsIn, actualInAmt, 1);

        assertApproxEqAbs(IERC20(WSTETH).balanceOf(bob) - bobBalanceBefore, outAmt, 1e9);
        assertApproxEqAbs(aliceBalanceBefore - IERC20(USDC).balanceOf(alice), actualInAmt, 2);

        // assert only weeth -> wsteth swap is left
        swaps = resolver.getAllVaultsSwap();
        assertEq(swaps.length, 1);
        assertEq(swaps[0].path.protocol, Vault_WEETH_WSTETH_V1);
        assertEq(swaps[0].data.withAbsorb, false);
        assertEq(swaps[0].data.inAmt, 168195126042305794);
        assertEq(swaps[0].data.outAmt, 191024190134745604);
    }
}
