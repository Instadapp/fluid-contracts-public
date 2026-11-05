// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { VaultsBaseTest } from "../dex/poolT1/vaults.t.sol";

import { FluidDexT1 } from "../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import { FluidDexT1Admin } from "../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import { Structs as DexAdminStructs } from "../../../contracts/protocols/dex/poolT1/adminModule/structs.sol";
import { IFluidDexT1 } from "../../../contracts/protocols/dex/interfaces/iDexT1.sol";

import { DexCalcs } from "../../../contracts/libraries/dexCalcs.sol";
import { DexSlotsLink } from "../../../contracts/libraries/dexSlotsLink.sol";
import { LiquiditySlotsLink } from "../../../contracts/libraries/liquiditySlotsLink.sol";
import { StorageRead } from "../../../contracts/libraries/storageRead.sol";

import { FluidVaultT2 } from "../../../contracts/protocols/vault/vaultT2/coreModule/main.sol";
import { FluidVaultT4 } from "../../../contracts/protocols/vault/vaultT4/coreModule/main.sol";
import { Error as FluidVaultErrors } from "../../../contracts/protocols/vault/error.sol";
import { ErrorTypes as VaultErrorTypes } from "../../../contracts/protocols/vault/errorTypes.sol";

/// @title Smart-collateral withdrawal-gap end-to-end tests against a real T2 / T4 vault + DEX.
/// @notice Pins the amount-aware gap predicate for operate() / operatePerfect(), and documents the known base-withdrawal-limit-crossing gap.
contract VaultSmartColWithdrawalGapTest is VaultsBaseTest {
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    uint256 internal constant OPEN_SHARES = 11_000e18;
    uint256 internal constant TOPUP_SHARES = 10e18;
    uint256 internal constant EXPAND_PERCENT = 1500; // 15%, 1e4 precision
    uint256 internal constant EXPAND_DURATION = 3600; // 1 hour

    struct GapState {
        uint256 S;
        uint256 L;
        uint256 gap;
        uint256 headroom;
    }

    // ---------------------------------------------------------------------------------------
    // storage / math helpers mirroring mainOperate.sol's withdrawal-gap check exactly
    // ---------------------------------------------------------------------------------------

    function _rawUserSupplyData(FluidDexT1 dex_, address user_) internal view returns (uint256) {
        return
            dex_.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT, user_)
            );
    }

    function _storedWithdrawalLimit(uint256 userSupplyData_) internal pure returns (uint256 limit_) {
        uint256 packed_ = (userSupplyData_ >> DexSlotsLink.BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT) & X64;
        limit_ = (packed_ >> DEFAULT_EXPONENT_SIZE) << (packed_ & DEFAULT_EXPONENT_MASK);
    }

    function _vaultWithdrawGapStored(address vault_) internal view returns (uint256) {
        // vaultVariables2 is storage slot 1 on every vault type (forge inspect FluidVaultT2 storage-layout).
        return (StorageRead(vault_).readFromStorage(bytes32(uint256(1))) >> 62) & X10;
    }

    function _setDexSupplyConfig(FluidDexT1 dex_, address vaultAddr_, uint256 baseWithdrawalLimit_) internal {
        DexAdminStructs.UserSupplyConfig[] memory cfg_ = new DexAdminStructs.UserSupplyConfig[](1);
        cfg_[0] = DexAdminStructs.UserSupplyConfig({
            user: vaultAddr_,
            expandPercent: EXPAND_PERCENT,
            expandDuration: EXPAND_DURATION,
            baseWithdrawalLimit: baseWithdrawalLimit_
        });

        vm.prank(admin);
        FluidDexT1Admin(address(dex_)).updateUserSupplyConfigs(cfg_);
    }

    /// @dev reads S / L / gap / headroom from real on-chain state, with the exact integer math mainOperate.sol uses.
    function _readGapState(FluidDexT1 dex_, address vaultAddr_) internal view returns (GapState memory g_) {
        uint256 rawData_ = _rawUserSupplyData(dex_, vaultAddr_);
        g_.S = getUserSupplyShare(dex_, vaultAddr_);
        g_.L = DexCalcs.calcWithdrawalLimitBeforeOperate(rawData_, g_.S);
        g_.gap = _vaultWithdrawGapStored(vaultAddr_);
        g_.headroom = ((g_.S * (1000 - g_.gap)) / 1000) - g_.L;
    }

    // ---------------------------------------------------------------------------------------
    // DEX withdraw-amount <-> shares estimation: `to_ == DEAD` reverts with shares_ before any transfer, so this never mutates state.
    // ---------------------------------------------------------------------------------------

    function _estimateWithdrawShares(FluidDexT1 dex_, uint256 token1Amt_) internal returns (uint256 shares_) {
        try dex_.withdraw(0, token1Amt_, type(uint256).max, DEAD) returns (uint256) {
            revert("estimate call did not revert");
        } catch (bytes memory lowLevelData_) {
            require(lowLevelData_.length >= 36, "unexpected estimate revert");
            bytes4 selector_;
            assembly {
                selector_ := mload(add(lowLevelData_, 0x20))
            }
            require(selector_ == IFluidDexT1.FluidDexLiquidityOutput.selector, "unexpected estimate error");
            assembly {
                shares_ := mload(add(lowLevelData_, 36))
            }
        }
    }

    /// @dev refines a reserve-ratio guess into the token1 amount that burns ~`targetShares_` via a single-token withdraw.
    function _token1AmtForShares(FluidDexT1 dex_, uint256 targetShares_) internal returns (uint256 amt_) {
        IFluidDexT1.CollateralReserves memory reserves_ = dexResolver.getDexCollateralReserves(address(dex_));
        uint256 totalShares_ = getTotalSupplyShares(dex_);

        amt_ = (targetShares_ * reserves_.token1RealReserves) / totalShares_;
        if (amt_ == 0) amt_ = 1000;

        for (uint256 i_; i_ < 6; ++i_) {
            uint256 got_ = _estimateWithdrawShares(dex_, amt_);
            if (got_ == 0) {
                amt_ = amt_ * 2;
                continue;
            }
            amt_ = (amt_ * targetShares_) / got_;
            if (amt_ == 0) amt_ = 1000;
        }
    }

    /// @dev binary search over token1Amt_ for the wei-exact boundary where simulated shares burned crosses `targetShares_`.
    function _findToken1AmtBoundary(
        FluidDexT1 dex_,
        uint256 targetShares_,
        uint256 initialHi_
    ) internal returns (uint256 passAmt_, uint256 failAmt_) {
        uint256 lo_ = 1000; // comfortably above the DEX's dust-redeem floor, negligible vs. target
        uint256 hi_ = initialHi_;

        while (_estimateWithdrawShares(dex_, hi_) <= targetShares_) {
            hi_ = hi_ * 2;
        }

        while (hi_ - lo_ > 1) {
            uint256 mid_ = (lo_ + hi_) / 2;
            if (_estimateWithdrawShares(dex_, mid_) <= targetShares_) {
                lo_ = mid_;
            } else {
                hi_ = mid_;
            }
        }

        passAmt_ = lo_;
        failAmt_ = hi_;
    }

    // ---------------------------------------------------------------------------------------
    // position opening / priming (T2)
    // ---------------------------------------------------------------------------------------

    function _openT2Position(address user_) internal returns (uint256 nftId_) {
        FluidVaultT2 vault_ = DAI_USDC_VAULT.vaultT2;

        vm.prank(user_);
        (nftId_, ) = vault_.operatePerfect(
            0,
            int256(OPEN_SHARES),
            int256(30_000 * DAI_USDC_VAULT.dex.token0Wei),
            int256(30_000 * DAI_USDC_VAULT.dex.token1Wei),
            0,
            user_
        );
    }

    function _topUpT2(uint256 nftId_, address user_) internal {
        FluidVaultT2 vault_ = DAI_USDC_VAULT.vaultT2;

        vm.prank(user_);
        vault_.operatePerfect(
            nftId_,
            int256(TOPUP_SHARES),
            int256(1000 * DAI_USDC_VAULT.dex.token0Wei),
            int256(1000 * DAI_USDC_VAULT.dex.token1Wei),
            0,
            user_
        );
    }

    /// @dev opens a T2 position, configures a DEX withdrawal limit relative to its supply, then activates + fully expands it.
    function _primeT2(address user_, uint256 baseLimitPercent_) internal returns (uint256 nftId_) {
        FluidDexT1 dex_ = DAI_USDC_VAULT.dex.dexCol;
        FluidVaultT2 vault_ = DAI_USDC_VAULT.vaultT2;

        nftId_ = _openT2Position(user_);

        uint256 s0_ = getUserSupplyShare(dex_, address(vault_));
        _setDexSupplyConfig(dex_, address(vault_), (s0_ * baseLimitPercent_) / 100);

        _topUpT2(nftId_, user_);

        vm.warp(block.timestamp + EXPAND_DURATION + 1);
    }

    // ---------------------------------------------------------------------------------------
    // position opening / priming (T4) - mirrors T2, smart col + zero smart debt
    // ---------------------------------------------------------------------------------------

    function _openT4Position(address user_) internal returns (uint256 nftId_) {
        FluidVaultT4 vault_ = DAI_USDC_VAULT.vaultT4;

        vm.prank(user_);
        (nftId_, ) = vault_.operatePerfect(
            0,
            int256(OPEN_SHARES),
            int256(30_000 * DAI_USDC_VAULT.dex.token0Wei),
            int256(30_000 * DAI_USDC_VAULT.dex.token1Wei),
            0,
            0,
            0,
            user_
        );
    }

    function _topUpT4(uint256 nftId_, address user_) internal {
        FluidVaultT4 vault_ = DAI_USDC_VAULT.vaultT4;

        vm.prank(user_);
        vault_.operatePerfect(
            nftId_,
            int256(TOPUP_SHARES),
            int256(1000 * DAI_USDC_VAULT.dex.token0Wei),
            int256(1000 * DAI_USDC_VAULT.dex.token1Wei),
            0,
            0,
            0,
            user_
        );
    }

    function _primeT4(address user_, uint256 baseLimitPercent_) internal returns (uint256 nftId_) {
        FluidDexT1 dex_ = DAI_USDC_VAULT.dex.dexColDebt;
        FluidVaultT4 vault_ = DAI_USDC_VAULT.vaultT4;

        nftId_ = _openT4Position(user_);

        uint256 s0_ = getUserSupplyShare(dex_, address(vault_));
        _setDexSupplyConfig(dex_, address(vault_), (s0_ * baseLimitPercent_) / 100);

        _topUpT4(nftId_, user_);

        vm.warp(block.timestamp + EXPAND_DURATION + 1);
    }

    // =========================================================================================
    // T2: operatePerfect - amount-aware gap check (exact shares, no estimation needed)
    // =========================================================================================

    function test_operatePerfect_WithdrawalGapBoundary() public {
        FluidDexT1 dex_ = DAI_USDC_VAULT.dex.dexCol;
        FluidVaultT2 vault_ = DAI_USDC_VAULT.vaultT2;

        uint256 nftId_ = _primeT2(alice, 50);

        GapState memory g_ = _readGapState(dex_, address(vault_));
        console2.log("[T2 operatePerfect] S", g_.S);
        console2.log("[T2 operatePerfect] L", g_.L);
        console2.log("[T2 operatePerfect] gap (stored, 1000=100%)", g_.gap);
        console2.log("[T2 operatePerfect] headroom", g_.headroom);

        uint256 snap_ = vm.snapshot();

        vm.prank(alice);
        vault_.operatePerfect(nftId_, -int256(g_.headroom), -int256(1), -int256(1), 0, alice);

        vm.revertTo(snap_);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidVaultErrors.FluidVaultError.selector,
                VaultErrorTypes.Vault__WithdrawMoreThanOperateLimit
            )
        );
        vault_.operatePerfect(nftId_, -int256(g_.headroom + 1), -int256(1), -int256(1), 0, alice);
    }

    // =========================================================================================
    // T2: operate() - amount-based withdraw, non-crossing
    // =========================================================================================

    function test_operate_WithdrawalGapBoundary_NonCrossing() public {
        FluidDexT1 dex_ = DAI_USDC_VAULT.dex.dexCol;
        FluidVaultT2 vault_ = DAI_USDC_VAULT.vaultT2;

        uint256 nftId_ = _primeT2(alice, 50);

        GapState memory g_ = _readGapState(dex_, address(vault_));
        console2.log("[T2 operate] S", g_.S);
        console2.log("[T2 operate] L", g_.L);
        console2.log("[T2 operate] headroom", g_.headroom);

        uint256 initialHi_ = _token1AmtForShares(dex_, g_.headroom) * 2 + 10_000;
        (uint256 passAmt_, uint256 failAmt_) = _findToken1AmtBoundary(dex_, g_.headroom, initialHi_);
        console2.log("[T2 operate] passAmt (token1 wei)", passAmt_);
        console2.log("[T2 operate] failAmt (token1 wei)", failAmt_);

        uint256 snap_ = vm.snapshot();

        vm.prank(alice);
        vault_.operate(nftId_, 0, -int256(passAmt_), -int256(1e30), 0, alice);

        vm.revertTo(snap_);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidVaultErrors.FluidVaultError.selector,
                VaultErrorTypes.Vault__WithdrawMoreThanOperateLimit
            )
        );
        vault_.operate(nftId_, 0, -int256(failAmt_), -int256(1e30), 0, alice);
    }

    // =========================================================================================
    // T2: crossing the DEX base limit mid-withdraw resets the stored limit to 0, skipping `temp3_ > 0` (known gap).
    // =========================================================================================

    function test_operate_CrossingBaseWithdrawalLimitSkipsGapCheck() public {
        FluidDexT1 dex_ = DAI_USDC_VAULT.dex.dexCol;
        FluidVaultT2 vault_ = DAI_USDC_VAULT.vaultT2;

        uint256 nftId_ = _primeT2(alice, 90);

        GapState memory g_ = _readGapState(dex_, address(vault_));
        uint256 crossingShares_ = (g_.S * 12) / 100;

        console2.log("[T2 crossing] S", g_.S);
        console2.log("[T2 crossing] L", g_.L);
        console2.log("[T2 crossing] headroom", g_.headroom);
        console2.log("[T2 crossing] target withdraw shares (12% of S)", crossingShares_);

        assertGt(crossingShares_, g_.headroom, "test setup: crossing withdrawal must exceed gap headroom");

        uint256 snap_ = vm.snapshot();

        // operatePerfect reads storage before the DEX withdraw, so temp3_ is still the real decayed limit.
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidVaultErrors.FluidVaultError.selector,
                VaultErrorTypes.Vault__WithdrawMoreThanOperateLimit
            )
        );
        vault_.operatePerfect(nftId_, -int256(crossingShares_), -int256(1), -int256(1), 0, alice);

        vm.revertTo(snap_);

        uint256 token1Amt_ = _token1AmtForShares(dex_, crossingShares_);

        vm.prank(alice);
        (, int256 supplyAmt_, ) = vault_.operate(nftId_, 0, -int256(token1Amt_), -int256(1e30), 0, alice);

        uint256 burned_ = uint256(-supplyAmt_);
        console2.log("[T2 crossing] actual shares burned via operate()", burned_);

        assertGt(burned_, g_.headroom, "known-gap witness requires burning more than the gap headroom");

        assertEq(
            _storedWithdrawalLimit(_rawUserSupplyData(dex_, address(vault_))),
            0,
            "DEX withdrawal limit must have reset to 0 after crossing the base limit"
        );
    }

    // =========================================================================================
    // T4 equivalents (non-crossing cases only, per task scope)
    // =========================================================================================

    function test_operatePerfect_WithdrawalGapBoundary_T4() public {
        FluidDexT1 dex_ = DAI_USDC_VAULT.dex.dexColDebt;
        FluidVaultT4 vault_ = DAI_USDC_VAULT.vaultT4;

        uint256 nftId_ = _primeT4(alice, 50);

        GapState memory g_ = _readGapState(dex_, address(vault_));
        console2.log("[T4 operatePerfect] S", g_.S);
        console2.log("[T4 operatePerfect] L", g_.L);
        console2.log("[T4 operatePerfect] headroom", g_.headroom);

        uint256 snap_ = vm.snapshot();

        vm.prank(alice);
        vault_.operatePerfect(nftId_, -int256(g_.headroom), -int256(1), -int256(1), 0, 0, 0, alice);

        vm.revertTo(snap_);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidVaultErrors.FluidVaultError.selector,
                VaultErrorTypes.Vault__WithdrawMoreThanOperateLimit
            )
        );
        vault_.operatePerfect(nftId_, -int256(g_.headroom + 1), -int256(1), -int256(1), 0, 0, 0, alice);
    }

    function test_operate_WithdrawalGapBoundary_NonCrossing_T4() public {
        FluidDexT1 dex_ = DAI_USDC_VAULT.dex.dexColDebt;
        FluidVaultT4 vault_ = DAI_USDC_VAULT.vaultT4;

        uint256 nftId_ = _primeT4(alice, 50);

        GapState memory g_ = _readGapState(dex_, address(vault_));
        console2.log("[T4 operate] S", g_.S);
        console2.log("[T4 operate] L", g_.L);
        console2.log("[T4 operate] headroom", g_.headroom);

        uint256 initialHi_ = _token1AmtForShares(dex_, g_.headroom) * 2 + 10_000;
        (uint256 passAmt_, uint256 failAmt_) = _findToken1AmtBoundary(dex_, g_.headroom, initialHi_);
        console2.log("[T4 operate] passAmt (token1 wei)", passAmt_);
        console2.log("[T4 operate] failAmt (token1 wei)", failAmt_);

        uint256 snap_ = vm.snapshot();

        vm.prank(alice);
        vault_.operate(nftId_, 0, -int256(passAmt_), -int256(1e30), 0, 0, 0, alice);

        vm.revertTo(snap_);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidVaultErrors.FluidVaultError.selector,
                VaultErrorTypes.Vault__WithdrawMoreThanOperateLimit
            )
        );
        vault_.operate(nftId_, 0, -int256(failAmt_), -int256(1e30), 0, 0, 0, alice);
    }
}
