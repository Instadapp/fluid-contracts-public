//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { fTokenNativeUnderlying } from "../../../contracts/protocols/lending/fToken/nativeUnderlying/fTokenNativeUnderlying.sol";
import { IFTokenNativeUnderlying } from "../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { Error } from "../../../contracts/protocols/lending/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";
import { Error as LiquidityError } from "../../../contracts/liquidity/error.sol";
import { ErrorTypes as LiquidityErrorTypes } from "../../../contracts/liquidity/errorTypes.sol";
import { SafeTransfer } from "../../../contracts/libraries/safeTransfer.sol";
import { LibsErrorTypes } from "../../../contracts/libraries/errorTypes.sol";
import { MockWETH } from "../../../contracts/mocks/mockWETH.sol";

import { fTokenBaseSetUp } from "./fToken.t.sol";

/// @dev Mints on its own behalf so the fToken's refund lands in `receive()`, which behaves as configured.
contract NativeMintCaller {
    enum ReceiveMode {
        Accept,
        Reject,
        BurnGas,
        ReenterDeposit
    }

    IFTokenNativeUnderlying internal immutable FTOKEN;
    ReceiveMode internal immutable MODE;
    uint256 internal immutable GAS_TO_BURN;

    bool public reentryBlocked;

    constructor(IFTokenNativeUnderlying fToken_, ReceiveMode mode_, uint256 gasToBurn_) {
        FTOKEN = fToken_;
        MODE = mode_;
        GAS_TO_BURN = gasToBurn_;
    }

    function mint(uint256 shares_, address receiver_) external payable returns (uint256) {
        return FTOKEN.mintNative{ value: msg.value }(shares_, receiver_);
    }

    function deposit(address receiver_) external payable returns (uint256) {
        return FTOKEN.depositNative{ value: msg.value }(receiver_);
    }

    receive() external payable {
        if (MODE == ReceiveMode.Reject) {
            revert("ETH rejected");
        } else if (MODE == ReceiveMode.BurnGas) {
            uint256 start_ = gasleft();
            while (start_ - gasleft() < GAS_TO_BURN) {}
        } else if (MODE == ReceiveMode.ReenterDeposit) {
            try FTOKEN.depositNative{ value: msg.value }(address(this)) {} catch (bytes memory reason_) {
                reentryBlocked =
                    keccak256(reason_) ==
                    keccak256(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Reentrancy));
            }
        }
    }
}

/// @title Native fToken `mintNative` deposits only `previewMint(shares)` and refunds the rest to the caller (no fork).
/// @dev fTokenNative.t.sol is excluded from CI by `.github/fork-test-paths.txt` (it forks for real WETH9),
///      so these run where it cannot. `MockWETH` gives the same `deposit`/`withdraw` behaviour without a fork.
contract FTokenNativeMintRefundTest is fTokenBaseSetUp {
    // 20% a year rewards over a full year give an exchange price of exactly 1.2, so assets = 1.2 * shares
    uint256 internal constant MINT_SHARES = 5 * DEFAULT_AMOUNT;
    uint256 internal constant MINT_ASSETS = 6 * DEFAULT_AMOUNT;
    uint256 internal constant EXCESS = 3 * DEFAULT_AMOUNT;

    // SafeTransfer forwards at most 50k gas to the refund receiver
    uint256 internal constant GAS_ABOVE_CAP = 60_000;
    uint256 internal constant GAS_BELOW_CAP = 30_000;

    IFTokenNativeUnderlying internal lendingFTokenNative;

    function setUp() public virtual override {
        super.setUp();

        lendingFTokenNative = IFTokenNativeUnderlying(address(lendingFToken));

        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(lendingFToken));

        vm.deal(alice, 1000 * DEFAULT_AMOUNT);
        vm.deal(bob, 1000 * DEFAULT_AMOUNT);

        vm.warp(block.timestamp + 365 days);
        assertEq(lendingFToken.previewMint(MINT_SHARES), MINT_ASSETS);
    }

    function _createToken(
        FluidLendingFactory lendingFactory_,
        IERC20 /** asset_ */
    ) internal virtual override returns (IERC4626) {
        address weth_ = address(new MockWETH());
        vm.prank(admin);
        factory.setFTokenCreationCode("NativeUnderlying", type(fTokenNativeUnderlying).creationCode);
        vm.prank(admin);
        return IERC4626(lendingFactory_.createToken(weth_, "NativeUnderlying", true));
    }

    function test_mintNative_RefundsExcessToCaller() public {
        uint256 callerBefore_ = alice.balance;
        uint256 liquidityEthBefore_ = address(liquidity).balance;

        vm.prank(alice);
        uint256 assets_ = lendingFTokenNative.mintNative{ value: MINT_ASSETS + EXCESS }(MINT_SHARES, alice);

        assertEq(assets_, MINT_ASSETS, "return value is the cost of the shares");
        assertEq(callerBefore_ - alice.balance, MINT_ASSETS, "caller pays exactly the cost");
        assertEq(lendingFToken.balanceOf(alice), MINT_SHARES, "receiver gets exactly the requested shares");
        assertEq(lendingFToken.totalSupply(), MINT_SHARES);
        assertEq(lendingFToken.totalAssets(), MINT_ASSETS);
        assertEq(address(liquidity).balance - liquidityEthBefore_, MINT_ASSETS, "Liquidity receives exactly the cost");
        assertEq(_liquidityBalance(), MINT_ASSETS);
        assertEq(address(lendingFToken).balance, 0, "fToken keeps no ETH");
    }

    function test_mintNative_RefundsSingleWeiExcess() public {
        uint256 assets_ = lendingFToken.previewMint(1);
        assertEq(assets_, 2);
        uint256 callerBefore_ = alice.balance;

        vm.prank(alice);
        lendingFTokenNative.mintNative{ value: assets_ + 1 }(1, alice);

        assertEq(callerBefore_ - alice.balance, assets_);
        assertEq(lendingFToken.balanceOf(alice), 1);
        assertEq(address(lendingFToken).balance, 0);
    }

    function test_mintNative_RefundGoesToCallerNotReceiver() public {
        uint256 callerBefore_ = bob.balance;
        uint256 receiverBefore_ = alice.balance;

        vm.prank(bob);
        uint256 assets_ = lendingFTokenNative.mintNative{ value: MINT_ASSETS + EXCESS }(MINT_SHARES, alice);

        assertEq(assets_, MINT_ASSETS);
        assertEq(callerBefore_ - bob.balance, MINT_ASSETS, "caller keeps the refund");
        assertEq(alice.balance, receiverBefore_, "receiver's ETH is untouched");
        assertEq(lendingFToken.balanceOf(alice), MINT_SHARES);
        assertEq(lendingFToken.balanceOf(bob), 0);
    }

    function test_mintNative_ReceiverNeedNotAcceptEth() public {
        NativeMintCaller rejecter_ = new NativeMintCaller(lendingFTokenNative, NativeMintCaller.ReceiveMode.Reject, 0);
        uint256 callerBefore_ = alice.balance;

        vm.prank(alice);
        lendingFTokenNative.mintNative{ value: MINT_ASSETS + EXCESS }(MINT_SHARES, address(rejecter_));

        assertEq(callerBefore_ - alice.balance, MINT_ASSETS);
        assertEq(lendingFToken.balanceOf(address(rejecter_)), MINT_SHARES);
    }

    function test_mintNative_TwoCallersAreEachRefunded() public {
        uint256 aliceBefore_ = alice.balance;
        uint256 bobBefore_ = bob.balance;

        vm.prank(alice);
        lendingFTokenNative.mintNative{ value: MINT_ASSETS + EXCESS }(MINT_SHARES, alice);
        vm.prank(bob);
        lendingFTokenNative.mintNative{ value: MINT_ASSETS + 2 * EXCESS }(MINT_SHARES, alice);

        assertEq(aliceBefore_ - alice.balance, MINT_ASSETS);
        assertEq(bobBefore_ - bob.balance, MINT_ASSETS);
        assertEq(lendingFToken.balanceOf(alice), 2 * MINT_SHARES);
        assertEq(lendingFToken.totalAssets(), 2 * MINT_ASSETS);
        assertEq(_liquidityBalance(), 2 * MINT_ASSETS);
        assertEq(address(lendingFToken).balance, 0);
    }

    function test_mintNative_ExactValueDepositsAllWithoutRefund() public {
        uint256 callerBefore_ = alice.balance;

        vm.prank(alice);
        uint256 assets_ = lendingFTokenNative.mintNative{ value: MINT_ASSETS }(MINT_SHARES, alice);

        assertEq(assets_, MINT_ASSETS);
        assertEq(callerBefore_ - alice.balance, MINT_ASSETS);
        assertEq(lendingFToken.balanceOf(alice), MINT_SHARES);
        assertEq(_liquidityBalance(), MINT_ASSETS);
        assertEq(address(lendingFToken).balance, 0);
    }

    function test_mintNative_RevertIfValueBelowAssets() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLendingError.selector,
                ErrorTypes.fTokenNativeUnderlying__TransferInsufficient
            )
        );
        vm.prank(alice);
        lendingFTokenNative.mintNative{ value: MINT_ASSETS - 1 }(MINT_SHARES, alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLendingError.selector,
                ErrorTypes.fTokenNativeUnderlying__TransferInsufficient
            )
        );
        vm.prank(alice);
        lendingFTokenNative.mintNative(MINT_SHARES, alice);
    }

    function test_mintNative_RevertIfZeroShares() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                LiquidityErrorTypes.UserModule__OperateAmountsZero
            )
        );
        vm.prank(alice);
        lendingFTokenNative.mintNative{ value: EXCESS }(0, alice);
    }

    function testFuzz_mintNative_ChargesExactlyPreviewMint(uint256 shares_, uint256 excess_, uint256 elapsed_) public {
        shares_ = bound(shares_, 1, 1e16);
        excess_ = bound(excess_, 0, 1e17);
        elapsed_ = bound(elapsed_, 0, 3 * 365 days);
        vm.warp(block.timestamp + elapsed_);
        vm.deal(alice, 1e18);

        uint256 expectedAssets_ = lendingFToken.previewMint(shares_);
        uint256 callerBefore_ = alice.balance;
        uint256 receiverBefore_ = bob.balance;
        uint256 liquidityEthBefore_ = address(liquidity).balance;

        vm.prank(alice);
        uint256 assets_ = lendingFTokenNative.mintNative{ value: expectedAssets_ + excess_ }(shares_, bob);

        assertEq(assets_, expectedAssets_);
        assertEq(callerBefore_ - alice.balance, expectedAssets_);
        assertEq(bob.balance, receiverBefore_);
        assertEq(address(liquidity).balance - liquidityEthBefore_, expectedAssets_);
        assertEq(lendingFToken.balanceOf(bob), shares_);
        assertEq(address(lendingFToken).balance, 0);
    }

    function test_mintNativeWithMaxAssets_RefundsExcessWhenMaxEqualsAssets() public {
        uint256 callerBefore_ = alice.balance;

        vm.prank(alice);
        uint256 assets_ = lendingFTokenNative.mintNative{ value: MINT_ASSETS + EXCESS }(MINT_SHARES, bob, MINT_ASSETS);

        assertEq(assets_, MINT_ASSETS);
        assertEq(callerBefore_ - alice.balance, MINT_ASSETS);
        assertEq(lendingFToken.balanceOf(bob), MINT_SHARES);
        assertEq(_liquidityBalance(), MINT_ASSETS);
        assertEq(address(lendingFToken).balance, 0);
    }

    function test_mintNativeWithMaxAssets_RefundsExcessWhenMaxAboveAssets() public {
        uint256 callerBefore_ = alice.balance;

        vm.prank(alice);
        uint256 assets_ = lendingFTokenNative.mintNative{ value: MINT_ASSETS + EXCESS }(
            MINT_SHARES,
            bob,
            type(uint256).max
        );

        assertEq(assets_, MINT_ASSETS);
        assertEq(callerBefore_ - alice.balance, MINT_ASSETS);
        assertEq(lendingFToken.balanceOf(bob), MINT_SHARES);
        assertEq(address(lendingFToken).balance, 0);
    }

    function test_mintNativeWithMaxAssets_RevertIfAssetsAboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__MaxAmount));
        vm.prank(alice);
        lendingFTokenNative.mintNative{ value: MINT_ASSETS + EXCESS }(MINT_SHARES, alice, MINT_ASSETS - 1);
    }

    function test_mintNative_RefundsContractCaller() public {
        NativeMintCaller caller_ = new NativeMintCaller(lendingFTokenNative, NativeMintCaller.ReceiveMode.Accept, 0);

        vm.prank(alice);
        caller_.mint{ value: MINT_ASSETS + EXCESS }(MINT_SHARES, alice);

        assertEq(address(caller_).balance, EXCESS);
        assertEq(lendingFToken.balanceOf(alice), MINT_SHARES);
        assertEq(address(lendingFToken).balance, 0);
    }

    function test_mintNative_RefundsContractCallerBurningLessThanGasCap() public {
        NativeMintCaller caller_ = new NativeMintCaller(
            lendingFTokenNative,
            NativeMintCaller.ReceiveMode.BurnGas,
            GAS_BELOW_CAP
        );

        vm.prank(alice);
        caller_.mint{ value: MINT_ASSETS + EXCESS }(MINT_SHARES, alice);

        assertEq(address(caller_).balance, EXCESS);
    }

    function test_mintNative_RevertIfRefundToEthRejectingCaller() public {
        NativeMintCaller caller_ = new NativeMintCaller(lendingFTokenNative, NativeMintCaller.ReceiveMode.Reject, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeTransfer.FluidSafeTransferError.selector,
                LibsErrorTypes.SafeTransfer__TransferFailed
            )
        );
        vm.prank(alice);
        caller_.mint{ value: MINT_ASSETS + EXCESS }(MINT_SHARES, alice);
    }

    function test_mintNative_ExactValueSucceedsForEthRejectingCaller() public {
        NativeMintCaller caller_ = new NativeMintCaller(lendingFTokenNative, NativeMintCaller.ReceiveMode.Reject, 0);

        vm.prank(alice);
        caller_.mint{ value: MINT_ASSETS }(MINT_SHARES, alice);

        assertEq(lendingFToken.balanceOf(alice), MINT_SHARES);
        assertEq(_liquidityBalance(), MINT_ASSETS);
    }

    function test_mintNative_RevertIfRefundToGasBurningCaller() public {
        NativeMintCaller caller_ = new NativeMintCaller(
            lendingFTokenNative,
            NativeMintCaller.ReceiveMode.BurnGas,
            GAS_ABOVE_CAP
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeTransfer.FluidSafeTransferError.selector,
                LibsErrorTypes.SafeTransfer__TransferFailed
            )
        );
        vm.prank(alice);
        caller_.mint{ value: MINT_ASSETS + EXCESS }(MINT_SHARES, alice);
    }

    function test_mintNative_ExactValueSucceedsForGasBurningCaller() public {
        NativeMintCaller caller_ = new NativeMintCaller(
            lendingFTokenNative,
            NativeMintCaller.ReceiveMode.BurnGas,
            GAS_ABOVE_CAP
        );

        vm.prank(alice);
        caller_.mint{ value: MINT_ASSETS }(MINT_SHARES, alice);

        assertEq(lendingFToken.balanceOf(alice), MINT_SHARES);
        assertEq(_liquidityBalance(), MINT_ASSETS);
    }

    function test_mintNative_RefundCannotReenter() public {
        NativeMintCaller caller_ = new NativeMintCaller(
            lendingFTokenNative,
            NativeMintCaller.ReceiveMode.ReenterDeposit,
            0
        );

        vm.prank(alice);
        caller_.mint{ value: MINT_ASSETS + EXCESS }(MINT_SHARES, alice);

        assertTrue(caller_.reentryBlocked(), "the deposit attempted from the refund hits the reentrancy guard");
        assertEq(address(caller_).balance, EXCESS, "refund still delivered");
        assertEq(lendingFToken.totalSupply(), MINT_SHARES, "nothing minted by the reentrant call");
        assertEq(_liquidityBalance(), MINT_ASSETS);
    }

    function test_depositNative_DepositsFullMsgValue() public {
        uint256 callerBefore_ = alice.balance;

        vm.prank(alice);
        uint256 shares_ = lendingFTokenNative.depositNative{ value: MINT_ASSETS }(alice);

        assertEq(shares_, MINT_SHARES);
        assertEq(callerBefore_ - alice.balance, MINT_ASSETS);
        assertEq(lendingFToken.balanceOf(alice), MINT_SHARES);
        assertEq(_liquidityBalance(), MINT_ASSETS);
        assertEq(address(lendingFToken).balance, 0);
    }

    function test_depositNative_DepositsFullMsgValueFromEthRejectingCaller() public {
        NativeMintCaller caller_ = new NativeMintCaller(lendingFTokenNative, NativeMintCaller.ReceiveMode.Reject, 0);

        // the extra wei is too small to mint another share but is still deposited, never refunded
        vm.prank(alice);
        uint256 shares_ = caller_.deposit{ value: MINT_ASSETS + 1 }(alice);

        assertEq(shares_, MINT_SHARES);
        assertEq(_liquidityBalance(), MINT_ASSETS + 1);
        assertEq(address(lendingFToken).balance, 0);
    }

    function _liquidityBalance() internal view returns (uint256 liquidityBalance_) {
        (, , , , , , liquidityBalance_, , ) = lendingFToken.getData();
    }
}
