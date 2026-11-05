//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAllowanceTransfer } from "../../../contracts/protocols/lending/interfaces/permit2/iAllowanceTransfer.sol";
import { Error } from "../../../contracts/protocols/lending/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";
import { MockWETH } from "../../../contracts/mocks/mockWETH.sol";

import { fTokenPermit2DepositsTestBase } from "./fTokenPermit2Deposits.t.sol";
import { Permit2Mock } from "./mocks/permit2Mock.sol";
import { fTokenNativeUnderlyingHelpersHarness } from "./harness/fTokenNativeUnderlyingHelpersHarness.sol";

/// @dev no realistic deposit carries more than uint160.max, so this calls `liquidityCallback` as Liquidity would
contract fTokenPermit2AmountBoundTest is fTokenPermit2DepositsTestBase {
    address internal constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // `_status` sits in slot 8 at bit 168 (`forge inspect fToken storage-layout`)
    uint256 internal constant SLOT_STATUS_COMPOSITE = 8;
    uint256 internal constant STATUS_OFFSET_BITS = 168;
    uint8 internal constant REENTRANCY_ENTERED = 2;

    Permit2Mock internal permit2Mock;

    function setUp() public virtual override {
        super.setUp();

        permit2Mock = new Permit2Mock();
        vm.etch(PERMIT2_ADDRESS, address(permit2Mock).code);
    }

    function _enterReentrancyGuard(address fToken_) internal {
        bytes32 slot = bytes32(SLOT_STATUS_COMPOSITE);
        uint256 cleared_ = uint256(vm.load(fToken_, slot)) & ~(uint256(0xff) << STATUS_OFFSET_BITS);
        vm.store(fToken_, slot, bytes32(cleared_ | (uint256(REENTRANCY_ENTERED) << STATUS_OFFSET_BITS)));
    }

    function test_liquidityCallback_RevertIfPermit2AmountOverflow() public {
        _enterReentrancyGuard(address(lendingFToken));

        vm.prank(address(liquidity));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Permit2AmountOverflow)
        );
        lendingFToken.liquidityCallback(address(underlying), uint256(type(uint160).max) + 1, abi.encode(true, alice));
    }

    function test_liquidityCallback_RevertIfPermit2AmountIsMaxUint256() public {
        _enterReentrancyGuard(address(lendingFToken));

        vm.prank(address(liquidity));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Permit2AmountOverflow)
        );
        lendingFToken.liquidityCallback(address(underlying), type(uint256).max, abi.encode(true, alice));
    }

    function test_liquidityCallback_AcceptsUint160MaxBoundary() public {
        _enterReentrancyGuard(address(lendingFToken));

        uint256 boundaryAmount = type(uint160).max;
        underlying.mint(alice, boundaryAmount);
        vm.prank(alice);
        underlying.approve(PERMIT2_ADDRESS, boundaryAmount);

        uint256 liquidityBalanceBefore = underlying.balanceOf(address(liquidity));

        vm.prank(address(liquidity));
        lendingFToken.liquidityCallback(address(underlying), boundaryAmount, abi.encode(true, alice));

        Permit2Mock recordedPermit2 = Permit2Mock(PERMIT2_ADDRESS);
        assertEq(recordedPermit2.transferFromCallCount(), 1);
        assertEq(recordedPermit2.lastFrom(), alice);
        assertEq(recordedPermit2.lastTo(), address(liquidity));
        assertEq(recordedPermit2.lastAmount(), boundaryAmount);
        assertEq(recordedPermit2.lastToken(), address(underlying));
        assertEq(underlying.balanceOf(address(liquidity)) - liquidityBalanceBefore, boundaryAmount);
    }
}

/// @dev same reason as above: the native deposit pipeline cannot carry such an amount, so the helper is called directly
contract fTokenNativeUnderlyingPermit2AmountBoundTest is Test {
    address internal constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant ALICE = address(0xA11CE);

    MockWETH internal weth;
    fTokenNativeUnderlyingHelpersHarness internal harness;

    function setUp() public {
        weth = new MockWETH();
        harness = new fTokenNativeUnderlyingHelpersHarness();

        Permit2Mock permit2Mock = new Permit2Mock();
        vm.etch(PERMIT2_ADDRESS, address(permit2Mock).code);
    }

    function test_prepareWrappedNativeDeposit_RevertIfPermit2AmountOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Permit2AmountOverflow)
        );
        harness.exposed_prepareWrappedNativeDeposit(
            IAllowanceTransfer(PERMIT2_ADDRESS),
            IERC20(address(weth)),
            uint256(type(uint160).max) + 1,
            abi.encode(true, ALICE)
        );
    }

    function test_prepareWrappedNativeDeposit_RevertIfPermit2AmountIsMaxUint256() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Permit2AmountOverflow)
        );
        harness.exposed_prepareWrappedNativeDeposit(
            IAllowanceTransfer(PERMIT2_ADDRESS),
            IERC20(address(weth)),
            type(uint256).max,
            abi.encode(true, ALICE)
        );
    }

    function test_prepareWrappedNativeDeposit_AcceptsUint160MaxBoundary() public {
        uint256 boundaryAmount = type(uint160).max;

        vm.deal(ALICE, boundaryAmount);
        vm.prank(ALICE);
        weth.deposit{ value: boundaryAmount }();
        vm.prank(ALICE);
        weth.approve(PERMIT2_ADDRESS, boundaryAmount);

        vm.prank(ALICE);
        harness.exposed_prepareWrappedNativeDeposit(
            IAllowanceTransfer(PERMIT2_ADDRESS),
            IERC20(address(weth)),
            boundaryAmount,
            abi.encode(true, ALICE)
        );

        Permit2Mock recordedPermit2 = Permit2Mock(PERMIT2_ADDRESS);
        assertEq(recordedPermit2.transferFromCallCount(), 1);
        assertEq(recordedPermit2.lastFrom(), ALICE);
        assertEq(recordedPermit2.lastTo(), address(harness));
        assertEq(recordedPermit2.lastAmount(), boundaryAmount);
        assertEq(recordedPermit2.lastToken(), address(weth));
        assertEq(weth.balanceOf(ALICE), 0);
        assertEq(address(harness).balance, boundaryAmount);
    }
}
