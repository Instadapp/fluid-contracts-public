//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultsBaseTest } from "./vaults.t.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { IFluidVault } from "../../../../contracts/protocols/vault/interfaces/iVault.sol";
import { TickMath } from "../../../../contracts/libraries/tickMath.sol";
import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

/// @notice Crafted-state guards on T2: a tick remainder between MIN_TICK_DEBT and MIN_DEBT, a branch holding less
///         debt than its position, absorbed liquidity with no top tick, and a single wei of absorbed debt.
contract VaultsCraftedStateGuardsTest is VaultsBaseTest {
    uint256 internal constant LIQUIDATABLE_PRICE = 870000000000000000;
    uint256 internal constant DEPOSIT_SHARES = 1e18;
    uint256 internal constant MIN_BRANCH_DEBT = 1e2;
    uint256 internal constant ABSORBED_LIQUIDITY_SLOT = 2;
    uint256 internal constant TICK_DATA_SLOT = 5;
    uint256 internal constant BRANCH_DATA_SLOT = 7;

    function _vault() internal view returns (address) {
        return address(DAI_USDC_VAULT.vaultT2);
    }

    function _openPosition() internal returns (uint256 nftId_, int256 tick_) {
        DexVaultParams memory v_ = DAI_USDC_VAULT;
        vm.prank(alice);
        (nftId_, , ) = v_.vaultT2.operate(
            0,
            int256(50 * v_.dex.token0Wei),
            int256(150 * v_.dex.token1Wei),
            1e18,
            int256(75 * v_.dex.token1Wei),
            alice
        );
        tick_ = _positionTick(nftId_);
    }

    function _depositShares(uint256 nftId_) internal {
        vm.prank(alice);
        DAI_USDC_VAULT.vaultT2.operatePerfect(nftId_, int256(DEPOSIT_SHARES), 1e18, 1e18, 0, address(0));
    }

    function _positionTick(uint256 nftId_) internal view returns (int256) {
        uint256 positionData_ = _vaultResolver.getPositionDataRaw(_vault(), nftId_);
        return (positionData_ & 2) == 2 ? int256((positionData_ >> 2) & X19) : -int256((positionData_ >> 2) & X19);
    }

    function _topTick() internal view returns (int256) {
        return _vaultResolver.getVaultState(_vault()).topTick;
    }

    function _tickDebt(int256 tick_) internal view returns (uint256) {
        uint256 bigNumber_ = (_vaultResolver.getTickDataRaw(_vault(), tick_) >> 25) & X64;
        return (bigNumber_ >> 8) << (bigNumber_ & X8);
    }

    function _tickHasDebt(int256 tick_) internal view returns (bool) {
        int256 mapId_ = tick_ < 0 ? ((tick_ + 1) / 256) - 1 : tick_ / 256;
        uint256 word_ = _vaultResolver.getTickHasDebtRaw(_vault(), mapId_);
        return ((word_ >> uint256(tick_ - mapId_ * 256)) & 1) == 1;
    }

    function _setTickDebt(int256 tick_, uint256 debt_) internal {
        bytes32 slot_ = keccak256(abi.encode(tick_, TICK_DATA_SLOT));
        uint256 tickData_ = uint256(vm.load(_vault(), slot_));
        vm.store(_vault(), slot_, bytes32((tickData_ & ~(X64 << 25)) | ((debt_ << 8) << 25)));
    }

    function _branchDebt(uint256 branchId_) internal view returns (uint256) {
        uint256 bigNumber_ = (_vaultResolver.getBranchDataRaw(_vault(), branchId_) >> 52) & X64;
        return (bigNumber_ >> 8) << (bigNumber_ & X8);
    }

    function _setBranchDebt(uint256 branchId_, uint256 debt_) internal {
        bytes32 slot_ = keccak256(abi.encode(branchId_, BRANCH_DATA_SLOT));
        uint256 branchData_ = uint256(vm.load(_vault(), slot_));
        vm.store(_vault(), slot_, bytes32((branchData_ & ~(X64 << 52)) | ((debt_ << 8) << 52)));
    }

    /// @dev The debt `operate` takes off the position's tick: re-derived from the collateral rounded up.
    function _debtOnTick(uint256 nftId_, int256 tick_) internal view returns (uint256) {
        uint256 colBigNumber_ = (_vaultResolver.getPositionDataRaw(_vault(), nftId_) >> 45) & X64;
        uint256 colRoundedUp_ = (colBigNumber_ & X8) == 0
            ? (colBigNumber_ >> 8) + 1
            : ((colBigNumber_ >> 8) << (colBigNumber_ & X8)) + (1 << (colBigNumber_ & X8));
        return ((TickMath.getRatioAtTick(int24(tick_)) * colRoundedUp_) >> 96) + 1;
    }

    function _depositWithTickRemainder(uint256 remainder_) internal returns (int256 oldTick_, int256 newTick_) {
        uint256 nftId_;
        (nftId_, oldTick_) = _openPosition();

        uint256 tickDebt_ = _debtOnTick(nftId_, oldTick_) + remainder_;
        assertLt(tickDebt_, 1 << 56, "precondition: the tick debt is stored without rounding");
        assertTrue(_tickHasDebt(oldTick_), "precondition: the tick is marked as holding debt");
        assertEq(_topTick(), oldTick_, "precondition: the position sits on the top tick");

        _setTickDebt(oldTick_, tickDebt_);
        assertEq(_tickDebt(oldTick_), tickDebt_, "precondition: the tick holds the position's debt and the remainder");

        _depositShares(nftId_);
        newTick_ = _positionTick(nftId_);
        assertLt(newTick_, oldTick_, "precondition: the deposit moves the position to a lower tick");
    }

    function test_operatePerfect_T2KeepsTickDebtAboveMinTickDebt() public {
        (int256 oldTick_, ) = _depositWithTickRemainder(5e3);

        assertEq(_tickDebt(oldTick_), 5e3, "the remainder stays on the tick");
        assertTrue(_tickHasDebt(oldTick_), "the tick stays marked as holding debt");
        assertEq(_topTick(), oldTick_, "the tick stays the top tick");
    }

    function test_operatePerfect_T2KeepsTickDebtAtMinTickDebt() public {
        (int256 oldTick_, ) = _depositWithTickRemainder(1e3);

        assertEq(_tickDebt(oldTick_), 1e3, "the remainder stays on the tick");
        assertTrue(_tickHasDebt(oldTick_), "the tick stays marked as holding debt");
        assertEq(_topTick(), oldTick_, "the tick stays the top tick");
    }

    function test_operatePerfect_T2ZeroesTickDebtBelowMinTickDebt() public {
        (int256 oldTick_, int256 newTick_) = _depositWithTickRemainder(999);

        assertEq(_tickDebt(oldTick_), 0, "the remainder is dropped");
        assertFalse(_tickHasDebt(oldTick_), "the tick is unmarked");
        assertEq(_topTick(), newTick_, "the top tick moves to the position's new tick");
    }

    function _liquidateTopTick() internal {
        _setOraclePrice(
            DAI_USDC_VAULT,
            VaultType.VaultT2,
            _calculatePrice(DAI_USDC_VAULT, VaultType.VaultT2, LIQUIDATABLE_PRICE)
        );
        FluidVaultResolver.LiquidationStruct memory liquidationData_ = getVaultLiquidation(payable(_vault()), 0);
        vm.prank(bob);
        DAI_USDC_VAULT.vaultT2.liquidate(liquidationData_.inAmt - 10, 0, 1, 1, bob, false);
        _setOraclePrice(DAI_USDC_VAULT, VaultType.VaultT2, _calculatePrice(DAI_USDC_VAULT, VaultType.VaultT2, 1e18));
    }

    /// @dev In an edge case a branch holds less than its position owes; removing the position floors the branch debt.
    function test_operatePerfect_T2FloorsBranchDebtWhenItIsBelowThePositionDebt() public {
        (uint256 nftId_, int256 tick_) = _openPosition();
        _liquidateTopTick();

        uint256 positionData_ = _vaultResolver.getPositionDataRaw(_vault(), nftId_);
        (, uint256 positionDebt_, , uint256 branchId_, ) = IFluidVault(_vault()).fetchLatestPosition(
            tick_,
            (positionData_ >> 21) & X24,
            _debtOnTick(nftId_, tick_),
            _vaultResolver.getTickDataRaw(_vault(), tick_)
        );
        assertGt(positionDebt_, 1e4, "precondition: the liquidation left a position debt");
        assertGt(_branchDebt(branchId_), positionDebt_, "precondition: the branch holds more than its position");

        _setBranchDebt(branchId_, positionDebt_ - 1);
        assertEq(_branchDebt(branchId_), positionDebt_ - 1, "precondition: the branch holds less than its position");

        _depositShares(nftId_);

        assertEq(_branchDebt(branchId_), MIN_BRANCH_DEBT, "the branch debt is floored at MIN_BRANCH_DEBT");
    }

    /// @dev Only a 100x crash lifts bob's dust position from setUp above the max limit.
    function _setupAbsorbedWithNoTopTick() internal {
        _openPosition();
        _setOraclePrice(DAI_USDC_VAULT, VaultType.VaultT2, _getOraclePrice(DAI_USDC_VAULT, VaultType.VaultT2) / 100);
        vm.prank(bob);
        DAI_USDC_VAULT.vaultT2.liquidate(0, 0, 0, 0, address(0), false);

        assertGt(_vaultResolver.getAbsorbedLiquidityRaw(_vault()), 0, "precondition: absorbed liquidity");
        assertEq(_topTick(), type(int256).min, "precondition: no top tick");
    }

    function _exchangePrices() internal view returns (uint256 supplyExPrice_, uint256 borrowExPrice_) {
        (, , supplyExPrice_, borrowExPrice_) = IFluidVault(_vault()).updateExchangePrices(
            _vaultResolver.getVaultVariables2Raw(_vault())
        );
    }

    function _liquidationAndMaxTick() internal returns (int256 liquidationTick_, int256 maxTick_) {
        uint256 vaultVariables2_ = _vaultResolver.getVaultVariables2Raw(_vault());
        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _exchangePrices();
        uint256 ratio_ = (((_getOraclePrice(DAI_USDC_VAULT, VaultType.VaultT2) * supplyExPrice_) / borrowExPrice_) *
            TickMath.ZERO_TICK_SCALED_RATIO) / 1e27;
        (liquidationTick_, ) = TickMath.getTickAtRatio((ratio_ * ((vaultVariables2_ >> 42) & X10)) / 1000);
        (maxTick_, ) = TickMath.getTickAtRatio((ratio_ * ((vaultVariables2_ >> 52) & X10)) / 1000);
    }

    function _absorbedSettlement() internal view returns (uint256 debt_, uint256 col_) {
        uint256 absorbed_ = _vaultResolver.getAbsorbedLiquidityRaw(_vault());
        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _exchangePrices();
        debt_ = ((absorbed_ & X128) * borrowExPrice_ + 1e12 - 1) / 1e12;
        col_ = ((absorbed_ >> 128) * supplyExPrice_) / 1e12;
    }

    function _stripSelector(bytes memory err_) internal pure returns (bytes memory out_) {
        out_ = new bytes(err_.length - 4);
        for (uint256 i_; i_ < out_.length; ++i_) out_[i_] = err_[i_ + 4];
    }

    /// @dev `simulateLiquidate` asks for the maximum, which reaches the tick loop; it must not walk a phantom tick 0.
    function test_simulateLiquidate_T2SettlesOnlyAbsorbedLiquidityWhenZeroTickIsLiquidatable() public {
        _setupAbsorbedWithNoTopTick();
        _setOraclePrice(DAI_USDC_VAULT, VaultType.VaultT2, (1e27 * 122) / 100);
        (int256 liquidationTick_, int256 maxTick_) = _liquidationAndMaxTick();
        assertLt(liquidationTick_, 0, "precondition: tick 0 is above the liquidation tick");
        assertGe(maxTick_, 0, "precondition: tick 0 is not above the max tick");
        (uint256 expectedDebt_, uint256 expectedCol_) = _absorbedSettlement();

        try IFluidVault(_vault()).simulateLiquidate(0, true) {
            fail();
        } catch (bytes memory err_) {
            assertEq(bytes4(err_), IFluidVault.FluidLiquidateResult.selector, "must reach the liquidation result");
            (uint256 colLiquidated_, uint256 debtLiquidated_) = abi.decode(_stripSelector(err_), (uint256, uint256));
            assertEq(debtLiquidated_, expectedDebt_, "exactly the absorbed debt is liquidated");
            assertEq(colLiquidated_, expectedCol_, "exactly the absorbed collateral is paid out");
        }
    }

    function _setAbsorbedDebt(uint256 debtRaw_) internal {
        uint256 colRaw_ = _vaultResolver.getAbsorbedLiquidityRaw(_vault()) >> 128;
        vm.store(_vault(), bytes32(ABSORBED_LIQUIDITY_SLOT), bytes32((colRaw_ << 128) | debtRaw_));
        assertEq(
            _vaultResolver.getAbsorbedLiquidityRaw(_vault()),
            (colRaw_ << 128) | debtRaw_,
            "precondition: the absorbed debt is crafted"
        );
        (, uint256 borrowExPrice_) = _exchangePrices();
        assertEq(borrowExPrice_, 1e12, "precondition: one raw debt unit is one wei");
    }

    function test_liquidate_RevertIfT2OnlyOneWeiOfAbsorbedDebtIsLiquidated() public {
        _setupAbsorbedWithNoTopTick();
        _setAbsorbedDebt(1);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidLiquidation));
        vm.prank(bob);
        DAI_USDC_VAULT.vaultT2.liquidate(25 * DAI_USDC_VAULT.dex.token1Wei, 0, 1, 1, bob, true);
    }

    function test_simulateLiquidate_T2SettlesTwoWeiOfAbsorbedDebt() public {
        _setupAbsorbedWithNoTopTick();
        _setAbsorbedDebt(2);
        uint256 colRaw_ = _vaultResolver.getAbsorbedLiquidityRaw(_vault()) >> 128;

        try IFluidVault(_vault()).simulateLiquidate(0, true) {
            fail();
        } catch (bytes memory err_) {
            assertEq(bytes4(err_), IFluidVault.FluidLiquidateResult.selector, "must reach the liquidation result");
            (uint256 colLiquidated_, uint256 debtLiquidated_) = abi.decode(_stripSelector(err_), (uint256, uint256));
            assertEq(debtLiquidated_, 2, "the two wei are liquidated");
            assertEq(colLiquidated_, colRaw_, "the absorbed collateral is paid out");
        }
    }
}
