// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Structs } from "./structs.sol";

abstract contract SourceTypes {
    uint8 internal constant SOURCE_NOT_SET = 0;
    uint8 internal constant SOURCE_CAPPED_RATE = 1;
    uint8 internal constant SOURCE_CHAINLINK = 2;
    uint8 internal constant SOURCE_STABLE = 3; // constant $1 price, no external source needed
    uint8 internal constant SOURCE_REDSTONE = 4; // Chainlink-compatible aggregator same read path as SOURCE_CHAINLINK
    /// @dev Fluid oracle with debt getters (`IFluidOracleWithDebt`), e.g. CLX stock oracles. No `centerPrice()`.
    uint8 internal constant SOURCE_FLUID_ORACLE = 5;
}

abstract contract PriceModes {
    uint8 internal constant PRICE_MODE_NOT_SET = 0;
    uint8 internal constant PRICE_MODE_MARKET = 1;
    uint8 internal constant PRICE_MODE_PEG = 2;
}

abstract contract TokenTypes {
    /// @dev Default before `setTokenType`; token is not listed.
    uint8 internal constant TOKEN_TYPE_NOT_SET = 0;
    uint8 internal constant TOKEN_TYPE_PEG = 1;
    uint8 internal constant TOKEN_TYPE_STABLE = 2;
    uint8 internal constant TOKEN_TYPE_VOLATILE = 3;
}

abstract contract SourceCapModes {
    uint8 internal constant SOURCE_CAP_NONE = 0;
    uint8 internal constant SOURCE_CAP_MIN = 1; // min(rate, capOperand)
    uint8 internal constant SOURCE_CAP_MAX = 2; // max(rate, capOperand)
}

abstract contract OverallCapModes {
    uint8 internal constant OVERALL_CAP_NONE = 0;
    uint8 internal constant OVERALL_CAP_MIN_CROSS_PATH = 1; // min(price, ref). PEG: other mapping; else altSrc.
    uint8 internal constant OVERALL_CAP_MAX_CROSS_PATH = 2; // max(price, ref). PEG: other mapping; else altSrc.
    uint8 internal constant OVERALL_CAP_MIN_OPERAND = 3; // min(price, overallCapOperand * 1e25)
    uint8 internal constant OVERALL_CAP_MAX_OPERAND = 4; // max(price, overallCapOperand * 1e25)
}

abstract contract TokenFlagsBitmap {
    /// @dev flagsBitmap bits for `TokenSourceConfig` metadata.
    ///      These flags allow the read path to skip SLOADs for mappings that have no data.
    uint8 internal constant FLAG_HAS_ALT_SOURCE = 1; // bit 0: alt sources exist in _tokenSources
    uint8 internal constant FLAG_HAS_ADDITIONAL_SOURCES = 2; // bit 1: _additionalTokenSources has primary sources
    uint8 internal constant FLAG_HAS_ADDITIONAL_ALT_SOURCES = 4; // bit 2: _additionalTokenSources has alt sources
    uint8 internal constant FLAG_GOVERNANCE_APPROVED = 8; // bit 3: gov-approved token sources (+ MS eMode shadow-create freeze); setTokenConfigGovernanceApproved
}

abstract contract OracleKeyFlagsBitmap {
    /// @dev flagsBitmap bits for OracleKeyConfig
    uint8 internal constant KEY_FLAG_FALLBACK = 1; // bit 0: fallback enabled
}

abstract contract Constants is
    SourceTypes,
    PriceModes,
    TokenTypes,
    SourceCapModes,
    OverallCapModes,
    TokenFlagsBitmap,
    OracleKeyFlagsBitmap
{
    uint8 internal constant PAUSED_OPERATE = 1; // bit 0: operate calls paused
    uint8 internal constant PAUSED_LIQUIDATE = 2; // bit 1: liquidate calls paused

    int8 internal constant MAX_MULTIPLIER = 21; // a source rate with less than 6 decimals precision is not known to exist
    int8 internal constant MIN_MULTIPLIER = -12; // a source rate with more than 39 decimals precision is not known to exist

    uint256 internal constant ORACLE_PRECISION = 1e27;
    uint256 internal constant CAP_OPERAND_PRECISION = 1e2;
    uint256 internal constant CAP_PRECISION = ORACLE_PRECISION / CAP_OPERAND_PRECISION; // 1e25

    /// @dev 10_000 basis points = 100%. Used for deviation ratio scaling and max `maxDeviationBPS` bound.
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @dev address that is mapped to the chain native token at Liquidity
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev Maximum allowed timespan for Chainlink oracles in operate() mode (25 hours)
    uint256 internal constant MAX_UPDATE_TIMESPAN_OPERATE = 25 hours;
    /// @dev Maximum allowed timespan for Chainlink oracles in liquidate() mode (7 days)
    uint256 internal constant MAX_UPDATE_TIMESPAN_LIQUIDATE = 7 days;

    /// This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1
    /// The exact slot which stored the admin address in infinite proxy of liquidity contracts
    bytes32 internal constant LIQUIDITY_GOVERNANCE_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @notice Team multisig allowed to trigger certain config changes
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
}

abstract contract TransientVariables {
    /// @dev Registered OracleKey for the current admin session (auto-cleared after transaction).
    address internal transient _tToken;
    uint256 internal transient _tEMode;
    uint256 internal transient _tIsOperate;
    uint256 internal transient _tIsCollateral;
    /// @dev 1 if multisig just created a new config in this transaction, 0 otherwise.
    uint256 internal transient _tIsNewConfig;
}

/// @notice Core protocol addresses set once at deployment (`FluidUsdOracle` constructor).
abstract contract Immutables {
    /// @notice Address of the liquidity contract.
    address public immutable LIQUIDITY;
}

abstract contract Variables is Constants, Structs, TransientVariables, Immutables {
    // ----------------------- slot 0 ---------------------------

    /// @notice Per-key configs: maps keccak256(abi.encode(token, eMode, isOperate, isCollateral)) => OracleKeyConfig.
    ///         Each key config is 1 slot, storing priceMode + caps + deviation + fallback flag.
    ///         This is one of the two hot-path SLOADs for the common `getPrice()` flow.
    mapping(bytes32 => OracleKeyConfig) internal _configs;

    // ----------------------- slot 1 ---------------------------

    /// @notice maps token => array of all configured eMode/isOperate/isCollateral combinations for that token.
    ///         Used by getConfiguredTokenOracles to enumerate all configs.
    mapping(address => ConfigMap[]) public configsMap;

    // ----------------------- slot 2 ---------------------------

    /// @dev guardian address => 1 if active, 0 if not. Guardians can pause tokens for isOperate calls.
    mapping(address => uint256) internal _guardians;

    // ----------------------- slot 3 ---------------------------

    /// @dev Main per-token source configuration + metadata.
    ///      This mapping is the second hot-path SLOAD for the common `getPrice()` flow:
    ///      `_tokenSources[token]` storage slot 0 (`primarySrc` word 0) packs metadata with leg-1 source fields.
    ///
    ///      The layout is intentionally optimized so common reads resolve in 2 SLOADs total:
    ///      1. `_configs[key]` for key-specific config.
    ///      2. `_tokenSources[token]` slot 0 for metadata + `primarySrc` leg 1 (`source1`, `sourceType1-3`, …).
    ///
    ///      Without packing metadata into slot 0, token reads would need an extra SLOAD on every price
    ///      lookup just to fetch pause state / token type / decimals / flags.
    ///
    ///      Metadata lives on `primarySrc` (after leg-1 fields, before `__placeholder1` / future slot 0 expansion).
    ///      `primarySrc` uses storage slots 0-2; `altSrc` uses slots 3-5. `sourceType2` and `sourceType3`
    ///      stay in slot 0 so the read path can branch without loading slots 1 or 2.
    ///
    ///      What this mapping stores depends on token type:
    ///      - VOLATILE/STABLE: market price sources in the primary leg fields (the only price type for these tokens),
    ///        keeping those tokens on the 2-SLOAD path.
    ///      - PEG: peg price sources in `_tokenSources`, while market price sources for PEG tokens are
    ///        stored separately in `_additionalTokenSources`.
    ///        Peg is stored as primary because it is the more common lookup, so PEG tokens also stay on
    ///        the 2-SLOAD path for their primary price reads.
    mapping(address => TokenSourceConfig) internal _tokenSources;

    // ----------------------- slot 4 ---------------------------

    /// @dev Additional per-token source configuration for secondary price types.
    ///      Reuses `TokenSourceConfig`, but only primary leg fields / `altSrc` are populated here.
    ///      Metadata bytes remain zero; listing metadata lives in `_tokenSources` so that
    ///      hot-path reads do not need to touch this mapping unless the requested price type is the
    ///      uncommon secondary one.
    ///
    ///      - PEG tokens: stores market price sources in the primary leg fields (secondary for PEG tokens).
    ///        Reading this path costs an extra SLOAD versus the common primary read.
    ///      - VOLATILE/STABLE: unused (these tokens only have market price in `_tokenSources`).
    mapping(address => TokenSourceConfig) internal _additionalTokenSources;
}
