// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { ResolverHelpers } from "../../../../contracts/periphery/resolvers/common/helpers.sol";
import { FluidVaultT1Resolver } from "../../../../contracts/periphery/resolvers/vaultT1/main.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { IFluidOracle } from "../../../../contracts/oracleV2/interfaces/iFluidOracle.sol";
import { FluidProtocolTypes } from "../../../../contracts/libraries/fluidProtocolTypes.sol";

/// @dev Simulates an L2 oracle: guarded getters revert while sequencer grace / downtime checks are active; raw getters succeed.
contract MockSequencerGraceOracle is IFluidOracle {
    uint256 internal constant _OPERATE_RATE = 1_500_000_000_000_000_000_000_000_000;
    uint256 internal constant _LIQUIDATE_RATE = 1_400_000_000_000_000_000_000_000_000;

    bool public guardedShouldRevert;

    error GuardedOracleRevert();

    function setGuardedShouldRevert(bool guardedShouldRevert_) external {
        guardedShouldRevert = guardedShouldRevert_;
    }

    function getExchangeRateOperate() external view returns (uint256 exchangeRate_) {
        if (guardedShouldRevert) revert GuardedOracleRevert();
        return _OPERATE_RATE;
    }

    function getExchangeRateLiquidate() external view returns (uint256 exchangeRate_) {
        if (guardedShouldRevert) revert GuardedOracleRevert();
        return _LIQUIDATE_RATE;
    }

    function getExchangeRate() external view returns (uint256 exchangeRate_) {
        if (guardedShouldRevert) revert GuardedOracleRevert();
        return _OPERATE_RATE;
    }

    function getExchangeRateOperateRaw() external pure returns (uint256 exchangeRate_) {
        return _OPERATE_RATE;
    }

    function getExchangeRateLiquidateRaw() external pure returns (uint256 exchangeRate_) {
        return _LIQUIDATE_RATE;
    }

    function getExchangeRateRaw() external pure returns (uint256 exchangeRate_) {
        return _OPERATE_RATE;
    }

    function infoName() external pure returns (string memory) {
        return "MOCK-L2-GRACE";
    }

    function targetDecimals() external pure returns (uint8) {
        return 27;
    }
}

/// @dev Legacy oracle without working raw getters (falls back to deprecated `getExchangeRate()`).
contract MockLegacyOracle is IFluidOracle {
    uint256 public rate = 2e27;

    function getExchangeRateOperate() external pure returns (uint256) {
        revert("legacy guarded fail");
    }

    function getExchangeRateLiquidate() external pure returns (uint256) {
        revert("legacy guarded fail");
    }

    function getExchangeRate() external view returns (uint256 exchangeRate_) {
        return rate;
    }

    function getExchangeRateOperateRaw() external view returns (uint256) {
        revert("no raw");
    }

    function getExchangeRateLiquidateRaw() external view returns (uint256) {
        revert("no raw");
    }

    function getExchangeRateRaw() external view returns (uint256) {
        revert("no raw");
    }

    function infoName() external pure returns (string memory) {
        return "LEGACY";
    }

    function targetDecimals() external pure returns (uint8) {
        return 27;
    }
}

/// @dev Minimal vault storage for resolver config reads (oracle address in vaultVariables2 bits 96+).
contract MockVaultT1Storage {
    address public linkedOracle;

    function setLinkedOracle(address linkedOracle_) external {
        linkedOracle = linkedOracle_;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256) {
        if (slot_ == bytes32(uint256(1))) {
            return uint256(uint160(linkedOracle)) << 96;
        }
        return 0;
    }
}

contract ResolverHelpersHarness is ResolverHelpers {
    function fetchOraclePrices(address oracle_) external view returns (uint256 operate_, uint256 liquidate_) {
        return _fetchOraclePrices(oracle_);
    }
}

contract FluidVaultT1ResolverHarness is FluidVaultT1Resolver {
    constructor() FluidVaultT1Resolver(address(1), address(2), address(3)) {}

    function vaultConfigOraclePrices(
        address vault_
    ) external view returns (uint256 operate_, uint256 liquidate_, address oracle_) {
        Configs memory configs_ = _getVaultConfig(vault_);
        return (configs_.oraclePriceOperate, configs_.oraclePriceLiquidate, configs_.oracle);
    }
}

contract FluidVaultResolverHarness is FluidVaultResolver {
    constructor() FluidVaultResolver(address(1), address(2)) {}

    function vaultConfigOraclePrices(
        address vault_,
        uint256 vaultType_
    ) external view returns (uint256 operate_, uint256 liquidate_, address oracle_) {
        Configs memory configs_ = _getVaultConfig(vault_, vaultType_);
        return (configs_.oraclePriceOperate, configs_.oraclePriceLiquidate, configs_.oracle);
    }
}

contract ResolverOracleRawTest is Test {
    ResolverHelpersHarness internal harness;
    MockSequencerGraceOracle internal graceOracle;
    MockLegacyOracle internal legacyOracle;

    function setUp() public {
        harness = new ResolverHelpersHarness();
        graceOracle = new MockSequencerGraceOracle();
        legacyOracle = new MockLegacyOracle();
    }

    function test_fetchOraclePrices_usesGuardedWhenHealthy() public {
        graceOracle.setGuardedShouldRevert(false);

        (uint256 operate_, uint256 liquidate_) = harness.fetchOraclePrices(address(graceOracle));
        assertEq(operate_, 1_500_000_000_000_000_000_000_000_000);
        assertEq(liquidate_, 1_400_000_000_000_000_000_000_000_000);
    }

    function test_fetchOraclePrices_gracePeriod_fallsBackToRaw() public {
        graceOracle.setGuardedShouldRevert(true);

        (uint256 operate_, uint256 liquidate_) = harness.fetchOraclePrices(address(graceOracle));
        assertGt(operate_, 0, "operate price via raw fallback");
        assertGt(liquidate_, 0, "liquidate price via raw fallback");
        assertEq(operate_, 1_500_000_000_000_000_000_000_000_000);
        assertEq(liquidate_, 1_400_000_000_000_000_000_000_000_000);
    }

    function test_fetchOraclePrices_sequencerDown_fallsBackToRaw() public {
        graceOracle.setGuardedShouldRevert(true);
        (uint256 operate_, uint256 liquidate_) = harness.fetchOraclePrices(address(graceOracle));
        assertGt(operate_, 0);
        assertGt(liquidate_, 0);
    }

    function test_fetchOraclePrices_legacyOracleFallback() public view {
        (uint256 operate_, uint256 liquidate_) = harness.fetchOraclePrices(address(legacyOracle));
        assertEq(operate_, 2e27);
        assertEq(liquidate_, operate_);
    }

    function test_fetchOraclePrices_zeroOracleReturnsZeros() public view {
        (uint256 operate_, uint256 liquidate_) = harness.fetchOraclePrices(address(0));
        assertEq(operate_, 0);
        assertEq(liquidate_, 0);
    }

    function test_vaultT1Resolver_getVaultConfig_doesNotRevert_duringGracePeriod() public {
        graceOracle.setGuardedShouldRevert(true);

        MockVaultT1Storage vault_ = new MockVaultT1Storage();
        vault_.setLinkedOracle(address(graceOracle));

        FluidVaultT1ResolverHarness resolver_ = new FluidVaultT1ResolverHarness();

        (uint256 operate_, uint256 liquidate_, address oracle_) = resolver_.vaultConfigOraclePrices(address(vault_));
        assertEq(oracle_, address(graceOracle));
        assertGt(operate_, 0, "resolver config must expose operate oracle price during grace");
        assertGt(liquidate_, 0, "resolver config must expose liquidate oracle price during grace");
    }

    function test_vaultT1Resolver_getVaultConfig_doesNotRevert_whileSequencerDown() public {
        graceOracle.setGuardedShouldRevert(true);

        MockVaultT1Storage vault_ = new MockVaultT1Storage();
        vault_.setLinkedOracle(address(graceOracle));

        FluidVaultT1ResolverHarness resolver_ = new FluidVaultT1ResolverHarness();

        (uint256 operate_, uint256 liquidate_, ) = resolver_.vaultConfigOraclePrices(address(vault_));
        assertGt(operate_, 0);
        assertGt(liquidate_, 0);
    }

    function test_vaultResolver_getVaultConfig_doesNotRevert_duringGracePeriod() public {
        graceOracle.setGuardedShouldRevert(true);

        MockVaultT1Storage vault_ = new MockVaultT1Storage();
        vault_.setLinkedOracle(address(graceOracle));

        FluidVaultResolverHarness resolver_ = new FluidVaultResolverHarness();

        (uint256 operate_, uint256 liquidate_, address oracle_) = resolver_.vaultConfigOraclePrices(
            address(vault_),
            FluidProtocolTypes.VAULT_T1_TYPE
        );
        assertEq(oracle_, address(graceOracle));
        assertGt(operate_, 0);
        assertGt(liquidate_, 0);
    }
}
