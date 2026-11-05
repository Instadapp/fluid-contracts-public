//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/console2.sol";

import { VaultsBaseTest } from "./vaults.t.sol";
import { FluidDexT1 } from "../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import { Error as FluidVaultError } from "../../../../contracts/protocols/vault/error.sol";
import { ErrorTypes as FluidVaultErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";

/// @notice The non-perfect smart-debt liquidation path must tolerate a dust shares shortfall (paid to the dex >
/// actually liquidatable) up to MAX_LIQUIDATION_SHARES_ROUNDING_DIFF, and still revert beyond it.
contract VaultT3LiquidationSharesToleranceTest is VaultsBaseTest {
    uint256 internal constant TOLERANCE = 1e3; // MAX_LIQUIDATION_SHARES_ROUNDING_DIFF

    function _openLiquidatableT3Position() internal returns (uint256 nftId_) {
        OperateParams memory params_ = OperateParams({
            supplyToken0: 100,
            supplyToken1: 0,
            supplyShareMinMax: 1,
            borrowToken0: 40,
            borrowToken1: 110,
            borrowShareMinMax: 150
        });

        OperateData memory d_ = _testOperate(
            DAI_USDC_VAULT,
            VaultType.VaultT3,
            _convertOperateParamsToWei(DAI_USDC_VAULT, VaultType.VaultT3, params_),
            alice,
            0,
            "liquidatable T3 setup"
        );
        nftId_ = d_.nftId;

        // drop oracle price 20% so the position is liquidatable
        _setOraclePrice(
            DAI_USDC_VAULT,
            VaultType.VaultT3,
            (_getOraclePrice(DAI_USDC_VAULT, VaultType.VaultT3) * 800) / 1000
        );
    }

    /// @dev paying for clearly more debt shares than liquidatable must still revert (only dust is tolerated)
    function test_liquidate_RevertsBeyondRoundingTolerance() public {
        uint256 nftId_ = _openLiquidatableT3Position();

        FluidVaultResolver.LiquidationStruct memory liq_ = getVaultLiquidation(
            payable(address(DAI_USDC_VAULT.vaultT3)),
            0
        );
        bool absorb_ = liq_.inAmtWithAbsorb > liq_.inAmt;
        uint256 liquidatable_ = absorb_ ? liq_.inAmtWithAbsorb : liq_.inAmt;
        assertGt(liquidatable_, 0, "precondition: position is liquidatable");

        VaultDexStateData memory pre_ = _getDexVaultState(DAI_USDC_VAULT, VaultType.VaultT3, alice, nftId_);

        // 1.5x the liquidatable shares, capped below the vault's total dex debt so the dex payback itself succeeds
        uint256 sharesTarget_ = liquidatable_ + liquidatable_ / 2;
        if (sharesTarget_ > (pre_.userDexBorrowShares * 9) / 10) {
            sharesTarget_ = (pre_.userDexBorrowShares * 9) / 10;
        }
        assertGt(sharesTarget_, liquidatable_ + TOLERANCE, "precondition: target is beyond the tolerance band");

        (uint256 token0Debt_, uint256 token1Debt_) = _getDexPaybackPerfectInOneTokenAmount(
            FluidDexT1(payable(_getDexTypeAddressForVault(DAI_USDC_VAULT, VaultType.VaultT3))),
            sharesTarget_,
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                FluidVaultError.FluidVaultError.selector,
                FluidVaultErrorTypes.VaultDex__DebtSharesPaidMoreThanAvailableLiquidation
            )
        );
        vm.prank(alice);
        DAI_USDC_VAULT.vaultT3.liquidate(token0Debt_, token1Debt_, 1, 0, alice, absorb_);
    }

    /// @dev a dust shares shortfall (dex burned wei more shares than the tick walk can credit, e.g. from
    /// exchange-price round-trips or share conversion granularity) must be accepted within the tolerance
    /// and revert beyond it. The dex payback return is mocked to place sharesPaid_ deterministically at
    /// the band edges; the tick walk, settlement and guard all run unmodified. Pre-fix, any positive
    /// shortfall reverted (mutation check: reverting the fix fails the within-band case).
    function test_liquidate_AcceptsDustRoundingShortfallWithinTolerance() public {
        _openLiquidatableT3Position();

        FluidDexT1 dex_ = FluidDexT1(payable(_getDexTypeAddressForVault(DAI_USDC_VAULT, VaultType.VaultT3)));
        FluidVaultResolver.LiquidationStruct memory liq_ = getVaultLiquidation(
            payable(address(DAI_USDC_VAULT.vaultT3)),
            0
        );
        bool absorb_ = liq_.inAmtWithAbsorb > liq_.inAmt;
        // the resolver quote runs the same walk + settlement, so it equals the max creditable amount
        uint256 maxCreditable_ = absorb_ ? liq_.inAmtWithAbsorb : liq_.inAmt;
        assertGt(maxCreditable_, 0, "precondition: position is liquidatable");

        // case 1: sharesPaid_ = max creditable + half the tolerance -> must be accepted, dust stays with the vault
        uint256 snapshot_ = vm.snapshot();
        vm.mockCall(
            address(dex_),
            abi.encodeWithSelector(FluidDexT1.payback.selector),
            abi.encode(maxCreditable_ + TOLERANCE / 2)
        );
        vm.prank(alice);
        (uint256 actualDebtShares_, uint256 actualColShares_) = DAI_USDC_VAULT.vaultT3.liquidate(
            1,
            0,
            1,
            0,
            alice,
            absorb_
        );
        assertEq(actualDebtShares_, maxCreditable_, "walk must credit exactly the max creditable amount");
        assertGt(actualColShares_, 0, "liquidation must have paid out collateral");
        vm.revertTo(snapshot_);

        // case 2: sharesPaid_ = max creditable + tolerance + 1 -> must still revert (only dust is tolerated)
        vm.mockCall(
            address(dex_),
            abi.encodeWithSelector(FluidDexT1.payback.selector),
            abi.encode(maxCreditable_ + TOLERANCE + 1)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidVaultError.FluidVaultError.selector,
                FluidVaultErrorTypes.VaultDex__DebtSharesPaidMoreThanAvailableLiquidation
            )
        );
        vm.prank(alice);
        DAI_USDC_VAULT.vaultT3.liquidate(1, 0, 1, 0, alice, absorb_);
    }
}

/// @notice T4 liquidation must tolerate dust shares shortfall within MAX_LIQUIDATION_SHARES_ROUNDING_DIFF.
contract VaultT4LiquidationSharesToleranceTest is VaultsBaseTest {
    uint256 internal constant TOLERANCE = 1e3; // MAX_LIQUIDATION_SHARES_ROUNDING_DIFF

    function _openLiquidatableT4Position() internal returns (uint256 nftId_) {
        OperateParams memory params_ = OperateParams({
            supplyToken0: 50,
            supplyToken1: 150,
            supplyShareMinMax: 1,
            borrowToken0: 50,
            borrowToken1: 100,
            borrowShareMinMax: 150
        });

        OperateData memory d_ = _testOperate(
            DAI_USDC_VAULT,
            VaultType.VaultT4,
            _convertOperateParamsToWei(DAI_USDC_VAULT, VaultType.VaultT4, params_),
            alice,
            0,
            "liquidatable T4 setup"
        );
        nftId_ = d_.nftId;

        _setOraclePrice(
            DAI_USDC_VAULT,
            VaultType.VaultT4,
            (_getOraclePrice(DAI_USDC_VAULT, VaultType.VaultT4) * 800) / 1000
        );
    }

    function test_liquidate_RevertsBeyondRoundingTolerance() public {
        uint256 nftId_ = _openLiquidatableT4Position();

        FluidVaultResolver.LiquidationStruct memory liq_ = getVaultLiquidation(
            payable(address(DAI_USDC_VAULT.vaultT4)),
            0
        );
        bool absorb_ = liq_.inAmtWithAbsorb > liq_.inAmt;
        uint256 liquidatable_ = absorb_ ? liq_.inAmtWithAbsorb : liq_.inAmt;
        assertGt(liquidatable_, 0, "precondition: position is liquidatable");

        VaultDexStateData memory pre_ = _getDexVaultState(DAI_USDC_VAULT, VaultType.VaultT4, alice, nftId_);

        uint256 sharesTarget_ = liquidatable_ + liquidatable_ / 2;
        if (sharesTarget_ > (pre_.userDexBorrowShares * 9) / 10) {
            sharesTarget_ = (pre_.userDexBorrowShares * 9) / 10;
        }
        assertGt(sharesTarget_, liquidatable_ + TOLERANCE, "precondition: target is beyond the tolerance band");

        (uint256 token0Debt_, uint256 token1Debt_) = _getDexPaybackPerfectInOneTokenAmount(
            FluidDexT1(payable(_getDexTypeAddressForVault(DAI_USDC_VAULT, VaultType.VaultT4))),
            sharesTarget_,
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                FluidVaultError.FluidVaultError.selector,
                FluidVaultErrorTypes.VaultDex__DebtSharesPaidMoreThanAvailableLiquidation
            )
        );
        vm.prank(alice);
        DAI_USDC_VAULT.vaultT4.liquidate(token0Debt_, token1Debt_, 1, 0, 1, 1, alice, absorb_);
    }

    function test_liquidate_AcceptsDustRoundingShortfallWithinTolerance() public {
        _openLiquidatableT4Position();

        FluidDexT1 dex_ = FluidDexT1(payable(_getDexTypeAddressForVault(DAI_USDC_VAULT, VaultType.VaultT4)));
        FluidVaultResolver.LiquidationStruct memory liq_ = getVaultLiquidation(
            payable(address(DAI_USDC_VAULT.vaultT4)),
            0
        );
        bool absorb_ = liq_.inAmtWithAbsorb > liq_.inAmt;
        uint256 maxCreditable_ = absorb_ ? liq_.inAmtWithAbsorb : liq_.inAmt;
        assertGt(maxCreditable_, 0, "precondition: position is liquidatable");

        uint256 snapshot_ = vm.snapshot();
        vm.mockCall(
            address(dex_),
            abi.encodeWithSelector(FluidDexT1.payback.selector),
            abi.encode(maxCreditable_ + TOLERANCE / 2)
        );
        vm.prank(alice);
        (uint256 actualDebtShares_, uint256 actualColShares_, , ) = DAI_USDC_VAULT.vaultT4.liquidate(
            1,
            0,
            1,
            0,
            1,
            1,
            alice,
            absorb_
        );
        assertEq(actualDebtShares_, maxCreditable_, "walk must credit exactly the max creditable amount");
        assertGt(actualColShares_, 0, "liquidation must have paid out collateral");
        vm.revertTo(snapshot_);

        vm.mockCall(
            address(dex_),
            abi.encodeWithSelector(FluidDexT1.payback.selector),
            abi.encode(maxCreditable_ + TOLERANCE + 1)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidVaultError.FluidVaultError.selector,
                FluidVaultErrorTypes.VaultDex__DebtSharesPaidMoreThanAvailableLiquidation
            )
        );
        vm.prank(alice);
        DAI_USDC_VAULT.vaultT4.liquidate(1, 0, 1, 0, 1, 1, alice, absorb_);
    }
}
