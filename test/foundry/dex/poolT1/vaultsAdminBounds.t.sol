//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { StorageRead } from "../../../../contracts/libraries/storageRead.sol";
import { FluidVaultT2Admin } from "../../../../contracts/protocols/vault/vaultT2/adminModule/main.sol";
import { FluidVaultT3Admin } from "../../../../contracts/protocols/vault/vaultT3/adminModule/main.sol";
import { FluidVaultT4Admin } from "../../../../contracts/protocols/vault/vaultT4/adminModule/main.sol";
import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

import { VaultsBaseTest } from "./vaults.t.sol";

/// @notice Vaults T2, T3 and T4 keep every signed rate within -20% and `X15`, and the collateral factor at or above
/// 3% and below the liquidation threshold, in the dedicated setters and in `updateCoreSettings` alike.
contract VaultsAdminBoundsTest is VaultsBaseTest {
    int256 internal constant MIN_RATE = -2000;
    int256 internal constant MAX_RATE = 0x7fff;
    // a signed rate is stored as (absolute value << 1) | isPositive
    uint256 internal constant MIN_RATE_STORED = 2000 << 1;
    uint256 internal constant MAX_RATE_STORED = (0x7fff << 1) | 1;

    // inputs are in 1e2 units and stored divided by 10
    uint256 internal constant MIN_COLLATERAL_FACTOR = 300;
    uint256 internal constant MIN_COLLATERAL_FACTOR_STORED = 30;
    uint256 internal constant LIQUIDATION_THRESHOLD = 8100;

    int256 internal constant VALID_RATE = 1000;
    uint256 internal constant VALID_COLLATERAL_FACTOR = 8000;

    function _vaultT2() internal view returns (address) {
        return address(DAI_USDC_VAULT.vaultT2);
    }

    function _vaultT3() internal view returns (address) {
        return address(DAI_USDC_VAULT.vaultT3);
    }

    function _vaultT4() internal view returns (address) {
        return address(DAI_USDC_VAULT.vaultT4);
    }

    function _expectValueAboveLimit() internal {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultAdmin__ValueAboveLimit));
    }

    /// @dev the `_updateCoreSettings*` helpers vary only the rates and the collateral factor and keep every other
    /// argument valid, so a revert pins exactly the bound under test
    function _updateCoreSettingsT2(int256 supplyRate_, uint256 collateralFactor_) internal {
        vm.prank(admin);
        FluidVaultT2Admin(_vaultT2()).updateCoreSettings(
            supplyRate_,
            10000,
            collateralFactor_,
            LIQUIDATION_THRESHOLD,
            9000,
            500,
            0,
            0
        );
    }

    function _updateCoreSettingsT3(int256 borrowRate_, uint256 collateralFactor_) internal {
        vm.prank(admin);
        FluidVaultT3Admin(_vaultT3()).updateCoreSettings(
            10000,
            borrowRate_,
            collateralFactor_,
            LIQUIDATION_THRESHOLD,
            9000,
            500,
            0,
            0
        );
    }

    function _updateCoreSettingsT4(int256 supplyRate_, int256 borrowRate_, uint256 collateralFactor_) internal {
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateCoreSettings(
            supplyRate_,
            borrowRate_,
            collateralFactor_,
            LIQUIDATION_THRESHOLD,
            9000,
            500,
            0,
            0
        );
    }

    function _vaultVariables2(address vault_) internal view returns (uint256) {
        return StorageRead(vault_).readFromStorage(bytes32(uint256(1)));
    }

    function _storedSupplyRate(address vault_) internal view returns (uint256) {
        return _vaultVariables2(vault_) & 0xffff;
    }

    function _storedBorrowRate(address vault_) internal view returns (uint256) {
        return (_vaultVariables2(vault_) >> 16) & 0xffff;
    }

    function _storedCollateralFactor(address vault_) internal view returns (uint256) {
        return (_vaultVariables2(vault_) >> 32) & 0x3ff;
    }

    function test_updateSupplyRateT2_RevertIfBelowMinimum() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT2Admin(_vaultT2()).updateSupplyRate(MIN_RATE - 1);
    }

    function test_updateSupplyRateT2_RevertIfAboveMaximum() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT2Admin(_vaultT2()).updateSupplyRate(MAX_RATE + 1);
    }

    function test_updateSupplyRateT2_AcceptsMinimum() public {
        vm.prank(admin);
        FluidVaultT2Admin(_vaultT2()).updateSupplyRate(MIN_RATE);

        assertEq(_storedSupplyRate(_vaultT2()), MIN_RATE_STORED);
    }

    function test_updateSupplyRateT2_AcceptsMaximum() public {
        vm.prank(admin);
        FluidVaultT2Admin(_vaultT2()).updateSupplyRate(MAX_RATE);

        assertEq(_storedSupplyRate(_vaultT2()), MAX_RATE_STORED);
    }

    function test_updateCoreSettingsT2_RevertIfSupplyRateBelowMinimum() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT2(MIN_RATE - 1, VALID_COLLATERAL_FACTOR);
    }

    function test_updateCoreSettingsT2_RevertIfSupplyRateAboveMaximum() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT2(MAX_RATE + 1, VALID_COLLATERAL_FACTOR);
    }

    function test_updateCoreSettingsT2_RevertIfCollateralFactorBelowMinimum() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT2(VALID_RATE, MIN_COLLATERAL_FACTOR - 1);
    }

    function test_updateCoreSettingsT2_RevertIfCollateralFactorAtLiquidationThreshold() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT2(VALID_RATE, LIQUIDATION_THRESHOLD);
    }

    function test_updateCoreSettingsT2_AcceptsMinimumRateAndCollateralFactor() public {
        _updateCoreSettingsT2(MIN_RATE, MIN_COLLATERAL_FACTOR);

        assertEq(_storedSupplyRate(_vaultT2()), MIN_RATE_STORED);
        assertEq(_storedCollateralFactor(_vaultT2()), MIN_COLLATERAL_FACTOR_STORED);
    }

    function test_updateCoreSettingsT2_AcceptsMaximumRate() public {
        _updateCoreSettingsT2(MAX_RATE, VALID_COLLATERAL_FACTOR);

        assertEq(_storedSupplyRate(_vaultT2()), MAX_RATE_STORED);
    }

    function test_updateCollateralFactorT2_RevertIfBelowMinimum() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT2Admin(_vaultT2()).updateCollateralFactor(MIN_COLLATERAL_FACTOR - 1);
    }

    function test_updateCollateralFactorT2_RevertIfAtLiquidationThreshold() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT2Admin(_vaultT2()).updateCollateralFactor(LIQUIDATION_THRESHOLD);
    }

    function test_updateCollateralFactorT2_AcceptsMinimum() public {
        vm.prank(admin);
        FluidVaultT2Admin(_vaultT2()).updateCollateralFactor(MIN_COLLATERAL_FACTOR);

        assertEq(_storedCollateralFactor(_vaultT2()), MIN_COLLATERAL_FACTOR_STORED);
    }

    function test_updateBorrowRateT3_RevertIfBelowMinimum() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT3Admin(_vaultT3()).updateBorrowRate(MIN_RATE - 1);
    }

    function test_updateBorrowRateT3_RevertIfAboveMaximum() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT3Admin(_vaultT3()).updateBorrowRate(MAX_RATE + 1);
    }

    function test_updateBorrowRateT3_AcceptsMinimum() public {
        vm.prank(admin);
        FluidVaultT3Admin(_vaultT3()).updateBorrowRate(MIN_RATE);

        assertEq(_storedBorrowRate(_vaultT3()), MIN_RATE_STORED);
    }

    function test_updateBorrowRateT3_AcceptsMaximum() public {
        vm.prank(admin);
        FluidVaultT3Admin(_vaultT3()).updateBorrowRate(MAX_RATE);

        assertEq(_storedBorrowRate(_vaultT3()), MAX_RATE_STORED);
    }

    function test_updateCoreSettingsT3_RevertIfBorrowRateBelowMinimum() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT3(MIN_RATE - 1, VALID_COLLATERAL_FACTOR);
    }

    function test_updateCoreSettingsT3_RevertIfBorrowRateAboveMaximum() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT3(MAX_RATE + 1, VALID_COLLATERAL_FACTOR);
    }

    function test_updateCoreSettingsT3_RevertIfCollateralFactorBelowMinimum() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT3(VALID_RATE, MIN_COLLATERAL_FACTOR - 1);
    }

    function test_updateCoreSettingsT3_RevertIfCollateralFactorAtLiquidationThreshold() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT3(VALID_RATE, LIQUIDATION_THRESHOLD);
    }

    function test_updateCoreSettingsT3_AcceptsMinimumRateAndCollateralFactor() public {
        _updateCoreSettingsT3(MIN_RATE, MIN_COLLATERAL_FACTOR);

        assertEq(_storedBorrowRate(_vaultT3()), MIN_RATE_STORED);
        assertEq(_storedCollateralFactor(_vaultT3()), MIN_COLLATERAL_FACTOR_STORED);
    }

    function test_updateCoreSettingsT3_AcceptsMaximumRate() public {
        _updateCoreSettingsT3(MAX_RATE, VALID_COLLATERAL_FACTOR);

        assertEq(_storedBorrowRate(_vaultT3()), MAX_RATE_STORED);
    }

    function test_updateCollateralFactorT3_RevertIfBelowMinimum() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT3Admin(_vaultT3()).updateCollateralFactor(MIN_COLLATERAL_FACTOR - 1);
    }

    function test_updateCollateralFactorT3_RevertIfAtLiquidationThreshold() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT3Admin(_vaultT3()).updateCollateralFactor(LIQUIDATION_THRESHOLD);
    }

    function test_updateCollateralFactorT3_AcceptsMinimum() public {
        vm.prank(admin);
        FluidVaultT3Admin(_vaultT3()).updateCollateralFactor(MIN_COLLATERAL_FACTOR);

        assertEq(_storedCollateralFactor(_vaultT3()), MIN_COLLATERAL_FACTOR_STORED);
    }

    function test_updateSupplyRateT4_RevertIfBelowMinimum() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateSupplyRate(MIN_RATE - 1);
    }

    function test_updateSupplyRateT4_RevertIfAboveMaximum() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateSupplyRate(MAX_RATE + 1);
    }

    function test_updateSupplyRateT4_AcceptsMinimum() public {
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateSupplyRate(MIN_RATE);

        assertEq(_storedSupplyRate(_vaultT4()), MIN_RATE_STORED);
    }

    function test_updateSupplyRateT4_AcceptsMaximum() public {
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateSupplyRate(MAX_RATE);

        assertEq(_storedSupplyRate(_vaultT4()), MAX_RATE_STORED);
    }

    function test_updateBorrowRateT4_RevertIfBelowMinimum() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateBorrowRate(MIN_RATE - 1);
    }

    function test_updateBorrowRateT4_RevertIfAboveMaximum() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateBorrowRate(MAX_RATE + 1);
    }

    function test_updateBorrowRateT4_AcceptsMinimum() public {
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateBorrowRate(MIN_RATE);

        assertEq(_storedBorrowRate(_vaultT4()), MIN_RATE_STORED);
    }

    function test_updateBorrowRateT4_AcceptsMaximum() public {
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateBorrowRate(MAX_RATE);

        assertEq(_storedBorrowRate(_vaultT4()), MAX_RATE_STORED);
    }

    function test_updateCoreSettingsT4_RevertIfSupplyRateBelowMinimum() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT4(MIN_RATE - 1, VALID_RATE, VALID_COLLATERAL_FACTOR);
    }

    function test_updateCoreSettingsT4_RevertIfSupplyRateAboveMaximum() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT4(MAX_RATE + 1, VALID_RATE, VALID_COLLATERAL_FACTOR);
    }

    function test_updateCoreSettingsT4_RevertIfBorrowRateBelowMinimum() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT4(VALID_RATE, MIN_RATE - 1, VALID_COLLATERAL_FACTOR);
    }

    function test_updateCoreSettingsT4_RevertIfBorrowRateAboveMaximum() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT4(VALID_RATE, MAX_RATE + 1, VALID_COLLATERAL_FACTOR);
    }

    function test_updateCoreSettingsT4_RevertIfCollateralFactorBelowMinimum() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT4(VALID_RATE, VALID_RATE, MIN_COLLATERAL_FACTOR - 1);
    }

    function test_updateCoreSettingsT4_RevertIfCollateralFactorAtLiquidationThreshold() public {
        _expectValueAboveLimit();
        _updateCoreSettingsT4(VALID_RATE, VALID_RATE, LIQUIDATION_THRESHOLD);
    }

    function test_updateCoreSettingsT4_AcceptsMinimumRatesAndCollateralFactor() public {
        _updateCoreSettingsT4(MIN_RATE, MIN_RATE, MIN_COLLATERAL_FACTOR);

        assertEq(_storedSupplyRate(_vaultT4()), MIN_RATE_STORED);
        assertEq(_storedBorrowRate(_vaultT4()), MIN_RATE_STORED);
        assertEq(_storedCollateralFactor(_vaultT4()), MIN_COLLATERAL_FACTOR_STORED);
    }

    function test_updateCoreSettingsT4_AcceptsMaximumRates() public {
        _updateCoreSettingsT4(MAX_RATE, MAX_RATE, VALID_COLLATERAL_FACTOR);

        assertEq(_storedSupplyRate(_vaultT4()), MAX_RATE_STORED);
        assertEq(_storedBorrowRate(_vaultT4()), MAX_RATE_STORED);
    }

    function test_updateCollateralFactorT4_RevertIfBelowMinimum() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateCollateralFactor(MIN_COLLATERAL_FACTOR - 1);
    }

    function test_updateCollateralFactorT4_RevertIfAtLiquidationThreshold() public {
        _expectValueAboveLimit();
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateCollateralFactor(LIQUIDATION_THRESHOLD);
    }

    function test_updateCollateralFactorT4_AcceptsMinimum() public {
        vm.prank(admin);
        FluidVaultT4Admin(_vaultT4()).updateCollateralFactor(MIN_COLLATERAL_FACTOR);

        assertEq(_storedCollateralFactor(_vaultT4()), MIN_COLLATERAL_FACTOR_STORED);
    }
}
