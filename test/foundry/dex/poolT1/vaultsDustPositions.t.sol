//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultsBaseTest } from "./vaults.t.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { FluidDexT1 } from "../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import { IFluidVault } from "../../../../contracts/protocols/vault/interfaces/iVault.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";
import { TickMath } from "../../../../contracts/libraries/tickMath.sol";
import { Error as DexError } from "../../../../contracts/protocols/dex/error.sol";
import { ErrorTypes as DexErrorTypes } from "../../../../contracts/protocols/dex/errorTypes.sol";
import { Error as VaultError } from "../../../../contracts/protocols/vault/error.sol";
import { ErrorTypes as VaultErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";

/// @notice A liquidation can leave a T2, T3 or T4 position with a net debt below MIN_DEBT. It stays with its owner. On
///         T2 a max payback and max withdraw close it. On T3 / T4 the dust payback is below the DEX's minimum burn, so
///         the owner borrows back above MIN_DEBT first. A deposit that leaves it in the band reverts.
contract VaultsDustPositionsTest is VaultsBaseTest {
    using BigMathMinified for uint256;

    uint256 internal constant LIQUIDATABLE_PRICE = 870000000000000000;
    uint256 internal constant MIN_DEBT = 1e4;
    // Far above MIN_OPERATE: the DEX mints no fewer than ~1e14 shares, Liquidity rejects deposits below the rounding
    // step of the total supply, and a position that keeps its debt needs the deposit to outweigh its debt rounding.
    uint256 internal constant SMART_DEPOSIT_SHARES = 1e16;
    uint256 internal constant NORMAL_DEPOSIT = 1e14;
    uint256 internal constant POSITION_DATA_SLOT = 3;

    struct DustPosition {
        uint256 netDebtRaw;
        uint256 colRaw;
        uint256 absorbedBefore;
    }

    function _accrueInterest() internal {
        vm.warp(block.timestamp + 1 days);
        assertGt(
            liquidityResolver_.getOverallTokenData(DAI_USDC_VAULT.dex.token1).borrowExchangePrice,
            1e12,
            "precondition: interest accrued at Liquidity"
        );
    }

    function _liquidate(VaultType vaultType_) internal {
        _setOraclePrice(DAI_USDC_VAULT, vaultType_, _calculatePrice(DAI_USDC_VAULT, vaultType_, LIQUIDATABLE_PRICE));
        FluidVaultResolver.LiquidationStruct memory liquidationData_ = getVaultLiquidation(
            payable(_getVaultTypeAddress(DAI_USDC_VAULT, vaultType_)),
            0
        );
        uint256 debtAmt_ = liquidationData_.inAmt - 10;

        if (vaultType_ == VaultType.VaultT2) {
            vm.prank(bob);
            DAI_USDC_VAULT.vaultT2.liquidate(debtAmt_, 0, 1, 1, bob, false);
        } else if (vaultType_ == VaultType.VaultT3) {
            vm.prank(bob);
            DAI_USDC_VAULT.vaultT3.liquidatePerfect(debtAmt_, 1e18, 1e18, 0, bob, false);
        } else {
            (uint256 token0Max_, uint256 token1Max_) = _getDexPaybackPerfect(
                FluidDexT1(payable(_getDexTypeAddressForVault(DAI_USDC_VAULT, VaultType.VaultT4))),
                debtAmt_
            );
            vm.prank(bob);
            DAI_USDC_VAULT.vaultT4.liquidatePerfect(debtAmt_, token0Max_, token1Max_, 0, 1, 1, bob, false);
        }

        _setOraclePrice(DAI_USDC_VAULT, vaultType_, _calculatePrice(DAI_USDC_VAULT, vaultType_, 1e18));
    }

    /// @dev A regular position plus a second one with a 12k wei debt on the same tick, so the liquidation of the
    ///      first leaves the second with a net debt below MIN_DEBT.
    function _setupT2DustPosition() internal returns (uint256 nftId_) {
        vm.startPrank(alice);
        DAI_USDC_VAULT.vaultT2.operate(
            0,
            int256(50 * DAI_USDC_VAULT.dex.token0Wei),
            int256(150 * DAI_USDC_VAULT.dex.token1Wei),
            1e18,
            int256(75 * DAI_USDC_VAULT.dex.token1Wei),
            alice
        );
        (nftId_, , ) = DAI_USDC_VAULT.vaultT2.operate(0, int256(16e15), int256(16e3), 1, int256(12e3), alice);
        vm.stopPrank();

        _liquidate(VaultType.VaultT2);
    }

    /// @dev A regular position plus a small one on the same tick, liquidated together. The smallest DEX borrow is
    ///      ~1e14 shares, far above MIN_DEBT, so tests lower the net debt by overwriting the stored dust.
    function _setupT3LiquidatedPosition() internal returns (uint256 nftId_) {
        vm.startPrank(alice);
        DAI_USDC_VAULT.vaultT3.operate(
            0,
            int256(100 * DAI_USDC_VAULT.dex.token0Wei),
            int256(40 * DAI_USDC_VAULT.dex.token0Wei),
            int256(110 * DAI_USDC_VAULT.dex.token1Wei),
            150 * 1e18,
            alice
        );
        (nftId_, ) = DAI_USDC_VAULT.vaultT3.operatePerfect(0, int256(1e16), int256(75e14), 1, 1, alice);
        vm.stopPrank();

        _liquidate(VaultType.VaultT3);
    }

    function _setupT4LiquidatedPosition() internal returns (uint256 nftId_) {
        vm.startPrank(alice);
        DAI_USDC_VAULT.vaultT4.operate(
            0,
            int256(50 * DAI_USDC_VAULT.dex.token0Wei),
            int256(150 * DAI_USDC_VAULT.dex.token1Wei),
            1e18,
            int256(50 * DAI_USDC_VAULT.dex.token0Wei),
            int256(100 * DAI_USDC_VAULT.dex.token1Wei),
            150 * 1e18,
            alice
        );
        (nftId_, ) = DAI_USDC_VAULT.vaultT4.operatePerfect(0, int256(1e16), 1e18, 1e18, int256(75e14), 1, 1, alice);
        vm.stopPrank();

        _liquidate(VaultType.VaultT4);
    }

    function _absorbedLiquidity(address vault_) internal view returns (uint256) {
        return _vaultResolver.getAbsorbedLiquidityRaw(vault_);
    }

    function _positionDataSlot(uint256 nftId_) internal pure returns (bytes32) {
        return keccak256(abi.encode(nftId_, POSITION_DATA_SLOT));
    }

    function _storedCol(address vault_, uint256 nftId_) internal view returns (uint256 colRaw_) {
        uint256 colBigNumber_ = (uint256(vm.load(vault_, _positionDataSlot(nftId_))) >> 45) & X64;
        colRaw_ = (colBigNumber_ >> 8) << (colBigNumber_ & X8);
    }

    /// @dev Overwrites the position's stored dust debt (bits 109-172). Returns the value that was stored, which
    ///      differs from `dustRaw_` once it no longer fits the 56 bit coefficient.
    function _setStoredDust(address vault_, uint256 nftId_, uint256 dustRaw_) internal returns (uint256 stored_) {
        bytes32 slot_ = _positionDataSlot(nftId_);
        uint256 dustBigNumber_ = dustRaw_.toBigNumber(56, 8, BigMathMinified.ROUND_DOWN);
        stored_ = (dustBigNumber_ >> 8) << (dustBigNumber_ & X8);

        uint256 positionData_ = uint256(vm.load(vault_, slot_));
        vm.store(vault_, slot_, bytes32((positionData_ & ~(X64 << 109)) | (dustBigNumber_ << 109)));
    }

    /// @dev The vault derives the pre-liquidation debt from the rounded up collateral.
    function _debtFromRoundedUpCol(uint256 positionData_, int256 tick_) internal pure returns (uint256) {
        uint256 colBigNumber_ = (positionData_ >> 45) & X64;
        uint256 colRoundedUp_ = (colBigNumber_ & X8) == 0
            ? (colBigNumber_ >> 8) + 1
            : ((colBigNumber_ >> 8) << (colBigNumber_ & X8)) + (1 << (colBigNumber_ & X8));
        return ((TickMath.getRatioAtTick(int24(tick_)) * colRoundedUp_) >> 96) + 1;
    }

    /// @dev Gross debt, collateral and dust of a liquidated position as the sync at the top of `operate` sees them.
    function _syncedPosition(
        address vault_,
        uint256 nftId_
    ) internal view returns (uint256 grossDebtRaw_, uint256 colRaw_, uint256 dustRaw_) {
        uint256 positionData_ = _vaultResolver.getPositionDataRaw(vault_, nftId_);
        int256 tick_ = (positionData_ & 2) == 2
            ? int256((positionData_ >> 2) & X19)
            : -int256((positionData_ >> 2) & X19);

        (, grossDebtRaw_, colRaw_, , ) = IFluidVault(vault_).fetchLatestPosition(
            tick_,
            (positionData_ >> 21) & X24,
            _debtFromRoundedUpCol(positionData_, tick_),
            _vaultResolver.getTickDataRaw(vault_, tick_)
        );

        uint256 dustBigNumber_ = (positionData_ >> 109) & X64;
        dustRaw_ = (dustBigNumber_ >> 8) << (dustBigNumber_ & X8);
    }

    /// @dev Stores the dust that leaves exactly `netDebtRaw_` of net debt after the sync.
    function _setNetDebt(address vault_, uint256 nftId_, uint256 netDebtRaw_) internal {
        (uint256 grossDebtRaw_, , ) = _syncedPosition(vault_, nftId_);
        assertEq(_setStoredDust(vault_, nftId_, grossDebtRaw_ - netDebtRaw_), grossDebtRaw_ - netDebtRaw_);
    }

    function _readDustPosition(address vault_, uint256 nftId_) internal returns (DustPosition memory p_) {
        (uint256 grossDebtRaw_, uint256 colRaw_, uint256 dustRaw_) = _syncedPosition(vault_, nftId_);
        p_.netDebtRaw = grossDebtRaw_ - dustRaw_;
        p_.colRaw = colRaw_;
        p_.absorbedBefore = _absorbedLiquidity(vault_);
        assertGt(p_.netDebtRaw, 0, "precondition: the liquidation left a net debt");
        assertLt(p_.netDebtRaw, MIN_DEBT, "precondition: the net debt is below MIN_DEBT");
    }

    function _assertClosed(uint256 nftId_) internal {
        (FluidVaultResolver.UserPosition memory position_, ) = _vaultResolver.positionByNftId(nftId_);
        assertEq(position_.supply, 0, "the position is closed");
        assertEq(position_.borrow, 0, "the position is closed");
    }

    function _expectUserDebtTooLow() internal {
        vm.expectRevert(
            abi.encodeWithSelector(VaultError.FluidVaultError.selector, VaultErrorTypes.Vault__UserDebtTooLow)
        );
    }

    function test_operatePerfect_T2OwnerClosesDustPositionAfterInterestAccrual() public {
        uint256 nftId_ = _setupT2DustPosition();
        _accrueInterest();
        address vault_ = address(DAI_USDC_VAULT.vaultT2);
        DustPosition memory p_ = _readDustPosition(vault_, nftId_);

        vm.prank(alice);
        DAI_USDC_VAULT.vaultT2.operatePerfect(nftId_, type(int256).min, -1, -1, type(int256).min, alice);

        assertEq(_absorbedLiquidity(vault_), p_.absorbedBefore, "nothing is absorbed");
        _assertClosed(nftId_);
    }

    function test_operate_T2PaybackFromAnyoneLeavesCollateralWithOwner() public {
        uint256 nftId_ = _setupT2DustPosition();
        _accrueInterest();
        address vault_ = address(DAI_USDC_VAULT.vaultT2);
        DustPosition memory p_ = _readDustPosition(vault_, nftId_);

        vm.prank(bob);
        (, , int256 debtLeg_) = DAI_USDC_VAULT.vaultT2.operate(nftId_, 0, 0, 0, type(int256).min, address(0));

        assertLt(debtLeg_, -1, "the caller pays the net debt, not just the rounding wei");
        assertEq(_absorbedLiquidity(vault_), p_.absorbedBefore, "nothing is absorbed");
        assertEq(_storedCol(vault_, nftId_), p_.colRaw, "the collateral stays on the position");
        (FluidVaultResolver.UserPosition memory position_, ) = _vaultResolver.positionByNftId(nftId_);
        assertTrue(position_.isSupplyPosition, "the position holds no debt");
    }

    function test_operatePerfect_RevertIfT2DepositLeavesDustPosition() public {
        uint256 nftId_ = _setupT2DustPosition();
        _accrueInterest();
        _readDustPosition(address(DAI_USDC_VAULT.vaultT2), nftId_);

        _expectUserDebtTooLow();
        vm.prank(bob);
        DAI_USDC_VAULT.vaultT2.operatePerfect(nftId_, int256(SMART_DEPOSIT_SHARES), 1e18, 1e18, 0, address(0));
    }

    function test_operatePerfect_RevertIfT3MaxPaybackOnDustPosition() public {
        uint256 nftId_ = _setupT3LiquidatedPosition();
        _setNetDebt(address(DAI_USDC_VAULT.vaultT3), nftId_, MIN_DEBT / 2);

        vm.expectRevert(abi.encodeWithSelector(DexError.FluidDexError.selector, DexErrorTypes.DexT1__BurnAmtOverflow));
        vm.prank(alice);
        DAI_USDC_VAULT.vaultT3.operatePerfect(nftId_, 0, type(int256).min, -1e18, -1e18, address(0));
    }

    function test_operatePerfect_T3OwnerBorrowsBackThenClosesDustPosition() public {
        uint256 nftId_ = _setupT3LiquidatedPosition();
        address vault_ = address(DAI_USDC_VAULT.vaultT3);
        _setNetDebt(vault_, nftId_, MIN_DEBT / 2);
        DustPosition memory p_ = _readDustPosition(vault_, nftId_);

        vm.startPrank(alice);
        DAI_USDC_VAULT.vaultT3.operatePerfect(nftId_, int256(1e16), int256(5e15), 1, 1, alice);
        DAI_USDC_VAULT.vaultT3.operatePerfect(nftId_, type(int256).min, type(int256).min, -1e18, -1e18, alice);
        vm.stopPrank();

        assertEq(_absorbedLiquidity(vault_), p_.absorbedBefore, "nothing is absorbed");
        _assertClosed(nftId_);
    }

    function test_operate_T3KeepsPositionWhenNetDebtEqualsMinDebt() public {
        uint256 nftId_ = _setupT3LiquidatedPosition();
        address vault_ = address(DAI_USDC_VAULT.vaultT3);
        (, uint256 colRaw_, ) = _syncedPosition(vault_, nftId_);
        _setNetDebt(vault_, nftId_, MIN_DEBT);
        uint256 absorbedLiquidityBefore_ = _absorbedLiquidity(vault_);

        vm.prank(bob);
        DAI_USDC_VAULT.vaultT3.operate(nftId_, int256(NORMAL_DEPOSIT), 0, 0, 0, address(0));

        assertEq(_absorbedLiquidity(vault_), absorbedLiquidityBefore_, "nothing should be absorbed");
        assertEq(_storedCol(vault_, nftId_), colRaw_ + NORMAL_DEPOSIT, "position should keep its collateral");
        (FluidVaultResolver.UserPosition memory position_, ) = _vaultResolver.positionByNftId(nftId_);
        assertFalse(position_.isSupplyPosition, "the position should keep its debt");
        // the write path rounds the net debt up by a wei or two
        assertApproxEqAbs(position_.borrow, MIN_DEBT, 2, "position should keep its net debt");
    }

    function test_operate_RevertIfT3NetDebtIsBelowMinDebtAfterSync() public {
        uint256 nftId_ = _setupT3LiquidatedPosition();
        // the write path adds one wei of rounding, so MIN_DEBT - 1 still clears the floor
        _setNetDebt(address(DAI_USDC_VAULT.vaultT3), nftId_, MIN_DEBT - 2);

        _expectUserDebtTooLow();
        vm.prank(bob);
        DAI_USDC_VAULT.vaultT3.operate(nftId_, int256(NORMAL_DEPOSIT), 0, 0, 0, address(0));
    }

    function test_operatePerfect_RevertIfT4MaxPaybackOnDustPosition() public {
        uint256 nftId_ = _setupT4LiquidatedPosition();
        _setNetDebt(address(DAI_USDC_VAULT.vaultT4), nftId_, MIN_DEBT / 2);

        vm.expectRevert(abi.encodeWithSelector(DexError.FluidDexError.selector, DexErrorTypes.DexT1__BurnAmtOverflow));
        vm.prank(alice);
        DAI_USDC_VAULT.vaultT4.operatePerfect(nftId_, 0, 0, 0, type(int256).min, -1e18, -1e18, address(0));
    }

    function test_operatePerfect_RevertIfT4DepositLeavesDustPosition() public {
        uint256 nftId_ = _setupT4LiquidatedPosition();
        _accrueInterest();
        _setNetDebt(address(DAI_USDC_VAULT.vaultT4), nftId_, MIN_DEBT / 2);

        _expectUserDebtTooLow();
        vm.prank(bob);
        DAI_USDC_VAULT.vaultT4.operatePerfect(nftId_, int256(SMART_DEPOSIT_SHARES), 1e18, 1e18, 0, 0, 0, address(0));
    }
}
