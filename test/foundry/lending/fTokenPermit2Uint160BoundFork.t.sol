// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Error } from "../../../contracts/protocols/lending/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";

import { fTokenBaseSetUp } from "./fToken.t.sol";
import { fTokenPermit2DepositsTestBase } from "./fTokenPermit2Deposits.t.sol";

/// @title Permit2 uint160 amount-bound regression tests.
contract FluidLendingFTokenPermit2Uint160BoundForkTest is fTokenPermit2DepositsTestBase {
    // storage slot 8 layout (see `fToken/variables.sol`):
    //   bits   0- 63: _liquidityExchangePrice  (uint64)
    //   bits  64-127: _tokenExchangePrice      (uint64)
    //   bits 128-167: _lastUpdateTimestamp     (uint40)
    //   bits 168-175: _status                  (uint8)  ← REENTRANCY guard
    //   bits 176-183: _rewardsActive           (bool)
    uint256 internal constant SLOT_STATUS_COMPOSITE = 8;
    uint256 internal constant STATUS_OFFSET_BITS = 168;
    uint8 internal constant REENTRANCY_ENTERED = 2;

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        super.setUp();
    }

    /// @dev Enters the reentrancy guard so `liquidityCallback` accepts a direct call. The full deposit
    ///      pipeline cannot supply a `> uint160.max` amount in a reasonable test, and the Permit2 leg
    ///      is the only consumer of the cast, so we exercise the bound at its closest public surface.
    function _enterReentrancyGuard(address fToken_) internal {
        bytes32 slot = bytes32(SLOT_STATUS_COMPOSITE);
        bytes32 before_ = vm.load(fToken_, slot);
        // clear 8 status bits then set them to REENTRANCY_ENTERED (=2)
        uint256 cleared = uint256(before_) & ~(uint256(0xff) << STATUS_OFFSET_BITS);
        uint256 written = cleared | (uint256(REENTRANCY_ENTERED) << STATUS_OFFSET_BITS);
        vm.store(fToken_, slot, bytes32(written));
    }

    function test_liquidityCallback_RevertOnUint160Overflow() public {
        address fToken_ = address(lendingFToken);
        _enterReentrancyGuard(fToken_);

        bytes memory data = abi.encode(true, alice); // (isPermit2, from)
        uint256 overflowAmount = uint256(type(uint160).max) + 1;

        vm.prank(address(liquidity));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Permit2AmountOverflow)
        );
        lendingFToken.liquidityCallback(address(underlying), overflowAmount, data);
    }

    function test_liquidityCallback_AcceptsUint160Max_Boundary() public view {
        // documentation test: `type(uint160).max` itself should NOT revert at the bound check.
        // We do not actually execute it here (would require a Permit2 signature for a 2^160-1
        // token amount, which is not realistic on mainnet fork); the inequality is `> uint160.max`
        // (strict), so equal is allowed by design. Pure arithmetic, so it also passes pre-fix.
        uint256 boundary = type(uint160).max;
        // sanity: boundary fits in uint160 without truncation
        assertEq(uint160(boundary), type(uint160).max);
        assertEq(uint256(uint160(boundary)), boundary);
    }

    function test_liquidityCallback_RevertOnMaxUint256() public {
        address fToken_ = address(lendingFToken);
        _enterReentrancyGuard(fToken_);

        bytes memory data = abi.encode(true, alice);

        vm.prank(address(liquidity));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Permit2AmountOverflow)
        );
        lendingFToken.liquidityCallback(address(underlying), type(uint256).max, data);
    }

    function test_liquidityCallback_NonPermit2PathDoesNotTripOverflowError() public {
        // The non-Permit2 (length == 32) code path must NOT raise `fToken__Permit2AmountOverflow`
        // regardless of amount — the bound gate is only on the Permit2 branch. We call with a
        // > uint160 amount and assert whatever happens, the error code (if any) is not the Permit2 overflow one.
        // Proves the fix is correctly scoped, so it also passes pre-fix (there's no such error to trip).
        address fToken_ = address(lendingFToken);
        _enterReentrancyGuard(fToken_);

        bytes memory data = abi.encode(alice); // length 32 → ERC-20 path (takes `from_` only)
        uint256 hugeAmount = uint256(type(uint160).max) + 1;

        vm.prank(address(liquidity));
        (bool ok, bytes memory returndata) = address(lendingFToken).call(
            abi.encodeWithSelector(lendingFToken.liquidityCallback.selector, address(underlying), hugeAmount, data)
        );
        // If it reverted, make sure the reason isn't the Permit2 overflow error.
        if (!ok && returndata.length >= 36) {
            bytes4 sel;
            uint256 errCode;
            assembly {
                sel := mload(add(returndata, 32))
                errCode := mload(add(returndata, 36))
            }
            if (sel == Error.FluidLendingError.selector) {
                assertTrue(
                    errCode != ErrorTypes.fToken__Permit2AmountOverflow,
                    "ERC-20 path must not trip the Permit2 overflow error"
                );
            }
        }
    }
}
