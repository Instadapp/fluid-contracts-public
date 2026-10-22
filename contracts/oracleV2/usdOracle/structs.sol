// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

abstract contract StorageStructs {
    struct TokenSources {
        // ---------- storage slot 0 ----------
        address source1; // 160 -- primary source 1 address
        int8 multiplier1; // 8  -- decimals multiplier: positive = multiply, negative = divide, to get to 1e27
        uint8 sourceType1; // 8 -- source type (see SOURCE_* constants)
        uint8 sourceType2; // 8 -- stored in slot 0 to avoid loading slot 1 just to check existence
        uint8 sourceType3; // 8 -- stored in slot 0 to avoid loading slot 2 just to check existence
        uint16 capOperand1; // 16 -- cap bound for leg 1 in 2-decimal precision (100 = 1.00). 0 = no cap.
        // -------------------------------------
        // Metadata (only meaningful on `_tokenSources.primarySrc`; zero on alt/additional buckets).
        uint8 pauseState; // 8 -- bit 0 = operate paused, bit 1 = liquidate paused
        uint8 tokenType; // 8  -- 0 = not listed, 1 = PEG, 2 = STABLE, 3 = VOLATILE
        uint8 decimals; // 8   -- IERC20.decimals() or 18 for native token
        /// @dev Stored and read only on `_tokenSources`, never on `_additionalTokenSources`.
        ///      Some bits describe whether corresponding configs exist in `_additionalTokenSources`.
        ///      bit 0 (FLAG_HAS_ALT_SOURCE): alt sources exist in this mapping (storage slots 3-5 / `altSrc`)
        ///      bit 1 (FLAG_HAS_ADDITIONAL_SOURCES): _additionalTokenSources has primary sources
        ///      bit 2 (FLAG_HAS_ADDITIONAL_ALT_SOURCES): _additionalTokenSources has alt sources
        ///      bit 3 (FLAG_GOVERNANCE_APPROVED): token-level sources approved by governance for downstream
        ///           policy (e.g. borrow limits) and MS eMode≠0 shadow-create freeze vs existing eMode-0 legs
        uint8 flagsBitmap; // 8
        // -------------------------------------
        uint16 __placeholder1; // 16 -- future slot 0 expansion
        // ---------- storage slot 1 ----------
        int8 multiplier2;
        address source2;
        uint16 capOperand2; // 16 -- cap bound for leg 2
        uint72 __placeholder2;
        // ---------- storage slot 2 ----------
        int8 multiplier3;
        address source3;
        uint16 capOperand3; // 16 -- cap bound for leg 3
        uint72 __placeholder3;
    }

    /// @dev Token-level source configuration using reusable three-source storage buckets.
    ///      `_tokenSources.primarySrc` packs metadata into storage slot 0 of the mapping value.
    ///      `_additionalTokenSources` and `altSrc` reuse the same shape but ignore metadata bytes.
    ///      Full `_tokenSources[token]` layout: slots 0-2 = `primarySrc`, slots 3-5 = `altSrc`.
    struct TokenSourceConfig {
        TokenSources primarySrc;
        TokenSources altSrc;
    }

    /// @dev Per-(token, eMode, isOperate, isCollateral) key configuration. Fits in 1 storage slot.
    ///      Intentionally slim: only stores a priceMode reference (which token-level source mapping
    ///      to read) plus key-specific parameters. Source feeds are configured per-token once and
    ///      shared by all keys for that token+mode — avoiding redundant feed storage and verification.
    struct OracleKeyConfig {
        uint8 priceMode; // PRICE_MODE_MARKET or PRICE_MODE_PEG
        uint8 sourceCapMode; // SOURCE_CAP_NONE / SOURCE_CAP_MIN / SOURCE_CAP_MAX
        uint8 overallCapMode; // OVERALL_CAP_NONE / MIN_CROSS_PATH / MAX_CROSS_PATH / MIN_OPERAND / MAX_OPERAND
        uint16 overallCapOperand; // 2-decimal precision bound for *_OPERAND modes (100 = 1.00). 0 for cross-path/none.
        uint24 maxDeviationBPS; // max deviation in basis points (100 = 1%). 0 = disabled.
        uint8 flagsBitmap; // bit 0: fallback enabled (KEY_FLAG_FALLBACK)
    }

    struct ConfigMap {
        uint240 eMode;
        bool isOperate;
        bool isCollateral;
    }
}

abstract contract MemoryStructs {
    struct SourceConfig {
        uint8 sourceType;
        address source;
        uint16 capOperand; // cap bound in 2-decimal precision (100 = 1.00). 0 = no cap for this leg.
    }

    /// @dev Read context threaded through the price tree as one memory pointer (avoids stack-too-deep).
    ///      `isWrite` selects `_readFluidSourceWrite` at Fluid/capped leaves.
    struct PriceReadContext {
        bool isOperate;
        bool isCollateral;
        bool isWrite;
    }

    struct OracleKey {
        address token;
        uint256 eMode;
        uint8 isOperate; // 0 = liquidate, 1 = operate
        uint8 isCollateral; // 0 = debt, 1 = collateral
    }
}

abstract contract ViewStructs {
    struct TokenMetadata {
        uint8 pauseState;
        uint8 tokenType;
        uint8 decimals;
        uint8 flagsBitmap;
    }

    struct SourcesWithRates {
        MemoryStructs.SourceConfig source1;
        MemoryStructs.SourceConfig source2;
        MemoryStructs.SourceConfig source3;
        uint256 rate1;
        uint256 rate2;
        uint256 rate3;
        uint256 price;
    }

    struct ConfiguredTokenOracle {
        address token;
        string symbol;
        uint256 eMode;
        bool isOperate;
        bool isCollateral;
        uint8 priceMode;
        SourcesWithRates primary;
        SourcesWithRates alt;
        /// @dev `_additionalTokenSources` (market price for PEG tokens). Zero when unset.
        SourcesWithRates additionalPrimary;
        SourcesWithRates additionalAlt;
        uint8 sourceCapMode;
        uint8 overallCapMode;
        uint16 overallCapOperand;
        uint24 maxDeviationBPS;
        bool isFallback;
        bool governanceApproved;
    }
}

abstract contract Structs is ViewStructs, StorageStructs, MemoryStructs {}
