//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultsBaseTest } from "./vaults.t.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { FluidVaultT2 } from "../../../../contracts/protocols/vault/vaultT2/coreModule/main.sol";
import { FluidVaultT2Admin } from "../../../../contracts/protocols/vault/vaultT2/adminModule/main.sol";
import { FluidVaultT3 } from "../../../../contracts/protocols/vault/vaultT3/coreModule/main.sol";
import { FluidVaultT3Admin } from "../../../../contracts/protocols/vault/vaultT3/adminModule/main.sol";
import { FluidVaultT4 } from "../../../../contracts/protocols/vault/vaultT4/coreModule/main.sol";
import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

/// @notice The borrow fee rounds up, absorbed liquidity stays liquidatable without a top tick, a collapsed debt per
///         collateral price reverts liquidation and perfect deposits bound both tokens, on the smart vault types.
contract VaultsRoundingAndAbsorbTest is VaultsBaseTest {
    uint256 internal constant FEE_BPS = 100;
    uint256 internal constant T2_BORROW = 100_000_000;
    uint256 internal constant PERFECT_DEPOSIT_SHARES = 1e16;
    uint256 internal constant PAYBACK_MAX_PER_SHARE = 1e20;

    function _vaultExchangePrices(
        address vault_
    ) internal view returns (uint256 supplyExPrice_, uint256 borrowExPrice_) {
        FluidVaultT2 v_ = FluidVaultT2(payable(vault_));
        (, , supplyExPrice_, borrowExPrice_) = v_.updateExchangePrices(v_.readFromStorage(bytes32(uint256(1))));
    }

    function _expectError(uint256 errorId_) internal {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, errorId_));
    }

    function _expectTopTickDoesNotExist() internal {
        _expectError(ErrorTypes.Vault__TopTickDoesNotExist);
    }

    function _setBorrowFee(uint256 feeBps_) internal {
        vm.prank(admin);
        FluidVaultT2Admin(address(DAI_USDC_VAULT.vaultT2)).updateBorrowFee(feeBps_);
    }

    function _totalBorrowRaw() internal returns (uint256 total_) {
        total_ = _getVaultVariablesData(address(DAI_USDC_VAULT.vaultT2)).totalBorrow;
        assertLt(total_, 1 << 56, "precondition: the packed total borrow is exact");
    }

    function _rawBorrow(uint256 amount_) internal view returns (uint256) {
        (, uint256 borrowExPrice_) = _vaultExchangePrices(address(DAI_USDC_VAULT.vaultT2));
        return (amount_ * 1e12) / borrowExPrice_ + 1;
    }

    function _borrowT2AtFee(uint256 feeBps_) internal returns (uint256 totalBorrowRise_) {
        DexVaultParams memory v_ = DAI_USDC_VAULT;
        _setBorrowFee(feeBps_);
        uint256 totalBefore_ = _totalBorrowRaw();

        vm.prank(alice);
        v_.vaultT2.operate(
            0,
            int256(200 * v_.dex.token0Wei),
            int256(200 * v_.dex.token1Wei),
            1,
            int256(T2_BORROW),
            alice
        );

        totalBorrowRise_ = _totalBorrowRaw() - totalBefore_;
    }

    function test_operate_T2ZeroBorrowFeeChargesNothing() public {
        uint256 rawBorrow_ = _rawBorrow(T2_BORROW);

        assertEq(
            _borrowT2AtFee(0),
            rawBorrow_ + 1,
            "a zero fee must add nothing but the rounding wei to the raw borrow"
        );
    }

    function test_operate_T2BorrowFeeRoundsUpOnInexactDivision() public {
        uint256 rawBorrow_ = _rawBorrow(T2_BORROW);
        uint256 numerator_ = rawBorrow_ * FEE_BPS;
        assertGt(numerator_ % 10000, 0, "precondition: the fee division is inexact");
        // the write path adds debt / 1e9 on top, which is 0 below 1e9, so the two rises differ by exactly the fee
        assertLt(rawBorrow_ + numerator_ / 10000 + 1, 1e9, "precondition: raw debt is below the padding step");

        uint256 noFeeDelta_ = _borrowT2AtFee(0);
        uint256 withFeeDelta_ = _borrowT2AtFee(FEE_BPS);
        assertEq(noFeeDelta_, rawBorrow_ + 1, "precondition: the fee applies to the raw borrow");

        uint256 fee_ = withFeeDelta_ - noFeeDelta_;
        assertEq(fee_, (numerator_ + 9999) / 10000, "the borrow fee must be the exact ceiling");
        assertEq(fee_, numerator_ / 10000 + 1, "the ceiling must be exactly one above the floor here");
    }

    function _openPosition(VaultType vaultType_) internal {
        DexVaultParams memory v_ = DAI_USDC_VAULT;
        vm.prank(alice);
        if (vaultType_ == VaultType.VaultT2) {
            v_.vaultT2.operate(
                0,
                int(50 * v_.dex.token0Wei),
                int(150 * v_.dex.token1Wei),
                1e18,
                int(75 * v_.dex.token1Wei),
                alice
            );
        } else if (vaultType_ == VaultType.VaultT3) {
            v_.vaultT3.operate(
                0,
                int(100 * v_.dex.token0Wei),
                int(40 * v_.dex.token0Wei),
                int(110 * v_.dex.token1Wei),
                150 * 1e18,
                alice
            );
        } else {
            v_.vaultT4.operate(
                0,
                int(50 * v_.dex.token0Wei),
                int(150 * v_.dex.token1Wei),
                1e18,
                int(50 * v_.dex.token0Wei),
                int(100 * v_.dex.token1Wei),
                150 * 1e18,
                alice
            );
        }
    }

    function _absorbOnly(VaultType vaultType_) internal {
        vm.prank(bob);
        if (vaultType_ == VaultType.VaultT2) {
            DAI_USDC_VAULT.vaultT2.liquidate(0, 0, 0, 0, address(0), false);
        } else if (vaultType_ == VaultType.VaultT3) {
            DAI_USDC_VAULT.vaultT3.liquidatePerfect(0, 0, 0, 0, address(0), false);
        } else {
            DAI_USDC_VAULT.vaultT4.liquidatePerfect(0, 0, 0, 0, 0, 0, address(0), false);
        }
    }

    /// @dev debt token amount on T2, debt shares on T3 and T4
    function _partialAmount(VaultType vaultType_) internal view returns (uint256) {
        return vaultType_ == VaultType.VaultT2 ? 25 * DAI_USDC_VAULT.dex.token1Wei : 25e18;
    }

    function _liquidate(
        address payable vault_,
        VaultType vaultType_,
        uint256 amount_,
        bool absorb_
    ) internal returns (uint256 debt_, uint256 col_) {
        vm.prank(bob);
        if (vaultType_ == VaultType.VaultT2) {
            (debt_, col_, , ) = FluidVaultT2(vault_).liquidate(amount_, 0, 1, 1, bob, absorb_);
        } else if (vaultType_ == VaultType.VaultT3) {
            (debt_, , , col_) = FluidVaultT3(vault_).liquidatePerfect(
                amount_,
                PAYBACK_MAX_PER_SHARE,
                PAYBACK_MAX_PER_SHARE,
                0,
                bob,
                absorb_
            );
        } else {
            (debt_, , , col_, , ) = FluidVaultT4(vault_).liquidatePerfect(
                amount_,
                PAYBACK_MAX_PER_SHARE,
                PAYBACK_MAX_PER_SHARE,
                0,
                1,
                1,
                bob,
                absorb_
            );
        }
    }

    function _vault(VaultType vaultType_) internal view returns (address payable) {
        if (vaultType_ == VaultType.VaultT2) return payable(address(DAI_USDC_VAULT.vaultT2));
        if (vaultType_ == VaultType.VaultT3) return payable(address(DAI_USDC_VAULT.vaultT3));
        return payable(address(DAI_USDC_VAULT.vaultT4));
    }

    /// @dev absorbs every position of the vault, the dust position of setUp included, so no top tick is left
    function _setupAbsorbedWithNoTopTick(VaultType vaultType_) internal {
        _openPosition(vaultType_);
        _setOraclePrice(DAI_USDC_VAULT, vaultType_, _getOraclePrice(DAI_USDC_VAULT, vaultType_) / 100);
        _absorbOnly(vaultType_);

        FluidVaultResolver.VaultEntireData memory data_ = _vaultResolver.getVaultEntireData(_vault(vaultType_));
        assertGt(data_.totalSupplyAndBorrow.absorbedBorrow, 0, "precondition: absorbed liquidity present");
        assertEq(data_.vaultState.topTick, type(int).min, "precondition: no top tick left");
    }

    struct Settlement {
        uint256 absorbedDebtRaw;
        uint256 absorbedColRaw;
        uint256 debtPaid;
        uint256 colPaidOut;
    }

    function _expectedSettlement(address vault_, uint256 amount_) internal view returns (Settlement memory s_) {
        uint256 absorbed_ = _vaultResolver.getAbsorbedLiquidityRaw(vault_);
        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _vaultExchangePrices(vault_);
        uint256 debtRaw_ = (amount_ * 1e12) / borrowExPrice_;
        uint256 colRaw_ = ((absorbed_ >> 128) * debtRaw_) / (absorbed_ & X128);

        s_.absorbedDebtRaw = (absorbed_ & X128) - debtRaw_;
        s_.absorbedColRaw = (absorbed_ >> 128) - colRaw_;
        s_.debtPaid = (debtRaw_ * borrowExPrice_ + 1e12 - 1) / 1e12;
        s_.colPaidOut = (colRaw_ * supplyExPrice_) / 1e12;
    }

    function _checkAbsorbedLiquidityIsLiquidatableWithoutTopTick(VaultType vaultType_) internal {
        _setupAbsorbedWithNoTopTick(vaultType_);
        address payable vault_ = _vault(vaultType_);
        uint256 amount_ = _partialAmount(vaultType_);
        Settlement memory s_ = _expectedSettlement(vault_, amount_);

        (uint256 debt_, uint256 col_) = _liquidate(vault_, vaultType_, amount_, true);

        uint256 absorbedAfter_ = _vaultResolver.getAbsorbedLiquidityRaw(vault_);
        assertGt(debt_, 0, "absorbed debt must be liquidatable");
        assertGt(col_, 0, "absorbed collateral must be paid out");
        assertEq(absorbedAfter_ & X128, s_.absorbedDebtRaw, "absorbed debt falls by the debt paid");
        assertEq(absorbedAfter_ >> 128, s_.absorbedColRaw, "absorbed collateral falls in proportion");
        assertEq(debt_, s_.debtPaid, "the debt paid is rounded up");
        assertEq(col_, s_.colPaidOut, "the collateral paid out is rounded down");
    }

    function _checkNoTopTickRevertsWithoutAbsorbFlag(VaultType vaultType_) internal {
        _setupAbsorbedWithNoTopTick(vaultType_);
        address payable vault_ = _vault(vaultType_);
        uint256 amount_ = _partialAmount(vaultType_);

        _expectTopTickDoesNotExist();
        _liquidate(vault_, vaultType_, amount_, false);
    }

    function _checkRevertsWhenNoTopTickAndNothingAbsorbed(VaultType vaultType_) internal {
        DexVaultParams memory fresh_ = _deployDexVaults(DAI_USDC);
        address payable vault_ = payable(_getVaultTypeAddress(fresh_, vaultType_));
        uint256 amount_ = _partialAmount(vaultType_);
        assertEq(_vaultResolver.getAbsorbedLiquidityRaw(vault_), 0, "precondition: nothing absorbed");
        assertEq(_vaultResolver.getVaultState(vault_).topTick, type(int).min, "precondition: no top tick");

        _expectTopTickDoesNotExist();
        _liquidate(vault_, vaultType_, amount_, true);
    }

    function test_liquidate_T2AbsorbedLiquidityIsLiquidatableWithoutTopTick() public {
        _checkAbsorbedLiquidityIsLiquidatableWithoutTopTick(VaultType.VaultT2);
    }

    function test_liquidate_T3AbsorbedLiquidityIsLiquidatableWithoutTopTick() public {
        _checkAbsorbedLiquidityIsLiquidatableWithoutTopTick(VaultType.VaultT3);
    }

    function test_liquidate_T4AbsorbedLiquidityIsLiquidatableWithoutTopTick() public {
        _checkAbsorbedLiquidityIsLiquidatableWithoutTopTick(VaultType.VaultT4);
    }

    function test_liquidate_RevertIfT2NoTopTickAndAbsorbFlagUnset() public {
        _checkNoTopTickRevertsWithoutAbsorbFlag(VaultType.VaultT2);
    }

    function test_liquidate_RevertIfT3NoTopTickAndAbsorbFlagUnset() public {
        _checkNoTopTickRevertsWithoutAbsorbFlag(VaultType.VaultT3);
    }

    function test_liquidate_RevertIfT4NoTopTickAndAbsorbFlagUnset() public {
        _checkNoTopTickRevertsWithoutAbsorbFlag(VaultType.VaultT4);
    }

    function test_liquidate_RevertIfT2NoTopTickAndNothingAbsorbed() public {
        _checkRevertsWhenNoTopTickAndNothingAbsorbed(VaultType.VaultT2);
    }

    function test_liquidate_RevertIfT3NoTopTickAndNothingAbsorbed() public {
        _checkRevertsWhenNoTopTickAndNothingAbsorbed(VaultType.VaultT3);
    }

    function test_liquidate_RevertIfT4NoTopTickAndNothingAbsorbed() public {
        _checkRevertsWhenNoTopTickAndNothingAbsorbed(VaultType.VaultT4);
    }

    /// @dev price 1 makes `1 * supplyExPrice / borrowExPrice` floor to 0 once borrow interest outgrows the supply rate
    function test_liquidate_RevertIfT2DebtPerColCollapsesToZero() public {
        // the default 10% supply rate outgrows the borrow interest at Liquidity within a year
        vm.prank(admin);
        FluidVaultT2Admin(address(DAI_USDC_VAULT.vaultT2)).updateSupplyRate(0);
        _openPosition(VaultType.VaultT2);
        vm.warp(block.timestamp + 365 days);
        _setOraclePrice(DAI_USDC_VAULT, VaultType.VaultT2, 1);
        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _vaultExchangePrices(address(DAI_USDC_VAULT.vaultT2));
        assertLt(supplyExPrice_, borrowExPrice_, "precondition: the borrow price outgrew the supply price");

        _expectError(ErrorTypes.Vault__InvalidOraclePrice);
        _liquidate(
            payable(address(DAI_USDC_VAULT.vaultT2)),
            VaultType.VaultT2,
            _partialAmount(VaultType.VaultT2),
            false
        );
    }

    function _operatePerfectDepositT2(int256 colToken0MinMax_, int256 colToken1MinMax_) internal {
        vm.prank(alice);
        DAI_USDC_VAULT.vaultT2.operatePerfect(
            0,
            int256(PERFECT_DEPOSIT_SHARES),
            colToken0MinMax_,
            colToken1MinMax_,
            0,
            alice
        );
    }

    function _operatePerfectDepositT4(int256 colToken0MinMax_, int256 colToken1MinMax_) internal {
        vm.prank(alice);
        DAI_USDC_VAULT.vaultT4.operatePerfect(
            0,
            int256(PERFECT_DEPOSIT_SHARES),
            colToken0MinMax_,
            colToken1MinMax_,
            0,
            0,
            0,
            alice
        );
    }

    function test_operatePerfect_RevertIfT2ColToken1MaxIsZero() public {
        _expectError(ErrorTypes.VaultDex__InvalidOperateAmount);
        _operatePerfectDepositT2(1e18, 0);
    }

    function test_operatePerfect_RevertIfT2ColToken1MaxIsNegative() public {
        _expectError(ErrorTypes.VaultDex__InvalidOperateAmount);
        _operatePerfectDepositT2(1e18, -1);
    }

    function test_operatePerfect_RevertIfT4ColToken1MaxIsZero() public {
        _expectError(ErrorTypes.VaultDex__InvalidOperateAmount);
        _operatePerfectDepositT4(1e18, 0);
    }

    function test_operatePerfect_RevertIfT4ColToken1MaxIsNegative() public {
        _expectError(ErrorTypes.VaultDex__InvalidOperateAmount);
        _operatePerfectDepositT4(1e18, -1);
    }

    function _rateInputs(address vault_) internal view returns (uint256 vaultVariables2_, uint256 rates_) {
        vaultVariables2_ = _vaultResolver.getVaultVariables2Raw(vault_);
        rates_ = _vaultResolver.getRateRaw(vault_);
    }

    function test_updateExchangePrices_T2BorrowPriceRoundsUp() public {
        _openPosition(VaultType.VaultT2);
        address vault_ = _vault(VaultType.VaultT2);
        // a stored price that is not a round 1e12 makes the final division inexact
        vm.warp(block.timestamp + 10 days);
        FluidVaultT2(payable(vault_)).updateExchangePricesOnStorage();
        vm.warp(block.timestamp + 10 days);
        (uint256 vaultVariables2_, uint256 rates_) = _rateInputs(vault_);

        (, uint256 liqBorrowExPrice_, , uint256 vaultBorrowExPrice_) = FluidVaultT2(payable(vault_))
            .updateExchangePrices(vaultVariables2_);

        uint256 increase_ = ((((liqBorrowExPrice_ * 1e18) / ((rates_ >> 64) & X64)) - 1e18) *
            ((vaultVariables2_ >> 16) & 0xffff)) / 10000;
        uint256 product_ = (rates_ >> 192) * (1e18 + increase_);
        assertGt(product_ % 1e18, 0, "precondition: the division is inexact");
        assertEq(vaultBorrowExPrice_, product_ / 1e18 + 1, "the vault borrow price rounds up");
    }

    /// @dev Only the Liquidity-backed leg rounds up; a smart debt leg accrues its own rate, rounded down.
    function test_updateExchangePrices_T3SmartDebtBorrowPriceRoundsDown() public {
        address vault_ = _vault(VaultType.VaultT3);
        vm.prank(admin);
        FluidVaultT3Admin(vault_).updateBorrowRate(1000);
        _openPosition(VaultType.VaultT3);
        vm.warp(block.timestamp + 10 days);
        (uint256 vaultVariables2_, uint256 rates_) = _rateInputs(vault_);

        (, , , uint256 vaultBorrowExPrice_) = FluidVaultT3(payable(vault_)).updateExchangePrices(vaultVariables2_);

        uint256 elapsed_ = block.timestamp - ((vaultVariables2_ >> 122) & 0x1ffffffff);
        uint256 numerator_ = (rates_ >> 192) * elapsed_ * ((vaultVariables2_ >> 17) & 0x7fff);
        uint256 denominator_ = 10000 * 365 days;
        assertEq((vaultVariables2_ >> 16) & 1, 1, "precondition: the smart debt rate is positive");
        assertGt(numerator_ % denominator_, 0, "precondition: the rate division is inexact");
        assertEq(vaultBorrowExPrice_, (rates_ >> 192) + numerator_ / denominator_, "the smart debt price rounds down");
    }
}
