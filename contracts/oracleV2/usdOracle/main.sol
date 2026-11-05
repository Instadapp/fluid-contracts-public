// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IUSDOracle } from "../interfaces/iUSDOracle.sol";
import { IFluidCappedRate } from "../interfaces/iFluidCappedRate.sol";
import { IFluidOracleWithDebt } from "../interfaces/iFluidOracleWithDebt.sol";
import { IChainlinkAggregatorV3 } from "../interfaces/external/IChainlinkAggregatorV3.sol";

import { Variables } from "./variables.sol";
import { Error } from "./error.sol";
import { ErrorTypes } from "./errorTypes.sol";
import { Events } from "./events.sol";
import { ChainlinkSourceReader } from "./sourceReaders/chainlinkSourceReader.sol";
import { FluidSourceReader } from "./sourceReaders/fluidSourceReader.sol";
import { TokenSymbolResolver } from "../common/tokenSymbolResolver.sol";

interface IReadFromStorage {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}

// ==================== Core ====================

abstract contract FluidUsdOracleCore is Variables, Error {
    /// @dev validates that an address is not the zero address
    modifier validAddress(address value_) {
        _checkValidAddress(value_);
        _;
    }

    function _checkValidAddress(address value_) internal pure {
        if (value_ == address(0)) {
            _revert(ErrorTypes.UsdOracle__AddressZero);
        }
    }

    /// @dev Computes the storage key for a config lookup.
    function _keyHash(
        address token_,
        uint256 eMode_,
        uint256 isOperate_,
        uint256 isCollateral_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(token_, eMode_, isOperate_, isCollateral_));
    }

    /// @dev SOURCE_CHAINLINK and SOURCE_REDSTONE both use AggregatorV3-compatible feeds.
    function _isChainlinkStyleSourceType(uint8 sourceType_) internal pure returns (bool) {
        return sourceType_ == SOURCE_CHAINLINK || sourceType_ == SOURCE_REDSTONE;
    }

    /// @dev Returns true if `configsMap[token_]` contains at least one row with `eMode == eMode_`.
    function _tokenHasEmodeInConfigsMap(address token_, uint256 eMode_) internal view returns (bool) {
        ConfigMap[] storage maps_ = configsMap[token_];
        uint256 len_ = maps_.length;
        for (uint256 i = 0; i < len_; ++i) {
            if (uint256(maps_[i].eMode) == eMode_) {
                return true;
            }
        }
        return false;
    }

    /// @dev True for STABLE tokens in PEG mode, which resolve to a constant $1 and skip the price tree.
    function _isStablePeg(uint8 tokenType_, uint8 priceMode_) internal pure returns (bool) {
        return tokenType_ == TOKEN_TYPE_STABLE && priceMode_ == PRICE_MODE_PEG;
    }

    /// @dev True for the two cross-path overall cap modes, which price against a second source leg.
    function _isCrossPath(uint8 overallCapMode_) internal pure returns (bool) {
        return overallCapMode_ == OVERALL_CAP_MIN_CROSS_PATH || overallCapMode_ == OVERALL_CAP_MAX_CROSS_PATH;
    }

    /// @dev Reverts if any listed key for `token_` still uses fallback, deviation, or CROSS_PATH.
    function _revertIfTokenKeysBlockAltRemoval(address token_) internal view {
        ConfigMap[] storage maps_ = configsMap[token_];
        uint256 len_ = maps_.length;
        for (uint256 i = 0; i < len_; ++i) {
            ConfigMap memory cm_ = maps_[i];
            bytes32 keyHash_ = _keyHash(token_, uint256(cm_.eMode), cm_.isOperate ? 1 : 0, cm_.isCollateral ? 1 : 0);
            OracleKeyConfig memory keyCfg_ = _configs[keyHash_];
            if (keyCfg_.priceMode == PRICE_MODE_NOT_SET) {
                continue;
            }
            if (keyCfg_.flagsBitmap & KEY_FLAG_FALLBACK != 0) {
                _revert(ErrorTypes.UsdOracle__FallbackMustBeDisabled);
            }
            if (keyCfg_.maxDeviationBPS > 0) {
                _revert(ErrorTypes.UsdOracle__DeviationCheckMustBeDisabled);
            }
            if (_isCrossPath(keyCfg_.overallCapMode)) {
                _revert(ErrorTypes.UsdOracle__CrossPathMustBeDisabled);
            }
        }
    }
}

// ==================== Authorization ====================

/// @dev All access control: governance resolution, modifiers, transient storage session,
///      guardian management, and token pause logic.
abstract contract FluidUsdOracleAuthorization is FluidUsdOracleCore, Events {
    /// @dev Validates that an address is governance (at Liquidity)
    modifier onlyGovernance() {
        _checkAuth(false);
        _;
    }

    /// @dev Validates that an address is either governance (at Liquidity) or TEAM_MULTISIG
    modifier onlyGovernanceOrMultisig() {
        _checkAuth(true);
        _;
    }

    /// @dev Ensures a key has been registered in transient storage for this transaction.
    modifier onlyWithTransientOracleKey() {
        _checkOnlyWithTransientOracleKey();
        _;
    }

    /// @dev Allows governance always. Allows multisig only if _tIsNewConfig == 1.
    modifier onlyGovernanceOrMSNewConfig() {
        _checkAuth(_tIsNewConfig == 1);
        _;
    }

    /// @dev Ensures a config exists for the registered key (priceMode is set).
    modifier onlyForExistingConfig() {
        _checkOnlyForExistingConfig();
        _;
    }

    /// @dev Governance always; TEAM_MULTISIG only when `allowMultisig_`.
    function _checkAuth(bool allowMultisig_) internal view {
        if (msg.sender == _getGovernanceAddr()) {
            return;
        }
        if (allowMultisig_ && msg.sender == TEAM_MULTISIG) {
            return;
        }
        _revert(ErrorTypes.UsdOracle__Unauthorized);
    }

    /// @dev TEAM_MULTISIG and not also governance (needed for when TEAM_MULTISIG == governance).
    function _isTeamMultisig() internal view returns (bool) {
        return msg.sender == TEAM_MULTISIG && msg.sender != _getGovernanceAddr();
    }

    /// @dev Reverts if `registerTransientOracleKey` was not called in this tx.
    function _checkOnlyWithTransientOracleKey() internal view {
        if (_tToken == address(0)) {
            _revert(ErrorTypes.UsdOracle__KeyNotRegistered);
        }
    }

    /// @dev Reverts if no priceMode is set for the registered key.
    function _checkOnlyForExistingConfig() internal view {
        if (!_registeredConfigExists()) {
            _revert(ErrorTypes.UsdOracle__ConfigDoesNotExist);
        }
    }

    /// @notice Registers an `OracleKey` in transient storage for subsequent admin calls within the same transaction.
    /// @dev Must be called before any other per-key admin method. Calling again overwrites and resets the new-config flag.
    ///      Reverts if the token has not been listed via `setTokenType`.
    /// @param key_ Token, eMode, operate/collateral tuple identifying the per-key config being edited.
    function registerTransientOracleKey(OracleKey memory key_) external onlyGovernanceOrMultisig {
        if (key_.token == address(0)) {
            _revert(ErrorTypes.UsdOracle__AddressZero);
        }
        if (key_.isOperate > 1 || key_.isCollateral > 1) {
            _revert(ErrorTypes.UsdOracle__InvalidParams);
        }
        if (_tokenSources[key_.token].primarySrc.tokenType == TOKEN_TYPE_NOT_SET) {
            _revert(ErrorTypes.UsdOracle__TokenNotListed);
        }

        _tToken = key_.token;
        _tEMode = key_.eMode;
        _tIsOperate = key_.isOperate;
        _tIsCollateral = key_.isCollateral;
        _tIsNewConfig = 0;
    }

    /// @notice Sets or removes a guardian address for operate-side pause toggles.
    /// @dev Only governance may call. Guardians cannot change liquidate pause state.
    /// @param guardian_ Address to grant or revoke guardian role.
    /// @param allowed_ True to enable, false to disable.
    function setGuardian(address guardian_, bool allowed_) external onlyGovernance validAddress(guardian_) {
        _guardians[guardian_] = allowed_ ? 1 : 0;
        emit LogGuardianSet(guardian_, allowed_);
    }

    /// @notice Lists a token and assigns its type (PEG, STABLE, VOLATILE).
    /// @dev Governance may change the type of an already-listed token. Multisig may only list a token that is
    ///      not yet listed (`TOKEN_TYPE_NOT_SET`); post-listing type changes are governance-only.
    ///      Crossing the PEG type boundary reverts while any key still reads a second leg (fallback,
    ///      deviation check, or CROSS_PATH): which bucket that leg lives in is type-dependent.
    ///      Fetches and stores ERC20 `decimals` (18 for `NATIVE_TOKEN_ADDRESS`). Writes `_tokenSources[token_].primarySrc` metadata fields only.
    /// @param token_ ERC20 or native sentinel address to list.
    /// @param tokenType_ One of `TOKEN_TYPE_PEG`, `TOKEN_TYPE_STABLE`, or `TOKEN_TYPE_VOLATILE`.
    function setTokenType(address token_, uint8 tokenType_) external onlyGovernanceOrMultisig validAddress(token_) {
        if (tokenType_ == TOKEN_TYPE_NOT_SET || tokenType_ > TOKEN_TYPE_VOLATILE) {
            _revert(ErrorTypes.UsdOracle__InvalidParams);
        }

        TokenSourceConfig storage cfg_ = _tokenSources[token_];
        if (_isTeamMultisig() && cfg_.primarySrc.tokenType != TOKEN_TYPE_NOT_SET) {
            _revert(ErrorTypes.UsdOracle__Unauthorized);
        }

        // PEG reads its second leg from `_additionalTokenSources`, STABLE / VOLATILE from `altSrc`, so only
        // a change across that boundary re-points live keys. STABLE <-> VOLATILE resolves identically.
        uint8 previousType_ = cfg_.primarySrc.tokenType;
        bool crossesPegBoundary_ = (previousType_ == TOKEN_TYPE_PEG) != (tokenType_ == TOKEN_TYPE_PEG);
        if (previousType_ != TOKEN_TYPE_NOT_SET && crossesPegBoundary_) {
            _revertIfTokenKeysBlockAltRemoval(token_);
        }

        uint8 decimals_;
        if (token_ == NATIVE_TOKEN_ADDRESS) {
            decimals_ = 18;
        } else {
            decimals_ = IERC20Metadata(token_).decimals();
        }

        cfg_.primarySrc.tokenType = tokenType_;
        cfg_.primarySrc.decimals = decimals_;
        emit LogTokenTypeSet(token_, tokenType_, decimals_);
    }

    /// @notice Sets per-token pause bits for pricing: operate (bit 0) and/or liquidate (bit 1).
    /// @dev Guardians may toggle operate pause only; governance or multisig may set any combination.
    /// @param token_ Token whose pause state is updated.
    /// @param pauseOperate_ When true, sets `PAUSED_OPERATE` on the token metadata.
    /// @param pauseLiquidate_ When true, sets `PAUSED_LIQUIDATE` on the token metadata.
    function setPausedState(address token_, bool pauseOperate_, bool pauseLiquidate_) external validAddress(token_) {
        bool isGovernanceOrMultisig_ = msg.sender == _getGovernanceAddr() || msg.sender == TEAM_MULTISIG;
        if (!isGovernanceOrMultisig_ && _guardians[msg.sender] != 1) {
            _revert(ErrorTypes.UsdOracle__Unauthorized);
        }

        TokenSourceConfig storage cfg_ = _tokenSources[token_];

        if (!isGovernanceOrMultisig_) {
            bool isLiquidatePaused_ = cfg_.primarySrc.pauseState & PAUSED_LIQUIDATE != 0;
            if (pauseLiquidate_ != isLiquidatePaused_) {
                _revert(ErrorTypes.UsdOracle__Unauthorized);
            }
        }

        uint8 newState_ = (pauseOperate_ ? PAUSED_OPERATE : 0) | (pauseLiquidate_ ? PAUSED_LIQUIDATE : 0);
        cfg_.primarySrc.pauseState = newState_;
        emit LogTokenPauseSet(token_, pauseOperate_, pauseLiquidate_);
    }

    /// @notice Sets or clears the governance-approved flag on token-level oracle sources (`FLAG_GOVERNANCE_APPROVED`).
    /// @dev Only governance may call. Used to stamp multisig-created token-level configs or revoke approval.
    /// @param token_ Token whose approval bit is updated.
    /// @param approved_ True to set the flag, false to clear it.
    function setTokenConfigGovernanceApproved(
        address token_,
        bool approved_
    ) external onlyGovernance validAddress(token_) {
        _setTokenGovernanceApproved(token_, _tokenSources[token_], approved_);
    }

    // --- Internal methods ---

    /// @dev `approved_ == true` sets `FLAG_GOVERNANCE_APPROVED`; `false` clears it (e.g. multisig token-level source write).
    function _setTokenGovernanceApproved(address token_, TokenSourceConfig storage cfg_, bool approved_) internal {
        if (approved_) {
            cfg_.primarySrc.flagsBitmap |= FLAG_GOVERNANCE_APPROVED;
        } else {
            cfg_.primarySrc.flagsBitmap &= ~FLAG_GOVERNANCE_APPROVED;
        }
        emit LogTokenConfigGovernanceApproved(token_, approved_);
    }

    /// @dev gets the governance address at Liquidity.
    function _getGovernanceAddr() internal view virtual returns (address governance_) {
        governance_ = address(uint160(IReadFromStorage(LIQUIDITY).readFromStorage(LIQUIDITY_GOVERNANCE_SLOT)));
    }

    /// @dev Loads the registered OracleKey from transient storage.
    function _getRegisteredKey() internal view returns (OracleKey memory key_) {
        key_.token = _tToken;
        key_.eMode = _tEMode;
        key_.isOperate = uint8(_tIsOperate);
        key_.isCollateral = uint8(_tIsCollateral);
    }

    /// @dev Clears the transient admin session for the current transaction.
    function _clearRegisteredKey() internal {
        _tToken = address(0);
        _tEMode = 0;
        _tIsOperate = 0;
        _tIsCollateral = 0;
        _tIsNewConfig = 0;
    }

    /// @dev Returns storage pointer to the OracleKeyConfig for the registered key.
    function _getRegisteredConfig() internal view returns (OracleKeyConfig storage) {
        return _configs[_keyHash(_tToken, _tEMode, _tIsOperate, _tIsCollateral)];
    }

    /// @dev Governance may always create or modify. TEAM_MULTISIG may only create new configs
    ///      (exact slot empty) on tokens that are not yet governance-approved.
    function _revertIfTeamMultisigModifiesExistingConfig(bool exists_) internal view {
        if (exists_ && _isTeamMultisig()) {
            _revert(ErrorTypes.UsdOracle__Unauthorized);
        }
    }

    /// @dev Per-key create/modify gate for `setPriceMode`. Same create-only rule as the bool overload,
    ///      plus: TEAM_MULTISIG creating eMode≠0 is treated as modifying existing live config when that
    ///      leg already has eMode 0 and the token is `FLAG_GOVERNANCE_APPROVED` (would shadow fallback).
    function _revertIfTeamMultisigModifiesExistingConfig(
        bool exists_,
        OracleKey memory key_,
        TokenSourceConfig storage tokenCfg_
    ) internal view {
        if (!_isTeamMultisig()) {
            return;
        }
        if (exists_) {
            _revert(ErrorTypes.UsdOracle__Unauthorized);
        }
        if (
            key_.eMode == 0 ||
            tokenCfg_.primarySrc.flagsBitmap & FLAG_GOVERNANCE_APPROVED == 0 ||
            _configs[_keyHash(key_.token, 0, key_.isOperate, key_.isCollateral)].priceMode == PRICE_MODE_NOT_SET
        ) {
            return;
        }
        _revert(ErrorTypes.UsdOracle__Unauthorized);
    }

    /// @dev Checks if a configuration exists for the registered key (priceMode is set).
    function _registeredConfigExists() internal view returns (bool) {
        return _getRegisteredConfig().priceMode != PRICE_MODE_NOT_SET;
    }
}

// ==================== Upgradeable ====================

abstract contract FluidUsdOracleUpgradeable is FluidUsdOracleAuthorization, UUPSUpgradeable {
    /// @dev Restricts UUPS implementation upgrades to governance (`onlyGovernance`).
    function _authorizeUpgrade(address) internal virtual override onlyGovernance {}
}

// ==================== Token Source Configs ====================

/// @dev Token-level source configuration: primary/alt sources in _tokenSources and _additionalTokenSources.
///      Source feeds are configured per-token and validated once here (Chainlink latestRoundData, capped-rate
///      getRate, etc.). All per-key configs that reference this token+mode inherit the validated sources
///      automatically — no feed re-specification or re-validation needed when adding new keys.
///      These methods do NOT use the transient admin session (no registerTransientOracleKey needed).
abstract contract FluidUsdOracleTokenSourceConfigs is FluidUsdOracleUpgradeable {
    // ---- Primary Source Config (in _tokenSources) ----
    // For VOLATILE/STABLE this is market price; for PEG this is peg price.

    /// @notice Sets primary (up to three leg) source configuration for a listed token.
    /// @dev Does not use the transient oracle key session. TEAM_MULTISIG may only create a new primary config, not overwrite.
    ///      Blocked entirely once the token is governance-approved.
    /// @param token_ Listed token address.
    /// @param src1_ Required first source chain leg.
    /// @param src2_ Optional second leg; use `SOURCE_NOT_SET` / zero address to omit.
    /// @param src3_ Optional third leg; must be unset if `src2_` is unset.
    function setSourceConfig(
        address token_,
        SourceConfig memory src1_,
        SourceConfig memory src2_,
        SourceConfig memory src3_
    ) external onlyGovernanceOrMultisig validAddress(token_) {
        TokenSourceConfig storage cfg_ = _tokenSources[token_];
        _revertIfTeamMultisigModifiesExistingConfig(
            cfg_.primarySrc.sourceType1 != SOURCE_NOT_SET || cfg_.primarySrc.flagsBitmap & FLAG_GOVERNANCE_APPROVED != 0
        );
        if (cfg_.primarySrc.tokenType == TOKEN_TYPE_NOT_SET) {
            _revert(ErrorTypes.UsdOracle__TokenNotListed);
        }

        _validateThreeSourceConfig(src1_, src2_, src3_);
        _writeSources(cfg_.primarySrc, src1_, src2_, src3_);
        _setTokenGovernanceApproved(token_, cfg_, !_isTeamMultisig());

        emit LogSourceConfigSet(token_, src1_, src2_, src3_);
    }

    /// @notice Removes primary source configuration for a token.
    /// @dev If alt sources exist, calls `removeAltSourceConfig` first. Only governance.
    /// @param token_ Token whose primary sources are cleared.
    function removeSourceConfig(address token_) external onlyGovernance validAddress(token_) {
        TokenSourceConfig storage cfg_ = _tokenSources[token_];
        if (cfg_.primarySrc.sourceType1 == SOURCE_NOT_SET) {
            _revert(ErrorTypes.UsdOracle__SourceConfigNotSet);
        }

        // primary removal breaks every key; guard fallback/deviation keys like alt removal does
        _revertIfTokenKeysBlockAltRemoval(token_);

        if (cfg_.primarySrc.flagsBitmap & FLAG_HAS_ALT_SOURCE != 0) {
            removeAltSourceConfig(token_);
        }

        _clearSources(cfg_.primarySrc);
        _setTokenGovernanceApproved(token_, cfg_, true);
        emit LogSourceConfigRemoved(token_);
    }

    // ---- Alt Source Config (in _tokenSources, slots 4-6) ----

    /// @notice Sets alt (fallback / deviation second-leg) source configuration for a token.
    /// @dev Requires primary sources. TEAM_MULTISIG may only create a new alt config, not overwrite.
    ///      Blocked entirely once the token is governance-approved.
    /// @param token_ Listed token address.
    /// @param alt1_ First alt leg (required if configuring alt).
    /// @param alt2_ Optional second alt leg.
    /// @param alt3_ Optional third alt leg.
    function setAltSourceConfig(
        address token_,
        SourceConfig memory alt1_,
        SourceConfig memory alt2_,
        SourceConfig memory alt3_
    ) external onlyGovernanceOrMultisig validAddress(token_) {
        TokenSourceConfig storage cfg_ = _tokenSources[token_];
        _revertIfTeamMultisigModifiesExistingConfig(
            cfg_.primarySrc.flagsBitmap & (FLAG_HAS_ALT_SOURCE | FLAG_GOVERNANCE_APPROVED) != 0
        );
        if (cfg_.primarySrc.sourceType1 == SOURCE_NOT_SET) {
            _revert(ErrorTypes.UsdOracle__SourceConfigNotSet);
        }

        _validateThreeSourceConfig(alt1_, alt2_, alt3_);
        _writeSources(cfg_.altSrc, alt1_, alt2_, alt3_);
        cfg_.primarySrc.flagsBitmap = cfg_.primarySrc.flagsBitmap | FLAG_HAS_ALT_SOURCE;
        _setTokenGovernanceApproved(token_, cfg_, !_isTeamMultisig());

        emit LogAltSourceConfigSet(token_, alt1_, alt2_, alt3_);
    }

    /// @notice Removes alt source configuration and clears `FLAG_HAS_ALT_SOURCE`.
    /// @dev Reverts if any key for `token_` still has fallback enabled or deviation check (`maxDeviationBPS > 0`).
    ///      Only governance.
    /// @param token_ Token whose alt sources are cleared.
    function removeAltSourceConfig(address token_) public onlyGovernance validAddress(token_) {
        TokenSourceConfig storage cfg_ = _tokenSources[token_];
        if (cfg_.primarySrc.flagsBitmap & FLAG_HAS_ALT_SOURCE == 0) {
            _revert(ErrorTypes.UsdOracle__AltSourceNotConfigured);
        }

        _revertIfTokenKeysBlockAltRemoval(token_);
        _clearSources(cfg_.altSrc);
        cfg_.primarySrc.flagsBitmap = cfg_.primarySrc.flagsBitmap & ~FLAG_HAS_ALT_SOURCE;
        _setTokenGovernanceApproved(token_, cfg_, true);
        emit LogAltSourceConfigRemoved(token_);
    }

    // ---- Additional Source Config (in _additionalTokenSources) ----
    // Only for PEG tokens. Stores market price sources (secondary price type for PEG).

    /// @notice Sets additional market-price sources for a PEG token (`_additionalTokenSources.primarySrc`).
    /// @dev TEAM_MULTISIG may only create a new additional config, not overwrite. Only valid for `TOKEN_TYPE_PEG`.
    ///      Blocked entirely once the token is governance-approved.
    /// @param token_ PEG token address.
    /// @param src1_ First market source leg.
    /// @param src2_ Optional second leg.
    /// @param src3_ Optional third leg.
    function setAdditionalSourceConfig(
        address token_,
        SourceConfig memory src1_,
        SourceConfig memory src2_,
        SourceConfig memory src3_
    ) external onlyGovernanceOrMultisig validAddress(token_) {
        TokenSourceConfig storage mainCfg_ = _tokenSources[token_];
        _revertIfTeamMultisigModifiesExistingConfig(
            mainCfg_.primarySrc.flagsBitmap & (FLAG_HAS_ADDITIONAL_SOURCES | FLAG_GOVERNANCE_APPROVED) != 0
        );
        if (mainCfg_.primarySrc.tokenType != TOKEN_TYPE_PEG) {
            _revert(ErrorTypes.UsdOracle__AdditionalNotAllowedForNonPeg);
        }

        _validateThreeSourceConfig(src1_, src2_, src3_);
        _writeSources(_additionalTokenSources[token_].primarySrc, src1_, src2_, src3_);
        mainCfg_.primarySrc.flagsBitmap = mainCfg_.primarySrc.flagsBitmap | FLAG_HAS_ADDITIONAL_SOURCES;
        _setTokenGovernanceApproved(token_, mainCfg_, !_isTeamMultisig());

        emit LogAdditionalSourceConfigSet(token_, src1_, src2_, src3_);
    }

    /// @notice Removes additional (market) primary sources for a PEG token.
    /// @dev If additional alt sources exist, removes them first. Only governance.
    /// @param token_ PEG token address.
    function removeAdditionalSourceConfig(address token_) external onlyGovernance validAddress(token_) {
        TokenSourceConfig storage mainCfg_ = _tokenSources[token_];
        if (mainCfg_.primarySrc.flagsBitmap & FLAG_HAS_ADDITIONAL_SOURCES == 0) {
            _revert(ErrorTypes.UsdOracle__SourceConfigNotSet);
        }

        // additional sources back the PEG deviation/cross-path leg; guard fallback/deviation keys like alt removal does
        _revertIfTokenKeysBlockAltRemoval(token_);

        if (mainCfg_.primarySrc.flagsBitmap & FLAG_HAS_ADDITIONAL_ALT_SOURCES != 0) {
            removeAdditionalAltSourceConfig(token_);
        }

        _clearSources(_additionalTokenSources[token_].primarySrc);
        mainCfg_.primarySrc.flagsBitmap = mainCfg_.primarySrc.flagsBitmap & ~FLAG_HAS_ADDITIONAL_SOURCES;
        _setTokenGovernanceApproved(token_, mainCfg_, true);
        emit LogAdditionalSourceConfigRemoved(token_);
    }

    // ---- Additional Alt Source Config (in _additionalTokenSources, slots 4-6) ----

    /// @notice Sets alt sources for the additional (market) mapping on a PEG token.
    /// @dev Requires `setAdditionalSourceConfig` to exist. TEAM_MULTISIG may only create, not overwrite.
    ///      Blocked entirely once the token is governance-approved.
    /// @param token_ PEG token address.
    /// @param alt1_ First additional-alt leg.
    /// @param alt2_ Optional second leg.
    /// @param alt3_ Optional third leg.
    function setAdditionalAltSourceConfig(
        address token_,
        SourceConfig memory alt1_,
        SourceConfig memory alt2_,
        SourceConfig memory alt3_
    ) external onlyGovernanceOrMultisig validAddress(token_) {
        TokenSourceConfig storage mainCfg_ = _tokenSources[token_];
        _revertIfTeamMultisigModifiesExistingConfig(
            mainCfg_.primarySrc.flagsBitmap & (FLAG_HAS_ADDITIONAL_ALT_SOURCES | FLAG_GOVERNANCE_APPROVED) != 0
        );
        if (mainCfg_.primarySrc.flagsBitmap & FLAG_HAS_ADDITIONAL_SOURCES == 0) {
            _revert(ErrorTypes.UsdOracle__SourceConfigNotSet);
        }

        _validateThreeSourceConfig(alt1_, alt2_, alt3_);
        _writeSources(_additionalTokenSources[token_].altSrc, alt1_, alt2_, alt3_);
        mainCfg_.primarySrc.flagsBitmap = mainCfg_.primarySrc.flagsBitmap | FLAG_HAS_ADDITIONAL_ALT_SOURCES;
        _setTokenGovernanceApproved(token_, mainCfg_, !_isTeamMultisig());

        emit LogAdditionalAltSourceConfigSet(token_, alt1_, alt2_, alt3_);
    }

    /// @notice Removes additional alt sources and clears `FLAG_HAS_ADDITIONAL_ALT_SOURCES`.
    /// @dev Same key-level constraints as `removeAltSourceConfig`. Only governance.
    /// @param token_ PEG token address.
    function removeAdditionalAltSourceConfig(address token_) public onlyGovernance validAddress(token_) {
        TokenSourceConfig storage mainCfg_ = _tokenSources[token_];
        if (mainCfg_.primarySrc.flagsBitmap & FLAG_HAS_ADDITIONAL_ALT_SOURCES == 0) {
            _revert(ErrorTypes.UsdOracle__AltSourceNotConfigured);
        }

        _revertIfTokenKeysBlockAltRemoval(token_);
        _clearSources(_additionalTokenSources[token_].altSrc);
        mainCfg_.primarySrc.flagsBitmap = mainCfg_.primarySrc.flagsBitmap & ~FLAG_HAS_ADDITIONAL_ALT_SOURCES;
        _setTokenGovernanceApproved(token_, mainCfg_, true);
        emit LogAdditionalAltSourceConfigRemoved(token_);
    }

    // --- Internal methods ---

    /// @dev Verifies that the source chain is contiguous and each configured source is valid.
    function _validateThreeSourceConfig(
        SourceConfig memory sourceCfg1_,
        SourceConfig memory sourceCfg2_,
        SourceConfig memory sourceCfg3_
    ) internal {
        _verifySourceConfig(sourceCfg1_.sourceType, sourceCfg1_.source);

        if (sourceCfg3_.sourceType != SOURCE_NOT_SET && sourceCfg2_.sourceType == SOURCE_NOT_SET) {
            _revert(ErrorTypes.UsdOracle__InvalidSource);
        }

        _validateOptionalSourceConfig(sourceCfg2_);
        _validateOptionalSourceConfig(sourceCfg3_);
    }

    /// @dev Validates an optional 2nd/3rd source leg; no-op when `SOURCE_NOT_SET`.
    function _validateOptionalSourceConfig(SourceConfig memory sourceCfg_) internal {
        if (sourceCfg_.sourceType == SOURCE_NOT_SET) {
            if (sourceCfg_.source != address(0)) {
                _revert(ErrorTypes.UsdOracle__InvalidSource);
            }
            return;
        }
        _verifySourceConfig(sourceCfg_.sourceType, sourceCfg_.source);
    }

    /// @dev Verifies that the source configuration is valid for the given source type and address.
    function _verifySourceConfig(uint8 sourceType_, address source_) internal {
        if (sourceType_ != SOURCE_STABLE && source_ == address(0)) {
            _revert(ErrorTypes.UsdOracle__AddressZero);
        }

        if (sourceType_ == SOURCE_CAPPED_RATE) {
            if (!_isCappedRate(source_)) {
                _revert(ErrorTypes.UsdOracle__InvalidSource);
            }
            return;
        }

        if (sourceType_ == SOURCE_FLUID_ORACLE) {
            if (!_isFluidOracleWithDebt(source_)) {
                _revert(ErrorTypes.UsdOracle__InvalidSource);
            }
            return;
        }

        if (_isChainlinkStyleSourceType(sourceType_)) {
            if (!_isChainlinkFeed(source_)) {
                _revert(ErrorTypes.UsdOracle__InvalidSource);
            }
            return;
        }

        if (sourceType_ == SOURCE_STABLE) {
            if (source_ != address(0)) {
                _revert(ErrorTypes.UsdOracle__InvalidSource);
            }
            return;
        }

        _revert(ErrorTypes.UsdOracle__InvalidSource);
    }

    /// @dev Checks if the provided address is a valid Chainlink feed by calling latestRoundData.
    function _isChainlinkFeed(address contract_) internal view returns (bool) {
        try IChainlinkAggregatorV3(contract_).latestRoundData() returns (
            uint80 roundId,
            int256,
            uint256,
            uint256,
            uint80
        ) {
            if (roundId > 0) {
                return true;
            }
        } catch {}
        return false;
    }

    /// @dev Checks if the provided address implements the FluidCappedRate interface with required methods.
    function _isCappedRate(address contract_) internal returns (bool) {
        try IFluidCappedRate(contract_).centerPrice() returns (uint256 value) {
            if (value == 0) {
                return false;
            }
        } catch {
            return false;
        }
        return _isFluidOracleWithDebt(contract_);
    }

    /// @dev Checks if the address implements Fluid oracle + debt getters (e.g. CLX). No `centerPrice()` required.
    function _isFluidOracleWithDebt(address contract_) internal view returns (bool) {
        try IFluidOracleWithDebt(contract_).getExchangeRateOperate() returns (uint256 value) {
            if (value == 0) {
                return false;
            }
        } catch {
            return false;
        }
        try IFluidOracleWithDebt(contract_).getExchangeRateOperateDebt() returns (uint256 value) {
            if (value == 0) {
                return false;
            }
        } catch {
            return false;
        }
        return true;
    }

    /// @dev Writes a 3-source chain into a TokenSources bucket.
    function _writeSources(
        TokenSources storage bucket_,
        SourceConfig memory src1_,
        SourceConfig memory src2_,
        SourceConfig memory src3_
    ) internal {
        bucket_.source1 = src1_.source;
        bucket_.multiplier1 = _deriveMultiplier(src1_.sourceType, src1_.source);
        bucket_.sourceType1 = src1_.sourceType;
        bucket_.sourceType2 = src2_.sourceType;
        bucket_.sourceType3 = src3_.sourceType;
        bucket_.capOperand1 = src1_.capOperand;
        bucket_.source2 = src2_.source;
        bucket_.multiplier2 = _deriveMultiplier(src2_.sourceType, src2_.source);
        bucket_.capOperand2 = src2_.capOperand;
        bucket_.source3 = src3_.source;
        bucket_.multiplier3 = _deriveMultiplier(src3_.sourceType, src3_.source);
        bucket_.capOperand3 = src3_.capOperand;
    }

    /// @dev Derives and validates source multiplier; return is stored for read-path gas efficiency.
    function _deriveMultiplier(uint8 sourceType_, address source_) internal view returns (int8 multiplier_) {
        if (
            sourceType_ == SOURCE_NOT_SET ||
            sourceType_ == SOURCE_CAPPED_RATE ||
            sourceType_ == SOURCE_FLUID_ORACLE ||
            sourceType_ == SOURCE_STABLE
        ) {
            return 0;
        }
        if (_isChainlinkStyleSourceType(sourceType_)) {
            uint8 feedDecimals_;
            try IChainlinkAggregatorV3(source_).decimals() returns (uint8 d_) {
                feedDecimals_ = d_;
            } catch {
                _revert(ErrorTypes.UsdOracle__InvalidSource);
            }
            int256 derived_ = int256(uint256(27)) - int256(uint256(feedDecimals_));
            if (derived_ > MAX_MULTIPLIER || derived_ < MIN_MULTIPLIER) {
                _revert(ErrorTypes.UsdOracle__InvalidMultiplier);
            }
            return int8(derived_);
        }
        _revert(ErrorTypes.UsdOracle__InvalidSourceType);
    }

    /// @dev Clears a 3-source chain from a TokenSources bucket.
    function _clearSources(TokenSources storage bucket_) internal {
        bucket_.source1 = address(0);
        bucket_.multiplier1 = 0;
        bucket_.sourceType1 = SOURCE_NOT_SET;
        bucket_.sourceType2 = SOURCE_NOT_SET;
        bucket_.sourceType3 = SOURCE_NOT_SET;
        bucket_.capOperand1 = 0;
        bucket_.source2 = address(0);
        bucket_.multiplier2 = 0;
        bucket_.capOperand2 = 0;
        bucket_.source3 = address(0);
        bucket_.multiplier3 = 0;
        bucket_.capOperand3 = 0;
    }
}

// ==================== Key Configs ====================

/// @dev Per-key configuration: priceMode assignment, source cap mode, overall cap, deviation check, and fallback management.
///      Each key only stores a priceMode reference (which token-level source mapping to use) plus
///      key-specific parameters — source feeds are never specified here, they are inherited from the
///      token-level config. Uses the transient admin session (registerTransientOracleKey must be called first)
///      so the key tuple is confirmed once and reused across all subsequent admin calls in the tx.
abstract contract FluidUsdOracleKeyConfigs is FluidUsdOracleTokenSourceConfigs {
    /// @notice Sets `PRICE_MODE_PEG` or `PRICE_MODE_MARKET` for the oracle key registered in this transaction.
    /// @dev Requires `registerTransientOracleKey`. Multisig may only create new keys; governance may update.
    ///      Validates token type vs required token-level sources. STABLE + PEG is rejected when the key
    ///      already has CROSS_PATH (`$1` skips overall cap, which would leave a dead depeg floor).
    ///      When creating: TEAM_MULTISIG cannot add eMode≠0 for a leg that already has eMode 0 if the token
    ///      is governance-approved (would shadow live eMode-0 fallback). Unapproved tokens remain MS-onboardable.
    /// @param priceMode_ `PRICE_MODE_MARKET` or `PRICE_MODE_PEG`.
    function setPriceMode(uint8 priceMode_) external onlyWithTransientOracleKey onlyGovernanceOrMultisig {
        bool exists_ = _registeredConfigExists();
        OracleKey memory key_ = _getRegisteredKey();

        TokenSourceConfig storage mainCfg_ = _tokenSources[key_.token];
        uint8 tokenType_ = mainCfg_.primarySrc.tokenType;
        if (tokenType_ == TOKEN_TYPE_NOT_SET) {
            _revert(ErrorTypes.UsdOracle__TokenNotListed);
        }

        _revertIfTeamMultisigModifiesExistingConfig(exists_, key_, mainCfg_);

        if (priceMode_ == PRICE_MODE_PEG) {
            // PEG mode: allowed for PEG tokens (needs sources) and STABLE tokens (constant $1, no sources).
            // VOLATILE tokens cannot use PEG mode.
            if (tokenType_ == TOKEN_TYPE_VOLATILE) {
                _revert(ErrorTypes.UsdOracle__PriceModeNotAllowed);
            }
            if (tokenType_ == TOKEN_TYPE_PEG && mainCfg_.primarySrc.sourceType1 == SOURCE_NOT_SET) {
                _revert(ErrorTypes.UsdOracle__SourceConfigNotSet);
            }
        } else if (priceMode_ == PRICE_MODE_MARKET) {
            if (tokenType_ == TOKEN_TYPE_PEG) {
                uint8 flags_ = mainCfg_.primarySrc.flagsBitmap;
                if (flags_ & FLAG_HAS_ADDITIONAL_SOURCES == 0) {
                    _revert(ErrorTypes.UsdOracle__SourceConfigNotSet);
                }
            } else if (mainCfg_.primarySrc.sourceType1 == SOURCE_NOT_SET) {
                _revert(ErrorTypes.UsdOracle__SourceConfigNotSet);
            }
        } else {
            _revert(ErrorTypes.UsdOracle__InvalidParams);
        }

        bytes32 keyHash_ = _keyHash(key_.token, key_.eMode, key_.isOperate, key_.isCollateral);
        if (exists_ && _isStablePeg(tokenType_, priceMode_)) {
            if (_isCrossPath(_configs[keyHash_].overallCapMode)) {
                _revert(ErrorTypes.UsdOracle__InvalidCapConfig);
            }
        }
        _configs[keyHash_].priceMode = priceMode_;

        if (!exists_) {
            configsMap[key_.token].push(
                ConfigMap({
                    eMode: uint240(key_.eMode),
                    isOperate: key_.isOperate != 0,
                    isCollateral: key_.isCollateral != 0
                })
            );
            if (_isTeamMultisig()) {
                _tIsNewConfig = 1;
            }
        }

        emit LogPriceModeSet(key_, priceMode_);
    }

    /// @notice Deletes the per-key config for the transiently registered oracle key and removes it from `configsMap`.
    /// @dev Only governance. Clears transient session after removal.
    function removeConfig() external onlyGovernance onlyWithTransientOracleKey onlyForExistingConfig {
        OracleKey memory key_ = _getRegisteredKey();

        delete _configs[_keyHash(key_.token, key_.eMode, key_.isOperate, key_.isCollateral)];

        ConfigMap[] storage arr_ = configsMap[key_.token];
        for (uint i = 0; i < arr_.length; i++) {
            if (
                arr_[i].eMode == key_.eMode &&
                arr_[i].isOperate == (key_.isOperate != 0) &&
                arr_[i].isCollateral == (key_.isCollateral != 0)
            ) {
                arr_[i] = arr_[arr_.length - 1];
                arr_.pop();
                break;
            }
        }

        emit LogOracleKeyConfigRemoved(key_);
        _clearRegisteredKey();
    }

    /// @notice Sets per-leg capping direction for the registered key (`SOURCE_CAP_MIN`, `SOURCE_CAP_MAX`, or `SOURCE_CAP_NONE`).
    /// @dev `SOURCE_CAP_MIN` only for collateral keys; `SOURCE_CAP_MAX` only for debt keys. Cap operands live on token sources.
    /// @param sourceCapMode_ Cap mode enum value.
    function setSourceCapMode(
        uint8 sourceCapMode_
    ) external onlyWithTransientOracleKey onlyGovernanceOrMSNewConfig onlyForExistingConfig {
        if (sourceCapMode_ > SOURCE_CAP_MAX) {
            _revert(ErrorTypes.UsdOracle__InvalidCapConfig);
        }
        if (sourceCapMode_ == SOURCE_CAP_MIN) {
            if (_tIsCollateral != 1) {
                _revert(ErrorTypes.UsdOracle__InvalidCapConfig);
            }
        } else if (sourceCapMode_ == SOURCE_CAP_MAX) {
            if (_tIsCollateral != 0) {
                _revert(ErrorTypes.UsdOracle__InvalidCapConfig);
            }
        }
        _getRegisteredConfig().sourceCapMode = sourceCapMode_;
        emit LogSourceCapModeSet(_getRegisteredKey(), sourceCapMode_);
    }

    /// @dev Reverts unless `_tToken` has a primary source on `_tokenSources` plus the reference source the
    ///      second leg is read from: `_additionalTokenSources.primarySrc` for PEG (see
    ///      `_getPegResolvedPrice`), `_tokenSources.altSrc` otherwise. Deviation checks and cross-path
    ///      overall caps both compare against that same source.
    function _revertIfReferenceSourceMissing() internal view {
        TokenSources storage primarySrc_ = _tokenSources[_tToken].primarySrc;
        if (primarySrc_.sourceType1 == SOURCE_NOT_SET) {
            _revert(ErrorTypes.UsdOracle__SourceConfigNotSet);
        }
        uint8 flags_ = primarySrc_.flagsBitmap;
        if (primarySrc_.tokenType == TOKEN_TYPE_PEG) {
            if (flags_ & FLAG_HAS_ADDITIONAL_SOURCES == 0) {
                _revert(ErrorTypes.UsdOracle__SourceConfigNotSet);
            }
        } else if (flags_ & FLAG_HAS_ALT_SOURCE == 0) {
            _revert(ErrorTypes.UsdOracle__AltSourceNotConfigured);
        }
    }

    /// @notice Sets overall cap mode and operand for the registered key (cross-path or operand clamp).
    /// @dev MIN modes require collateral keys; MAX modes require debt keys. Cross-path operand must be 0.
    ///      PEG CROSS_PATH requires `_tokenSources.primarySrc` and additional (same as deviation). VOLATILE/STABLE
    ///      MARKET require alt. STABLE PEG is rejected. `setPriceMode(PEG)` on STABLE and `setTokenType` cannot
    ///      leave a live CROSS_PATH key on an incompatible mode or type.
    ///      Operand modes scale `overallCapOperand_` by `CAP_PRECISION` (2-decimal operand → ORACLE_PRECISION).
    /// @param overallCapMode_ One of `OVERALL_CAP_*` constants.
    /// @param overallCapOperand_ 2-decimal operand for operand modes; must be 0 for `OVERALL_CAP_NONE` and cross-path modes.
    function setOverallCap(
        uint8 overallCapMode_,
        uint16 overallCapOperand_
    ) external onlyWithTransientOracleKey onlyGovernanceOrMSNewConfig onlyForExistingConfig {
        if (overallCapMode_ > OVERALL_CAP_MAX_OPERAND) {
            _revert(ErrorTypes.UsdOracle__InvalidCapConfig);
        }

        if (overallCapMode_ == OVERALL_CAP_NONE) {
            if (overallCapOperand_ != 0) {
                _revert(ErrorTypes.UsdOracle__InvalidCapConfig);
            }
        } else {
            if (overallCapMode_ == OVERALL_CAP_MIN_CROSS_PATH || overallCapMode_ == OVERALL_CAP_MIN_OPERAND) {
                if (_tIsCollateral != 1) {
                    _revert(ErrorTypes.UsdOracle__InvalidCapConfig);
                }
            } else {
                if (_tIsCollateral != 0) {
                    _revert(ErrorTypes.UsdOracle__InvalidCapConfig);
                }
            }

            if (overallCapMode_ <= OVERALL_CAP_MAX_CROSS_PATH) {
                if (overallCapOperand_ != 0) {
                    _revert(ErrorTypes.UsdOracle__InvalidCapConfig);
                }
                // STABLE PEG returns a constant $1 that never reaches the overall cap, so it has no second leg.
                if (_isStablePeg(_tokenSources[_tToken].primarySrc.tokenType, _getRegisteredConfig().priceMode)) {
                    _revert(ErrorTypes.UsdOracle__InvalidCapConfig);
                }
                _revertIfReferenceSourceMissing();
            } else {
                // Operand modes: operand must be > 0
                if (overallCapOperand_ == 0) {
                    _revert(ErrorTypes.UsdOracle__InvalidCapConfig);
                }
            }
        }

        OracleKeyConfig storage cfg_ = _getRegisteredConfig();
        cfg_.overallCapMode = overallCapMode_;
        cfg_.overallCapOperand = overallCapOperand_;
        emit LogOverallCapSet(_getRegisteredKey(), overallCapMode_, overallCapOperand_);
    }

    /// @notice Enables operate-only max deviation between primary and reference leg (PEG: peg vs market; else primary vs alt).
    /// @dev Requires the appropriate second-leg sources to exist. Can be combined with fallback.
    /// @param maxDeviationBPS_ Max deviation in basis points; must satisfy `0 < maxDeviationBPS_ <= BPS_DENOMINATOR`.
    function enableDeviationCheck(
        uint24 maxDeviationBPS_
    ) external onlyWithTransientOracleKey onlyGovernanceOrMSNewConfig onlyForExistingConfig {
        if (maxDeviationBPS_ == 0 || maxDeviationBPS_ > BPS_DENOMINATOR) {
            _revert(ErrorTypes.UsdOracle__InvalidParams);
        }

        _revertIfReferenceSourceMissing();

        _getRegisteredConfig().maxDeviationBPS = maxDeviationBPS_;

        OracleKey memory key_ = _getRegisteredKey();
        emit LogDeviationCheckEnabled(key_, maxDeviationBPS_);
    }

    /// @notice Disables deviation check for the registered key (`maxDeviationBPS = 0`).
    /// @dev Only governance.
    function disableDeviationCheck() external onlyWithTransientOracleKey onlyGovernance onlyForExistingConfig {
        _getRegisteredConfig().maxDeviationBPS = 0;
        OracleKey memory key_ = _getRegisteredKey();
        emit LogDeviationCheckDisabled(key_);
    }

    /// @notice Enables fallback to the alt chain for the mapping this key uses (primary vs additional for PEG market mode).
    /// @dev Requires the corresponding alt sources flag. Can be combined with deviation check.
    function enableFallback() external onlyWithTransientOracleKey onlyGovernanceOrMSNewConfig onlyForExistingConfig {
        OracleKeyConfig storage cfg_ = _getRegisteredConfig();
        TokenSourceConfig storage mainCfg_ = _tokenSources[_tToken];
        uint8 tokenType_ = mainCfg_.primarySrc.tokenType;
        uint8 flags_ = mainCfg_.primarySrc.flagsBitmap;

        // Fallback uses the alt chain on whichever mapping this key reads from. For PEG tokens in MARKET
        // mode, price (and thus fallback) is resolved from `_additionalTokenSources`, so we require
        // `_additionalTokenSources.altSrc` (`FLAG_HAS_ADDITIONAL_ALT_SOURCES`). For all other cases the
        // key uses `_tokenSources` only, so we require `_tokenSources.altSrc` (`FLAG_HAS_ALT_SOURCE`).
        if (tokenType_ == TOKEN_TYPE_PEG && cfg_.priceMode == PRICE_MODE_MARKET) {
            if (flags_ & FLAG_HAS_ADDITIONAL_ALT_SOURCES == 0) {
                _revert(ErrorTypes.UsdOracle__AltSourceNotConfigured);
            }
        } else {
            if (flags_ & FLAG_HAS_ALT_SOURCE == 0) {
                _revert(ErrorTypes.UsdOracle__AltSourceNotConfigured);
            }
        }

        cfg_.flagsBitmap = cfg_.flagsBitmap | KEY_FLAG_FALLBACK;
        OracleKey memory key_ = _getRegisteredKey();
        emit LogFallbackEnabled(key_);
    }

    /// @notice Disables fallback for the registered key (clears `KEY_FLAG_FALLBACK`).
    /// @dev Only governance.
    function disableFallback() external onlyWithTransientOracleKey onlyGovernance onlyForExistingConfig {
        OracleKeyConfig storage cfg_ = _getRegisteredConfig();
        cfg_.flagsBitmap = cfg_.flagsBitmap & ~KEY_FLAG_FALLBACK;
        OracleKey memory key_ = _getRegisteredKey();
        emit LogFallbackDisabled(key_);
    }
}

// ==================== Source Read ====================

/// @dev Implements source reads with a `doRevert_` flag: true = revert on failure, false = return 0.
abstract contract FluidUsdOracleSourceRead is FluidUsdOracleCore, ChainlinkSourceReader, FluidSourceReader {
    /// @dev Applies source multiplier so every leg is normalized to ORACLE_PRECISION.
    function _applyMultiplier(uint256 rate_, int8 multiplier_) internal pure returns (uint256) {
        if (multiplier_ > 0) {
            return rate_ * uint256(10 ** uint8(multiplier_));
        }
        if (multiplier_ < 0) {
            unchecked {
                return rate_ / uint256(10 ** uint8(-multiplier_));
            }
        }
        return rate_;
    }

    /// @dev Applies the leg multiplier, then zero-checks per `doRevert_` (division can round small rates to 0).
    function _normalizeRate(uint256 rate_, int8 multiplier_, bool doRevert_) internal pure returns (uint256) {
        rate_ = _applyMultiplier(rate_, multiplier_);
        if (rate_ == 0) {
            if (!doRevert_) return 0;
            _revert(ErrorTypes.UsdOracle__RateZero);
        }
        return rate_;
    }

    /// @dev Applies a per-leg cap: returns min(rate, cap) or max(rate, cap) depending on capDirection_.
    ///      capOperand_ is in 2-decimal precision (100 = 1.00 = 1e27 in ORACLE_PRECISION).
    function _applyLegCap(uint256 rate_, uint16 capOperand_, uint8 capDirection_) internal pure returns (uint256) {
        // keep a 0 (failed/stale leg) as the failure sentinel; else SOURCE_CAP_MAX would floor it and mask the failure
        if (rate_ == 0) return 0;
        if (capOperand_ == 0) return rate_;
        uint256 capValue_;
        unchecked {
            capValue_ = uint256(capOperand_) * CAP_PRECISION;
        }
        if (capDirection_ == SOURCE_CAP_MIN) {
            return rate_ < capValue_ ? rate_ : capValue_;
        }
        // SOURCE_CAP_MAX
        return rate_ > capValue_ ? rate_ : capValue_;
    }

    /// @dev Applies overall cap to the final price.
    ///      Cross-path modes use refPrice_ (PEG: other mapping primary; else altSrc).
    ///      Operand modes compare against overallCapOperand * 1e25.
    ///      refPrice_ is ignored for non-cross-path modes.
    function _applyOverallCap(
        uint256 price_,
        uint256 refPrice_,
        OracleKeyConfig memory keyConfig_
    ) internal pure returns (uint256) {
        uint8 mode_ = keyConfig_.overallCapMode;
        if (mode_ == OVERALL_CAP_NONE) {
            return price_;
        }
        if (mode_ == OVERALL_CAP_MIN_CROSS_PATH) {
            return price_ < refPrice_ ? price_ : refPrice_;
        }
        if (mode_ == OVERALL_CAP_MAX_CROSS_PATH) {
            return price_ > refPrice_ ? price_ : refPrice_;
        }
        uint256 capValue_;
        unchecked {
            capValue_ = uint256(keyConfig_.overallCapOperand) * CAP_PRECISION;
        }
        if (mode_ == OVERALL_CAP_MIN_OPERAND) {
            return price_ < capValue_ ? price_ : capValue_;
        }
        // OVERALL_CAP_MAX_OPERAND
        return price_ > capValue_ ? price_ : capValue_;
    }

    /// @dev Reads a single configured source and returns its normalized 1e27 rate.
    ///      When doRevert_ is true, reverts on failure. When false, returns 0 instead.
    function _readSource(
        uint8 sourceType_,
        address source_,
        int8 multiplier_,
        bool isOperate_,
        bool isCollateral_,
        bool doRevert_
    ) internal view returns (uint256 rate_) {
        if (sourceType_ == SOURCE_CAPPED_RATE || sourceType_ == SOURCE_FLUID_ORACLE) {
            rate_ = _readFluidSource(source_, isOperate_, isCollateral_);
        } else if (_isChainlinkStyleSourceType(sourceType_)) {
            rate_ = _readChainlink(source_, isOperate_, doRevert_);
        } else if (sourceType_ == SOURCE_STABLE) {
            rate_ = ORACLE_PRECISION;
        } else {
            if (!doRevert_) return 0;
            _revert(ErrorTypes.UsdOracle__InvalidSourceType);
        }

        rate_ = _normalizeRate(rate_, multiplier_, doRevert_);
    }

    function _readSourceMaybeWrite(
        uint8 sourceType_,
        address source_,
        int8 multiplier_,
        PriceReadContext memory ctx_,
        bool doRevert_
    ) internal returns (uint256 rate_) {
        if (ctx_.isWrite && (sourceType_ == SOURCE_CAPPED_RATE || sourceType_ == SOURCE_FLUID_ORACLE)) {
            return
                _normalizeRate(
                    _readFluidSourceWrite(source_, ctx_.isOperate, ctx_.isCollateral),
                    multiplier_,
                    doRevert_
                );
        }
        return _readSource(sourceType_, source_, multiplier_, ctx_.isOperate, ctx_.isCollateral, doRevert_);
    }

    /// @dev Reads a single source in "raw" mode for getPriceRawForMode. Returns 0 on any failure (never reverts).
    ///      Capped rate / Fluid oracle sources use the uncapped `getExchangeRate()` getter instead of the directional getExchangeRate* methods,
    ///      returning the unfiltered price without operate/liquidate/collateral/debt distinction.
    ///      Chainlink sources use the liquidate (more lenient) staleness timespan since getPriceRawForMode
    ///      has no isOperate parameter. Returns 0 on stale data instead of reverting.
    function _readSourceRaw(
        uint8 sourceType_,
        address source_,
        int8 multiplier_
    ) internal view returns (uint256 rate_) {
        if (sourceType_ == SOURCE_CAPPED_RATE || sourceType_ == SOURCE_FLUID_ORACLE) {
            rate_ = _readFluidSourceRaw(source_);
        } else if (_isChainlinkStyleSourceType(sourceType_)) {
            rate_ = _readChainlinkRaw(source_);
        } else if (sourceType_ == SOURCE_STABLE) {
            rate_ = ORACLE_PRECISION;
        } else {
            return 0;
        }

        if (rate_ != 0) {
            rate_ = _applyMultiplier(rate_, multiplier_);
        }
    }

    /// @dev Reads up to 3 sources from a `TokenSources` bucket (non-reverting), returning configs, rates, and composed price.
    function _readSourcesWithRates(
        TokenSources storage bucket_,
        bool isOperate_,
        bool isCollateral_
    ) internal view returns (SourcesWithRates memory result_) {
        result_.source1 = SourceConfig(bucket_.sourceType1, bucket_.source1, bucket_.capOperand1);
        result_.source2 = SourceConfig(bucket_.sourceType2, bucket_.source2, bucket_.capOperand2);
        result_.source3 = SourceConfig(bucket_.sourceType3, bucket_.source3, bucket_.capOperand3);

        result_.rate1 = _readSource(
            bucket_.sourceType1,
            bucket_.source1,
            bucket_.multiplier1,
            isOperate_,
            isCollateral_,
            false
        );
        result_.price = result_.rate1;

        if (bucket_.sourceType2 != SOURCE_NOT_SET) {
            result_.rate2 = _readSource(
                bucket_.sourceType2,
                bucket_.source2,
                bucket_.multiplier2,
                isOperate_,
                isCollateral_,
                false
            );
            result_.price = (result_.price * result_.rate2) / ORACLE_PRECISION;
        }
        if (bucket_.sourceType3 != SOURCE_NOT_SET) {
            result_.rate3 = _readSource(
                bucket_.sourceType3,
                bucket_.source3,
                bucket_.multiplier3,
                isOperate_,
                isCollateral_,
                false
            );
            result_.price = (result_.price * result_.rate3) / ORACLE_PRECISION;
        }
    }

    /// @dev Computes a composed price from a `TokenSources` bucket.
    ///      Loads slot 2 / 3 only if the prior source type indicates they are configured.
    ///      When capDirection_ != SOURCE_CAP_NONE, applies per-leg capping using each leg's capOperand.
    ///      When doRevert_ is true, reverts on any source failure or zero price. When false, returns 0 instead.
    function _readComposedPrice(
        TokenSources storage bucket_,
        PriceReadContext memory ctx_,
        bool doRevert_,
        uint8 capDirection_
    ) internal returns (uint256 price_) {
        uint8 sourceType2_ = bucket_.sourceType2;
        uint8 sourceType3_ = bucket_.sourceType3;
        price_ = _readSourceMaybeWrite(bucket_.sourceType1, bucket_.source1, bucket_.multiplier1, ctx_, doRevert_);

        if (capDirection_ != SOURCE_CAP_NONE) {
            price_ = _applyLegCap(price_, bucket_.capOperand1, capDirection_);
        }

        if (sourceType2_ == SOURCE_NOT_SET) {
            return price_;
        }

        uint256 rate2_ = _readSourceMaybeWrite(sourceType2_, bucket_.source2, bucket_.multiplier2, ctx_, doRevert_);
        if (capDirection_ != SOURCE_CAP_NONE) {
            rate2_ = _applyLegCap(rate2_, bucket_.capOperand2, capDirection_);
        }
        price_ = (price_ * rate2_) / ORACLE_PRECISION;

        if (sourceType3_ == SOURCE_NOT_SET) {
            if (price_ == 0) {
                if (!doRevert_) return 0;
                _revert(ErrorTypes.UsdOracle__RateZero);
            }
            return price_;
        }

        uint256 rate3_ = _readSourceMaybeWrite(sourceType3_, bucket_.source3, bucket_.multiplier3, ctx_, doRevert_);
        if (capDirection_ != SOURCE_CAP_NONE) {
            rate3_ = _applyLegCap(rate3_, bucket_.capOperand3, capDirection_);
        }
        price_ = (price_ * rate3_) / ORACLE_PRECISION;

        if (price_ == 0) {
            if (!doRevert_) return 0;
            _revert(ErrorTypes.UsdOracle__RateZero);
        }
    }

    /// @dev Raw composed price from a `TokenSources` bucket (for `getPriceRawForMode`).
    ///      Loads slot 2 / 3 only if the prior source type indicates they are configured. Never reverts.
    function _readComposedPriceRaw(TokenSources storage bucket_) internal view returns (uint256 priceRaw_) {
        uint8 sourceType2_ = bucket_.sourceType2;
        uint8 sourceType3_ = bucket_.sourceType3;
        priceRaw_ = _readSourceRaw(bucket_.sourceType1, bucket_.source1, bucket_.multiplier1);

        if (sourceType2_ == SOURCE_NOT_SET) {
            return priceRaw_;
        }

        uint256 rate2_ = _readSourceRaw(sourceType2_, bucket_.source2, bucket_.multiplier2);
        priceRaw_ = (priceRaw_ * rate2_) / ORACLE_PRECISION;

        if (sourceType3_ == SOURCE_NOT_SET) {
            return priceRaw_;
        }

        uint256 rate3_ = _readSourceRaw(sourceType3_, bucket_.source3, bucket_.multiplier3);
        priceRaw_ = (priceRaw_ * rate3_) / ORACLE_PRECISION;
    }
}

// ==================== Alt Price Read (deviation/fallback) ====================

/// @dev Handles alt-source flow: deviation check and/or fallback.
abstract contract FluidUsdOracleAltPriceRead is FluidUsdOracleSourceRead {
    /// @dev Reads primary price (non-reverting), then resolves fallback, deviation, and overall cap.
    ///      For non-PEG: fallbackAltCfg_ and deviationCfg_ both point to altSrc.
    ///      For PEG: fallbackAltCfg_ is the selected mapping's altSrc; deviationCfg_ crosses mappings
    ///      (and doubles as the cross-path reference for overall cap).
    ///      The reference price is read at most once, reused for deviation check and cross-path cap.
    ///      CROSS_PATH operate fail-closes (`doRevert_=true`). CROSS_PATH liquidate reads the ref soft and
    ///      skips the cap when it is `0` so a dead other path cannot halt liquidations.
    function _getPriceWithAlt(
        TokenSources storage primaryCfg_,
        TokenSources storage fallbackAltCfg_,
        bool hasFallbackAlt_,
        TokenSources storage deviationCfg_,
        OracleKeyConfig memory keyConfig_,
        PriceReadContext memory ctx_,
        uint8 capDirection_
    ) internal returns (uint256 price_) {
        price_ = _readComposedPrice(primaryCfg_, ctx_, false, capDirection_);
        if (price_ == 0) {
            if (ctx_.isOperate && keyConfig_.maxDeviationBPS > 0) {
                _revert(ErrorTypes.UsdOracle__RateZero);
            }
            if (keyConfig_.flagsBitmap & KEY_FLAG_FALLBACK == 0) {
                _revert(ErrorTypes.UsdOracle__RateZero);
            }
            if (!hasFallbackAlt_) {
                _revert(ErrorTypes.UsdOracle__AltSourceNotConfigured);
            }
            price_ = _readComposedPrice(fallbackAltCfg_, ctx_, true, capDirection_);
        }

        uint256 refPrice_;
        bool isCrossPath_ = _isCrossPath(keyConfig_.overallCapMode);

        if (ctx_.isOperate && keyConfig_.maxDeviationBPS > 0) {
            refPrice_ = _readComposedPrice(deviationCfg_, ctx_, true, capDirection_);
            uint256 diff_;
            unchecked {
                diff_ = price_ > refPrice_ ? price_ - refPrice_ : refPrice_ - price_;
            }
            if ((diff_ * BPS_DENOMINATOR) / price_ > keyConfig_.maxDeviationBPS) {
                _revert(ErrorTypes.UsdOracle__MaxDeviation);
            }
        } else if (isCrossPath_) {
            // Operate fail-closes. Liquidate must still price off primary if the other path is dead —
            // never `min(price, 0)`.
            refPrice_ = _readComposedPrice(deviationCfg_, ctx_, ctx_.isOperate, capDirection_);
            if (refPrice_ == 0) {
                return price_;
            }
        }

        return _applyOverallCap(price_, refPrice_, keyConfig_);
    }

    /// @dev Resolves price from the non-PEG source config storage reference.
    ///      Non-PEG: deviation and fallback both use altSrc.
    ///      Applies per-leg caps via sourceCapMode and overall cap if configured.
    function _getResolvedPrice(
        TokenSourceConfig storage srcCfg_,
        TokenMetadata memory meta_,
        OracleKeyConfig memory keyConfig_,
        PriceReadContext memory ctx_
    ) internal returns (uint256 price_) {
        uint8 capDirection_ = keyConfig_.sourceCapMode;

        bool hasAlt_ = meta_.flagsBitmap & FLAG_HAS_ALT_SOURCE != 0;
        if (
            hasAlt_ ||
            keyConfig_.maxDeviationBPS > 0 ||
            keyConfig_.flagsBitmap & KEY_FLAG_FALLBACK != 0 ||
            _isCrossPath(keyConfig_.overallCapMode)
        ) {
            return
                _getPriceWithAlt(
                    srcCfg_.primarySrc,
                    srcCfg_.altSrc,
                    hasAlt_,
                    srcCfg_.altSrc,
                    keyConfig_,
                    ctx_,
                    capDirection_
                );
        }

        price_ = _readComposedPrice(srcCfg_.primarySrc, ctx_, true, capDirection_);
        return _applyOverallCap(price_, 0, keyConfig_);
    }

    /// @dev PEG-token resolved price:
    ///      - deviation compares `_tokenSources.primarySrc` vs `_additionalTokenSources.primarySrc`
    ///      - fallback remains within the selected mapping and uses that mapping's alt sources
    ///      - per-leg caps, deviation, and overall cap (cross-path or operand) handled by _getPriceWithAlt
    function _getPegResolvedPrice(
        address token_,
        TokenSourceConfig storage tokenCfg_,
        TokenMetadata memory meta_,
        OracleKeyConfig memory keyConfig_,
        PriceReadContext memory ctx_
    ) internal returns (uint256 price_) {
        TokenSources storage primaryCfg_;
        TokenSources storage altBucket_;
        TokenSources storage deviationRef_;
        bool hasFallbackAlt_;

        if (keyConfig_.priceMode == PRICE_MODE_MARKET) {
            // market price is in additional sources
            primaryCfg_ = _additionalTokenSources[token_].primarySrc;
            hasFallbackAlt_ = meta_.flagsBitmap & FLAG_HAS_ADDITIONAL_ALT_SOURCES != 0;
            altBucket_ = _additionalTokenSources[token_].altSrc;
            deviationRef_ = tokenCfg_.primarySrc;
        } else {
            // peg price is in primary sources
            primaryCfg_ = tokenCfg_.primarySrc;
            hasFallbackAlt_ = meta_.flagsBitmap & FLAG_HAS_ALT_SOURCE != 0;
            altBucket_ = tokenCfg_.altSrc;
            deviationRef_ = _additionalTokenSources[token_].primarySrc;
        }

        if (
            !hasFallbackAlt_ &&
            keyConfig_.maxDeviationBPS == 0 &&
            keyConfig_.flagsBitmap & KEY_FLAG_FALLBACK == 0 &&
            !_isCrossPath(keyConfig_.overallCapMode)
        ) {
            price_ = _readComposedPrice(primaryCfg_, ctx_, true, keyConfig_.sourceCapMode);
            return _applyOverallCap(price_, 0, keyConfig_);
        }

        return
            _getPriceWithAlt(
                primaryCfg_,
                altBucket_,
                hasFallbackAlt_,
                deviationRef_,
                keyConfig_,
                ctx_,
                keyConfig_.sourceCapMode
            );
    }
}

// ==================== Views ====================

/// @dev All public view / query methods: getPrice, getPriceRawForMode, getPriceDetailed, getConfiguredTokenOracles, etc.
abstract contract FluidUsdOracleViews is IUSDOracle, FluidUsdOracleAltPriceRead, TokenSymbolResolver {
    /// @dev Guard hook for price reads; L2 overrides with the sequencer gate. Raw/impl entries skip it on purpose.
    function _beforeGuardedPriceRead() internal view virtual {}

    /// @inheritdoc IUSDOracle
    function isGuardian(address addr_) external view override returns (bool) {
        return _guardians[addr_] == 1;
    }

    /// @inheritdoc IUSDOracle
    function getTokenConfig(
        address token_
    ) external view override returns (bool operatePaused_, bool liquidatePaused_, uint8 tokenType_, uint8 decimals_) {
        TokenSourceConfig storage cfg_ = _tokenSources[token_];
        operatePaused_ = cfg_.primarySrc.pauseState & PAUSED_OPERATE != 0;
        liquidatePaused_ = cfg_.primarySrc.pauseState & PAUSED_LIQUIDATE != 0;
        tokenType_ = cfg_.primarySrc.tokenType;
        decimals_ = cfg_.primarySrc.decimals;
    }

    /// @inheritdoc IUSDOracle
    function isTokenConfigGovernanceApproved(address token_) external view override returns (bool) {
        return _tokenSources[token_].primarySrc.flagsBitmap & FLAG_GOVERNANCE_APPROVED != 0;
    }

    /// @inheritdoc IUSDOracle
    function isEmodeValid(uint256 emode_, address token_) external view override returns (bool) {
        return _tokenHasEmodeInConfigsMap(token_, emode_);
    }

    /// @inheritdoc IUSDOracle
    /// @dev Runs the tree in Write mode: Fluid/capped legs use `IFluidOracleWrite` getters. Reads should use `getPriceView`.
    function getPrice(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) public virtual override returns (uint256 price_) {
        _beforeGuardedPriceRead();
        return _getPriceImpl(token_, emode_, isOperate_, isCollateral_, true);
    }

    /// @inheritdoc IUSDOracle
    function getPriceView(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) public view virtual override returns (uint256 price_) {
        _beforeGuardedPriceRead();
        return _getPriceImplStatic(token_, emode_, isOperate_, isCollateral_);
    }

    /// @inheritdoc IUSDOracle
    function getPriceDetailed(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) public virtual override returns (uint256 price_, uint8 decimals_, uint8 tokenType_) {
        price_ = getPrice(token_, emode_, isOperate_, isCollateral_);
        (decimals_, tokenType_) = _getMetadata(token_);
    }

    /// @inheritdoc IUSDOracle
    function getPriceDetailedView(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) public view virtual override returns (uint256 price_, uint8 decimals_, uint8 tokenType_) {
        price_ = getPriceView(token_, emode_, isOperate_, isCollateral_);
        (decimals_, tokenType_) = _getMetadata(token_);
    }

    /// @inheritdoc IUSDOracle
    /// @dev Resolver read path: intentionally not behind `_beforeGuardedPriceRead` (e.g. skips the L2 sequencer gate).
    function getPriceDetailedViewRaw(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) public view virtual override returns (uint256 price_, uint8 decimals_, uint8 tokenType_) {
        price_ = _getPriceImplStatic(token_, emode_, isOperate_, isCollateral_);
        (decimals_, tokenType_) = _getMetadata(token_);
    }

    /// @inheritdoc IUSDOracle
    function getPriceRawForMode(
        address token_,
        uint8 priceMode_
    ) public view virtual override returns (uint256 priceRaw_, uint8 decimals_, uint8 tokenType_) {
        _beforeGuardedPriceRead();
        return _priceRawForMode(token_, priceMode_);
    }

    /// @inheritdoc IUSDOracle
    function getPricesRawForMode(
        address[] calldata tokens_,
        uint8[] calldata priceModes_
    )
        public
        view
        virtual
        override
        returns (uint256[] memory pricesRaw_, uint8[] memory decimals_, uint8[] memory tokenTypes_)
    {
        _beforeGuardedPriceRead(); // once for the whole batch
        uint256 len_ = tokens_.length;
        if (priceModes_.length != len_) {
            _revert(ErrorTypes.UsdOracle__InvalidParams);
        }

        pricesRaw_ = new uint256[](len_);
        decimals_ = new uint8[](len_);
        tokenTypes_ = new uint8[](len_);
        for (uint256 i = 0; i < len_; ++i) {
            (pricesRaw_[i], decimals_[i], tokenTypes_[i]) = _priceRawForMode(tokens_[i], priceModes_[i]);
        }
    }

    /// @dev Unguarded body shared by the single and batch getters.
    function _priceRawForMode(
        address token_,
        uint8 priceMode_
    ) internal view returns (uint256 priceRaw_, uint8 decimals_, uint8 tokenType_) {
        if (priceMode_ == PRICE_MODE_NOT_SET) {
            return (0, 0, 0);
        }

        TokenSourceConfig storage tokenCfg_ = _tokenSources[token_];
        TokenMetadata memory meta_ = _metadata(tokenCfg_);
        tokenType_ = meta_.tokenType;
        decimals_ = meta_.decimals;

        if (tokenType_ == TOKEN_TYPE_NOT_SET) {
            return (0, 0, 0);
        }
        if (priceMode_ == PRICE_MODE_PEG) {
            if (tokenType_ == TOKEN_TYPE_STABLE) {
                return (ORACLE_PRECISION, decimals_, tokenType_);
            }
            if (tokenType_ != TOKEN_TYPE_PEG) {
                return (0, decimals_, tokenType_);
            }
        }

        TokenSources storage primaryCfg_;
        TokenSources storage fallbackAltCfg_;
        bool hasFallbackAlt_;
        if (tokenType_ == TOKEN_TYPE_PEG && priceMode_ == PRICE_MODE_MARKET) {
            if (meta_.flagsBitmap & FLAG_HAS_ADDITIONAL_SOURCES == 0) {
                return (0, decimals_, tokenType_);
            }
            primaryCfg_ = _additionalTokenSources[token_].primarySrc;
            fallbackAltCfg_ = _additionalTokenSources[token_].altSrc;
            hasFallbackAlt_ = meta_.flagsBitmap & FLAG_HAS_ADDITIONAL_ALT_SOURCES != 0;
        } else {
            primaryCfg_ = tokenCfg_.primarySrc;
            fallbackAltCfg_ = tokenCfg_.altSrc;
            hasFallbackAlt_ = meta_.flagsBitmap & FLAG_HAS_ALT_SOURCE != 0;
        }

        if (primaryCfg_.sourceType1 == SOURCE_NOT_SET) {
            return (0, decimals_, tokenType_);
        }

        priceRaw_ = _readComposedPriceRaw(primaryCfg_);
        if (priceRaw_ == 0 && hasFallbackAlt_) {
            priceRaw_ = _readComposedPriceRaw(fallbackAltCfg_);
        }
    }

    /// @inheritdoc IUSDOracle
    function getConfiguredTokenOracles(
        address token_
    ) external view override returns (ConfiguredTokenOracle[] memory infos_) {
        ConfigMap[] memory configMaps_ = configsMap[token_];
        uint256 len_ = configMaps_.length;
        infos_ = new ConfiguredTokenOracle[](len_);

        string memory tokenSymbol_ = _tokenSymbol(token_);
        for (uint256 i = 0; i < len_; ++i) {
            infos_[i] = _buildConfiguredTokenOracle(token_, tokenSymbol_, configMaps_[i]);
        }
    }

    // --- Internal methods ---

    /// @dev Enforces pause bits, resolves key config (eMode fallback to 0), then PEG vs non-PEG price resolution.
    function _getPriceImpl(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_,
        bool isWrite_
    ) internal returns (uint256 price_) {
        TokenSourceConfig storage tokenCfg_ = _tokenSources[token_];
        TokenMetadata memory meta_ = _metadata(tokenCfg_);

        uint8 pauseState_ = meta_.pauseState;
        if (isOperate_) {
            if (pauseState_ & PAUSED_OPERATE != 0) {
                _revert(ErrorTypes.UsdOracle__TokenPaused);
            }
        } else {
            if (pauseState_ & PAUSED_LIQUIDATE != 0) {
                _revert(ErrorTypes.UsdOracle__TokenPaused);
            }
        }

        uint256 isOp_ = isOperate_ ? 1 : 0;
        uint256 isCol_ = isCollateral_ ? 1 : 0;
        // Load key config for emode_, falling back to eMode 0 if unset.
        OracleKeyConfig memory keyConfig_ = _configs[_keyHash(token_, emode_, isOp_, isCol_)];
        if (keyConfig_.priceMode == PRICE_MODE_NOT_SET) {
            keyConfig_ = _configs[_keyHash(token_, 0, isOp_, isCol_)];
        }
        if (keyConfig_.priceMode == PRICE_MODE_NOT_SET) {
            _revert(ErrorTypes.UsdOracle__NoConfig);
        }

        uint8 tokenType_ = meta_.tokenType;

        // STABLE + PEG: constant $1, cheapest path (2 SLOADs, no caps — peg is exactly $1).
        if (_isStablePeg(tokenType_, keyConfig_.priceMode)) {
            return ORACLE_PRECISION;
        }

        PriceReadContext memory ctx_ = PriceReadContext({
            isOperate: isOperate_,
            isCollateral: isCollateral_,
            isWrite: isWrite_
        });

        if (tokenType_ == TOKEN_TYPE_PEG) {
            return _getPegResolvedPrice(token_, tokenCfg_, meta_, keyConfig_, ctx_);
        }

        return _getResolvedPrice(tokenCfg_, meta_, keyConfig_, ctx_);
    }

    /// @dev View entry helper: staticcall `_getPriceImplNoWrite` so one non-view price tree serves Write and view.
    function _getPriceImplStatic(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) internal view returns (uint256 price_) {
        (bool success_, bytes memory data_) = address(this).staticcall(
            abi.encodeCall(this._getPriceImplNoWrite, (token_, emode_, isOperate_, isCollateral_))
        );
        if (!success_) {
            assembly {
                revert(add(data_, 0x20), mload(data_))
            }
        }
        price_ = abi.decode(data_, (uint256));
    }

    /// @dev Self-staticcall target for `_getPriceImplStatic` (Write mode off); public only for the bridge, self-call gated.
    function _getPriceImplNoWrite(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) public virtual returns (uint256 price_) {
        if (msg.sender != address(this)) {
            _revert(ErrorTypes.UsdOracle__OnlySelf);
        }
        return _getPriceImpl(token_, emode_, isOperate_, isCollateral_, false);
    }

    /// @dev Copies packed token metadata from `_tokenSources[token].primarySrc` storage slot 0.
    function _metadata(TokenSourceConfig storage tokenCfg_) internal view returns (TokenMetadata memory meta_) {
        meta_ = TokenMetadata({
            pauseState: tokenCfg_.primarySrc.pauseState,
            tokenType: tokenCfg_.primarySrc.tokenType,
            decimals: tokenCfg_.primarySrc.decimals,
            flagsBitmap: tokenCfg_.primarySrc.flagsBitmap
        });
    }

    /// @dev Reads listing metadata from `_tokenSources[token_].primarySrc`.
    function _getMetadata(address token_) internal view returns (uint8 decimals_, uint8 tokenType_) {
        TokenSourceConfig storage tokenCfg_ = _tokenSources[token_];
        decimals_ = tokenCfg_.primarySrc.decimals;
        tokenType_ = tokenCfg_.primarySrc.tokenType;
    }

    /// @dev Builds a single ConfiguredTokenOracle entry. Extracted to avoid stack-too-deep in the loop.
    function _buildConfiguredTokenOracle(
        address token_,
        string memory tokenSymbol_,
        ConfigMap memory configMap_
    ) internal view returns (ConfiguredTokenOracle memory info_) {
        OracleKeyConfig memory keyCfg_ = _configs[
            _keyHash(token_, configMap_.eMode, configMap_.isOperate ? 1 : 0, configMap_.isCollateral ? 1 : 0)
        ];

        info_.token = token_;
        info_.symbol = tokenSymbol_;
        info_.eMode = configMap_.eMode;
        info_.isOperate = configMap_.isOperate;
        info_.isCollateral = configMap_.isCollateral;
        info_.priceMode = keyCfg_.priceMode;
        info_.sourceCapMode = keyCfg_.sourceCapMode;
        info_.overallCapMode = keyCfg_.overallCapMode;
        info_.overallCapOperand = keyCfg_.overallCapOperand;
        info_.maxDeviationBPS = keyCfg_.maxDeviationBPS;
        info_.isFallback = keyCfg_.flagsBitmap & KEY_FLAG_FALLBACK != 0;

        TokenSourceConfig storage tokenCfg_ = _tokenSources[token_];
        info_.governanceApproved = tokenCfg_.primarySrc.flagsBitmap & FLAG_GOVERNANCE_APPROVED != 0;
        TokenSources storage primaryCfg_;
        TokenSources storage altCfg_;
        bool hasAlt_;
        bool useAdditional_ = (tokenCfg_.primarySrc.tokenType == TOKEN_TYPE_PEG &&
            keyCfg_.priceMode == PRICE_MODE_MARKET);
        if (useAdditional_) {
            primaryCfg_ = _additionalTokenSources[token_].primarySrc;
            altCfg_ = _additionalTokenSources[token_].altSrc;
            hasAlt_ = tokenCfg_.primarySrc.flagsBitmap & FLAG_HAS_ADDITIONAL_ALT_SOURCES != 0;
        } else {
            primaryCfg_ = tokenCfg_.primarySrc;
            altCfg_ = tokenCfg_.altSrc;
            hasAlt_ = tokenCfg_.primarySrc.flagsBitmap & FLAG_HAS_ALT_SOURCE != 0;
        }
        info_.primary = _readSourcesWithRates(primaryCfg_, configMap_.isOperate, configMap_.isCollateral);
        if (hasAlt_) {
            info_.alt = _readSourcesWithRates(altCfg_, configMap_.isOperate, configMap_.isCollateral);
        }

        // Reported for every key: primary/alt only resolve to these when priceMode is MARKET, but
        // OVERALL_CAP_MIN/MAX_CROSS_PATH reads them on PEG keys too.
        uint8 flags_ = tokenCfg_.primarySrc.flagsBitmap;
        if (flags_ & FLAG_HAS_ADDITIONAL_SOURCES != 0) {
            info_.additionalPrimary = _readSourcesWithRates(
                _additionalTokenSources[token_].primarySrc,
                configMap_.isOperate,
                configMap_.isCollateral
            );
        }
        if (flags_ & FLAG_HAS_ADDITIONAL_ALT_SOURCES != 0) {
            info_.additionalAlt = _readSourcesWithRates(
                _additionalTokenSources[token_].altSrc,
                configMap_.isOperate,
                configMap_.isCollateral
            );
        }
    }
}

// ==================== Final Contract ====================

/// @title FluidUsdOracle
/// @notice Core USD oracle: token-level sources, per-key modes/caps, and `getPrice` in `ORACLE_PRECISION` (1e27) USD units.
contract FluidUsdOracle is FluidUsdOracleKeyConfigs, FluidUsdOracleViews {
    /// @notice Deploys the oracle with the Liquidity contract used to resolve governance.
    /// @param liquidity_ Liquidity proxy address (governance read via `LIQUIDITY_GOVERNANCE_SLOT`).
    constructor(address liquidity_) validAddress(liquidity_) {
        LIQUIDITY = liquidity_;
    }
}
