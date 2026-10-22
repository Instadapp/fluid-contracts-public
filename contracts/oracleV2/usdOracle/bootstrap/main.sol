// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { FluidUsdOracle } from "../main.sol";
import { FluidUsdOracleBootstrapAuth } from "./bootstrapBase.sol";

/// @title FluidUsdOracleBootstrap
/// @notice Temporary first-deploy L1 implementation. Upgrade to `FluidUsdOracle` when setup is done.
/// @dev Exposes `BOOTSTRAP_ADMIN`-gated `multicall` (self-delegatecall) for same-tx token + key wiring.
contract FluidUsdOracleBootstrap is FluidUsdOracle, FluidUsdOracleBootstrapAuth {
    /// @param liquidity_ Liquidity proxy (same as `FluidUsdOracle`).
    /// @param bootstrapAdmin_ Address allowed to configure the oracle and to authorize UUPS upgrades while bootstrapping.
    constructor(
        address liquidity_,
        address bootstrapAdmin_
    ) FluidUsdOracle(liquidity_) FluidUsdOracleBootstrapAuth(bootstrapAdmin_) {}

    function _getGovernanceAddr() internal view override returns (address) {
        return _governanceAddrWithBootstrap(super._getGovernanceAddr());
    }

    function _authorizeUpgrade(address) internal override {
        _authorizeUpgradeWithBootstrap(TEAM_MULTISIG, super._getGovernanceAddr());
    }
}
