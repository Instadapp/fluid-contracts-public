// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Structs } from "./structs.sol";

abstract contract Events is Structs {
    // ---- Token-level source config events ----

    event LogSourceConfigSet(address token, SourceConfig source1, SourceConfig source2, SourceConfig source3);

    event LogSourceConfigRemoved(address token);

    event LogAltSourceConfigSet(
        address token,
        SourceConfig altSource1,
        SourceConfig altSource2,
        SourceConfig altSource3
    );

    event LogAltSourceConfigRemoved(address token);

    event LogAdditionalSourceConfigSet(address token, SourceConfig source1, SourceConfig source2, SourceConfig source3);

    event LogAdditionalSourceConfigRemoved(address token);

    event LogAdditionalAltSourceConfigSet(
        address token,
        SourceConfig altSource1,
        SourceConfig altSource2,
        SourceConfig altSource3
    );

    event LogAdditionalAltSourceConfigRemoved(address token);

    // ---- Per-key config events ----

    /// @dev Emitted by `setPriceMode`.
    event LogPriceModeSet(OracleKey key, uint8 priceMode);

    event LogOracleKeyConfigRemoved(OracleKey key);

    event LogSourceCapModeSet(OracleKey key, uint8 sourceCapMode);

    event LogOverallCapSet(OracleKey key, uint8 overallCapMode, uint16 overallCapOperand);

    event LogDeviationCheckEnabled(OracleKey key, uint24 maxDeviationBPS);

    event LogDeviationCheckDisabled(OracleKey key);

    event LogFallbackEnabled(OracleKey key);

    event LogFallbackDisabled(OracleKey key);

    // ---- Token metadata + guardian events ----

    event LogGuardianSet(address guardian, bool allowed);

    event LogTokenPauseSet(address token, bool operatePaused, bool liquidatePaused);

    event LogTokenTypeSet(address token, uint8 tokenType, uint8 decimals);

    event LogTokenConfigGovernanceApproved(address token, bool approved);
}
