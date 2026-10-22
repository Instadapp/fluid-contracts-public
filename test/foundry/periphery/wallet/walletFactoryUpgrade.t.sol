//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "./walletFactory.t.sol";
import { FluidWalletFactoryErrorsAndEvents } from "../../../../contracts/periphery/wallet/factory/main.sol";
import { FluidWallet } from "../../../../contracts/periphery/wallet/wallet/proxy.sol";

contract FluidWalletFactoryUpgradeTest is FluidWalletFactoryTest {
    function _transferOneDaiToAlice() internal returns (FluidWalletImplementation.Action[] memory actions_) {
        actions_ = new FluidWalletImplementation.Action[](1);
        actions_[0] = FluidWalletErrorsAndEvents.Action({
            target: address(DAI),
            data: abi.encodeWithSignature("transfer(address,uint256)", alice, 1 ether),
            operation: 0,
            value: 0
        });
    }

    function test_upgradeTo_KeepsWalletTemplateAndExistingWallets() public {
        address wallet_ = fluidWalletFactory.deploy(address(alice));
        TestERC20(address(DAI)).mint(wallet_, 100 ether);
        address template_ = fluidWalletFactory.WALLET_PROXY();

        address newLogic_ = address(
            new FluidWalletFactory(
                address(vaultFactory),
                address(fluidWalletFactory),
                fluidWalletFactory.WALLET_PROXY()
            )
        );
        assertEq(FluidWalletFactory(payable(newLogic_)).WALLET_PROXY(), template_, "new logic must reuse the template");

        vm.prank(bob);
        fluidWalletFactory.upgradeTo(newLogic_);

        assertEq(fluidWalletFactory.WALLET_PROXY(), template_);
        assertEq(fluidWalletFactory.computeWallet(alice), wallet_);
        assertEq(fluidWalletFactory.deploy(address(alice)), wallet_);

        vm.prank(alice);
        FluidWalletImplementation(payable(wallet_)).cast(_transferOneDaiToAlice());
        assertEq(IERC20(address(DAI)).balanceOf(wallet_), 99 ether);
    }

    function test_upgradeTo_RevertIfWalletTemplateChanges() public {
        // a fresh template for the same proxy would give every owner a new wallet address
        address newTemplate_ = address(new FluidWallet(address(fluidWalletFactory)));
        address newLogic_ = address(
            new FluidWalletFactory(address(vaultFactory), address(fluidWalletFactory), newTemplate_)
        );

        vm.prank(bob);
        vm.expectRevert(FluidWalletFactoryErrorsAndEvents.FluidWalletFactory__InvalidOperation.selector);
        fluidWalletFactory.upgradeTo(newLogic_);
    }

    function test_constructor_RevertIfWalletTemplateZero() public {
        vm.expectRevert(FluidWalletFactoryErrorsAndEvents.FluidWalletFactory__InvalidOperation.selector);
        new FluidWalletFactory(address(vaultFactory), address(fluidWalletFactory), address(0));
    }

    function test_constructor_RevertIfWalletTemplateServesAnotherFactory() public {
        address otherTemplate_ = address(new FluidWallet(makeAddr("otherFactoryProxy")));
        vm.expectRevert(FluidWalletFactoryErrorsAndEvents.FluidWalletFactory__InvalidOperation.selector);
        new FluidWalletFactory(address(vaultFactory), address(fluidWalletFactory), otherTemplate_);
    }
}
