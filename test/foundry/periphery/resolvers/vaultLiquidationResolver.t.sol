//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FluidVaultLiquidationResolver } from "../../../../contracts/periphery/resolvers/vaultLiquidation/main.sol";
import { Structs } from "../../../../contracts/periphery/resolvers/vaultLiquidation/structs.sol";
import { IFluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/iVaultResolver.sol";
import { IFluidVaultFactory } from "../../../../contracts/protocols/vault/interfaces/iVaultFactory.sol";
import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";
import { IFluidVaultT1 } from "../../../../contracts/protocols/vault/interfaces/iVaultT1.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";

contract FluidVaultLiquidationResolverTest is Test {
    IFluidVaultResolver internal constant VAULT_RESOLVER =
        IFluidVaultResolver(0x8DD65DaDb217f73A94Efb903EB2dc7B49D97ECca);
    IFluidVaultFactory internal constant VAULT_FACTORY = IFluidVaultFactory(0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d);

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address internal constant VAULT_ETH_USDC = 0xeAbBfca72F8a8bf14C4ac59e69ECB2eB69F0811C;
    address internal constant VAULT_WSTETH_ETH = 0xA0F83Fc5885cEBc0420ce7C7b139Adc80c4F4D91;
    address internal constant VAULT_WSTETH_USDC = 0x51197586F6A9e2571868b6ffaef308f3bdfEd3aE;
    address internal constant VAULT_WSTETH_USDT = 0x1c2bB46f36561bc4F05A94BD50916496aa501078;

    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    address bob = makeAddr("bob");

    FluidVaultLiquidationResolver resolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19377005);

        // constructor params
        // IFluidVaultResolver vaultResolver_
        resolver = new FluidVaultLiquidationResolver(VAULT_RESOLVER);
    }

    function test_deployment() public {
        assertEq(address(resolver.VAULT_RESOLVER()), address(VAULT_RESOLVER));
    }

    function test_getAllSwapPairs() public {
        Structs.VaultData[] memory vaultDatas = resolver.getAllSwapPairs();
        assertEq(vaultDatas.length, 5);
        assertEq(vaultDatas[0].vault, VAULT_ETH_USDC);
        assertEq(vaultDatas[0].tokenIn, USDC);
        assertEq(vaultDatas[0].tokenOut, ETH);

        assertEq(vaultDatas[2].vault, VAULT_WSTETH_ETH);
        assertEq(vaultDatas[2].tokenIn, ETH);
        assertEq(vaultDatas[2].tokenOut, WSTETH);

        assertEq(vaultDatas[4].vault, VAULT_WSTETH_USDT);
        assertEq(vaultDatas[4].tokenIn, USDT);
        assertEq(vaultDatas[4].tokenOut, WSTETH);
    }

    function test_getVaultForSwap() public {
        assertEq(resolver.getVaultForSwap(USDC, ETH), VAULT_ETH_USDC);
        assertEq(resolver.getVaultForSwap(ETH, WSTETH), VAULT_WSTETH_ETH);
        assertEq(resolver.getVaultForSwap(USDT, WSTETH), VAULT_WSTETH_USDT);
        assertEq(resolver.getVaultForSwap(WSTETH, USDC), address(0));
    }

    function test_getVaultsForSwap() public {
        address[] memory tokensIn = new address[](3);
        tokensIn[0] = ETH;
        tokensIn[1] = WSTETH;
        tokensIn[2] = USDC;
        address[] memory tokensOut = new address[](3);
        tokensOut[0] = ETH;
        tokensOut[1] = WSTETH;
        tokensOut[2] = USDC;
        Structs.VaultData[] memory vaultDatas = resolver.getVaultsForSwap(tokensIn, tokensOut);

        // should find routes: USDC -> ETH, USDC -> WSTETH, ETH -> WSTETH
        assertEq(vaultDatas.length, 3);
        assertEq(vaultDatas[0].vault, VAULT_WSTETH_ETH);
        assertEq(vaultDatas[0].tokenIn, ETH);
        assertEq(vaultDatas[0].tokenOut, WSTETH);

        assertEq(vaultDatas[1].vault, VAULT_ETH_USDC);
        assertEq(vaultDatas[1].tokenIn, USDC);
        assertEq(vaultDatas[1].tokenOut, ETH);

        assertEq(vaultDatas[2].vault, VAULT_WSTETH_USDC);
        assertEq(vaultDatas[2].tokenIn, USDC);
        assertEq(vaultDatas[2].tokenOut, WSTETH);
    }

    function test_getSwapAvailable() public {
        // assert initially no swap available
        Structs.SwapData memory swapData = resolver.getSwapAvailable(USDC, ETH);
        assertEq(swapData.inAmt, 0);
        assertEq(swapData.outAmt, 0);
        assertEq(swapData.inAmtWithAbsorb, 0);
        assertEq(swapData.outAmtWithAbsorb, 0);
        assertEq(swapData.vault, VAULT_ETH_USDC);

        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_ETH_USDC, 15);

        // check that liquidation is now available and swap data is as expected
        swapData = resolver.getSwapAvailable(USDC, ETH);
        assertEq(swapData.inAmt, 13519);
        assertEq(swapData.outAmt, 4261623418724);
        assertEq(swapData.inAmtWithAbsorb, swapData.inAmt);
        assertEq(swapData.outAmtWithAbsorb, swapData.outAmt);
        assertEq(swapData.vault, VAULT_ETH_USDC);

        // reduce oracle price more, into absorb territory, run absorb and check again
        _reduceVaultOraclePrice(VAULT_ETH_USDC, 20);

        vm.prank(bob);
        IFluidVaultT1(VAULT_ETH_USDC).absorb();

        // check that liquidation is now available and swap data is as expected
        swapData = resolver.getSwapAvailable(USDC, ETH);
        assertEq(swapData.inAmt, 1079615031403); // 1.079.615,031403 USDC
        assertEq(swapData.outAmt, 425403010045446193701); // 425,403010045446193701 ETH
        assertEq(swapData.inAmtWithAbsorb, 1529830467285); // 1.529.830,467285 USDC
        assertEq(swapData.outAmtWithAbsorb, 587977363017178865259); // ~587.977 ETH
        assertEq(swapData.vault, VAULT_ETH_USDC);
    }

    function test_getSwapsAvailable() public {
        address[] memory tokensIn = new address[](2);
        tokensIn[0] = ETH;
        tokensIn[1] = USDC;
        address[] memory tokensOut = new address[](2);
        tokensOut[0] = ETH;
        tokensOut[1] = WSTETH;

        // assert initially no swap available
        Structs.SwapData[] memory swapData = resolver.getSwapsAvailable(tokensIn, tokensOut);
        assertEq(swapData[0].inAmt, 0);
        assertEq(swapData[0].outAmt, 0);
        assertEq(swapData[0].inAmtWithAbsorb, 0);
        assertEq(swapData[0].outAmtWithAbsorb, 0);
        assertEq(swapData[0].vault, VAULT_WSTETH_ETH);

        assertEq(swapData[1].inAmt, 0);
        assertEq(swapData[1].outAmt, 0);
        assertEq(swapData[1].inAmtWithAbsorb, 0);
        assertEq(swapData[1].outAmtWithAbsorb, 0);
        assertEq(swapData[1].vault, VAULT_ETH_USDC);

        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_ETH_USDC, 32); // same as 15% + then 20% subsequently
        vm.prank(bob);
        IFluidVaultT1(VAULT_ETH_USDC).absorb();

        _reduceVaultOraclePrice(VAULT_WSTETH_ETH, 9);
        vm.prank(bob);
        IFluidVaultT1(VAULT_WSTETH_ETH).absorb();

        // check that liquidation is now available and swap data is as expected
        swapData = resolver.getSwapsAvailable(tokensIn, tokensOut);
        assertEq(swapData[0].inAmt, 364494819510876217438); // 364 ETH
        assertEq(swapData[0].outAmt, 345820852379987135441); // for 345 wstETH
        assertEq(swapData[0].inAmtWithAbsorb, 8647892178185540329665); // 8647 ETH
        assertEq(swapData[0].outAmtWithAbsorb, 8236620852379986965534); // for 8236 wstETH
        assertEq(swapData[0].vault, VAULT_WSTETH_ETH);

        assertEq(swapData[1].inAmt, 1079615031403); // 1.079.615,031403 USDC
        assertEq(swapData[1].outAmt, 425403010045446193701); // 425,403010045446193701 ETH
        assertEq(swapData[1].inAmtWithAbsorb, 1529830467285); // 1.529.830,467285 USDC
        assertEq(swapData[1].outAmtWithAbsorb, 587977363017178865259); // ~587.977 ETH
        assertEq(swapData[1].vault, VAULT_ETH_USDC);
    }

    function test_getSwapCalldata() public {
        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_ETH_USDC, 32); // same as 15% + then 20% subsequently
        vm.prank(bob);
        IFluidVaultT1(VAULT_ETH_USDC).absorb();

        Structs.SwapData memory swapData = resolver.getSwapAvailable(USDC, ETH);
        assertEq(swapData.inAmt, 1079615031403);
        assertEq(swapData.outAmt, 425403010045446193701);
        assertEq(swapData.inAmtWithAbsorb, 1529830467285);
        assertEq(swapData.outAmtWithAbsorb, 587977363017178865259);
        assertEq(swapData.vault, VAULT_ETH_USDC);

        uint256 tokenInAmt = swapData.inAmt / 2;
        uint256 tokenOutAmt = swapData.outAmt / 2;
        bytes memory liquidateCalldata = resolver.getSwapCalldata(
            swapData.vault,
            bob,
            tokenInAmt,
            tokenOutAmt,
            10000, // 1% slippage
            false
        );

        // executing the received calldata should trigger the liquidation and result in desired swap
        address alice = 0x5B541d54e79052B34188db9A43F7b00ea8E2C4B1;
        vm.prank(alice);
        IERC20(USDC).approve(VAULT_ETH_USDC, type(uint256).max);

        uint256 aliceUSDCBalanceBefore = IERC20(USDC).balanceOf(alice);
        uint256 bobETHBalanceBefore = payable(bob).balance;

        vm.prank(alice);
        (bool success, ) = address(VAULT_ETH_USDC).call(liquidateCalldata);
        assertTrue(success);

        assertApproxEqAbs(aliceUSDCBalanceBefore - IERC20(USDC).balanceOf(alice), tokenInAmt, 1);
        // expected output amount is half of 425403010045446193701 so 212701505022723096850
        // we do receive 212701505022328092456
        assertEq(payable(bob).balance - bobETHBalanceBefore, 212701505022328092456);
        assertApproxEqAbs(payable(bob).balance - bobETHBalanceBefore, tokenOutAmt, 1e9); // output amount might be a bit less
        assertLt(payable(bob).balance - bobETHBalanceBefore, tokenOutAmt); // output should be LESS not more

        // completeley liquidate with absorb
        swapData = resolver.getSwapAvailable(USDC, ETH);
        assertEq(swapData.inAmt, 539807515703);
        assertEq(swapData.outAmt, 212701505023513105640);
        assertEq(swapData.inAmtWithAbsorb, 990022951585);
        assertEq(swapData.outAmtWithAbsorb, 375275857995245777197);
        assertEq(swapData.vault, VAULT_ETH_USDC);

        tokenInAmt = swapData.inAmtWithAbsorb;
        tokenOutAmt = swapData.outAmtWithAbsorb;
        liquidateCalldata = resolver.getSwapCalldata(
            swapData.vault,
            bob,
            tokenInAmt,
            tokenOutAmt,
            10000, // 1% slippage
            true
        );

        // executing the received calldata should trigger the liquidation and result in desired swap
        aliceUSDCBalanceBefore = IERC20(USDC).balanceOf(alice);
        bobETHBalanceBefore = payable(bob).balance;

        vm.prank(alice);
        (success, ) = address(VAULT_ETH_USDC).call(liquidateCalldata);
        assertTrue(success);

        assertApproxEqAbs(aliceUSDCBalanceBefore - IERC20(USDC).balanceOf(alice), tokenInAmt, 1);
        assertApproxEqAbs(payable(bob).balance - bobETHBalanceBefore, tokenOutAmt, 1e9); // output amount might be a bit less
        assertLt(payable(bob).balance - bobETHBalanceBefore, tokenOutAmt); // output should be LESS not more

        // ensure no more liquidation available now
        swapData = resolver.getSwapAvailable(USDC, ETH);
        assertEq(swapData.inAmt, 0);
        assertEq(swapData.outAmt, 0);
        assertEq(swapData.inAmtWithAbsorb, 0);
        assertEq(swapData.outAmtWithAbsorb, 0);
        assertEq(swapData.vault, VAULT_ETH_USDC);
    }

    function test_getSwapDataForVault() public {
        // assert initially no swap available
        Structs.SwapData memory swapData = resolver.getSwapDataForVault(VAULT_ETH_USDC);
        assertEq(swapData.inAmt, 0);
        assertEq(swapData.outAmt, 0);
        assertEq(swapData.inAmtWithAbsorb, 0);
        assertEq(swapData.outAmtWithAbsorb, 0);
        assertEq(swapData.vault, VAULT_ETH_USDC);

        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_ETH_USDC, 32);
        vm.prank(bob);
        IFluidVaultT1(VAULT_ETH_USDC).absorb();

        swapData = resolver.getSwapDataForVault(VAULT_ETH_USDC);
        assertEq(swapData.inAmt, 1079615031403); // 1.079.615,031403 USDC
        assertEq(swapData.outAmt, 425403010045446193701); // 425,403010045446193701 ETH
        assertEq(swapData.inAmtWithAbsorb, 1529830467285); // 1.529.830,467285 USDC
        assertEq(swapData.outAmtWithAbsorb, 587977363017178865259); // ~587.977 ETH
        assertEq(swapData.vault, VAULT_ETH_USDC);
    }

    function test_exactInput() public {
        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_ETH_USDC, 32);
        vm.prank(bob);
        IFluidVaultT1(VAULT_ETH_USDC).absorb();

        // check should return available amount if wanted input amount is too big
        (address vault, uint256 actualInAmt, uint256 outAmt, bool withAbsorb) = resolver.exactInput(USDC, ETH, 1e60);
        assertEq(withAbsorb, true); // with absorb is true when amount can not be covered
        assertEq(actualInAmt, 1529830467285); // 1.529.830,467285 USDC
        assertEq(outAmt, 587977363017178865259); // ~587.977 ETH
        assertEq(vault, VAULT_ETH_USDC);

        // ratio out per in with absorb:    587977363017178865259 / 1529830467285 -> 384341517
        // ratio out per in without absorb: 425403010045446193701 / 1079615031403 -> 394032129
        // ratio without absorb is better (more out per in better)

        // check should return exact amount if available
        (vault, actualInAmt, outAmt, withAbsorb) = resolver.exactInput(USDC, ETH, 1e11);
        assertEq(withAbsorb, false);
        assertEq(actualInAmt, 1e11);
        assertEq(outAmt, 39403212966812727290); // 1e11 * 425403010045446193701 / 1079615031403
        assertEq(vault, VAULT_ETH_USDC);

        // reduce oracle price more, causing more debt to go into absorb territory but when not running absorb,
        // liquidate() without absorb reverts so now we get a withAbsorb = true case
        _reduceVaultOraclePrice(VAULT_ETH_USDC, 1);
        Structs.SwapData memory swapData = resolver.getSwapDataForVault(VAULT_ETH_USDC);
        assertEq(swapData.inAmt, 0); 
        assertEq(swapData.outAmt, 0);
        assertEq(swapData.inAmtWithAbsorb, 450215435882);
        assertEq(swapData.outAmtWithAbsorb, 162574352971732671557);
        assertEq(swapData.vault, VAULT_ETH_USDC);

        (vault, actualInAmt, outAmt, withAbsorb) = resolver.exactInput(USDC, ETH, 1e11);
        assertEq(withAbsorb, true);
        assertEq(actualInAmt, 1e11);
        assertEq(outAmt, 36110346295266268965); // 1e11 * 162574352971732671557 / 450215435882
        assertEq(vault, VAULT_ETH_USDC);

        // check execution is as expected
         bytes memory liquidateCalldata = resolver.getSwapCalldata(
            swapData.vault,
            bob,
            actualInAmt,
            outAmt,
            10000, // 1% slippage
            withAbsorb
        );

        // executing the received calldata should trigger the liquidation and result in desired swap
        address alice = 0x5B541d54e79052B34188db9A43F7b00ea8E2C4B1;
        vm.prank(alice);
        IERC20(USDC).approve(VAULT_ETH_USDC, type(uint256).max);

        uint256 aliceUSDCBalanceBefore = IERC20(USDC).balanceOf(alice);
        uint256 bobETHBalanceBefore = payable(bob).balance;

        vm.prank(alice);
        (bool success, ) = address(VAULT_ETH_USDC).call(liquidateCalldata);
        assertTrue(success);

        assertApproxEqAbs(aliceUSDCBalanceBefore - IERC20(USDC).balanceOf(alice), actualInAmt, 1);
        assertApproxEqAbs(payable(bob).balance - bobETHBalanceBefore, outAmt, 1e8); // output amount might be a bit less
        assertLt(payable(bob).balance - bobETHBalanceBefore, outAmt); // output should be LESS not more
    }

    function test_exactOutput() public {
        // set a mockOracle as oracle and move positions into liquidation territory
        _reduceVaultOraclePrice(VAULT_ETH_USDC, 32);
        vm.prank(bob);
        IFluidVaultT1(VAULT_ETH_USDC).absorb();

        // check should return available amount if wanted output amount is too big
        (address vault, uint256 inAmt, uint256 actualOutAmt, bool withAbsorb) = resolver.exactOutput(USDC, ETH, 1e60);
        assertEq(withAbsorb, true); // with absorb is true when amount can not be covered
        assertEq(inAmt, 1529830467285); // 1.529.830,467285 USDC
        assertEq(actualOutAmt, 587977363017178865259); // ~587.977 ETH
        assertEq(vault, VAULT_ETH_USDC);

        // ratio in per out with absorb:    1529830467285 * 1e18 / 587977363017178865259 -> 2601852662
        // ratio in per out without absorb: 1079615031403 * 1e18 / 425403010045446193701 -> 2537864109
        // ratio without absorb is better (less in per out needed better)

        // check should return exact amount if available
        (vault, inAmt, actualOutAmt, withAbsorb) = resolver.exactOutput(USDC, ETH, 1e20);
        assertEq(withAbsorb, false);
        // 1e20 * 1079615031403 * 1e27 / 425403010045446193701 / 1e27 = 253786410981
        // -> 1e20 * 2537864109818272644 / 1e27 = 253786410981
        assertEq(inAmt, 253786410981); 
        assertEq(actualOutAmt, 1e20);
        assertEq(vault, VAULT_ETH_USDC);

        // reduce oracle price more, causing more debt to go into absorb territory but when not running absorb,
        // liquidate() without absorb reverts so now we get a withAbsorb = true case
        _reduceVaultOraclePrice(VAULT_ETH_USDC, 1);
        Structs.SwapData memory swapData = resolver.getSwapDataForVault(VAULT_ETH_USDC);
        assertEq(swapData.inAmt, 0); 
        assertEq(swapData.outAmt, 0);
        assertEq(swapData.inAmtWithAbsorb, 450215435882);
        assertEq(swapData.outAmtWithAbsorb, 162574352971732671557);
        assertEq(swapData.vault, VAULT_ETH_USDC);

        (vault, inAmt, actualOutAmt, withAbsorb) = resolver.exactOutput(USDC, ETH, 1e20);
        assertEq(withAbsorb, true);
        assertEq(inAmt, 276928942143); // 1e20 * 450215435882 / 162574352971732671557
        assertEq(actualOutAmt, 1e20);
        assertEq(vault, VAULT_ETH_USDC);

        // check execution is as expected
         bytes memory liquidateCalldata = resolver.getSwapCalldata(
            swapData.vault,
            bob,
            inAmt,
            actualOutAmt,
            10000, // 1% slippage
            withAbsorb
        );

        // executing the received calldata should trigger the liquidation and result in desired swap
        address alice = 0x5B541d54e79052B34188db9A43F7b00ea8E2C4B1;
        vm.prank(alice);
        IERC20(USDC).approve(VAULT_ETH_USDC, type(uint256).max);

        uint256 aliceUSDCBalanceBefore = IERC20(USDC).balanceOf(alice);
        uint256 bobETHBalanceBefore = payable(bob).balance;

        vm.prank(alice);
        (bool success, ) = address(VAULT_ETH_USDC).call(liquidateCalldata);
        assertTrue(success);

        assertApproxEqAbs(aliceUSDCBalanceBefore - IERC20(USDC).balanceOf(alice), inAmt, 1);
        assertApproxEqAbs(payable(bob).balance - bobETHBalanceBefore, actualOutAmt, 1e9); // output amount might be a bit less
        assertLt(payable(bob).balance - bobETHBalanceBefore, actualOutAmt); // output should be LESS not more
    }

    function _reduceVaultOraclePrice(address vault, uint256 reductionInPercent) internal {
        FluidVaultResolver.VaultEntireData memory vaultData = VAULT_RESOLVER.getVaultEntireData(vault);

        uint256 currentOraclePrice = vaultData.configs.oraclePrice;

        // set a mockOracle as oracle and move positions into liquidation territory
        MockOracle oracle = new MockOracle();

        vm.prank(GOVERNANCE);
        FluidVaultT1Admin(vault).updateOracle(address(oracle));

        oracle.setPrice((currentOraclePrice * (100 - reductionInPercent)) / 100); // simulate price drop
        vaultData = VAULT_RESOLVER.getVaultEntireData(vault);
        assertLt(vaultData.configs.oraclePrice, currentOraclePrice);
    }
}
