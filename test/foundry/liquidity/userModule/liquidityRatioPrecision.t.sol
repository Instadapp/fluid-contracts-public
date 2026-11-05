//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";

/// @dev Supply ratio, borrow ratio and utilization are computed over amounts scaled by EXCHANGE_PRICES_PRECISION
/// (with-interest `raw * exchangePrice`, interest-free `amount * 1e12`) in both `operate()` and
/// `updateExchangePrices()`, instead of over amounts truncated to token units first. The two only differ once
/// exchange prices are off 1e12 and the totals are small, which tests that stay at price 1e12 cannot see.
contract LiquidityRatioPrecisionTest is LiquidityUserModuleBaseTest {
    struct State {
        uint256 supplyRaw;
        uint256 supplyFree;
        uint256 borrowRaw;
        uint256 borrowFree;
        uint256 supplyPrice;
        uint256 borrowPrice;
    }

    // uneven offsets so the accrued exchange prices come out with no round digits
    uint256 internal constant ELAPSED = 100 days + 7 hours + 13 minutes + 41 seconds;

    // far below 2**56, where BigMath stores totals exactly, so decoded storage equals the encoders' inputs
    uint256 internal constant MAX_FUZZ_AMOUNT = 1e9;

    function setUp() public virtual override {
        super.setUp();
    }

    // positions are opened at price 1e12, where raw amounts still equal token amounts

    function _open(
        uint256 supplyWithInterest_,
        uint256 supplyInterestFree_,
        uint256 borrowWithInterest_,
        uint256 borrowInterestFree_
    ) internal {
        if (supplyWithInterest_ > 0) {
            _supply(address(liquidity), mockProtocolWithInterest, address(USDC), alice, supplyWithInterest_);
        }
        if (supplyInterestFree_ > 0) {
            _supply(address(liquidity), mockProtocolInterestFree, address(USDC), alice, supplyInterestFree_);
        }
        if (borrowWithInterest_ > 0) {
            _borrow(mockProtocolWithInterest, address(USDC), bob, borrowWithInterest_);
        }
        if (borrowInterestFree_ > 0) {
            _borrow(mockProtocolInterestFree, address(USDC), bob, borrowInterestFree_);
        }
    }

    function _openWithInterestHeavy() internal {
        _open(2000, 1000, 500, 100);
    }

    function _openInterestFreeHeavy() internal {
        _open(1000, 3000, 200, 500);
    }

    function _openBounded(
        uint256 supplyWithInterest_,
        uint256 supplyInterestFree_,
        uint256 borrowWithInterest_,
        uint256 borrowInterestFree_
    ) internal {
        supplyWithInterest_ = bound(supplyWithInterest_, 1, MAX_FUZZ_AMOUNT);
        supplyInterestFree_ = bound(supplyInterestFree_, 0, MAX_FUZZ_AMOUNT);
        // a quarter of supply per borrow side keeps the total well clear of max utilization
        uint256 maxBorrow_ = (supplyWithInterest_ + supplyInterestFree_) / 4;
        _open(
            supplyWithInterest_,
            supplyInterestFree_,
            bound(borrowWithInterest_, 0, maxBorrow_),
            bound(borrowInterestFree_, 0, maxBorrow_)
        );
    }

    /// @dev past the 1 day forced write window, so `operate()` persists the ratios it computes
    function _operateAfter(uint256 elapsed_) internal {
        vm.warp(block.timestamp + elapsed_);
        _supply(address(liquidity), mockProtocolInterestFree, address(USDC), alice, 1);
        _assertOperateWroteStorage();
    }

    function _updateExchangePricesAfter(uint256 elapsed_) internal {
        vm.warp(block.timestamp + elapsed_);
        _updateExchangePrices();
    }

    function _updateExchangePrices() internal {
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateExchangePrices(tokens_);
    }

    /// @dev for an admin call in the same block as an `operate()`: blanks what `operate()` stored, so only
    /// `updateExchangePrices()` can put the asserted values there. No time has passed, so prices do not move.
    function _clearStoredRatiosAndUtilization() internal {
        bytes32 slot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            address(USDC)
        );
        uint256 packed_ = uint256(vm.load(address(liquidity), slot_));
        packed_ &= ~((X14 << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) |
            (X15 << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_RATIO) |
            (X15 << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_RATIO));
        vm.store(address(liquidity), slot_, bytes32(packed_));
    }

    function _readState() internal view returns (State memory s_) {
        uint256 totalAmounts_ = resolver.getTotalAmounts(address(USDC));
        uint256 packed_ = resolver.getExchangePricesAndConfig(address(USDC));

        s_.supplyRaw = _fromBigNumber(totalAmounts_ & X64);
        s_.supplyFree = _fromBigNumber(
            (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_SUPPLY_INTEREST_FREE) & X64
        );
        s_.borrowRaw = _fromBigNumber(
            (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST) & X64
        );
        s_.borrowFree = _fromBigNumber(totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_INTEREST_FREE);
        s_.supplyPrice = (packed_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) & X64;
        s_.borrowPrice = (packed_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) & X64;
    }

    function _fromBigNumber(uint256 bigNumber_) internal pure returns (uint256) {
        return BigMathMinified.fromBigNumber(bigNumber_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
    }

    /// @dev the exchange prices the next `operate()` or `updateExchangePrices()` call will use
    function _pricesNow() internal view returns (uint256 supplyPrice_, uint256 borrowPrice_) {
        return LiquidityCalcs.calcExchangePrices(resolver.getExchangePricesAndConfig(address(USDC)));
    }

    function _lastUpdateTimestamp() internal view returns (uint256) {
        return
            (resolver.getExchangePricesAndConfig(address(USDC)) >>
                LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) & X33;
    }

    function _storedUtilization() internal view returns (uint256) {
        return
            (resolver.getExchangePricesAndConfig(address(USDC)) >>
                LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) & X14;
    }

    // reference formulas: `truncated_` false is the scaled math the encoders run, true divides everything by
    // EXCHANGE_PRICES_PRECISION first, which drops the fraction of every token unit

    function _supplyAmounts(
        State memory s_,
        bool truncated_
    ) internal pure returns (uint256 withInterest_, uint256 interestFree_) {
        withInterest_ = s_.supplyRaw * s_.supplyPrice;
        interestFree_ = s_.supplyFree * EXCHANGE_PRICES_PRECISION;
        if (truncated_) {
            withInterest_ /= EXCHANGE_PRICES_PRECISION;
            interestFree_ /= EXCHANGE_PRICES_PRECISION;
        }
    }

    function _borrowAmounts(
        State memory s_,
        bool truncated_
    ) internal pure returns (uint256 withInterest_, uint256 interestFree_) {
        withInterest_ = s_.borrowRaw * s_.borrowPrice;
        interestFree_ = s_.borrowFree * EXCHANGE_PRICES_PRECISION;
        if (truncated_) {
            withInterest_ /= EXCHANGE_PRICES_PRECISION;
            interestFree_ /= EXCHANGE_PRICES_PRECISION;
        }
    }

    /// @dev ratio as stored: `(value << 1) | flag`, flag set when the interest-free side is bigger. Only the
    /// supply side rounds that branch up (`roundUpInverted_`), the borrow side floors both.
    function _ratioField(
        uint256 withInterest_,
        uint256 interestFree_,
        bool roundUpInverted_
    ) internal pure returns (uint256) {
        if (withInterest_ > interestFree_) {
            return ((interestFree_ * FOUR_DECIMALS) / withInterest_) << 1;
        }
        if (withInterest_ < interestFree_) {
            uint256 numerator_ = withInterest_ * FOUR_DECIMALS;
            if (roundUpInverted_) {
                numerator_ += interestFree_ - 1;
            }
            return ((numerator_ / interestFree_) << 1) | 1;
        }
        return withInterest_ > 0 ? FOUR_DECIMALS << 1 : 0;
    }

    function _supplyRatio(State memory s_, bool truncated_) internal pure returns (uint256) {
        (uint256 withInterest_, uint256 interestFree_) = _supplyAmounts(s_, truncated_);
        return _ratioField(withInterest_, interestFree_, true);
    }

    function _borrowRatio(State memory s_, bool truncated_) internal pure returns (uint256) {
        (uint256 withInterest_, uint256 interestFree_) = _borrowAmounts(s_, truncated_);
        return _ratioField(withInterest_, interestFree_, false);
    }

    function _utilization(State memory s_, bool truncated_) internal pure returns (uint256) {
        (uint256 supplyWithInterest_, uint256 supplyInterestFree_) = _supplyAmounts(s_, truncated_);
        (uint256 borrowWithInterest_, uint256 borrowInterestFree_) = _borrowAmounts(s_, truncated_);

        uint256 totalSupply_ = supplyWithInterest_ + supplyInterestFree_;
        if (totalSupply_ == 0) {
            return 0;
        }
        return ((borrowWithInterest_ + borrowInterestFree_) * FOUR_DECIMALS) / totalSupply_;
    }

    function _assertOperateWroteStorage() internal {
        assertEq(_lastUpdateTimestamp(), block.timestamp, "test setup sanity: operate did not write storage");
    }

    function _assertStoredSupplyRatio(State memory s_) internal {
        uint256 expected_ = _supplyRatio(s_, false);
        _assertSupplyRatio(resolver, address(USDC), uint8(expected_ & 1), expected_ >> 1);
    }

    function _assertStoredBorrowRatio(State memory s_) internal {
        uint256 expected_ = _borrowRatio(s_, false);
        _assertBorrowRatio(resolver, address(USDC), uint8(expected_ & 1), expected_ >> 1);
    }

    function _assertStoredUtilization(State memory s_) internal {
        assertEq(_storedUtilization(), _utilization(s_, false), "utilization is not as expected");
    }

    function _assertAllScaled() internal {
        State memory s_ = _readState();
        _assertStoredSupplyRatio(s_);
        _assertStoredBorrowRatio(s_);
        _assertStoredUtilization(s_);
    }

    /// @dev `mode_` is the expected flag, 0 with-interest bigger and 1 interest-free bigger. Also asserts that
    /// truncating first would have stored something else, so the check cannot pass on the old math.
    function _assertSupplyRatioScaled(uint256 mode_) internal {
        State memory s_ = _readState();
        assertTrue(
            _supplyRatio(s_, false) != _supplyRatio(s_, true),
            "test setup sanity: truncating first would not change the supply ratio"
        );
        assertEq(_supplyRatio(s_, false) & 1, mode_, "test setup sanity: unexpected supply ratio branch");
        _assertStoredSupplyRatio(s_);
    }

    function _assertBorrowRatioScaled(uint256 mode_) internal {
        State memory s_ = _readState();
        assertTrue(
            _borrowRatio(s_, false) != _borrowRatio(s_, true),
            "test setup sanity: truncating first would not change the borrow ratio"
        );
        assertEq(_borrowRatio(s_, false) & 1, mode_, "test setup sanity: unexpected borrow ratio branch");
        _assertStoredBorrowRatio(s_);
    }

    function _assertUtilizationScaled() internal {
        State memory s_ = _readState();
        assertTrue(
            _utilization(s_, false) != _utilization(s_, true),
            "test setup sanity: truncating first would not change the utilization"
        );
        _assertStoredUtilization(s_);
    }

    // The next four end with one interest-free amount sized from the exchange price that a same-block `operate()`
    // or `updateExchangePrices()` uses, which lets two sides line up exactly at a price that is not 1e12.

    /// @dev 1e12 raw is worth exactly the supply price in token units, so supplying that many interest-free
    /// units makes the scaled supplies identical. The borrow only exists to accrue interest.
    function _openSuppliesScaledEqual() internal {
        _open(1e12, 0, 4e11, 0);
        vm.warp(block.timestamp + ELAPSED);
        (uint256 supplyPrice_, ) = _pricesNow();
        _supply(address(liquidity), mockProtocolInterestFree, address(USDC), alice, supplyPrice_);
    }

    /// @dev the interest-free supply is the with-interest supply's worth rounded down to a token unit: equal once
    /// truncated, while the scaled with-interest supply keeps its fraction and stays bigger
    function _openSuppliesOnlyTruncatedEqual() internal {
        uint256 supplyRaw_ = 3000;
        _open(supplyRaw_, 0, 1000, 0);
        vm.warp(block.timestamp + ELAPSED);
        (uint256 supplyPrice_, ) = _pricesNow();
        uint256 floored_ = (supplyRaw_ * supplyPrice_) / EXCHANGE_PRICES_PRECISION;
        _supply(address(liquidity), mockProtocolInterestFree, address(USDC), alice, floored_);
    }

    /// @dev the interest-free supply is liquidity only
    function _openBorrowsScaledEqual() internal {
        _open(0, 5e12, 1e12, 0);
        vm.warp(block.timestamp + ELAPSED);
        (, uint256 borrowPrice_) = _pricesNow();
        _borrow(mockProtocolInterestFree, address(USDC), bob, borrowPrice_);
    }

    function _openBorrowsOnlyTruncatedEqual() internal {
        uint256 borrowRaw_ = 1000;
        _open(0, 100_000, borrowRaw_, 0);
        vm.warp(block.timestamp + ELAPSED);
        (, uint256 borrowPrice_) = _pricesNow();
        uint256 floored_ = (borrowRaw_ * borrowPrice_) / EXCHANGE_PRICES_PRECISION;
        _borrow(mockProtocolInterestFree, address(USDC), bob, floored_);
    }

    function _assertSuppliesScaledEqual() internal {
        State memory s_ = _readState();
        assertGt(s_.supplyPrice, EXCHANGE_PRICES_PRECISION, "test setup sanity: supply price must have accrued");
        (uint256 withInterest_, uint256 interestFree_) = _supplyAmounts(s_, false);
        assertEq(withInterest_, interestFree_, "test setup sanity: scaled supplies must be equal");

        _assertSupplyRatio(resolver, address(USDC), 0, FOUR_DECIMALS);
    }

    function _assertBorrowsScaledEqual() internal {
        State memory s_ = _readState();
        assertGt(s_.borrowPrice, EXCHANGE_PRICES_PRECISION, "test setup sanity: borrow price must have accrued");
        (uint256 withInterest_, uint256 interestFree_) = _borrowAmounts(s_, false);
        assertEq(withInterest_, interestFree_, "test setup sanity: scaled borrows must be equal");

        _assertBorrowRatio(resolver, address(USDC), 0, FOUR_DECIMALS);
    }

    /// @dev truncated math would store 100% here, the real ratio is just below
    function _assertSuppliesOnlyTruncatedEqual() internal {
        State memory s_ = _readState();
        (uint256 withInterest_, uint256 interestFree_) = _supplyAmounts(s_, true);
        assertEq(withInterest_, interestFree_, "test setup sanity: truncated supplies must be equal");
        assertEq(_supplyRatio(s_, true), FOUR_DECIMALS << 1, "test setup sanity: truncated math must read 100%");
        assertLt(_supplyRatio(s_, false) >> 1, FOUR_DECIMALS, "test setup sanity: scaled ratio must be below 100%");

        _assertSupplyRatioScaled(0);
    }

    function _assertBorrowsOnlyTruncatedEqual() internal {
        State memory s_ = _readState();
        (uint256 withInterest_, uint256 interestFree_) = _borrowAmounts(s_, true);
        assertEq(withInterest_, interestFree_, "test setup sanity: truncated borrows must be equal");
        assertEq(_borrowRatio(s_, true), FOUR_DECIMALS << 1, "test setup sanity: truncated math must read 100%");
        assertLt(_borrowRatio(s_, false) >> 1, FOUR_DECIMALS, "test setup sanity: scaled ratio must be below 100%");

        _assertBorrowRatioScaled(0);
    }

    function test_operate_SupplyRatioUsesScaledAmountsWhenWithInterestBigger() public {
        _openWithInterestHeavy();
        _operateAfter(ELAPSED);

        _assertSupplyRatioScaled(0);
    }

    function test_operate_SupplyRatioUsesScaledAmountsWhenInterestFreeBigger() public {
        _openInterestFreeHeavy();
        _operateAfter(ELAPSED);

        _assertSupplyRatioScaled(1);
    }

    function test_operate_SupplyRatioIsFourDecimalsWhenScaledSuppliesEqual() public {
        _openSuppliesScaledEqual();
        _assertOperateWroteStorage();

        _assertSuppliesScaledEqual();
    }

    function test_operate_SupplyRatioBelowFourDecimalsWhenOnlyTruncatedSuppliesEqual() public {
        _openSuppliesOnlyTruncatedEqual();
        _assertOperateWroteStorage();

        _assertSuppliesOnlyTruncatedEqual();
    }

    function test_operate_BorrowRatioUsesScaledAmountsWhenWithInterestBigger() public {
        _openWithInterestHeavy();
        _operateAfter(ELAPSED);

        _assertBorrowRatioScaled(0);
    }

    function test_operate_BorrowRatioUsesScaledAmountsWhenInterestFreeBigger() public {
        _openInterestFreeHeavy();
        _operateAfter(ELAPSED);

        _assertBorrowRatioScaled(1);
    }

    function test_operate_BorrowRatioIsFourDecimalsWhenScaledBorrowsEqual() public {
        _openBorrowsScaledEqual();
        _assertOperateWroteStorage();

        _assertBorrowsScaledEqual();
    }

    function test_operate_BorrowRatioBelowFourDecimalsWhenOnlyTruncatedBorrowsEqual() public {
        _openBorrowsOnlyTruncatedEqual();
        _assertOperateWroteStorage();

        _assertBorrowsOnlyTruncatedEqual();
    }

    function test_operate_UtilizationUsesScaledAmountsWhenWithInterestBigger() public {
        _openWithInterestHeavy();
        _operateAfter(ELAPSED);

        _assertUtilizationScaled();
    }

    function test_operate_UtilizationUsesScaledAmountsWhenInterestFreeBigger() public {
        _openInterestFreeHeavy();
        _operateAfter(ELAPSED);

        _assertUtilizationScaled();
    }

    function testFuzz_operate_StoredValuesMatchScaledFormula(
        uint256 supplyWithInterest_,
        uint256 supplyInterestFree_,
        uint256 borrowWithInterest_,
        uint256 borrowInterestFree_,
        uint256 elapsed_
    ) public {
        _openBounded(supplyWithInterest_, supplyInterestFree_, borrowWithInterest_, borrowInterestFree_);
        _operateAfter(bound(elapsed_, 1 days + 1, 3 * 365 days));

        _assertAllScaled();
    }

    function test_updateExchangePrices_SupplyRatioUsesScaledAmountsWhenWithInterestBigger() public {
        _openWithInterestHeavy();
        _updateExchangePricesAfter(ELAPSED);

        _assertSupplyRatioScaled(0);
    }

    function test_updateExchangePrices_SupplyRatioUsesScaledAmountsWhenInterestFreeBigger() public {
        _openInterestFreeHeavy();
        _updateExchangePricesAfter(ELAPSED);

        _assertSupplyRatioScaled(1);
    }

    function test_updateExchangePrices_SupplyRatioIsFourDecimalsWhenScaledSuppliesEqual() public {
        _openSuppliesScaledEqual();
        _clearStoredRatiosAndUtilization();
        _updateExchangePrices();

        _assertSuppliesScaledEqual();
    }

    function test_updateExchangePrices_SupplyRatioBelowFourDecimalsWhenOnlyTruncatedSuppliesEqual() public {
        _openSuppliesOnlyTruncatedEqual();
        _clearStoredRatiosAndUtilization();
        _updateExchangePrices();

        _assertSuppliesOnlyTruncatedEqual();
    }

    function test_updateExchangePrices_BorrowRatioUsesScaledAmountsWhenWithInterestBigger() public {
        _openWithInterestHeavy();
        _updateExchangePricesAfter(ELAPSED);

        _assertBorrowRatioScaled(0);
    }

    function test_updateExchangePrices_BorrowRatioUsesScaledAmountsWhenInterestFreeBigger() public {
        _openInterestFreeHeavy();
        _updateExchangePricesAfter(ELAPSED);

        _assertBorrowRatioScaled(1);
    }

    function test_updateExchangePrices_BorrowRatioIsFourDecimalsWhenScaledBorrowsEqual() public {
        _openBorrowsScaledEqual();
        _clearStoredRatiosAndUtilization();
        _updateExchangePrices();

        _assertBorrowsScaledEqual();
    }

    function test_updateExchangePrices_BorrowRatioBelowFourDecimalsWhenOnlyTruncatedBorrowsEqual() public {
        _openBorrowsOnlyTruncatedEqual();
        _clearStoredRatiosAndUtilization();
        _updateExchangePrices();

        _assertBorrowsOnlyTruncatedEqual();
    }

    function test_updateExchangePrices_UtilizationUsesScaledAmountsWhenWithInterestBigger() public {
        _openWithInterestHeavy();
        _updateExchangePricesAfter(ELAPSED);

        _assertUtilizationScaled();
    }

    function test_updateExchangePrices_UtilizationUsesScaledAmountsWhenInterestFreeBigger() public {
        _openInterestFreeHeavy();
        _updateExchangePricesAfter(ELAPSED);

        _assertUtilizationScaled();
    }

    function testFuzz_updateExchangePrices_StoredValuesMatchScaledFormula(
        uint256 supplyWithInterest_,
        uint256 supplyInterestFree_,
        uint256 borrowWithInterest_,
        uint256 borrowInterestFree_,
        uint256 elapsed_
    ) public {
        _openBounded(supplyWithInterest_, supplyInterestFree_, borrowWithInterest_, borrowInterestFree_);
        _updateExchangePricesAfter(bound(elapsed_, 1 days + 1, 3 * 365 days));

        _assertAllScaled();
    }
}
