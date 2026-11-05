//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";

// Pins the ceil-rounding fix for the inverted (supplyInterestFree > supplyWithInterest) branch of the
// supplyRatio encoder shared by userModule/main.sol (~line 987) and adminModule/main.sol (~line 284).
// Flooring that branch understates the stored ratio, and the consumer (LiquidityCalcs.calcExchangePrices,
// liquidityCalcs.sol:129) inverts it -- turning the understatement into an over-credit of supply yield
// unbacked by any borrow interest actually paid (up to ~2x at the smallest representable ratio).
contract LiquiditySupplyRatioRoundingTest is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    // ------------------------------------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------------------------------------

    /// @dev supplies USDC interest-free (mode 0) then with interest (mode 1) via alice, both in the same
    /// block so the exchange price is still exactly EXCHANGE_PRICES_PRECISION (1:1) when the encoder runs.
    function _setUpSupplyRatio(uint256 interestFree_, uint256 withInterest_) internal {
        _supply(address(liquidity), mockProtocolInterestFree, address(USDC), alice, interestFree_);
        _supply(address(liquidity), mockProtocolWithInterest, address(USDC), alice, withInterest_);
    }

    /// @dev mirrors the fixed encoder's inverted-branch rounding.
    function _ceilRatio(uint256 numerator_, uint256 denominator_) internal pure returns (uint256) {
        return ((numerator_ * FOUR_DECIMALS) + denominator_ - 1) / denominator_;
    }

    /// @dev mirrors the unchanged non-inverted / equal branch rounding.
    function _floorRatio(uint256 numerator_, uint256 denominator_) internal pure returns (uint256) {
        return (numerator_ * FOUR_DECIMALS) / denominator_;
    }

    /// @dev supplies `interestFree_` / `withInterest_`, borrows `borrowAmount_` with interest via bob, warps
    /// `warpSeconds_`, and returns the yield credited to with-interest supply vs. interest paid by with-interest
    /// borrow over that interval. Raw amounts are read before the warp; they are untouched by time, only by
    /// operate(), so they stay valid for both the "before" and "after" exchange price snapshot.
    function _supplyBorrowAndMeasureYield(
        uint256 interestFree_,
        uint256 withInterest_,
        uint256 borrowAmount_,
        uint256 warpSeconds_
    ) internal returns (uint256 credited_, uint256 paid_) {
        _setUpSupplyRatio(interestFree_, withInterest_);
        _borrow(mockProtocolWithInterest, address(USDC), bob, borrowAmount_);

        ResolverStructs.OverallTokenData memory before_ = resolver.getOverallTokenData(address(USDC));

        vm.warp(block.timestamp + warpSeconds_);

        ResolverStructs.OverallTokenData memory after_ = resolver.getOverallTokenData(address(USDC));

        credited_ =
            (before_.supplyRawInterest * (after_.supplyExchangePrice - before_.supplyExchangePrice)) /
            EXCHANGE_PRICES_PRECISION;
        paid_ =
            (before_.borrowRawInterest * (after_.borrowExchangePrice - before_.borrowExchangePrice)) /
            EXCHANGE_PRICES_PRECISION;
    }

    // ------------------------------------------------------------------------------------------------
    // A. encoder, inverted branch (flag 1) -- fixed rounding
    // ------------------------------------------------------------------------------------------------

    function test_operate_SupplyRatioRoundsUpWhenInterestFreeBigger() public {
        // worked example: F = 1,000,000 USDC, W = 199 USDC -> W*1e4/F = 1.99, ceil = 2 (floor would be 1).
        uint256 interestFree_ = 1_000_000 * 1e6;
        uint256 withInterest_ = 199 * 1e6;

        _setUpSupplyRatio(interestFree_, withInterest_);

        _assertSupplyRatio(resolver, address(USDC), 1, _ceilRatio(withInterest_, interestFree_));
        _assertSupplyRatio(resolver, address(USDC), 1, 2);
    }

    function test_operate_SupplyRatioExactDivisionUnchangedByRounding() public {
        // W is exactly half of F, so W*1e4/F has no remainder: ceil and floor agree, fix is a no-op here.
        uint256 interestFree_ = 1_000_000 * 1e6;
        uint256 withInterest_ = 500_000 * 1e6;

        uint256 ceil_ = _ceilRatio(withInterest_, interestFree_);
        assertEq(ceil_, _floorRatio(withInterest_, interestFree_), "test setup sanity: expected exact division");

        _setUpSupplyRatio(interestFree_, withInterest_);

        _assertSupplyRatio(resolver, address(USDC), 1, ceil_);
        _assertSupplyRatio(resolver, address(USDC), 1, 5000);
    }

    function test_operate_SupplyRatioFlooringToZeroNowStoresMinimumOne() public {
        // W*1e4 < F, so the old floor() stored 0 -> raw field (0<<1)|1 == 1, which the consumer reads as
        // "no raw supply" and skips crediting any yield at all. ceil() must store 1 instead, never 0.
        uint256 interestFree_ = 1_000_000 * 1e6;
        uint256 withInterest_ = 100;

        assertEq(_floorRatio(withInterest_, interestFree_), 0, "test setup sanity: expected floor to underflow to 0");

        _setUpSupplyRatio(interestFree_, withInterest_);

        _assertSupplyRatio(resolver, address(USDC), 1, 1);
    }

    function test_fuzz_operate_SupplyRatioNeverExceedsFourDecimals(
        uint256 interestFree_,
        uint256 withInterest_
    ) public {
        // bounded well under the 2**80 operate-amount-ratio-check threshold and MAX_TOKEN_AMOUNT_CAP so no
        // unrelated revert path is reachable; interestFree_ is forced strictly bigger to hit the inverted branch.
        withInterest_ = bound(withInterest_, 1, 1e12);
        interestFree_ = bound(interestFree_, withInterest_ + 1, 1e13);

        uint256 expectedRatio_ = _ceilRatio(withInterest_, interestFree_);
        // W < F strictly => W*1e4/F < 1e4 as a real number => its ceiling can not exceed 1e4 (100%), which
        // also keeps it well within the 14 bits available for the value part of the packed field.
        assertLe(expectedRatio_, FOUR_DECIMALS, "supplyRatio value must never exceed 1e4 (100%)");

        _setUpSupplyRatio(interestFree_, withInterest_);

        _assertSupplyRatio(resolver, address(USDC), 1, expectedRatio_);
    }

    // ------------------------------------------------------------------------------------------------
    // B. encoder, branches that must NOT change
    // ------------------------------------------------------------------------------------------------

    function test_operate_SupplyRatioFlooredWhenWithInterestBigger() public {
        // same 199 / 1,000,000 pair as the worked example, roles swapped: W > F now floors, unaffected by fix.
        uint256 interestFree_ = 199 * 1e6;
        uint256 withInterest_ = 1_000_000 * 1e6;

        _setUpSupplyRatio(interestFree_, withInterest_);

        _assertSupplyRatio(resolver, address(USDC), 0, _floorRatio(interestFree_, withInterest_));
        _assertSupplyRatio(resolver, address(USDC), 0, 1);
    }

    function test_operate_SupplyRatioFourDecimalsWhenSuppliesEqual() public {
        uint256 amount_ = 500_000 * 1e6;

        _setUpSupplyRatio(amount_, amount_);

        _assertSupplyRatio(resolver, address(USDC), 0, FOUR_DECIMALS);
    }

    // ------------------------------------------------------------------------------------------------
    // C. admin module parity
    // ------------------------------------------------------------------------------------------------

    function test_updateExchangePrices_SupplyRatioMatchesUserModuleEncoder() public {
        uint256 interestFree_ = 1_000_000 * 1e6;
        uint256 withInterest_ = 199 * 1e6;
        uint256 expectedRatio_ = _ceilRatio(withInterest_, interestFree_);

        _setUpSupplyRatio(interestFree_, withInterest_);

        // userModule's operate() already wrote the ratio.
        _assertSupplyRatio(resolver, address(USDC), 1, expectedRatio_);

        // adminModule recomputes supplyRatio independently from totalAmounts in storage. Call it in the same
        // block (no warp) so both encoders see the identical supplyWithInterest / supplyInterestFree inputs.
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateExchangePrices(tokens_);

        // must land on the exact same packed value, or the two encoders have drifted apart.
        _assertSupplyRatio(resolver, address(USDC), 1, expectedRatio_);
    }

    // ------------------------------------------------------------------------------------------------
    // D. end-to-end invariant: credited supply yield can never exceed borrow interest actually paid
    // ------------------------------------------------------------------------------------------------

    function test_operate_SupplyYieldCreditedNeverExceedsBorrowInterestPaid() public {
        (uint256 credited_, uint256 paid_) = _supplyBorrowAndMeasureYield(
            1_000_000 * 1e6, // interest-free supply F
            199 * 1e6, // with-interest supply W (F >> W, the shape that broke pre-fix)
            500_000 * 1e6, // with-interest borrow
            PASS_1YEAR_TIME
        );

        assertGt(paid_, 0, "test setup sanity: borrowers must actually accrue interest");
        // fee is 0 for USDC by default, and only with-interest supply/borrow ever earn/pay yield, so a
        // correct encoder can under-credit on rounding but must never credit more than was actually paid.
        assertLe(credited_, paid_, "supply yield credited exceeds borrow interest paid -> unbacked yield");
    }

    function test_operate_SupplyYieldCreditedNeverExceedsBorrowInterestPaid_RatioSweep() public {
        uint256[5] memory ratios_ = [uint256(1), 2, 10, 100, 1000];
        // F fixed at 10,000 USDC. W = r USDC would divide exactly, where ceil == floor and the rounding is a no-op;
        // the +1 wei puts the true ratio just above r so floor gives r and ceil gives r+1 — the maximum-error case,
        // where the old floor over-credited by (r+1)/r.
        uint256 interestFree_ = 10_000 * 1e6;
        uint256 borrowAmount_ = 5_000 * 1e6;

        for (uint256 i; i < ratios_.length; i++) {
            uint256 snapshotId_ = vm.snapshot();

            uint256 withInterest_ = (ratios_[i] * 1e6) + 1;
            assertEq(_ceilRatio(withInterest_, interestFree_), ratios_[i] + 1, "sweep case must straddle a boundary");

            (uint256 credited_, uint256 paid_) = _supplyBorrowAndMeasureYield(
                interestFree_,
                withInterest_,
                borrowAmount_,
                PASS_1YEAR_TIME
            );

            assertGt(paid_, 0, "test setup sanity: borrowers must actually accrue interest");
            assertLe(credited_, paid_, "supply yield credited exceeds borrow interest paid -> unbacked yield");

            vm.revertTo(snapshotId_);
        }
    }
}
