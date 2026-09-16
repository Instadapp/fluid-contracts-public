// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

library ErrorTypes {
    uint256 internal constant UsdOracle__AddressZero = 310001;
    uint256 internal constant UsdOracle__Unauthorized = 310002;
    uint256 internal constant UsdOracle__InvalidMultiplier = 310003;
    uint256 internal constant UsdOracle__InvalidSource = 310004;
    uint256 internal constant UsdOracle__NoConfig = 310005;
    uint256 internal constant UsdOracle__InvalidSourceType = 310006;
    uint256 internal constant UsdOracle__RateZero = 310007;
    uint256 internal constant UsdOracle__ChainlinkStale = 310008;
    uint256 internal constant UsdOracle__InvalidParams = 310009;
    uint256 internal constant UsdOracle__RateInvalid = 310010;
    uint256 internal constant UsdOracle__ConfigDoesNotExist = 310011;
    uint256 internal constant UsdOracle__InvalidCapConfig = 310012;
    uint256 internal constant UsdOracle__AltSourceNotConfigured = 310013;
    uint256 internal constant UsdOracle__TokenPaused = 310014;
    uint256 internal constant UsdOracle__KeyNotRegistered = 310015;
    uint256 internal constant UsdOracle__TokenNotListed = 310016;
    uint256 internal constant UsdOracle__SequencerDown = 310017;
    uint256 internal constant UsdOracle__SequencerGracePeriod = 310018;
    uint256 internal constant UsdOracle__MaxDeviation = 310019;
    uint256 internal constant UsdOracle__PriceModeNotAllowed = 310020;
    uint256 internal constant UsdOracle__AdditionalNotAllowedForNonPeg = 310021;
    uint256 internal constant UsdOracle__SourceConfigNotSet = 310022;
    /// @dev `removeAltSourceConfig` / `removeAdditionalAltSourceConfig` while any per-key config for the token still has fallback enabled.
    uint256 internal constant UsdOracle__FallbackMustBeDisabled = 310023;
    /// @dev `removeAltSourceConfig` / `removeAdditionalAltSourceConfig` while any per-key config for the token still has `maxDeviationBPS > 0`.
    uint256 internal constant UsdOracle__DeviationCheckMustBeDisabled = 310024;
    /// @dev self-call-only method called by an external account (e.g. `_getPriceImplNoWrite`).
    uint256 internal constant UsdOracle__OnlySelf = 310025;
    /// @dev source-config removal, or `setTokenType` across the PEG boundary, while a key still has CROSS_PATH.
    uint256 internal constant UsdOracle__CrossPathMustBeDisabled = 310026;
}
