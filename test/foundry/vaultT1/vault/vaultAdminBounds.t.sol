//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultT1BaseTest } from "./vault.t.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

/// @notice The T1 admin keeps the collateral factor at or above 3% and below the liquidation threshold, in
/// `updateCollateralFactor` and in `updateCoreSettings` alike.
contract VaultT1AdminBoundsTest is VaultT1BaseTest {
    // inputs are in 1e2 units and stored divided by 10
    uint256 internal constant MIN_COLLATERAL_FACTOR = 300;
    uint256 internal constant MIN_COLLATERAL_FACTOR_STORED = 30;
    uint256 internal constant LIQUIDATION_THRESHOLD = 8100;

    function _vaultAdmin() internal view returns (FluidVaultT1Admin) {
        return FluidVaultT1Admin(address(vaultOne));
    }

    function _expectValueAboveLimit() internal {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultAdmin__ValueAboveLimit));
    }

    /// @dev the collateral factor is the only argument that varies, every other argument is valid
    function _updateCoreSettings(uint256 collateralFactor_) internal {
        vm.prank(alice);
        _vaultAdmin().updateCoreSettings(10000, 10000, collateralFactor_, LIQUIDATION_THRESHOLD, 9000, 500, 0, 0);
    }

    function _storedCollateralFactor() internal view returns (uint256) {
        return (vaultOne.readFromStorage(bytes32(uint256(1))) >> 32) & 0x3ff;
    }

    function test_updateCollateralFactor_RevertIfBelowMinimum() public {
        _expectValueAboveLimit();
        vm.prank(alice);
        _vaultAdmin().updateCollateralFactor(MIN_COLLATERAL_FACTOR - 1);
    }

    function test_updateCollateralFactor_AcceptsMinimum() public {
        vm.prank(alice);
        _vaultAdmin().updateCollateralFactor(MIN_COLLATERAL_FACTOR);

        assertEq(_storedCollateralFactor(), MIN_COLLATERAL_FACTOR_STORED);
    }

    function test_updateCollateralFactor_RevertIfAtLiquidationThreshold() public {
        _expectValueAboveLimit();
        vm.prank(alice);
        _vaultAdmin().updateCollateralFactor(LIQUIDATION_THRESHOLD);
    }

    function test_updateCollateralFactor_AcceptsJustBelowLiquidationThreshold() public {
        vm.prank(alice);
        _vaultAdmin().updateCollateralFactor(LIQUIDATION_THRESHOLD - 10);

        assertEq(_storedCollateralFactor(), (LIQUIDATION_THRESHOLD - 10) / 10);
    }

    function test_updateCoreSettings_RevertIfCollateralFactorBelowMinimum() public {
        _expectValueAboveLimit();
        _updateCoreSettings(MIN_COLLATERAL_FACTOR - 1);
    }

    function test_updateCoreSettings_AcceptsMinimumCollateralFactor() public {
        _updateCoreSettings(MIN_COLLATERAL_FACTOR);

        assertEq(_storedCollateralFactor(), MIN_COLLATERAL_FACTOR_STORED);
    }

    function test_updateCoreSettings_RevertIfCollateralFactorAtLiquidationThreshold() public {
        _expectValueAboveLimit();
        _updateCoreSettings(LIQUIDATION_THRESHOLD);
    }

    function test_updateCoreSettings_AcceptsCollateralFactorJustBelowLiquidationThreshold() public {
        _updateCoreSettings(LIQUIDATION_THRESHOLD - 10);

        assertEq(_storedCollateralFactor(), (LIQUIDATION_THRESHOLD - 10) / 10);
    }
}
