//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultT1BaseTest } from "./vault.t.sol";
import { TickMath } from "../../../../contracts/libraries/tickMath.sol";
import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

/// @notice Crafted-state guards: a tick remainder between MIN_TICK_DEBT and MIN_DEBT, absorbed liquidity with no top
///         tick under a liquidatable zero tick, and a single wei of absorbed debt.
contract VaultT1CraftedStateGuardsTest is VaultT1BaseTest {
    bool internal constant POSITIVE_TICK = true;
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant X10 = 0x3ff;
    uint256 internal constant X19 = 0x7ffff;
    uint256 internal constant X128 = type(uint128).max;
    uint256 internal constant ABSORBED_LIQUIDITY_SLOT = 2;
    uint256 internal constant TICK_DATA_SLOT = 5;

    // Packed tick debt carries no rounding below 2^56, so the crafted remainders are exact.
    uint256 internal constant COLLATERAL = 5e16;
    uint256 internal constant DEBT = 2e16;
    uint256 internal constant DEPOSIT = 1e16;

    function _positionTick(uint256 nftId_) internal view returns (int256) {
        uint256 positionData_ = vaultResolver.getPositionDataRaw(address(vaultOne), nftId_);
        return (positionData_ & 2) == 2 ? int256((positionData_ >> 2) & X19) : -int256((positionData_ >> 2) & X19);
    }

    function _topTick() internal view returns (int256) {
        return vaultResolver.getVaultState(address(vaultOne)).topTick;
    }

    function _tickDebt(int256 tick_) internal view returns (uint256) {
        uint256 bigNumber_ = (vaultResolver.getTickDataRaw(address(vaultOne), tick_) >> 25) & X64;
        return (bigNumber_ >> 8) << (bigNumber_ & X8);
    }

    function _tickHasDebt(int256 tick_) internal view returns (bool) {
        int256 mapId_ = tick_ < 0 ? ((tick_ + 1) / 256) - 1 : tick_ / 256;
        uint256 word_ = vaultResolver.getTickHasDebtRaw(address(vaultOne), mapId_);
        return ((word_ >> uint256(tick_ - mapId_ * 256)) & 1) == 1;
    }

    function _setTickDebt(int256 tick_, uint256 debt_) internal {
        bytes32 slot_ = keccak256(abi.encode(tick_, TICK_DATA_SLOT));
        uint256 tickData_ = uint256(vm.load(address(vaultOne), slot_));
        vm.store(address(vaultOne), slot_, bytes32((tickData_ & ~(X64 << 25)) | ((debt_ << 8) << 25)));
    }

    /// @dev The debt `operate` takes off the position's tick: re-derived from the collateral rounded up.
    function _debtOnTick(uint256 nftId_, int256 tick_) internal view returns (uint256) {
        uint256 colBigNumber_ = (vaultResolver.getPositionDataRaw(address(vaultOne), nftId_) >> 45) & X64;
        uint256 colRoundedUp_ = (colBigNumber_ & X8) == 0
            ? (colBigNumber_ >> 8) + 1
            : ((colBigNumber_ >> 8) << (colBigNumber_ & X8)) + (1 << (colBigNumber_ & X8));
        return ((TickMath.getRatioAtTick(int24(tick_)) * colRoundedUp_) >> 96) + 1;
    }

    function _depositWithTickRemainder(uint256 remainder_) internal returns (int256 oldTick_, int256 newTick_) {
        setOraclePrice((1e27 * 126) / 100, POSITIVE_TICK);
        vm.prank(alice);
        (uint256 nftId_, , ) = vaultOne.operate(0, int256(COLLATERAL), int256(DEBT), alice);
        oldTick_ = _positionTick(nftId_);

        uint256 tickDebt_ = _debtOnTick(nftId_, oldTick_) + remainder_;
        assertLt(tickDebt_, 1 << 56, "precondition: the tick debt is stored without rounding");
        assertTrue(_tickHasDebt(oldTick_), "precondition: the tick is marked as holding debt");
        assertEq(_topTick(), oldTick_, "precondition: the position sits on the top tick");

        _setTickDebt(oldTick_, tickDebt_);
        assertEq(_tickDebt(oldTick_), tickDebt_, "precondition: the tick holds the position's debt and the remainder");

        vm.prank(alice);
        vaultOne.operate(nftId_, int256(DEPOSIT), 0, alice);
        newTick_ = _positionTick(nftId_);
        assertLt(newTick_, oldTick_, "precondition: the deposit moves the position to a lower tick");
    }

    function test_operate_KeepsTickDebtAboveMinTickDebt() public {
        (int256 oldTick_, ) = _depositWithTickRemainder(5e3);

        assertEq(_tickDebt(oldTick_), 5e3, "the remainder stays on the tick");
        assertTrue(_tickHasDebt(oldTick_), "the tick stays marked as holding debt");
        assertEq(_topTick(), oldTick_, "the tick stays the top tick");
    }

    function test_operate_KeepsTickDebtAtMinTickDebt() public {
        (int256 oldTick_, ) = _depositWithTickRemainder(1e3);

        assertEq(_tickDebt(oldTick_), 1e3, "the remainder stays on the tick");
        assertTrue(_tickHasDebt(oldTick_), "the tick stays marked as holding debt");
        assertEq(_topTick(), oldTick_, "the tick stays the top tick");
    }

    function test_operate_ZeroesTickDebtBelowMinTickDebt() public {
        (int256 oldTick_, int256 newTick_) = _depositWithTickRemainder(999);

        assertEq(_tickDebt(oldTick_), 0, "the remainder is dropped");
        assertFalse(_tickHasDebt(oldTick_), "the tick is unmarked");
        assertEq(_topTick(), newTick_, "the top tick moves to the position's new tick");
    }

    function _setupAbsorbedWithNoTopTick() internal {
        setOraclePrice((1e27 * 126) / 100, POSITIVE_TICK);
        vm.prank(alice);
        vaultOne.operate(0, 10000e18, 10000e18, alice);

        setOraclePrice((1e27 * 110) / 100, POSITIVE_TICK);
        vm.prank(bob);
        vaultOne.liquidate(0, 0, address(0), false);

        assertGt(vaultResolver.getAbsorbedLiquidityRaw(address(vaultOne)), 0, "precondition: absorbed liquidity");
        assertEq(_topTick(), type(int256).min, "precondition: no top tick");
    }

    function _exchangePrices() internal view returns (uint256 supplyExPrice_, uint256 borrowExPrice_) {
        (, , supplyExPrice_, borrowExPrice_) = vaultOne.updateExchangePrices(
            vaultResolver.getVaultVariables2Raw(address(vaultOne))
        );
    }

    function _liquidationAndMaxTick() internal view returns (int256 liquidationTick_, int256 maxTick_) {
        uint256 vaultVariables2_ = vaultResolver.getVaultVariables2Raw(address(vaultOne));
        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _exchangePrices();
        uint256 ratio_ = (((oracleOne.price() * supplyExPrice_) / borrowExPrice_) * TickMath.ZERO_TICK_SCALED_RATIO) /
            1e27;
        (liquidationTick_, ) = TickMath.getTickAtRatio((ratio_ * ((vaultVariables2_ >> 42) & X10)) / 1000);
        (maxTick_, ) = TickMath.getTickAtRatio((ratio_ * ((vaultVariables2_ >> 52) & X10)) / 1000);
    }

    function _absorbedSettlement() internal view returns (uint256 debt_, uint256 col_) {
        uint256 absorbed_ = vaultResolver.getAbsorbedLiquidityRaw(address(vaultOne));
        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _exchangePrices();
        debt_ = ((absorbed_ & X128) * borrowExPrice_ + 1e12 - 1) / 1e12;
        col_ = ((absorbed_ >> 128) * supplyExPrice_) / 1e12;
    }

    function _stripSelector(bytes memory err_) internal pure returns (bytes memory out_) {
        out_ = new bytes(err_.length - 4);
        for (uint256 i_; i_ < out_.length; ++i_) out_[i_] = err_[i_ + 4];
    }

    /// @dev Asking for twice the absorbed debt reaches the tick loop, which must not walk a phantom tick 0. The DEAD
    ///      address simulation stops before the Liquidity payback, which the sole position's rounded up tick debt
    ///      would underflow.
    function test_liquidate_SettlesOnlyAbsorbedLiquidityWhenZeroTickIsLiquidatable() public {
        _setupAbsorbedWithNoTopTick();
        setOraclePrice((1e27 * 122) / 100, POSITIVE_TICK);
        (int256 liquidationTick_, int256 maxTick_) = _liquidationAndMaxTick();
        assertLt(liquidationTick_, 0, "precondition: tick 0 is above the liquidation tick");
        assertGe(maxTick_, 0, "precondition: tick 0 is not above the max tick");
        (uint256 expectedDebt_, uint256 expectedCol_) = _absorbedSettlement();

        vm.prank(bob);
        try vaultOne.liquidate(2 * expectedDebt_, 0, DEAD, true) {
            fail();
        } catch (bytes memory err_) {
            assertEq(bytes4(err_), Error.FluidLiquidateResult.selector, "must reach the liquidation result");
            (uint256 colLiquidated_, uint256 debtLiquidated_) = abi.decode(_stripSelector(err_), (uint256, uint256));
            assertEq(debtLiquidated_, expectedDebt_, "exactly the absorbed debt is liquidated");
            assertEq(colLiquidated_, expectedCol_, "exactly the absorbed collateral is paid out");
        }
    }

    function _setAbsorbedDebt(uint256 debtRaw_) internal {
        uint256 colRaw_ = vaultResolver.getAbsorbedLiquidityRaw(address(vaultOne)) >> 128;
        vm.store(address(vaultOne), bytes32(ABSORBED_LIQUIDITY_SLOT), bytes32((colRaw_ << 128) | debtRaw_));
        assertEq(
            vaultResolver.getAbsorbedLiquidityRaw(address(vaultOne)),
            (colRaw_ << 128) | debtRaw_,
            "precondition: the absorbed debt is crafted"
        );
        (, uint256 borrowExPrice_) = _exchangePrices();
        assertEq(borrowExPrice_, 1e12, "precondition: one raw debt unit is one wei");
    }

    function test_liquidate_RevertIfOnlyOneWeiOfAbsorbedDebtIsLiquidated() public {
        _setupAbsorbedWithNoTopTick();
        _setAbsorbedDebt(1);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidLiquidation));
        vm.prank(bob);
        vaultOne.liquidate(1000e18, 0, bob, true);
    }

    function test_liquidate_SettlesTwoWeiOfAbsorbedDebt() public {
        _setupAbsorbedWithNoTopTick();
        _setAbsorbedDebt(2);
        uint256 colRaw_ = vaultResolver.getAbsorbedLiquidityRaw(address(vaultOne)) >> 128;

        vm.prank(bob);
        try vaultOne.liquidate(1000e18, 0, DEAD, true) {
            fail();
        } catch (bytes memory err_) {
            assertEq(bytes4(err_), Error.FluidLiquidateResult.selector, "must reach the liquidation result");
            (uint256 colLiquidated_, uint256 debtLiquidated_) = abi.decode(_stripSelector(err_), (uint256, uint256));
            assertEq(debtLiquidated_, 2, "the two wei are liquidated");
            assertEq(colLiquidated_, colRaw_, "the absorbed collateral is paid out");
        }
    }
}
