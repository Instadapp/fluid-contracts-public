// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { FluidUsdOracleL2 } from "../mainL2.sol";
import { FluidUsdOracleBootstrapAuth } from "./bootstrapBase.sol";

/// @title FluidUsdOracleL2Bootstrap
/// @notice Temporary first-deploy L2 implementation (sequencer feed + bootstrap auth). Upgrade to `FluidUsdOracleL2` when setup is done.
/// @dev Inherits `FluidUsdOracleL2` for sequencer-gated price paths; bootstrap privilege via `FluidUsdOracleBootstrapAuth`
///      (includes `BOOTSTRAP_ADMIN`-gated `multicall` for same-tx token + key wiring).
contract FluidUsdOracleL2Bootstrap is FluidUsdOracleL2, FluidUsdOracleBootstrapAuth {
    /// @param liquidity_ Liquidity proxy.
    /// @param sequencerUptimeFeed_ Chainlink L2 sequencer uptime feed.
    /// @param bootstrapAdmin_ Address allowed to configure and to authorize UUPS upgrades while bootstrapping.
    constructor(
        address liquidity_,
        address sequencerUptimeFeed_,
        address bootstrapAdmin_
    ) FluidUsdOracleL2(liquidity_, sequencerUptimeFeed_) FluidUsdOracleBootstrapAuth(bootstrapAdmin_) {}

    function _getGovernanceAddr() internal view override returns (address) {
        return _governanceAddrWithBootstrap(super._getGovernanceAddr());
    }

    function _authorizeUpgrade(address) internal override {
        _authorizeUpgradeWithBootstrap(TEAM_MULTISIG, super._getGovernanceAddr());
    }
}
