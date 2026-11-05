//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultT1BaseTest } from "./vault.t.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { TickMath } from "../../../../contracts/libraries/tickMath.sol";

/// @notice Liquidation rounding that needs an accrued borrow exchange price, a collateral unit worth far less than a
///         debt unit, or a tick liquidated whole. Runs on vaultTwo, 18 decimal DAI collateral against 6 decimal USDC.
contract VaultT1LiquidationRoundingTest is VaultT1BaseTest {
    uint256 internal constant X10 = 0x3ff;
    uint256 internal constant X19 = 0x7ffff;
    uint256 internal constant TICK_DATA_SLOT = 5;

    uint256 internal constant OPEN_PRICE = 1e15;
    uint256 internal constant COLLATERAL = 10_000e18;
    uint256 internal constant DEBT = 7_990e6;
    uint256 internal constant LOWER_DEBT = 7_500e6;
    uint256 internal constant LIQUIDATED_DEBT = 400e6;
    uint256 internal constant WHOLE_TICK_DEBT = 5;

    function _openPosition(uint256 debt_) internal returns (int256 tick_) {
        _setOracleTwoPrice(OPEN_PRICE);
        vm.prank(alice);
        (uint256 nftId_, , ) = vaultTwo.operate(0, int256(COLLATERAL), int256(debt_), alice);
        uint256 positionData_ = vaultResolver.getPositionDataRaw(address(vaultTwo), nftId_);
        tick_ = (positionData_ & 2) == 2 ? int256((positionData_ >> 2) & X19) : -int256((positionData_ >> 2) & X19);
    }

    function _exchangePrices() internal view returns (uint256 supplyExPrice_, uint256 borrowExPrice_) {
        (, , supplyExPrice_, borrowExPrice_) = vaultTwo.updateExchangePrices(
            vaultResolver.getVaultVariables2Raw(address(vaultTwo))
        );
    }

    function _setPriceForLtv(int256 tick_, uint256 ltvPerMille_) internal {
        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _exchangePrices();
        uint256 debtPerCol_ = (TickMath.getRatioAtTick(int24(tick_)) * 1e27 * 1000) /
            (TickMath.ZERO_TICK_SCALED_RATIO * ltvPerMille_);
        _setOracleTwoPrice((debtPerCol_ * borrowExPrice_) / supplyExPrice_);
    }

    function _setPenalty(uint256 penalty_) internal {
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultTwo)).updateLiquidationPenalty(penalty_);
    }

    function _rawTotalBorrow() internal returns (uint256) {
        uint256 bigNumber_ = (vaultResolver.getVaultVariablesRaw(address(vaultTwo)) >> 146) & X64;
        assertEq(bigNumber_ & X8, 0, "precondition: the packed total borrow is exact");
        return bigNumber_ >> 8;
    }

    function _debtPerCol() internal view returns (uint256 up_, uint256 down_) {
        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _exchangePrices();
        uint256 scaledPrice_ = oracleTwo.price() * supplyExPrice_;
        up_ = (scaledPrice_ + borrowExPrice_ - 1) / borrowExPrice_;
        down_ = scaledPrice_ / borrowExPrice_;
    }

    function _colPerDebt(uint256 debtPerCol_, uint256 penalty_) internal pure returns (uint256) {
        return ((1e54 / debtPerCol_) * (10000 + penalty_)) / 10000;
    }

    function _collateralPaid(uint256 rawCol_, uint256 supplyExPrice_) internal pure returns (uint256) {
        return (rawCol_ * supplyExPrice_) / 1e12;
    }

    function test_liquidate_PaysCeilingOfReleasedRawDebt() public {
        int256 tick_ = _openPosition(DEBT);
        vm.warp(block.timestamp + 365 days);
        _setPriceForLtv(tick_, 850);
        (, uint256 borrowExPrice_) = _exchangePrices();
        assertGt(borrowExPrice_, 1e12, "precondition: the borrow price accrued interest");

        uint256 rawBefore_ = _rawTotalBorrow();
        vm.prank(bob);
        (uint256 debtPaid_, ) = vaultTwo.liquidate(LIQUIDATED_DEBT, 0, bob, false);
        uint256 released_ = rawBefore_ - _rawTotalBorrow();

        assertEq(released_, (LIQUIDATED_DEBT * 1e12) / borrowExPrice_, "precondition: the amount limits the debt");
        assertGt((released_ * borrowExPrice_) % 1e12, 0, "precondition: converting the raw debt back is inexact");
        assertEq(debtPaid_, (released_ * borrowExPrice_ + 1e12 - 1) / 1e12, "the debt paid is the exact ceiling");
        assertEq(debtPaid_, (released_ * borrowExPrice_) / 1e12 + 1, "the ceiling is one above the floor here");
    }

    function test_liquidate_PaysCollateralFromRoundedUpDebtPerCol() public {
        uint256 penalty_ = 100;
        _setPenalty(penalty_);
        int256 tick_ = _openPosition(DEBT);
        vm.warp(block.timestamp + 365 days);
        _setPriceForLtv(tick_, 850);

        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _exchangePrices();
        (uint256 debtPerColUp_, uint256 debtPerColDown_) = _debtPerCol();
        assertGt(debtPerColUp_, debtPerColDown_, "precondition: the debt per collateral division is inexact");

        uint256 rawDebt_ = (LIQUIDATED_DEBT * 1e12) / borrowExPrice_;
        uint256 expected_ = _collateralPaid((rawDebt_ * _colPerDebt(debtPerColUp_, penalty_)) / 1e27, supplyExPrice_);
        uint256 expectedIfFloored_ = _collateralPaid(
            (rawDebt_ * _colPerDebt(debtPerColDown_, penalty_)) / 1e27,
            supplyExPrice_
        );
        assertLt(expected_, expectedIfFloored_, "precondition: rounding the debt per collateral down overpays");

        vm.prank(bob);
        (, uint256 colPaid_) = vaultTwo.liquidate(LIQUIDATED_DEBT, 0, bob, false);

        assertEq(colPaid_, expected_, "the collateral follows the rounded up debt per collateral");
    }

    function _setTickDebt(int256 tick_, uint256 debt_) internal {
        bytes32 slot_ = keccak256(abi.encode(tick_, TICK_DATA_SLOT));
        uint256 tickData_ = uint256(vm.load(address(vaultTwo), slot_));
        vm.store(address(vaultTwo), slot_, bytes32((tickData_ & ~(X64 << 25)) | ((debt_ << 8) << 25)));
    }

    function _liquidationAndMaxTick() internal view returns (int256 liquidationTick_, int256 maxTick_) {
        uint256 vaultVariables2_ = vaultResolver.getVaultVariables2Raw(address(vaultTwo));
        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _exchangePrices();
        uint256 ratio_ = (((oracleTwo.price() * supplyExPrice_) / borrowExPrice_) * TickMath.ZERO_TICK_SCALED_RATIO) /
            1e27;
        (liquidationTick_, ) = TickMath.getTickAtRatio((ratio_ * ((vaultVariables2_ >> 42) & X10)) / 1000);
        (maxTick_, ) = TickMath.getTickAtRatio((ratio_ * ((vaultVariables2_ >> 52) & X10)) / 1000);
    }

    /// @dev Crafted tick debt: a tick is liquidated whole only at a few raw units, honest ticks hold at least 1e3.
    function test_liquidate_PaysCollateralOnOneLessDebtWhenTickIsLiquidatedWhole() public {
        int256 topTick_ = _openPosition(DEBT);
        int256 nextTick_ = _openPosition(LOWER_DEBT);
        _setPriceForLtv(topTick_, 885);
        (int256 liquidationTick_, int256 maxTick_) = _liquidationAndMaxTick();
        assertLe(topTick_, maxTick_, "precondition: the top tick is not absorbed");
        assertGt(nextTick_, liquidationTick_, "precondition: the next tick is above the liquidation tick");
        assertLt(nextTick_, topTick_, "precondition: the next tick is below the top tick");
        _setTickDebt(topTick_, WHOLE_TICK_DEBT);

        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _exchangePrices();
        (uint256 debtPerCol_, ) = _debtPerCol();
        uint256 colPerDebt_ = _colPerDebt(debtPerCol_, 0);
        assertGe(colPerDebt_, 1e27, "precondition: a raw debt unit is worth at least a raw collateral unit");
        uint256 tickRatio_ = TickMath.getRatioAtTick(int24(topTick_));
        uint256 nextRatio_ = TickMath.getRatioAtTick(int24(nextTick_));
        uint256 toNextTick_ = ((WHOLE_TICK_DEBT - (nextRatio_ * WHOLE_TICK_DEBT) / tickRatio_) * 1e27) /
            (1e27 - (colPerDebt_ * nextRatio_) / TickMath.ZERO_TICK_SCALED_RATIO);
        assertEq(toNextTick_, WHOLE_TICK_DEBT, "precondition: reaching the next tick takes the whole tick");

        uint256 rawDebt_ = (LIQUIDATED_DEBT * 1e12) / borrowExPrice_;
        uint256 restDebt_ = rawDebt_ - (WHOLE_TICK_DEBT - 1);
        uint256 expected_ = _collateralPaid(
            ((WHOLE_TICK_DEBT - 1) * colPerDebt_) / 1e27 + (restDebt_ * colPerDebt_) / 1e27,
            supplyExPrice_
        );
        uint256 collateralFirst_ = _collateralPaid(
            (WHOLE_TICK_DEBT * colPerDebt_) / 1e27 + (restDebt_ * colPerDebt_) / 1e27,
            supplyExPrice_
        );
        assertGt(collateralFirst_, expected_, "precondition: the collateral taken before the adjustment overpays");

        vm.prank(bob);
        (uint256 debtPaid_, uint256 colPaid_) = vaultTwo.liquidate(LIQUIDATED_DEBT, 0, bob, false);

        assertEq(debtPaid_, (rawDebt_ * borrowExPrice_ + 1e12 - 1) / 1e12, "the debt paid is the requested amount");
        assertEq(colPaid_, expected_, "the whole tick is paid on one raw debt unit less");
    }
}
