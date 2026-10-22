// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidSmartLending } from "../../../../contracts/protocols/dex/smartLending/main.sol";
import { Error as FluidDexError } from "../../../../contracts/protocols/dex/error.sol";
import { ErrorTypes as FluidDexErrorTypes } from "../../../../contracts/protocols/dex/errorTypes.sol";
import { IFluidDexFactory } from "../../../../contracts/protocols/dex/interfaces/iDexFactory.sol";
import { IFluidDexT1 } from "../../../../contracts/protocols/dex/interfaces/iDexT1.sol";

/// @dev Regression tests for dusty Smart Lending deposits that would mint zero fSL.
contract FluidSmartLendingDepositZeroSharesTest is Test {
    address internal constant LIQUIDITY_PLACEHOLDER = address(0xBEEF);
    address internal constant DEX_FACTORY_PLACEHOLDER = address(0xDEF0);
    address internal constant SMART_LENDING_FACTORY_PLACEHOLDER = address(0xD0D0);
    address internal constant DEX_PLACEHOLDER = address(0x1111);

    address internal constant TOKEN0 = address(0xAAA0);
    address internal constant TOKEN1 = address(0xBBB1);

    uint256 internal constant DEX_ID = 7;

    FluidSmartLending internal smartLending;

    address internal alice = makeAddr("alice");

    function setUp() public {
        vm.mockCall(
            DEX_FACTORY_PLACEHOLDER,
            abi.encodeWithSelector(IFluidDexFactory.getDexAddress.selector, DEX_ID),
            abi.encode(DEX_PLACEHOLDER)
        );

        IFluidDexT1.ConstantViews memory cv;
        cv.dexId = DEX_ID;
        cv.liquidity = LIQUIDITY_PLACEHOLDER;
        cv.token0 = TOKEN0;
        cv.token1 = TOKEN1;
        vm.mockCall(DEX_PLACEHOLDER, abi.encodeWithSelector(IFluidDexT1.constantsView.selector), abi.encode(cv));

        smartLending = new FluidSmartLending(
            DEX_ID,
            LIQUIDITY_PLACEHOLDER,
            DEX_FACTORY_PLACEHOLDER,
            SMART_LENDING_FACTORY_PLACEHOLDER
        );

        // Sanity: `exchangePrice` is seeded to 1e18 so `(shares_ * 1e18) / exchangePrice == shares_`
        // and our boundary math is readable.
        assertEq(uint256(smartLending.exchangePrice()), 1e18);
    }

    // ------------------------------------------------------------------
    // deposit — dust paths must revert with `SmartLending__ZeroSharesMinted`.
    // ------------------------------------------------------------------

    function test_deposit_RevertOnZeroShares() public {
        // DEX returns `shares_ = 0`, which would underflow after the `-1` cushion.
        vm.mockCall(
            DEX_PLACEHOLDER,
            abi.encodeWithSelector(IFluidDexT1.deposit.selector, uint256(1), uint256(1), uint256(0), false),
            abi.encode(uint256(0))
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexError.FluidSmartLendingError.selector,
                FluidDexErrorTypes.SmartLending__ZeroSharesMinted
            )
        );
        smartLending.deposit(1, 1, 0, alice);
    }

    function test_deposit_RevertOnOneShareDust() public {
        // One raw fSL after the dust cushion would mint 0.
        vm.mockCall(
            DEX_PLACEHOLDER,
            abi.encodeWithSelector(IFluidDexT1.deposit.selector, uint256(1), uint256(1), uint256(0), false),
            abi.encode(uint256(1))
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexError.FluidSmartLendingError.selector,
                FluidDexErrorTypes.SmartLending__ZeroSharesMinted
            )
        );
        smartLending.deposit(1, 1, 0, alice);
    }

    function test_deposit_AcceptsBoundaryAmountOne() public {
        // DEX returns `shares_ = 2` → `(2 * 1e18) / 1e18 - 1 == 1` → minimum allowed.
        vm.mockCall(
            DEX_PLACEHOLDER,
            abi.encodeWithSelector(IFluidDexT1.deposit.selector, uint256(1), uint256(1), uint256(0), false),
            abi.encode(uint256(2))
        );

        vm.prank(alice);
        (uint256 amount_, uint256 shares_) = smartLending.deposit(1, 1, 0, alice);

        assertEq(shares_, 2, "DEX returned 2 shares");
        assertEq(amount_, 1, "amount_ must be the minimum non-dust value (1)");
        assertEq(smartLending.balanceOf(alice), 1, "alice must be credited exactly 1 fSL at boundary");
    }

    function test_deposit_HappyPath_UnaffectedByGuard() public {
        // Realistic `shares_` — exchangePrice=1e18, so `amount_ = shares_ - 1`.
        uint256 dexShares = 1_000e18;
        vm.mockCall(
            DEX_PLACEHOLDER,
            abi.encodeWithSelector(IFluidDexT1.deposit.selector, uint256(500e18), uint256(500e18), uint256(0), false),
            abi.encode(dexShares)
        );

        vm.prank(alice);
        (uint256 amount_, uint256 shares_) = smartLending.deposit(500e18, 500e18, 0, alice);

        assertEq(shares_, dexShares);
        assertEq(amount_, dexShares - 1, "happy path mints `shares - 1` fSL (unchanged by guard)");
        assertEq(smartLending.balanceOf(alice), dexShares - 1);
    }

    // ------------------------------------------------------------------
    // depositPerfect — dust path must revert with `SmartLending__ZeroSharesMinted`.
    // ------------------------------------------------------------------

    function test_depositPerfect_RevertOnZeroShares() public {
        // Zero requested shares must not mint.
        vm.mockCall(
            DEX_PLACEHOLDER,
            abi.encodeWithSelector(IFluidDexT1.depositPerfect.selector, uint256(1), uint256(0), uint256(0), false),
            abi.encode(uint256(0), uint256(0))
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexError.FluidSmartLendingError.selector,
                FluidDexErrorTypes.SmartLending__ZeroSharesMinted
            )
        );
        smartLending.depositPerfect(0, 0, 0, alice);
    }

    function test_depositPerfect_AcceptsBoundaryOneShare() public {
        // `shares_ = 1` → `amount_ = (1 * 1e18) / 1e18 = 1`. No `-1` on this branch, so 1 is
        // the minimum legal amount (not 2).
        vm.mockCall(
            DEX_PLACEHOLDER,
            abi.encodeWithSelector(IFluidDexT1.depositPerfect.selector, uint256(2), uint256(0), uint256(0), false),
            abi.encode(uint256(0), uint256(0))
        );

        vm.prank(alice);
        (uint256 amount_, , ) = smartLending.depositPerfect(1, 0, 0, alice);

        assertEq(amount_, 1, "depositPerfect boundary amount_ == 1 must succeed");
        assertEq(smartLending.balanceOf(alice), 1);
    }
}
