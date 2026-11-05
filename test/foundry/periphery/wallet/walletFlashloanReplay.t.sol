//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "./walletFactory.t.sol";

contract FlashloanReplayHook {
    address public wallet;
    bytes public data;
    bool public replayed;
    bool public blocked;

    function stage(address wallet_, bytes memory data_) external {
        wallet = wallet_;
        data = data_;
    }

    function hook() external {
        if (replayed || blocked) return;
        try
            FluidWalletImplementation(payable(wallet)).executeOperation(
                new address[](0),
                new uint256[](0),
                new uint256[](0),
                wallet,
                data
            )
        {
            replayed = true;
        } catch (bytes memory reason_) {
            blocked = bytes4(reason_) == FluidWalletErrorsAndEvents.FluidWallet__Unauthorized.selector;
        }
    }
}

contract FluidWalletFlashloanReplayTest is FluidWalletFactoryTest {
    function test_executeOperation_RevertIfReplayedDuringFlashloan() public {
        address wallet_ = fluidWalletFactory.deploy(address(alice));
        TestERC20(address(DAI)).mint(wallet_, 100 ether);

        FlashloanReplayHook hook_ = new FlashloanReplayHook();

        FluidWalletImplementation.Action[] memory inner_ = new FluidWalletImplementation.Action[](2);
        inner_[0] = FluidWalletErrorsAndEvents.Action({
            target: address(DAI),
            data: abi.encodeWithSignature("transfer(address,uint256)", address(hook_), 10 ether),
            operation: 0,
            value: 0
        });
        inner_[1] = FluidWalletErrorsAndEvents.Action({
            target: address(hook_),
            data: abi.encodeWithSelector(FlashloanReplayHook.hook.selector),
            operation: 0,
            value: 0
        });
        bytes memory innerData_ = abi.encode(inner_);
        // a contract in the action path that knows the inner bytes upfront (e.g. from the mempool)
        hook_.stage(wallet_, innerData_);

        address[] memory tokens_ = new address[](1);
        uint256[] memory amounts_ = new uint256[](1);
        tokens_[0] = address(DAI);
        amounts_[0] = 1;

        FluidWalletImplementation.Action[] memory actions_ = new FluidWalletImplementation.Action[](1);
        actions_[0] = FluidWalletErrorsAndEvents.Action({
            target: address(fla),
            data: abi.encodeWithSelector(InstaFlashInterface.flashLoan.selector, tokens_, amounts_, 5, innerData_, ""),
            operation: 2,
            value: 0
        });

        vm.prank(alice);
        FluidWalletImplementation(payable(wallet_)).cast(actions_);

        assertFalse(hook_.replayed(), "inner actions replayed");
        assertTrue(hook_.blocked(), "replay not rejected as unauthorized");
        assertEq(IERC20(address(DAI)).balanceOf(address(hook_)), 10 ether);
        assertEq(uint256(vm.load(wallet_, bytes32(uint256(1)))), 1);
    }

    function test_executeOperation_RevertIfCalledOutsideFlashloan() public {
        address wallet_ = fluidWalletFactory.deploy(address(alice));
        vm.expectRevert(FluidWalletErrorsAndEvents.FluidWallet__Unauthorized.selector);
        FluidWalletImplementation(payable(wallet_)).executeOperation(
            new address[](0),
            new uint256[](0),
            new uint256[](0),
            wallet_,
            abi.encode(new FluidWalletImplementation.Action[](0))
        );
    }
}
