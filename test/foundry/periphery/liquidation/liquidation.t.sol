//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LiquidityBaseTest } from "../../liquidity/liquidityBaseTest.t.sol";
import { IFluidLiquidityLogic } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidVaultT1 } from "../../../../contracts/protocols/vault/vaultT1/coreModule/main.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";
import { VaultFactoryTest } from "../../vaultT1/factory/vaultFactory.t.sol";
import { VaultT1BaseTest } from "../../vaultT1/vault/vault.t.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { VaultT1Liquidator } from "../../../../contracts/periphery/liquidation/main.sol";

import { TickMath } from "../../../../contracts/libraries/tickMath.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";

import { Structs as VaultStructs } from "../../../../contracts/periphery/resolvers/vault/structs.sol";

import "../../testERC20.sol";
import "../../testERC20Dec6.sol";
import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";

import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

import { MockFLA } from "../../../../contracts/mocks/mockFLA.sol";
import { MockSwap } from "../../../../contracts/mocks/mockSwap.sol";
import { MockWETH } from "../../../../contracts/mocks/mockWETH.sol";

contract VaultT1LiquidatorTest is VaultT1BaseTest {
    using stdStorage for StdStorage;

    VaultT1Liquidator vaultT1Liquidation;
    MockWETH wETH;
    MockFLA fla;
    MockSwap swapAggr;

    function setUp() public virtual override {
        super.setUp();

        wETH = new MockWETH();
        fla = new MockFLA();
        swapAggr = new MockSwap();
        address[] memory rebalancers = new address[](1);
        rebalancers[0] = address(alice);
        vaultT1Liquidation = new VaultT1Liquidator(address(bob), address(fla), address(wETH), rebalancers);

        TestERC20(address(DAI)).mint(address(fla), 1e50 ether);
        TestERC20(address(DAI)).mint(address(swapAggr), 1e50 ether);
        TestERC20(address(USDC)).mint(address(fla), 1e50 ether);
        TestERC20(address(USDC)).mint(address(swapAggr), 1e50 ether);
        TestERC20(address(DAI)).mint(address(vaultT1Liquidation), 1e50 ether);
        TestERC20(address(USDC)).mint(address(vaultT1Liquidation), 1e50 ether);
        vm.deal(alice, 500 ether);
        vm.startPrank(alice);
        wETH.deposit{ value: 200 ether }();
        wETH.transfer(address(fla), 100 ether);
        wETH.transfer(address(swapAggr), 100 ether);
        vm.stopPrank();
        vm.deal(address(swapAggr), 1e50 ether);
        vm.deal(address(vaultT1Liquidation), 1e20 ether);
    }

    function testVaultT1LiquidatorContractNativeCollateral() public {
        int nativeCol_ = 5 * 1e18;
        int debt_ = 7900 * 1e18;

        uint oracleThreePrice_ = 1e27 * (2000); // 1 ETH = 2000 DAI

        // 1e27 * 2000 * 1e18 / 1 * 1e18
        _setOracleThreePrice(oracleThreePrice_);

        vm.prank(alice);
        vaultThree.operate{ value: uint(nativeCol_) }(
            0, // new position
            nativeCol_,
            debt_,
            alice
        );
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(address(vaultThree));
        assertNotEq(vaultData_.configs.oraclePriceOperate, 0);
        assertNotEq(vaultData_.configs.oraclePriceLiquidate, 0);
        assertNotEq(vaultData_.totalSupplyAndBorrow.totalSupplyVault, 0);
        assertNotEq(vaultData_.totalSupplyAndBorrow.totalBorrowVault, 0);

        oracleThreePrice_ = (oracleThreePrice_ * 95) / 100;
        _setOracleThreePrice(oracleThreePrice_);

        _liquidate(address(vaultThree));
    }

    function testVaultT1LiquidatorContractNativeDebt() public {
        int collateral = 10_000 * 1e18;
        int debt = 3.995 * 1e18;
        uint oraclePrice = (1e27 * (1 * 1e18)) / (2000 * 1e18); // 1 ETH = 2000 DAI => 1 DAI => 1/2000 ETH

        address vault = address(vaultFour);

        // 1e27 * 1 * 1e18 / 2000 * 1e18
        _setOracleFourPrice(oraclePrice);

        vm.prank(alice);
        vaultFour.operate(
            0, // new position
            collateral,
            debt,
            alice
        );
        
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(address(vault));
        assertNotEq(vaultData_.configs.oraclePriceOperate, 0);
        assertNotEq(vaultData_.configs.oraclePriceLiquidate, 0);
        assertNotEq(vaultData_.totalSupplyAndBorrow.totalSupplyVault, 0);
        assertNotEq(vaultData_.totalSupplyAndBorrow.totalBorrowVault, 0);
        console.log("Oracle data oraclePriceOperate", vaultData_.configs.oraclePriceOperate);
        console.log("Oracle data oraclePriceLiquidate", vaultData_.configs.oraclePriceLiquidate);
        console.log("Oracle data", vaultData_.totalSupplyAndBorrow.totalSupplyVault, 0);
        console.log("Oracle data", vaultData_.totalSupplyAndBorrow.totalBorrowVault, 0);

        oraclePrice = (oraclePrice * 975) / 1000;
        _setOracleFourPrice(oraclePrice);
        vaultData_ = vaultResolver.getVaultEntireData(address(vault));
        assertNotEq(vaultData_.configs.oraclePriceOperate, 0);
        assertNotEq(vaultData_.configs.oraclePriceLiquidate, 0);
        assertNotEq(vaultData_.totalSupplyAndBorrow.totalSupplyVault, 0);
        assertNotEq(vaultData_.totalSupplyAndBorrow.totalBorrowVault, 0);
        console.log("Oracle data after oraclePriceOperate", vaultData_.configs.oraclePriceOperate);
        console.log("Oracle data after oraclePriceLiquidate", vaultData_.configs.oraclePriceLiquidate);

        _liquidate(vault);
    }

    function _liquidate(address vault) internal {
        VaultStructs.LiquidationStruct memory liquidationData_ = vaultResolver.getVaultLiquidation(address(vault), 0);
        assertNotEq(liquidationData_.tokenOutAmtOne, 0, "liquidationData_.tokenOutAmtOne: Before first liquidation");
        assertNotEq(liquidationData_.tokenInAmtOne, 0, "liquidationData_.tokenInAmtOne: Before first liquidation");
        assertNotEq(liquidationData_.tokenOutAmtTwo, 0, "liquidationData_.tokenOutAmtTwo: Before first liquidation");
        assertNotEq(liquidationData_.tokenInAmtTwo, 0, "liquidationData_.tokenInAmtTwo: Before first liquidation");

        console.log("liquidationData_.tokenOutAmtOne: Before first liquidation", liquidationData_.tokenOutAmtOne);
        console.log("liquidationData_.tokenInAmtOne: Before first liquidation", liquidationData_.tokenInAmtOne);
        console.log("liquidationData_.tokenOutAmtTwo: Before first liquidation", liquidationData_.tokenOutAmtTwo);
        console.log("liquidationData_.tokenInAmtTwo: Before first liquidation", liquidationData_.tokenInAmtTwo);

        VaultT1Liquidator.LiquidationParams memory liquidationParams = VaultT1Liquidator.LiquidationParams({
            vault: address(vault),
            supply: liquidationData_.tokenOut,
            borrow: liquidationData_.tokenIn,
            supplyAmount: (liquidationData_.tokenOutAmtOne * 110) / 100,
            borrowAmount: (liquidationData_.tokenInAmtOne * 110) / 100,
            colPerUnitDebt: 0,
            absorb: true,
            swapRouter: address(swapAggr),
            swapApproval: address(swapAggr),
            swapData: abi.encodeWithSelector(
                MockSwap.swap.selector,
                liquidationData_.tokenIn, // buy
                liquidationData_.tokenOut, // sell,
                liquidationData_.tokenInAmtOne,
                liquidationData_.tokenOutAmtOne
            ),
            route: 5
        });

        vm.prank(alice);
        vaultT1Liquidation.liquidation(liquidationParams);

        liquidationData_ = vaultResolver.getVaultLiquidation(address(vault), 0);
        assertEq(liquidationData_.tokenOutAmtOne, 0, "liquidationData_.tokenOutAmtOne: After first liquidation");
        assertEq(liquidationData_.tokenInAmtOne, 0, "liquidationData_.tokenInAmtOne: After first liquidation");
        assertEq(liquidationData_.tokenOutAmtTwo, 0, "liquidationData_.tokenOutAmtTwo: After first liquidation");
        assertEq(liquidationData_.tokenInAmtTwo, 0, "liquidationData_.tokenInAmtTwo: After first liquidation");

        liquidationData_ = vaultResolver.getVaultLiquidation(address(vault), 0);
        assertEq(liquidationData_.tokenOutAmtOne, 0, "liquidationData_.tokenOutAmtOne: Before second liquidation");
        assertEq(liquidationData_.tokenInAmtOne, 0, "liquidationData_.tokenInAmtOne: Before second liquidation");
        assertEq(liquidationData_.tokenOutAmtTwo, 0, "liquidationData_.tokenOutAmtTwo: Before second liquidation");
        assertEq(liquidationData_.tokenInAmtTwo, 0, "liquidationData_.tokenInAmtTwo: Before second liquidation");

        liquidationParams = VaultT1Liquidator.LiquidationParams({
            vault: address(vault),
            supply: liquidationData_.tokenOut,
            borrow: liquidationData_.tokenIn,
            supplyAmount: (liquidationData_.tokenOutAmtOne * 110) / 100,
            borrowAmount: (liquidationData_.tokenInAmtOne * 110) / 100,
            colPerUnitDebt: 0,
            absorb: true,
            swapRouter: address(swapAggr),
            swapApproval: address(swapAggr),
            swapData: abi.encodeWithSelector(
                MockSwap.swap.selector,
                liquidationData_.tokenIn, // buy
                liquidationData_.tokenOut, // sell,
                liquidationData_.tokenInAmtOne,
                liquidationData_.tokenOutAmtOne
            ),
            route: 5
        });

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultT1__InvalidLiquidationAmt)
        );
        vaultT1Liquidation.liquidation(liquidationParams);

        liquidationData_ = vaultResolver.getVaultLiquidation(address(vault), 0);
        assertEq(liquidationData_.tokenOutAmtOne, 0, "liquidationData_.tokenOutAmtOne: After second liquidation");
        assertEq(liquidationData_.tokenInAmtOne, 0, "liquidationData_.tokenInAmtOne: After second liquidation");
        assertEq(liquidationData_.tokenOutAmtTwo, 0, "liquidationData_.tokenOutAmtTwo: After second liquidation");
        assertEq(liquidationData_.tokenInAmtTwo, 0, "liquidationData_.tokenInAmtTwo: After second liquidation");
    }
}
