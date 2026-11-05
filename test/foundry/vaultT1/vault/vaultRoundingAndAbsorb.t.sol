//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { VaultT1BaseTest } from "./vault.t.sol";
import { FluidVaultT1 } from "../../../../contracts/protocols/vault/vaultT1/coreModule/main.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";
import { CalcsVaultSimulatedTime } from "../../../../contracts/periphery/resolvers/revenue/calcsVaultSimulatedTime.sol";

contract CalcsVaultSimulatedTimeHarness {
    function updateExchangePrices(
        uint256 vaultVariables2_,
        uint256 vaultRates_,
        uint256 liquiditySupplyExchangePricesAndConfig_,
        uint256 liquidityBorrowExchangePricesAndConfig_,
        uint256 blockTimestamp_
    ) external pure returns (uint256, uint256, uint256, uint256) {
        return
            CalcsVaultSimulatedTime.updateExchangePrices(
                vaultVariables2_,
                vaultRates_,
                liquiditySupplyExchangePricesAndConfig_,
                liquidityBorrowExchangePricesAndConfig_,
                blockTimestamp_
            );
    }
}

/// @notice Borrow fee rounds up, liquidation payouts round in the protocol's favour, and absorbed liquidity
/// stays liquidatable without a top tick.
contract VaultT1RoundingAndAbsorbTest is VaultT1BaseTest {
    bool internal constant POSITIVE_TICK = true;

    function _setBorrowFee(uint256 feeBps_) internal {
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultOne)).updateBorrowFee(feeBps_);
    }

    function _positionDebt(uint256 nftId_) internal view returns (uint256) {
        (FluidVaultResolver.UserPosition memory position_, ) = vaultResolver.positionByNftId(nftId_);
        return position_.borrow;
    }

    /// @dev opens a healthy position on vaultOne at the standard test price
    function _openPosition(int256 collateral_, int256 debt_) internal returns (uint256 nftId_) {
        setOraclePrice(((1e27 * 126) / 100), POSITIVE_TICK);
        vm.prank(alice);
        (nftId_, , ) = vaultOne.operate(0, collateral_, debt_, alice);
    }

    // ###################### borrow fee rounds up ######################

    /// @dev The critical regression guard: with a zero borrow fee, no fee may be charged at all.
    /// A naive `(x * fee) / 10000 + 1` style ceiling would silently charge every borrower on every
    /// fee-less vault. The `+ 9999` form must leave a zero fee at exactly zero.
    function test_zeroBorrowFee_chargesNothing() public {
        _setBorrowFee(0);

        int256 debt_ = 1000 * 1e18;
        uint256 nftId_ = _openPosition(10000 * 1e18, debt_);

        uint256 debtRegistered_ = _positionDebt(nftId_);

        assertGe(debtRegistered_, uint256(debt_), "debt must at least cover the borrowed amount");
        // the only excess allowed is the pre-existing +1 raw round-up converted back through the exchange
        // price (~1e12 here). The smallest configurable fee is 0.01% = 1e17 on this borrow, so a bound of
        // debt/1e6 still catches any real fee with a ~100x margin.
        assertLe(debtRegistered_, uint256(debt_) + uint256(debt_) / 1e6, "zero fee must not charge a fee");
    }

    function test_borrowFee_isChargedAndNeverBelowFloor() public {
        uint256 feeBps_ = 100; // 1%
        int256 debt_ = 1000 * 1e18;

        // baseline with no fee: isolates the fee from the pre-existing +1 raw round-up, which both borrows share
        _setBorrowFee(0);
        uint256 noFeeDebt_ = _positionDebt(_openPosition(10000 * 1e18, debt_));

        _setBorrowFee(feeBps_);
        uint256 withFeeDebt_ = _positionDebt(_openPosition(10000 * 1e18, debt_));

        uint256 feeCharged_ = withFeeDebt_ - noFeeDebt_;
        uint256 floorFee_ = (uint256(debt_) * feeBps_) / 10000;

        assertGe(feeCharged_, floorFee_, "fee must never be below the floor amount");
        // and the ceiling must not overshoot: at most one raw unit above the floor, converted back
        assertLe(feeCharged_, floorFee_ + floorFee_ / 1e9 + 1e12, "fee must not exceed ceil of the floor amount");
    }

    /// @dev Exact-value test: the fee difference between floor and ceil is a single raw unit, which is only
    /// observable if BigMath does not truncate it. Amounts are kept below 2^56 so the vault's packed
    /// totalBorrow is exact, and the borrow is chosen so the fee division leaves a remainder.
    function test_borrowFee_exactCeilingOnInexactDivision() public {
        int256 debt_ = 1e15 + 7; // raw not a multiple of 100 -> fee division leaves a remainder
        uint256 feeBps_ = 100; // 1%

        // baseline: no fee. delta equals the raw debt the vault registered for this borrow.
        _setBorrowFee(0);
        uint256 before0_ = _vaultTotalBorrow();
        _openPosition(10000 * 1e18, debt_);
        uint256 noFeeDelta_ = _vaultTotalBorrow() - before0_;

        // same borrow in the same block with a 1% fee
        _setBorrowFee(feeBps_);
        _openPosition(10000 * 1e18, debt_);
        uint256 withFeeDelta_ = _vaultTotalBorrow() - before0_ - noFeeDelta_;

        uint256 feeCharged_ = withFeeDelta_ - noFeeDelta_;
        uint256 numerator_ = noFeeDelta_ * feeBps_;
        assertGt(numerator_ % 10000, 0, "precondition: fee division is inexact");

        // the fix must charge the exact ceiling; the pre-fix floor would be one raw unit lower
        assertEq(feeCharged_, (numerator_ + 9999) / 10000, "borrow fee must be the exact ceiling");
        assertEq(feeCharged_, numerator_ / 10000 + 1, "ceiling must be exactly one above the floor here");
    }

    function _vaultTotalBorrow() internal view returns (uint256) {
        return vaultResolver.getVaultEntireData(address(vaultOne)).totalSupplyAndBorrow.totalBorrowVault;
    }

    function test_borrowFeeScalesWithConfiguredRate() public {
        int256 debt_ = 1000 * 1e18;

        _setBorrowFee(0);
        uint256 noFeeDebt_ = _positionDebt(_openPosition(10000 * 1e18, debt_));

        _setBorrowFee(100); // 1%
        uint256 withFeeDebt_ = _positionDebt(_openPosition(10000 * 1e18, debt_));

        assertGt(withFeeDebt_, noFeeDebt_, "a configured fee must increase registered debt");
        uint256 delta_ = withFeeDebt_ - noFeeDebt_;
        assertApproxEqRel(delta_, uint256(debt_) / 100, 1e12, "fee delta must be ~1% of the borrow");
    }

    // ###################### liquidation payout invariants ######################

    /// @dev The liquidator must never receive more collateral per unit of debt than the oracle-implied
    /// ratio entitles them to. Deriving colPerDebt from a floor-rounded debtPerCol inflated it in the
    /// liquidator's favour, which the ceil-rounded reciprocal prevents. With a debtPerCol near 1e27 both roundings
    /// pay the same, so the exact payout is pinned in VaultT1LiquidationRoundingTest on a far smaller debtPerCol.
    function test_liquidatorNeverReceivesMoreThanEntitledRatio() public {
        _openPosition(10000 * 1e18, 10000 * 1e18);

        // drop into liquidatable territory
        uint256 liquidationPrice_ = (1e27 * 122) / 100;
        setOraclePrice(liquidationPrice_, POSITIVE_TICK);

        vm.prank(bob);
        (uint256 debtLiquidated_, uint256 colLiquidated_) = vaultOne.liquidate(2000 * 1e18, 0, address(bob), true);

        assertGt(debtLiquidated_, 0, "liquidation happened");
        assertGt(colLiquidated_, 0, "collateral paid out");

        // colPerDebt must round DOWN: collateral received must not exceed debt / price (0% penalty configured).
        // Exchange prices are still 1e12 here so the oracle price is the full conversion factor.
        uint256 entitledCol_ = (debtLiquidated_ * 1e27) / liquidationPrice_;
        assertLe(
            colLiquidated_,
            entitledCol_,
            "liquidator must not receive more collateral than the oracle-implied entitlement"
        );
    }

    /// @dev When debtPerCol floors to zero the original code reverted via `1e54 / 0`. The fix divides by the ceiling,
    /// which is >= 1, so without the explicit check the call would only revert later, with empty data, in
    /// `TickMath.getTickAtRatio(0)`. The check keeps the revert explicit.
    function test_liquidate_revertsWhenDebtPerColCollapsesToZero() public {
        _openPosition(10000 * 1e18, 10000 * 1e18);

        // accrue borrow interest so borrowExPrice > supplyExPrice
        vm.warp(block.timestamp + 365 days);

        // minimum non-zero oracle price: price * supplyExPrice / borrowExPrice now floors to 0
        _setOracleOnePrice(1);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidOraclePrice));
        vm.prank(bob);
        vaultOne.liquidate(2000 * 1e18, 0, address(bob), true);
    }

    function test_liquidatorPaysAtLeastReleasedDebt() public {
        _openPosition(10000 * 1e18, 10000 * 1e18);
        setOraclePrice((1e27 * 122) / 100, POSITIVE_TICK);

        uint256 borrowBefore_ = vaultResolver
            .getVaultEntireData(address(vaultOne))
            .totalSupplyAndBorrow
            .totalBorrowVault;

        vm.prank(bob);
        (uint256 debtLiquidated_, ) = vaultOne.liquidate(2000 * 1e18, 0, address(bob), true);

        uint256 borrowAfter_ = vaultResolver
            .getVaultEntireData(address(vaultOne))
            .totalSupplyAndBorrow
            .totalBorrowVault;

        // what the liquidator paid must cover the debt the vault released; ceiling rounding
        // guarantees payment >= released value, so it can never come up short.
        assertGe(debtLiquidated_, borrowBefore_ - borrowAfter_, "liquidator payment must cover released debt");
    }

    // ###################### absorbed liquidity without a top tick ######################

    /// @dev leaves the vault with absorbedLiquidity > 0 and no top tick at all, by absorbing its only position
    function _setupAbsorbedWithNoTopTick() internal {
        _openPosition(10000 * 1e18, 10000 * 1e18);

        // crash the price so the only position sits above liquidationMaxLimit and gets absorbed
        setOraclePrice((1e27 * 110) / 100, POSITIVE_TICK);

        // absorb only: debtAmt_ == 0 returns right after the absorb spell
        vm.prank(bob);
        vaultOne.liquidate(0, 0, address(0), false);

        FluidVaultResolver.VaultEntireData memory data_ = vaultResolver.getVaultEntireData(address(vaultOne));
        assertGt(data_.totalSupplyAndBorrow.absorbedBorrow, 0, "precondition: absorbed liquidity present");
        assertEq(data_.vaultState.topTick, type(int).min, "precondition: no top tick left");
    }

    function test_absorbedLiquidityIsLiquidatableWithoutTopTick() public {
        _setupAbsorbedWithNoTopTick();

        // before the fix this reverted with Vault__TopTickDoesNotExist, stranding the absorbed amounts
        vm.prank(bob);
        (uint256 debtLiquidated_, uint256 colLiquidated_) = vaultOne.liquidate(1000 * 1e18, 0, address(bob), true);

        assertGt(debtLiquidated_, 0, "absorbed debt must be liquidatable");
        assertGt(colLiquidated_, 0, "absorbed collateral must be paid out");

        FluidVaultResolver.VaultEntireData memory data_ = vaultResolver.getVaultEntireData(address(vaultOne));
        assertLt(data_.totalSupplyAndBorrow.absorbedBorrow, 10000 * 1e18, "absorbed borrow must have been reduced");
    }

    function test_noTopTick_stillRevertsWithoutAbsorbFlag() public {
        _setupAbsorbedWithNoTopTick();

        // absorb_ = false keeps the original behaviour: there is nothing to liquidate on ticks
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__TopTickDoesNotExist));
        vm.prank(bob);
        vaultOne.liquidate(1000 * 1e18, 0, address(bob), false);
    }

    function test_revertsWhenNoTopTickAndNothingAbsorbed() public {
        // fresh vault: no top tick and no absorbed liquidity must still revert even with absorb_ = true
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__TopTickDoesNotExist));
        vm.prank(bob);
        vaultOne.liquidate(1000 * 1e18, 0, address(bob), true);
    }

    function test_normalLiquidationPathUnchangedWhenTopTickExists() public {
        _openPosition(10000 * 1e18, 10000 * 1e18);
        setOraclePrice((1e27 * 122) / 100, POSITIVE_TICK);

        // with a top tick present the sentinel must not engage: normal liquidation still works
        vm.prank(bob);
        (uint256 debtLiquidated_, uint256 colLiquidated_) = vaultOne.liquidate(2000 * 1e18, 0, address(bob), true);

        assertGt(debtLiquidated_, 0, "normal liquidation path unaffected");
        assertGt(colLiquidated_, 0, "normal liquidation path unaffected");
    }

    // ###################### absorb empties every tick inside liquidate(): no Panic(0x11) ######################

    /// @dev opens the vault's only position, then crashes the price so a single liquidate() call absorbs every tick
    function _crashSoleTick() internal {
        _openPosition(10000 * 1e18, 10000 * 1e18);
        setOraclePrice((1e27 * 60) / 100, POSITIVE_TICK);
    }

    /// @dev before the fix the post-absorb decode read the emptied top tick as tick 0, the tick loop ran on a
    /// phantom tick holding 0 debt and `debtLiquidated_ -= 1` underflowed with Panic(0x11).
    function test_absorbAllTicksInCall_withoutAbsorbFlag_revertsCleanly() public {
        _crashSoleTick();

        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidLiquidation));
        vm.prank(bob);
        vaultOne.liquidate(1000 * 1e18, 0, address(bob), false);

        // the absorb itself can still be committed permissionlessly
        vm.prank(bob);
        vaultOne.liquidate(0, 0, address(0), false);
        FluidVaultResolver.VaultEntireData memory data_ = vaultResolver.getVaultEntireData(address(vaultOne));
        assertGt(data_.totalSupplyAndBorrow.absorbedBorrow, 0, "absorb committed");
        assertEq(data_.vaultState.topTick, type(int).min, "no top tick left");
    }

    /// @dev asking for more than the absorbed debt in the same call used to reach the same underflow in the tick loop.
    /// Now the absorbed liquidity is settled and the tick loop is skipped. Checked via the DEAD_ADDRESS simulation
    /// (reverts with FluidLiquidateResult after the tick loop, before the Liquidity payback): the sole position's
    /// tick-rounded debt exceeds the vault's Liquidity borrow, a pre-existing, unrelated payback underflow.
    function test_absorbAllTicksInCall_amountAboveAbsorbed_settlesAbsorbed() public {
        _crashSoleTick();

        vm.prank(bob);
        try vaultOne.liquidate(20000 * 1e18, 0, address(0x000000000000000000000000000000000000dEaD), true) {
            fail();
        } catch (bytes memory err_) {
            assertEq(
                bytes4(err_),
                Error.FluidLiquidateResult.selector,
                "must reach the liquidation result, not Panic(0x11)"
            );
            (uint256 colLiquidated_, uint256 debtLiquidated_) = abi.decode(_stripSelector(err_), (uint256, uint256));
            assertGt(debtLiquidated_, 10000 * 1e18, "absorbed debt liquidated");
            assertLt(debtLiquidated_, 10100 * 1e18, "only the absorbed debt is liquidated");
            assertGt(colLiquidated_, 0, "absorbed collateral paid out");
        }
    }

    function _stripSelector(bytes memory err_) internal pure returns (bytes memory out_) {
        out_ = new bytes(err_.length - 4);
        for (uint256 i_; i_ < out_.length; ++i_) out_[i_] = err_[i_ + 4];
    }

    /// @dev Accrues and stores once so the stored prices are no longer round 1e12, then accrues again.
    function _accrueTwice(uint256 elapsed_) internal {
        vm.warp(block.timestamp + 10 days);
        vaultOne.updateExchangePricesOnStorage();
        vm.warp(block.timestamp + elapsed_);
    }

    function _borrowPriceInputs() internal view returns (uint256 vaultVariables2_, uint256 rates_) {
        vaultVariables2_ = vaultResolver.getVaultVariables2Raw(address(vaultOne));
        rates_ = vaultResolver.getRateRaw(address(vaultOne));
    }

    /// @dev Stored vault borrow price times the magnified Liquidity growth, before the final division by 1e18.
    function _borrowPriceProduct(
        uint256 vaultVariables2_,
        uint256 rates_,
        uint256 liqBorrowExPrice_
    ) internal pure returns (uint256) {
        uint256 increase_ = ((((liqBorrowExPrice_ * 1e18) / ((rates_ >> 64) & X64)) - 1e18) *
            ((vaultVariables2_ >> 16) & 0xffff)) / 10000;
        return (rates_ >> 192) * (1e18 + increase_);
    }

    function test_updateExchangePrices_BorrowPriceRoundsUp() public {
        _openPosition(10000 * 1e18, 1000 * 1e18);
        _accrueTwice(10 days);
        (uint256 vaultVariables2_, uint256 rates_) = _borrowPriceInputs();

        (, uint256 liqBorrowExPrice_, , uint256 vaultBorrowExPrice_) = vaultOne.updateExchangePrices(vaultVariables2_);

        uint256 product_ = _borrowPriceProduct(vaultVariables2_, rates_, liqBorrowExPrice_);
        assertGt(product_ % 1e18, 0, "precondition: the division is inexact");
        assertEq(vaultBorrowExPrice_, product_ / 1e18 + 1, "the vault borrow price rounds up");
    }

    function testFuzz_updateExchangePrices_BorrowPriceIsTheCeiling(uint32 elapsed_, uint16 magnifier_) public {
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultOne)).updateBorrowRateMagnifier(magnifier_);
        _openPosition(10000 * 1e18, 1000 * 1e18);
        _accrueTwice(bound(elapsed_, 1, 365 days));
        (uint256 vaultVariables2_, uint256 rates_) = _borrowPriceInputs();

        (, uint256 liqBorrowExPrice_, , uint256 vaultBorrowExPrice_) = vaultOne.updateExchangePrices(vaultVariables2_);

        uint256 product_ = _borrowPriceProduct(vaultVariables2_, rates_, liqBorrowExPrice_);
        assertEq(vaultBorrowExPrice_, (product_ + 1e18 - 1) / 1e18, "the vault borrow price is the exact ceiling");
    }

    function test_updateExchangePrices_BorrowPriceUnchangedWithoutAccrual() public {
        _openPosition(10000 * 1e18, 1000 * 1e18);
        vm.warp(block.timestamp + 10 days);
        vaultOne.updateExchangePricesOnStorage();
        (uint256 vaultVariables2_, uint256 rates_) = _borrowPriceInputs();

        (, , , uint256 vaultBorrowExPrice_) = vaultOne.updateExchangePrices(vaultVariables2_);

        assertEq(vaultBorrowExPrice_, rates_ >> 192, "without Liquidity accrual the stored price is returned as is");
    }

    function test_updateExchangePrices_RevenueResolverCopyMatchesVault() public {
        _openPosition(10000 * 1e18, 1000 * 1e18);
        _accrueTwice(10 days);
        (uint256 vaultVariables2_, uint256 rates_) = _borrowPriceInputs();
        IFluidLiquidity liquidity_ = IFluidLiquidity(address(liquidity));
        uint256 supplyConfig_ = liquidity_.readFromStorage(
            LiquiditySlotsLink.calculateMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                vaultOne.constantsView().supplyToken
            )
        );
        uint256 borrowConfig_ = liquidity_.readFromStorage(
            LiquiditySlotsLink.calculateMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                vaultOne.constantsView().borrowToken
            )
        );

        (uint256 liqSupply_, uint256 liqBorrow_, uint256 vaultSupply_, uint256 vaultBorrow_) = vaultOne
            .updateExchangePrices(vaultVariables2_);
        (
            uint256 simLiqSupply_,
            uint256 simLiqBorrow_,
            uint256 simVaultSupply_,
            uint256 simVaultBorrow_
        ) = new CalcsVaultSimulatedTimeHarness().updateExchangePrices(
                vaultVariables2_,
                rates_,
                supplyConfig_,
                borrowConfig_,
                block.timestamp
            );

        assertEq(simLiqSupply_, liqSupply_, "liquidity supply price");
        assertEq(simLiqBorrow_, liqBorrow_, "liquidity borrow price");
        assertEq(simVaultSupply_, vaultSupply_, "vault supply price");
        assertEq(simVaultBorrow_, vaultBorrow_, "vault borrow price");
    }
}
