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

import { FluidWalletFactory } from "../../../../contracts/periphery/wallet/factory/main.sol";
import { FluidWalletFactoryProxy } from "../../../../contracts/periphery/wallet/factory/proxy.sol";

import { FluidWalletImplementation, FluidWalletErrorsAndEvents } from "../../../../contracts/periphery/wallet/wallet/main.sol";
import { FluidWallet } from "../../../../contracts/periphery/wallet/wallet/proxy.sol";

interface InstaFlashInterface {
    function flashLoan(address[] memory tokens, uint256[] memory amts, uint route, bytes memory data, bytes memory extraData) external;
}

contract FluidWalletFactoryTest is VaultT1BaseTest {
    using stdStorage for StdStorage;

    FluidWalletFactory fluidWalletFactory;
    FluidWalletFactory fluidWalletFactoryImplementation;
    FluidWalletImplementation fluidWalletImplementation;
    MockWETH wETH;
    MockFLA fla;
    MockSwap swapAggr;

    function setUp() public virtual override {
        super.setUp();

        wETH = new MockWETH();
        fla = new MockFLA();
        swapAggr = new MockSwap();

        vm.startPrank(bob);
        FluidWalletFactoryProxy proxy = new FluidWalletFactoryProxy(
            address(new FluidWalletFactory(address(vaultFactory), address(0))),
            abi.encode()
        );
        fluidWalletFactory = FluidWalletFactory(payable(proxy));
        fluidWalletFactory.initialize(address(bob));

        fluidWalletFactoryImplementation = new FluidWalletFactory(address(vaultFactory), address(proxy));
        FluidWalletFactory(payable(proxy)).upgradeTo(address(fluidWalletFactoryImplementation));
        
        fluidWalletImplementation = new FluidWalletImplementation(
            address(vaultFactory),
            address(proxy)
        );

        fluidWalletFactory.changeImplementation(address(fluidWalletImplementation));
        vm.stopPrank();

        assertNotEq(fluidWalletFactory.walletImplementation(), address(0));

        TestERC20(address(DAI)).mint(address(fla), 1e50 ether);
        TestERC20(address(DAI)).mint(address(swapAggr), 1e50 ether);
        TestERC20(address(USDC)).mint(address(fla), 1e50 ether);
        TestERC20(address(USDC)).mint(address(swapAggr), 1e50 ether);
        // TestERC20(address(DAI)).mint(address(vaultT1Migrator), 1e50 ether);
        // TestERC20(address(USDC)).mint(address(vaultT1Migrator), 1e50 ether);
        vm.deal(alice, 1e7 ether);
        vm.startPrank(alice);
        wETH.deposit{ value: 1e6 ether }();
        wETH.transfer(address(fla), 1e5 ether);
        wETH.transfer(address(swapAggr), 100 ether);
        vm.stopPrank();
        vm.deal(address(swapAggr), 1e50 ether);
        // vm.deal(address(vaultT1Migrator), 1e20 ether);
    }

    function testFailUpgradableOfImplementationNonOwner() public {
        address fluidWalletFactoryImplementationNew = address(new FluidWalletFactory(address(vaultFactory), address(fluidWalletFactory)));

        vm.prank(alice);
        fluidWalletFactory.upgradeTo(fluidWalletFactoryImplementationNew);
    }

    function testUpgradableOfImplementation() public {
        address fluidWalletFactoryImplementationNew = address(new FluidWalletFactory(address(vaultFactory), address(fluidWalletFactory)));

        vm.prank(bob);
        fluidWalletFactory.upgradeTo(fluidWalletFactoryImplementationNew);
    }

    function testDeploymentOfWallet() public {
        address wallet_ = fluidWalletFactory.deploy(address(alice));
        assertEq(wallet_, fluidWalletFactory.computeWallet(address(alice)));
    }

    function testSimpleERC20Actions() public {
        address wallet_ = fluidWalletFactory.deploy(address(alice));

        FluidWalletImplementation.Action[] memory actions_ = new FluidWalletImplementation.Action[](1);
        actions_[0] = FluidWalletErrorsAndEvents.Action({
            target: address(DAI),
            data: abi.encodeWithSignature("transfer(address,uint256)", alice, 1e18),
            operation: 0,
            value: 0
        });

        TestERC20(address(DAI)).mint(address(wallet_), 1e50 ether);

        vm.prank(alice);
        FluidWalletImplementation(wallet_).cast(actions_);
    }

    function testFailFlashloanActionsDueToOperation() public {
        address wallet_ = fluidWalletFactory.deploy(address(alice));

        FluidWalletImplementation.Action[] memory actions_ = new FluidWalletImplementation.Action[](1);

        address[] memory tokens_ = new address[](1);
        uint256[] memory amounts_ = new uint256[](1);

        FluidWalletImplementation.Action[] memory flashloanActions_ = new FluidWalletImplementation.Action[](1);
        flashloanActions_[0] = FluidWalletErrorsAndEvents.Action({
            target: address(DAI),
            data: abi.encodeWithSignature("transfer(address,uint256)", address(fla), 10 ether),
            operation: 0,
            value: 0
        });


        tokens_[0] = address(DAI);
        amounts_[0] = 10 ether;

        actions_[0] = FluidWalletErrorsAndEvents.Action({
            target: address(fla),
            data: abi.encodeWithSelector(
                InstaFlashInterface.flashLoan.selector,
                tokens_,
                amounts_,
                5,
                abi.encode(flashloanActions_),
                abi.encode()
            ),
            operation: 0,
            value: 0
        });

        TestERC20(address(DAI)).mint(address(wallet_), 1e50 ether);

        vm.prank(alice);
        FluidWalletImplementation(wallet_).cast(actions_);
    }

    function testFlashloanActions() public {
        address wallet_ = fluidWalletFactory.deploy(address(alice));

        FluidWalletImplementation.Action[] memory actions_ = new FluidWalletImplementation.Action[](1);

        address[] memory tokens_ = new address[](1);
        uint256[] memory amounts_ = new uint256[](1);

        FluidWalletImplementation.Action[] memory flashloanActions_ = new FluidWalletImplementation.Action[](1);
        flashloanActions_[0] = FluidWalletErrorsAndEvents.Action({
            target: address(DAI),
            data: abi.encodeWithSignature("transfer(address,uint256)", address(fla), 10 ether),
            operation: 0,
            value: 0
        });


        tokens_[0] = address(DAI);
        amounts_[0] = 10 ether;

        actions_[0] = FluidWalletErrorsAndEvents.Action({
            target: address(fla),
            data: abi.encodeWithSelector(
                InstaFlashInterface.flashLoan.selector,
                tokens_,
                amounts_,
                5,
                abi.encode(flashloanActions_),
                abi.encode()
            ),
            operation: 2,
            value: 0
        });

        TestERC20(address(DAI)).mint(address(wallet_), 1e50 ether);

        vm.prank(alice);
        FluidWalletImplementation(wallet_).cast(actions_);

        assertEq(uint256(vm.load(wallet_, bytes32(uint256(1)))), 1);
    }

    function testVaultOperation() public {
        address wallet_ = fluidWalletFactory.computeWallet(address(alice));

        int collateral = 10_000 * 1e18;
        int debt = 7000 * 1e6;
        uint oraclePrice = (1e27 * (1 * 1e6)) / (1 * 1e18); // 1 DAI = 1 USDC

        _setOracleTwoPrice(oraclePrice);

        vm.prank(alice);
        (uint256 nftId_, ,) = vaultTwo.operate(
            0,
            collateral,
            debt,
            alice
        );

        FluidWalletImplementation.Action[] memory actions_ = new FluidWalletImplementation.Action[](2);
        actions_[0] = FluidWalletErrorsAndEvents.Action({
            target: address(DAI),
            data: abi.encodeWithSignature(
                "approve(address,uint256)",
                address(vaultTwo),
                uint256(collateral)
            ),
            operation: 0,
            value: 0
        });

        actions_[1] = FluidWalletErrorsAndEvents.Action({
            target: address(vaultTwo),
            data: abi.encodeWithSelector(
                vaultTwo.operate.selector,
                nftId_,
                collateral,
                debt,
                wallet_
            ),
            operation: 0,
            value: 0
        });

        TestERC20(address(DAI)).mint(address(wallet_), 1e50 ether);

        vm.prank(alice);
        vaultFactory.safeTransferFrom(
            alice,
            address(fluidWalletFactory),
            nftId_,
            abi.encode(actions_)
        );

        assertEq(vaultFactory.ownerOf(nftId_), alice, "Owner-of-nft-is-not-alice");
        assertEq(vaultFactory.balanceOf(wallet_), 0, "wallet-of-balance-is-not");
        assertEq(DAI.balanceOf(wallet_), 0, "DAI-balance-is-not-zero");
        assertEq(USDC.balanceOf(wallet_), 0, "USDC-balance-is-not-zero");
        assertEq(uint256(vm.load(wallet_, bytes32(uint256(1)))), 1);
        assertEq(vaultFactory.ownerOf(nftId_), alice);
    }

    function testVaultOperationNativeDebt() public {
        address wallet_ = fluidWalletFactory.computeWallet(address(alice));

        int collateral = 10_000 * 1e6;
        int debt = 3.995 * 1e18;
        uint oraclePrice = (1e27 * (1 * 1e18)) / (2000 * 1e6); // 1 ETH = 2000 USDC => 1 USDC => 1/2000 ETH

        // 1e27 * 1 * 1e18 / 2000 * 1e6
        _setOracleFourPrice(oraclePrice);

        vm.prank(alice);
        (uint256 nftId_, , ) = vaultFour.operate(
            0, // new position
            collateral,
            debt,
            alice
        );

        FluidWalletImplementation.Action[] memory actions_ = new FluidWalletImplementation.Action[](2);
        actions_[0] = FluidWalletErrorsAndEvents.Action({
            target: address(USDC),
            data: abi.encodeWithSignature(
                "approve(address,uint256)",
                address(vaultFour),
                uint256(collateral)
            ),
            operation: 0,
            value: 0
        });

        actions_[1] = FluidWalletErrorsAndEvents.Action({
            target: address(vaultFour),
            data: abi.encodeWithSelector(
                vaultFour.operate.selector,
                nftId_,
                collateral,
                debt,
                wallet_
            ),
            operation: 0,
            value: 0
        });

        TestERC20(address(USDC)).mint(address(wallet_), 1e50 * 1e6);

        vm.prank(alice);
        vaultFactory.safeTransferFrom(
            alice,
            address(fluidWalletFactory),
            nftId_,
            abi.encode(actions_)
        );

        assertEq(vaultFactory.ownerOf(nftId_), alice, "Owner-of-nft-is-not-alice");
        assertEq(vaultFactory.balanceOf(wallet_), 0, "wallet-of-balance-is-not");
        assertEq(USDC.balanceOf(wallet_), 0, "USDC-balance-is-not-zero");
        assertEq(wallet_.balance, 0, "ETH-balance-is-not-zero");
        assertEq(uint256(vm.load(wallet_, bytes32(uint256(1)))), 1);
        assertEq(vaultFactory.ownerOf(nftId_), alice);
    }
}
