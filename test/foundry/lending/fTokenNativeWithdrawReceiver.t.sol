//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { fTokenNativeUnderlying } from "../../../contracts/protocols/lending/fToken/nativeUnderlying/fTokenNativeUnderlying.sol";
import { IFTokenNativeUnderlying } from "../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { Events as fTokenEvents } from "../../../contracts/protocols/lending/fToken/events.sol";
import { MockWETH } from "../../../contracts/mocks/mockWETH.sol";

import { fTokenBaseSetUp } from "./fToken.t.sol";

/// @title Native fToken: max withdraw / redeem resolve against owner_, and Withdraw names the real receiver (no fork).
/// @dev fTokenNative.t.sol is excluded from CI by `.github/fork-test-paths.txt` (it forks for real WETH9),
///      so these never run there. `MockWETH` gives the same `deposit`/`withdraw` behaviour without a fork.
contract FTokenNativeWithdrawReceiverTest is fTokenBaseSetUp, fTokenEvents {
    MockWETH internal weth;
    IFTokenNativeUnderlying internal lendingFTokenNative;

    function setUp() public virtual override {
        super.setUp();

        lendingFTokenNative = IFTokenNativeUnderlying(address(lendingFToken));

        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(lendingFToken));

        vm.deal(alice, 1000 * DEFAULT_AMOUNT);
        vm.deal(bob, 1000 * DEFAULT_AMOUNT);
    }

    function _createToken(
        FluidLendingFactory lendingFactory_,
        IERC20 /** asset_ */
    ) internal virtual override returns (IERC4626) {
        weth = new MockWETH();
        vm.prank(admin);
        factory.setFTokenCreationCode("NativeUnderlying", type(fTokenNativeUnderlying).creationCode);
        vm.prank(admin);
        return IERC4626(lendingFactory_.createToken(address(weth), "NativeUnderlying", true));
    }

    // the `UINT256_MAX` shortcut on `withdrawNative`/`redeemNative` must resolve against the
    // owner whose shares are burned, not against the caller.

    function test_withdrawNative_MaxUsesOwnerBalance() public {
        uint256 ownerDeposit = DEFAULT_AMOUNT * 3;
        uint256 spenderDeposit = DEFAULT_AMOUNT;

        vm.prank(bob);
        lendingFTokenNative.depositNative{ value: ownerDeposit }(bob);
        vm.prank(alice);
        lendingFTokenNative.depositNative{ value: spenderDeposit }(alice);

        vm.prank(bob);
        lendingFTokenNative.approve(alice, ownerDeposit);

        address payable receiver = payable(address(0xBEEF));
        uint256 receiverEthBefore = receiver.balance;

        vm.prank(alice);
        uint256 shares = lendingFTokenNative.withdrawNative(type(uint256).max, receiver, bob);

        assertEq(shares, ownerDeposit, "burn should equal balanceOf(owner_)");
        assertEq(lendingFTokenNative.balanceOf(bob), 0, "owner shares drained");
        assertEq(lendingFTokenNative.balanceOf(alice), spenderDeposit, "spender shares untouched");
        assertEq(receiver.balance - receiverEthBefore, ownerDeposit, "receiver got owner's assets");
        assertEq(lendingFTokenNative.allowance(bob, alice), 0, "allowance consumed");
    }

    function test_redeemNative_MaxUsesOwnerBalance() public {
        uint256 ownerDeposit = DEFAULT_AMOUNT * 3;
        uint256 spenderDeposit = DEFAULT_AMOUNT;

        vm.prank(bob);
        lendingFTokenNative.depositNative{ value: ownerDeposit }(bob);
        vm.prank(alice);
        lendingFTokenNative.depositNative{ value: spenderDeposit }(alice);

        vm.prank(bob);
        lendingFTokenNative.approve(alice, ownerDeposit);

        address payable receiver = payable(address(0xBEEF));
        uint256 receiverEthBefore = receiver.balance;

        vm.prank(alice);
        uint256 assets = lendingFTokenNative.redeemNative(type(uint256).max, receiver, bob);

        assertEq(assets, ownerDeposit, "redeem equals balanceOf(owner_)");
        assertEq(lendingFTokenNative.balanceOf(bob), 0, "owner shares drained");
        assertEq(lendingFTokenNative.balanceOf(alice), spenderDeposit, "spender shares untouched");
        assertEq(receiver.balance - receiverEthBefore, ownerDeposit, "receiver got owner's assets");
        assertEq(lendingFTokenNative.allowance(bob, alice), 0, "allowance consumed");
    }

    /// @dev sanity: caller == owner is unaffected by the fix.
    function test_withdrawNative_MaxSelfOwnerUnchanged() public {
        vm.prank(alice);
        lendingFTokenNative.depositNative{ value: DEFAULT_AMOUNT }(alice);

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        uint256 shares = lendingFTokenNative.withdrawNative(type(uint256).max, alice, alice);

        assertEq(shares, DEFAULT_AMOUNT);
        assertEq(lendingFTokenNative.balanceOf(alice), 0);
        assertEq(alice.balance - balanceBefore, DEFAULT_AMOUNT);
    }

    // the WETH-output withdraw/redeem path must emit the real user-visible receiver, not the
    // fToken contract address it internally routes the native-to-WETH conversion through.

    function test_withdrawERC4626_EmitsRealReceiver() public {
        vm.prank(alice);
        lendingFTokenNative.depositNative{ value: DEFAULT_AMOUNT }(alice);

        address realReceiver = address(0xCAFE);

        vm.expectEmit(true, true, true, true, address(lendingFToken));
        emit Withdraw(alice, realReceiver, alice, DEFAULT_AMOUNT, DEFAULT_AMOUNT);

        vm.prank(alice);
        lendingFToken.withdraw(DEFAULT_AMOUNT, realReceiver, alice);

        assertEq(IERC20(address(weth)).balanceOf(realReceiver), DEFAULT_AMOUNT, "receiver got WETH");
        assertEq(IERC20(address(weth)).balanceOf(address(lendingFToken)), 0, "fToken holds no WETH");
    }

    function test_redeemERC4626_EmitsRealReceiver() public {
        vm.prank(alice);
        lendingFTokenNative.depositNative{ value: DEFAULT_AMOUNT }(alice);

        address realReceiver = address(0xBEAD);
        uint256 shares = lendingFToken.balanceOf(alice);

        vm.expectEmit(true, true, true, true, address(lendingFToken));
        emit Withdraw(alice, realReceiver, alice, DEFAULT_AMOUNT, shares);

        vm.prank(alice);
        lendingFToken.redeem(shares, realReceiver, alice);

        assertEq(IERC20(address(weth)).balanceOf(realReceiver), DEFAULT_AMOUNT);
    }

    /// @dev sanity: the native-ETH-out path already emitted the real receiver pre-fix; confirm still does.
    function test_withdrawNative_EmitsRealReceiver_Unchanged() public {
        vm.prank(alice);
        lendingFTokenNative.depositNative{ value: DEFAULT_AMOUNT }(alice);

        address payable realReceiver = payable(address(0xF007));

        vm.expectEmit(true, true, true, true, address(lendingFToken));
        emit Withdraw(alice, realReceiver, alice, DEFAULT_AMOUNT, DEFAULT_AMOUNT);

        vm.prank(alice);
        lendingFTokenNative.withdrawNative(DEFAULT_AMOUNT, realReceiver, alice);

        assertEq(realReceiver.balance, DEFAULT_AMOUNT, "receiver got native ETH");
    }
}
