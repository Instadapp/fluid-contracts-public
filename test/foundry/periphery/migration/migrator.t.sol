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

import { VaultT1Migrator } from "../../../../contracts/periphery/migration/main.sol";

import { FluidVaultFactory } from "../../../../contracts/protocols/vault/factory/main.sol";

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

contract VaultT1MigratorTest is VaultT1BaseTest {
    using stdStorage for StdStorage;

    FluidVaultT1 vaultOne2;
    FluidVaultT1 vaultTwo2;
    FluidVaultT1 vaultThree2;
    FluidVaultT1 vaultFour2;

    VaultT1Migrator vaultT1Migrator;
    MockWETH wETH;
    MockFLA fla;
    MockSwap swapAggr;

    FluidVaultFactory vaultFactory2;

    FluidVaultResolver vaultResolver2;

    function setUp() public virtual override {
        super.setUp();

        wETH = new MockWETH();
        fla = new MockFLA();
        swapAggr = new MockSwap();
        address[] memory rebalancers = new address[](1);
        rebalancers[0] = address(alice);

        vaultFactory2 = new FluidVaultFactory(admin);
        vm.prank(admin);
        vaultFactory2.setDeployer(alice, true);

        vm.prank(admin);
        vaultFactory2.setGlobalAuth(alice, true);
        vm.prank(admin);
        vaultFactory2.setVaultDeploymentLogic(address(vaultT1Deployer), true);

        vaultT1Migrator = new VaultT1Migrator(
            address(bob),
            address(fla),
            address(wETH),
            address(vaultFactory),
            address(vaultFactory2)
        );

        vm.startPrank(bob);
        vaultT1Migrator.setFlashloanConfig(address(DAI), 5, 1e6 * 1e18);
        vaultT1Migrator.setFlashloanConfig(address(USDC), 5, 1e6 * 1e6);
        vaultT1Migrator.setFlashloanConfig(address(nativeToken), 5, 1e4 * 1e18);
        vm.stopPrank();

        TestERC20(address(DAI)).mint(address(fla), 1e50 ether);
        TestERC20(address(DAI)).mint(address(swapAggr), 1e50 ether);
        TestERC20(address(USDC)).mint(address(fla), 1e50 ether);
        TestERC20(address(USDC)).mint(address(swapAggr), 1e50 ether);
        TestERC20(address(DAI)).mint(address(vaultT1Migrator), 1e50 ether);
        TestERC20(address(USDC)).mint(address(vaultT1Migrator), 1e50 ether);
        vm.deal(alice, 1e7 ether);
        vm.startPrank(alice);
        wETH.deposit{ value: 1e6 ether }();
        wETH.transfer(address(fla), 1e5 ether);
        wETH.transfer(address(swapAggr), 100 ether);
        vm.stopPrank();
        vm.deal(address(swapAggr), 1e50 ether);
        vm.deal(address(vaultT1Migrator), 1e20 ether);

        vaultResolver2 = new FluidVaultResolver(address(vaultFactory2), address(liquidityResolver));

        supplyToken = TestERC20Dec6(address(USDC)); // TODO UPDATE
        borrowToken = TestERC20(address(DAI));

        // FluidVaultT1(_deployVaultTokens2(address(supplyToken), address(borrowToken)));
        vaultOne2 = FluidVaultT1(_deployVaultTokens2(address(supplyToken), address(borrowToken)));
        vaultTwo2 = FluidVaultT1(_deployVaultTokens2(address(borrowToken), address(supplyToken)));
        vaultThree2 = FluidVaultT1(_deployVaultTokens2(address(nativeToken), address(borrowToken)));
        vaultFour2 = FluidVaultT1(_deployVaultTokens2(address(supplyToken), address(nativeToken)));

        MockOracle(_setDefaultVaultSettings(address(vaultOne2)));
        MockOracle(_setDefaultVaultSettings(address(vaultTwo2)));
        MockOracle(_setDefaultVaultSettings(address(vaultThree2)));
        MockOracle(_setDefaultVaultSettings(address(vaultFour2)));

        vm.startPrank(alice);
        FluidVaultT1Admin vaultAdmin_ = FluidVaultT1Admin(address(vaultOne2));
        vaultAdmin_.updateOracle(address(oracleOne));

        vaultAdmin_ = FluidVaultT1Admin(address(vaultTwo2));
        vaultAdmin_.updateOracle(address(oracleTwo));

        vaultAdmin_ = FluidVaultT1Admin(address(vaultThree2));
        vaultAdmin_.updateOracle(address(oracleThree));

        vaultAdmin_ = FluidVaultT1Admin(address(vaultFour2));
        vaultAdmin_.updateOracle(address(oracleFour));
        vm.stopPrank();

        _setUserAllowancesDefault(address(liquidity), address(admin), address(supplyToken), address(vaultOne2));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(borrowToken), address(vaultOne2));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(borrowToken), address(vaultTwo2));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(supplyToken), address(vaultTwo2));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(nativeToken), address(vaultThree2));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(borrowToken), address(vaultThree2));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(supplyToken), address(vaultFour2));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(nativeToken), address(vaultFour2));

        _setApproval(USDC, address(vaultOne2), alice);
        _setApproval(DAI, address(vaultOne2), alice);
        _setApproval(USDC, address(vaultTwo2), alice);
        _setApproval(DAI, address(vaultTwo2), alice);
        _setApproval(USDC, address(vaultThree2), alice);
        _setApproval(DAI, address(vaultThree2), alice);
        _setApproval(USDC, address(vaultFour2), alice);
        _setApproval(DAI, address(vaultFour2), alice);
    }

    function _deployVaultTokens2(address supplyToken_, address borrowToken_) internal returns (address vault_) {
        vm.prank(alice);
        bytes memory vaultT1CreationCode = abi.encodeCall(vaultT1Deployer.vaultT1, (supplyToken_, borrowToken_));
        vault_ = address(FluidVaultT1(vaultFactory2.deployVault(address(vaultT1Deployer), vaultT1CreationCode)));
    }

    function testMigrationVaultOne() public {
        int collateral = 10_000 * 1e6;
        int debt = 7000 * 1e18;
        uint oraclePrice = (1e27 * (1 * 1e18)) / (1 * 1e6); // 1 DAI = 1 USDC

        _setOracleOnePrice(oraclePrice);

        vm.prank(bob);
        vaultOne.operate(0, collateral * 10, debt * 10, alice);

        vm.startPrank(alice);
        (uint256 nftId, , ) = vaultOne.operate(0, collateral, debt, alice);

        vaultFactory.safeTransferFrom(alice, address(vaultT1Migrator), nftId);
    }

    function testMigrationVaultTwo() public {
        int collateral = 10_000 * 1e18;
        int debt = 7000 * 1e6;
        uint oraclePrice = (1e27 * (1 * 1e6)) / (1 * 1e18); // 1 DAI = 1 USDC

        _setOracleTwoPrice(oraclePrice);

        vm.prank(bob);
        vaultTwo.operate(0, collateral * 10, debt * 10, alice);

        vm.startPrank(alice);
        (uint256 nftId, , ) = vaultTwo.operate(0, collateral, debt, alice);

        vaultFactory.safeTransferFrom(alice, address(vaultT1Migrator), nftId);
    }

    function testMigrationNativeDebt() public {
        int collateral = 10_000 * 1e6;
        int debt = 3.5 * 1e18;
        uint oraclePrice = (1e27 * (1 * 1e18)) / (2000 * 1e6); // 1 ETH = 2000 USDC

        _setOracleFourPrice(oraclePrice);

        vm.prank(bob);
        vaultFour.operate(0, collateral * 10, debt * 10, alice);

        vm.startPrank(alice);
        (uint256 nftId, , ) = vaultFour.operate(0, collateral, debt, alice);

        vaultFactory.safeTransferFrom(alice, address(vaultT1Migrator), nftId);
    }

    function testMigrationNativeCollateral() public {
        int collateral = 5 * 1e18;
        int debt = 7000 * 1e18;
        uint oraclePrice = (1e27 * (2000 * 1e18)) / (1 * 1e18); // 1 ETH = 2000 DAI

        _setOracleThreePrice(oraclePrice);

        vm.prank(bob);
        vaultThree.operate{ value: uint256(collateral * 10) }(0, collateral * 10, debt * 10, alice);

        vm.startPrank(alice);
        (uint256 nftId, , ) = vaultThree.operate{ value: uint256(collateral) }(0, collateral, debt, alice);

        vaultFactory.safeTransferFrom(alice, address(vaultT1Migrator), nftId);
    }
}
