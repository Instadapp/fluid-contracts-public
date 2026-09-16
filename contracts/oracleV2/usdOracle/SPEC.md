# FluidUsdOracle Technical Specification

This document describes the exact behavior of the code in `contracts/oracleV2/usdOracle` as it exists in this branch, including implementation quirks that differ from the likely intended design.

**Solidity version**: `0.8.36`  
**License**: `BUSL-1.1`

**Related documentation:** [`default-oracle-configs.md`](./default-oracle-configs.md) — internal guide for token-type classification, cap direction rules, default per-key patterns, and the vault combination matrix when wiring new listings. [`README.md`](./README.md) — integration-oriented overview of this directory.

---

## 1. Design Rationale

The architecture is shaped by two primary goals:

### 1.1 Gas-optimized price reads

The `getPrice()` hot path dominates on-chain gas costs. The storage layout is designed to resolve the most common price lookups in **2 SLOADs**:

1. One SLOAD for `_tokenSources[token]` storage slot 0 (`primarySrc` word 0), which packs leg-1 source fields and token metadata (pause state, token type, decimals, existence flags) into a single 256-bit word.
2. One SLOAD for the per-key `OracleKeyConfig` (priceMode, caps, deviation, fallback — all in 1 slot).

Without this packing, token metadata would live in a separate mapping and require a third SLOAD on every price read. For PEG tokens requesting their primary (peg) price, the 2-SLOAD path still applies. Only PEG tokens requesting market price pay an extra SLOAD to read from `_additionalTokenSources`.

### 1.2 Admin efficiency and verify-once source feeds

Source feeds (Chainlink addresses, capped rate contracts) are configured **per-token**, not per-key. Multipliers are derived internally at write-time. A single `setSourceConfig(token, ...)` call defines the market price feed chain for a token, and every key that references that token and price mode automatically uses it. This means:

- **Verify once, reference many times.** When governance sets up a Chainlink feed for ETH, it is validated and stored once. Every `(ETH, eMode, isOperate, isCollateral)` key that uses `PRICE_MODE_MARKET` reads from the same stored feed. There is no need to re-specify or re-validate the same source addresses for each key combination.
- **Per-key configs are slim.** Each key only stores a `priceMode` (which source mapping to use), caps, deviation threshold, and fallback flag. This keeps the per-key config to 1 slot and avoids repeating source feed data across potentially dozens of keys for the same token.
- **Transient admin session.** Per-key admin methods use a transient storage session: `registerTransientOracleKey()` stores the active key in transient storage, and all subsequent admin calls in the same transaction (setPriceMode, setSourceCapMode, setOverallCap, enableFallback, etc.) operate on that key without repeating it. This reduces calldata and ensures consistency across multi-step config updates.

**Token type changes:** `tokenType` drives which branch `_getPriceImpl` uses (PEG vs VOLATILE/STABLE paths and which mappings are read). Per-key configs do not store token type. Therefore `setTokenType` by the team multisig is only allowed while the token is still unlisted; governance may change type after listing so any migration stays an explicit governance action. A change that crosses the PEG boundary (PEG <-> STABLE/VOLATILE) reverts while any key still reads a reference source — fallback, deviation check, or CROSS_PATH — because PEG takes that leg from `_additionalTokenSources` and STABLE/VOLATILE from `altSrc`: disable the feature first, retype, then re-enable so the second-leg check runs against the new type. STABLE <-> VOLATILE resolves identically and is not gated.

---

## 2. Overview

Operational guidance for choosing defaults per token side and vault type lives in [`default-oracle-configs.md`](./default-oracle-configs.md); this spec describes what the implementation does once keys are set.

`FluidUsdOracle` maps `(token, eMode, isOperate, isCollateral)` tuples to USD prices at `1e27` precision.

Source configurations are defined **per-token** in `_tokenSources` (and optionally `_additionalTokenSources`), while per-key configs reference a **price mode** (MARKET or PEG) to determine which source mapping to read.

The codebase contains:

- `FluidUsdOracle`: base implementation
- `FluidUsdOracleL2`: L2 variant that gates every price method behind a Chainlink sequencer uptime check
- `FluidUsdOracleProxy`: thin `ERC1967Proxy`

The implementation inherits `UUPSUpgradeable` for upgrade authorization, but the proxy contract itself is an `ERC1967Proxy`.

---

## 3. Storage Layout

### 3.1 Per-key config mapping

```text
mapping(bytes32 => OracleKeyConfig) _configs
```

The key is `keccak256(abi.encode(token, eMode, isOperate, isCollateral))`.

Each `OracleKeyConfig` fits in **1 slot** (88/256 bits used):

| Field | Bits | Purpose |
|---|---|---|
| `priceMode` | 8 | `PRICE_MODE_MARKET` or `PRICE_MODE_PEG` once configured; `PRICE_MODE_NOT_SET` (0) for an empty / unset slot |
| `sourceCapMode` | 8 | `SOURCE_CAP_NONE` / `SOURCE_CAP_MIN` / `SOURCE_CAP_MAX` — per-leg cap direction (operands on `TokenSources`) |
| `overallCapMode` | 8 | `OVERALL_CAP_NONE` or cross-path / operand modes — post-composition cap |
| `overallCapOperand` | 16 | 2-decimal bound for `*_OPERAND` modes (100 = $1.00); 0 for none/cross-path |
| `maxDeviationBPS` | 24 | max deviation in basis points. 0 = disabled |
| `flagsBitmap` | 8 | bit 0: fallback enabled (KEY_FLAG_FALLBACK) |

### 3.2 Config index by token

```text
mapping(address => ConfigMap[]) configsMap
```

Tracks every explicitly stored `(eMode, isOperate, isCollateral)` tuple for a token. This is only an enumeration index for `getConfiguredTokenOracles()`; it is not used for price lookup fallback.

### 3.3 Guardians

```text
mapping(address => uint256) _guardians
```

`1` means active guardian, `0` means inactive.

### 3.4 Main token sources + metadata

```text
mapping(address => TokenSourceConfig) _tokenSources
```

Each token's primary source configuration plus packed metadata. What this mapping stores depends on token type:

- **VOLATILE/STABLE**: market price sources (the only price type for these tokens).
- **PEG**: peg price sources. Peg price is the primary/most-used price for PEG tokens, so storing it here keeps the common lookup at 2 SLOADs. Market price sources for PEG tokens are stored separately in `_additionalTokenSources`.

Token metadata (pauseState, tokenType, decimals, flagsBitmap) is packed into `primarySrc` storage slot 0 alongside `source1` and `sourceType1`–`3`. Metadata is flattened into `TokenSources` (not a separate nested struct on `TokenSourceConfig`) so the hot path avoids an extra SLOAD.

### 3.5 Additional token sources

```text
mapping(address => TokenSourceConfig) _additionalTokenSources
```

Additional per-token source configuration. Uses the same `TokenSourceConfig` shape; `primarySrc` / `altSrc` source legs may be populated but metadata bytes in `primarySrc` slot 0 stay zero. Listing metadata lives only in `_tokenSources`.

- **PEG tokens**: stores market price sources (secondary for PEG tokens).
- **VOLATILE/STABLE**: unused.

---

## 4. TokenSourceConfig Packing

Slot indices below are **0-based** (EVM / `vm.load(base + n)`), per `structs.sol`.

`TokenSourceConfig` occupies **6 storage slots** per mapping value:

```text
struct TokenSourceConfig {
  TokenSources primarySrc;  // storage slots 0–2
  TokenSources altSrc;        // storage slots 3–5
}
```

### `primarySrc` slot 0

```text
source1 (160) | multiplier1 (8) | sourceType1 (8) | sourceType2 (8) | sourceType3 (8) | capOperand1 (16) |
pauseState (8) | tokenType (8) | decimals (8) | flagsBitmap (8) | __placeholder1 (16, future slot 0 expansion)
```

### `primarySrc` slots 1–2

```text
Slot 1: multiplier2 | source2 | capOperand2 | __placeholder2
Slot 2: multiplier3 | source3 | capOperand3 | __placeholder3
```

### `altSrc` slots 3–5

Same `TokenSources` field layout as `primarySrc`. Metadata bytes in slot 3 are **zero** (only `_tokenSources.primarySrc` slot 0 carries listing metadata).

Notable packing choices:

- Metadata is **inside** `TokenSources`, after leg-1 fields and before `__placeholder1`, so it shares slot 0 with `source1` — not in a nested `TokenMetadata` struct on `TokenSourceConfig` (that layout would put metadata in word 0 and `source1` in word 2).
- `sourceType2` and `sourceType3` stay in slot 0 so the read path can branch without loading slots 1 or 2.
- `flagsBitmap` stays in slot 0 so alt/additional presence can be checked before touching `altSrc` (slots 3–5).

### SLOAD count for `getPrice` hot path

| Scenario | SLOADs | Breakdown |
|---|---|---|
| VOLATILE/STABLE (market = primary) | **2** | key config + `_tokenSources` slot 0 |
| PEG with peg price (= primary) | **2** | key config + `_tokenSources` slot 0 |
| PEG with market price (= secondary) | **3** | key config + `_tokenSources` slot 0 (metadata/flags) + `_additionalTokenSources` slot 0 |

Additional SLOADs for multi-leg primary configs (slots 1 and/or 2) and alt flows (slots 3–5).

---

## 5. Constants

### 5.1 Source types

| Constant | Value | Meaning |
|---|---|---|
| `SOURCE_NOT_SET` | 0 | Source absent |
| `SOURCE_CAPPED_RATE` | 1 | `IFluidCappedRate` (requires `centerPrice()`) |
| `SOURCE_CHAINLINK` | 2 | Chainlink aggregator V3 |
| `SOURCE_STABLE` | 3 | Hardcoded `$1` (`1e27`) |
| `SOURCE_REDSTONE` | 4 | RedStone (Chainlink-compatible aggregator; same read path as `SOURCE_CHAINLINK`) |
| `SOURCE_FLUID_ORACLE` | 5 | `IFluidOracleWithDebt` (e.g. CLX stock oracles; no `centerPrice()`) |

### 5.2 Price modes

| Constant | Value | Meaning |
|---|---|---|
| `PRICE_MODE_NOT_SET` | 0 | No mode configured |
| `PRICE_MODE_MARKET` | 1 | Market price |
| `PRICE_MODE_PEG` | 2 | Peg price |

### 5.3 Token flags (`primarySrc.flagsBitmap` on `_tokenSources`)

| Constant | Value | Meaning |
|---|---|---|
| `FLAG_HAS_ALT_SOURCE` | 1 | Alt sources exist in this mapping (`altSrc`, storage slots 3–5) |
| `FLAG_HAS_ADDITIONAL_SOURCES` | 2 | `_additionalTokenSources` has primary sources |
| `FLAG_HAS_ADDITIONAL_ALT_SOURCES` | 4 | `_additionalTokenSources` has alt sources |
| `FLAG_GOVERNANCE_APPROVED` | 8 | Current token-level USD oracle sources are governance-approved (on-chain signal for downstream policy, e.g. borrow-limit actions that TEAM_MULTISIG must not take until approved; also freezes MS from creating eMode≠0 keys that would shadow existing eMode-0 fallback legs) |

**Governance-approved flag — behavior:** On `setSourceConfig` / `setAltSourceConfig` / `setAdditionalSourceConfig` / `setAdditionalAltSourceConfig`, governance callers set this bit; TEAM_MULTISIG clears it (multisig-created configs are un-stamped until governance edits sources or calls `setTokenConfigGovernanceApproved(true)`). Governance-only `remove*` methods on token-level sources **set** the bit (any governance change remains approved). `setTokenConfigGovernanceApproved` (governance only) can set or clear the bit without changing sources. While the bit is set, TEAM_MULTISIG also cannot `setPriceMode`-create an eMode≠0 key that would shadow an existing eMode-0 leg for the same `(token, isOperate, isCollateral)` (see §8.2). Only governance can clear the bit (see lockout below), so that MS onboarding path re-opens only by governance.

**Approved-token source lockout:** once the bit is set, all four token-level source setters are **governance-only** — TEAM_MULTISIG reverts with `UsdOracle__Unauthorized` even on a bucket it could otherwise *create*. Each setter re-stamps approval from the caller, so an MS write would clear the bit and disarm the §8.2 shadow-create guard in the same tx. Enforced by `_revertIfTeamMultisigOnApprovedToken` ahead of the create-only check. Unapproved tokens are unaffected.

### 5.4 OracleKeyConfig flags

| Constant | Value | Meaning |
|---|---|---|
| `KEY_FLAG_FALLBACK` | 1 | Alt source may replace primary on failure |

### 5.5 Pause bits

| Constant | Value | Meaning |
|---|---|---|
| `PAUSED_OPERATE` | 1 | Operate prices paused |
| `PAUSED_LIQUIDATE` | 2 | Liquidate prices paused |

### 5.6 Token types

| Constant | Value | Meaning |
|---|---|---|
| `TOKEN_TYPE_NOT_SET` | 0 | Token not listed (same value; code uses the `TOKEN_TYPE_NOT_SET` constant) |
| `TOKEN_TYPE_PEG` | 1 | Pegged asset |
| `TOKEN_TYPE_STABLE` | 2 | Stablecoin |
| `TOKEN_TYPE_VOLATILE` | 3 | Volatile asset |

### 5.7 Source cap modes (per-leg)

Applied to each configured leg in `TokenSources` / `_additionalTokenSources` using `SourceConfig.capOperand` (2-decimal USD, same scaling as legacy min/max caps: `100` = $1.00).

| Constant | Value | Meaning |
|---|---|---|
| `SOURCE_CAP_NONE` | 0 | No per-leg cap; `capOperand` ignored |
| `SOURCE_CAP_MIN` | 1 | `min(rate, capOperand * 1e25)` per leg when `capOperand > 0` |
| `SOURCE_CAP_MAX` | 2 | `max(rate, capOperand * 1e25)` per leg when `capOperand > 0` |

### 5.8 Overall cap modes (post-composition)

Applied after composing the resolved price (and after per-leg caps). `overallCapOperand` is 2-decimal USD for operand modes; cross-path modes ignore it (must be 0).

| Constant | Value | Meaning |
|---|---|---|
| `OVERALL_CAP_NONE` | 0 | No overall cap |
| `OVERALL_CAP_MIN_CROSS_PATH` | 1 | `min(resolved, ref)` — PEG: other mapping’s primary; VOLATILE / STABLE MARKET: `altSrc`. Not allowed on STABLE PEG (`$1` path skips caps) |
| `OVERALL_CAP_MAX_CROSS_PATH` | 2 | `max(resolved, ref)` — same `ref` as MIN_CROSS_PATH |
| `OVERALL_CAP_MIN_OPERAND` | 3 | `min(resolved, overallCapOperand * 1e25)` |
| `OVERALL_CAP_MAX_OPERAND` | 4 | `max(resolved, overallCapOperand * 1e25)` |

### 5.9 Precision and bounds

- `ORACLE_PRECISION = 1e27`
- `BPS_DENOMINATOR = 10_000` (100% in basis points; deviation ratio scaling and max `maxDeviationBPS` bound)
- `MIN_MULTIPLIER = -12`
- `MAX_MULTIPLIER = 21`
- Chainlink staleness windows:
  - operate: `25 hours`
  - liquidate: `7 days`

---

## 6. Token Type / Price Mode Relationship

The "primary" price type depends on the token type:

| Token type | `_tokenSources` stores | `_additionalTokenSources` stores | Allowed price modes |
|---|---|---|---|
| VOLATILE | market price | unused | MARKET only |
| STABLE | market price | unused | MARKET or PEG (constant $1) |
| PEG | peg price (primary) | market price (secondary) | PEG or MARKET |

### Source resolution logic

Given a per-key `priceMode` and token `tokenType`:

```text
if tokenType == PEG:
    PRICE_MODE_PEG   -> _tokenSources[token]           (primary)
    PRICE_MODE_MARKET -> _additionalTokenSources[token] (secondary)
if tokenType == STABLE:
    PRICE_MODE_MARKET -> _tokenSources[token]           (primary)
    PRICE_MODE_PEG   -> constant ORACLE_PRECISION ($1)  (no sources needed)
if tokenType == VOLATILE:
    PRICE_MODE_MARKET -> _tokenSources[token]           (primary)
    PRICE_MODE_PEG   -> revert / return 0 (not allowed)
```

Behavioral consequences of that selection:

- non-PEG tokens use `_tokenSources.altSrc` for both fallback and deviation checks
- PEG tokens use the selected mapping's alt sources only for fallback
- PEG tokens use `_tokenSources.primarySrc` vs `_additionalTokenSources.primarySrc` for deviation checks

---

## 7. Admin Session Pattern

Admin methods are split into two tiers with different session semantics, reflecting the verify-once design (see section 1.2):

### 7.1 Token-level source config (stateless)

Methods like `setSourceConfig`, `setAltSourceConfig`, and `setAdditionalSourceConfig` take a token address directly. They are called infrequently — only when onboarding a new token or changing its feed chain. Source validation (checking Chainlink `latestRoundData()`, capped-rate `centerPrice()` / `getExchangeRateOperateDebt()`, etc.) happens once at this stage. Every per-key config that later references this token and price mode automatically inherits the validated sources with no further feed verification needed.

Access split for token-level source config:

- governance may create, modify, and remove
- team multisig may only create a source config when that exact config does not already exist
- removal remains governance-only

### 7.2 Per-key config (transient session)

Per-key admin methods read the active `OracleKey` from transient storage:

1. Caller invokes `registerTransientOracleKey(OracleKey)`.
2. The key is stored in `_tToken`, `_tEMode`, `_tIsOperate`, `_tIsCollateral`.
3. Subsequent per-key admin calls in the same transaction (`setPriceMode`, `setSourceCapMode`, `setOverallCap`, `enableFallback`, etc.) reuse that registered key without repeating the tuple in calldata.
4. `removeConfig()` explicitly clears the transient key after deletion.

`registerTransientOracleKey()` also resets `_tIsNewConfig` to `0`.

Transient variables are automatically cleared at transaction end because they use Solidity's `transient` storage feature.

This session pattern means a typical admin flow for adding a new key is:
```
registerTransientOracleKey(token, eMode, isOperate, isCollateral)
setPriceMode(PRICE_MODE_MARKET)  // references already-validated token sources
setSourceCapMode(SOURCE_CAP_NONE)
setOverallCap(OVERALL_CAP_NONE, 0)
enableDeviationCheck(...)
```
The key tuple is specified once, the source feeds are never re-specified (they were set at the token level), and each per-key method only stores the slim per-key parameters (mode, source/overall caps, deviation, fallback).

---

## 8. Access Control

### 8.1 Roles

| Role | Resolution | Capabilities |
|---|---|---|
| Governance | Read from Liquidity admin slot | Full privilege set, including upgrades |
| Team multisig | `TEAM_MULTISIG` constant | Token listing, pause control, `registerTransientOracleKey()`, create-only source config writes, and new-config-only key-config privileges |
| Guardian | `_guardians` mapping | Can change only the operate-pause bit |

### 8.2 Multisig restriction

`setPriceMode()` is the gate that marks a key config as "new in this tx":

- governance may create or update
- multisig may create only
- if multisig creates a new config, `_tIsNewConfig` becomes `1`
- **approved eMode-0 shadow guard:** when creating (`priceMode` was unset), if `msg.sender == TEAM_MULTISIG`, `eMode != 0`, the same `(token, isOperate, isCollateral)` already has an eMode-0 config, and `FLAG_GOVERNANCE_APPROVED` is set on the token, the call reverts with `UsdOracle__Unauthorized`. Enforced inside the per-key overload of `_revertIfTeamMultisigModifiesExistingConfig` (same create-only helper family as token-level source setters). That prevents MS from inserting a more-specific key that would intercept live eMode-0 fallback pricing after governance has stamped the token. While the token is unapproved, MS may still create more-specific eModes during onboarding. Governance is never subject to this guard.

Methods guarded by `onlyGovernanceOrMSNewConfig` allow:

- governance always
- multisig only if `_tIsNewConfig == 1`

That means the multisig can only follow up on a config it created earlier in the same transaction.

The same "create only, not modify" rule is also enforced on token-level source setters, but without using the transient key session:

- `setSourceConfig()` checks whether `_tokenSources[token].primarySrc` already exists
- `setAltSourceConfig()` checks whether `FLAG_HAS_ALT_SOURCE` is already set
- `setAdditionalSourceConfig()` checks whether `FLAG_HAS_ADDITIONAL_SOURCES` is already set
- `setAdditionalAltSourceConfig()` checks whether `FLAG_HAS_ADDITIONAL_ALT_SOURCES` is already set

If the relevant source config already exists and `msg.sender == TEAM_MULTISIG`, the setter reverts with `UsdOracle__Unauthorized`. Governance may still modify existing source configs.

### 8.3 Pause permissions

`setPausedState(token, pauseOperate, pauseLiquidate)` behaves as follows:

- governance or multisig may set either bit freely
- guardians may call it, but any change to the liquidate bit reverts
- the token does not need to be listed for pause state to be set

---

## 9. Source Validation

`_verifySourceConfig()` validates each configured source before it can be written into storage.

Validation steps:

- if `sourceType != SOURCE_STABLE`, `source` must be non-zero
- derived multiplier must lie in `[-12, 21]` (derived as `27 - feed.decimals()` for chainlink-style sources)`
- `SOURCE_CAPPED_RATE` requires `_isCappedRate(source)` to return `true`
- `SOURCE_FLUID_ORACLE` requires `_isFluidOracleWithDebt(source)` to return `true`
- `SOURCE_CHAINLINK` / `SOURCE_REDSTONE` require `_isChainlinkFeed(source)` to return `true` (both use the AggregatorV3-compatible read path)
- `SOURCE_STABLE` requires `source == address(0)`
- any other source type reverts with `UsdOracle__InvalidSource`

Helper semantics:

- `_isChainlinkFeed()` returns `true` only if `latestRoundData()` succeeds and the returned `roundId` is non-zero
- `_isCappedRate()` returns `true` only if `centerPrice()` succeeds with a non-zero value and `_isFluidOracleWithDebt(source)` is `true`
- `_isFluidOracleWithDebt()` returns `true` only if `getExchangeRateOperate()` and `getExchangeRateOperateDebt()` both succeed and both return non-zero values (no `centerPrice()` probe)

This validation is used by all `setSourceConfig`, `setAltSourceConfig`, `setAdditionalSourceConfig`, and `setAdditionalAltSourceConfig` methods.

---

## 10. Source Reading Semantics

### 10.1 `_readSource` (used by `getPrice`)

`_readSource()` dispatches by `sourceType`:

- capped rate / Fluid oracle: `_readFluidSource(source, isOperate, isCollateral)` — directional method based on operate/liquidate and collateral/debt
- Chainlink: `_readChainlink(source, isOperate, doRevert)` — staleness and sign checks; behavior depends on `doRevert` (see §10.4)
- stable: `ORACLE_PRECISION`
- anything else: `UsdOracle__InvalidSourceType`

After the raw read it applies the stored multiplier, then reverts with `UsdOracle__RateZero` if the normalized value is `0`.

### 10.2 `_readSourceRaw` (used by `getPriceRawForMode`)

`_readSourceRaw()` dispatches by `sourceType` but with raw semantics:

- capped rate: calls `getExchangeRate()` (view). Uncapped rate without operate/liquidate/collateral/debt distinction (no `_INVERT_CENTER_PRICE` apply on this path; inverted capped rates use directional getters on `getPrice` / `getPriceView`).
- Chainlink: uses `_readChainlinkRaw()` which always uses the liquidate (more lenient) staleness timespan and returns 0 instead of reverting on stale or negative data.
- stable: `ORACLE_PRECISION`
- unknown type: returns 0 (no revert)

After the raw read it applies the stored multiplier. Returns 0 on any failure (never reverts).

### 10.3 Derived multiplier behavior

- positive multiplier: multiply by `10 ** multiplier`
- negative multiplier: divide by `10 ** abs(multiplier)`
- zero: unchanged

### 10.4 Chainlink reader behavior

`_readChainlink(feed, isOperate, doRevert_)` wraps only the `latestRoundData()` call in `try/catch`. If that call **reverts**, the `catch` runs and `updatedAt_` remains unset (treated like invalid data below).

**After** the `try` (not inside it), the implementation checks, in order:

- `updatedAt_ == 0` → if `!doRevert_` return `0`; else revert `UsdOracle__RateInvalid`
- staleness vs operate (`25 hours`) or liquidate (`7 days`) window → if `!doRevert_` return `0`; else revert `UsdOracle__ChainlinkStale`
- `exchangeRate_ < 0` → if `!doRevert_` return `0`; else revert `UsdOracle__RateInvalid`

So **`doRevert_` controls whether failures surface as dedicated errors vs `0`:**

| `doRevert_` | Stale / invalid / negative | Successful read |
|---|---|---|
| `false` | Returns `0` (no `ChainlinkStale` / `RateInvalid`) | Normal `rate_` |
| `true` | Reverts `UsdOracle__ChainlinkStale` or `UsdOracle__RateInvalid` as above | Normal `rate_` |

**Where this shows up in pricing:**

- The **first** primary composed read inside `_getPriceWithAlt` uses `_readComposedPrice(..., doRevert_=false)`, so Chainlink issues there become **`0`** on the primary (then fallback / `RateZero` logic), **not** `ChainlinkStale` / `RateInvalid`.
- Paths that call `_readSource` / `_readComposedPrice` with **`doRevert_=true`** (e.g. simple no-alt path, fallback alt read, deviation reference read) **can** revert with **`UsdOracle__ChainlinkStale`** or **`UsdOracle__RateInvalid`** when the feed is stale or invalid.
- `_readSource` then reverts `UsdOracle__RateZero` if the normalized rate is `0` (including when Chainlink returned `0` with `doRevert_=false`).

### 10.5 Fluid source reader behavior (`SOURCE_CAPPED_RATE` / `SOURCE_FLUID_ORACLE`)

Both source types share `_readFluidSource()` / `_readFluidSourceRaw()` / `_readFluidSourceWrite()` (via `FluidSourceReader`).

Non-view `getPrice` runs one price tree with a Write flag on `PriceReadContext` (memory struct, no transient storage). Fluid/capped leaves then read via `_readFluidSourceWrite`, which tries the direction's `IFluidOracleWrite` getter — `getExchangeRateOperateWrite` / `getExchangeRateLiquidateWrite` on collateral, the `*DebtWrite` pair on debt — and uses that rate.

Any Write failure (missing selector or source error) falls back to the view getter, so `doRevert_` semantics match the view path: a failing source zeroes the leg rather than bubbling its own error. `getPriceView` staticcalls `_getPriceImplNoWrite` (same tree, Write off; self-call gated).

`_readFluidSource()` chooses the method based on `(isOperate, isCollateral)`:

| `isOperate` | `isCollateral` | Method |
|---|---|---|
| `true` | `true` | `getExchangeRateOperate()` |
| `true` | `false` | `getExchangeRateOperateDebt()` |
| `false` | `true` | `getExchangeRateLiquidate()` |
| `false` | `false` | `getExchangeRateLiquidateDebt()` |

Each external call is wrapped in `try/catch`, so a failed call also returns `0`.

For raw mode (`getPriceRawForMode`), `_readFluidSourceRaw()` (shared by `SOURCE_CAPPED_RATE` and `SOURCE_FLUID_ORACLE`) calls the uncapped `getExchangeRate()` getter instead, returning the unfiltered price without any directional distinction.

---

## 11. Price Composition and Caps

### 11.1 Composition

Composed price logic is multiplicative:

```text
price = rate1
if source2 is set: price = (price * rate2) / 1e27
if source3 is set: price = (price * rate3) / 1e27
```

Source chains must be contiguous: source 3 cannot exist if source 2 is unset.

### 11.2 Zero handling

Important exact behavior:

- each individual source read normalizing to zero reverts on the reverting path (`doRevert_=true`) and returns `0` on the non-reverting path (`doRevert_=false`)
- the composed price is explicitly checked for zero both after the two-leg case (when no third leg is configured) and after the third-leg multiplication
- on a zero composed price, `_readComposedPrice()` reverts with `UsdOracle__RateZero` when `doRevert_=true`, or returns `0` when `doRevert_=false`

Consequences:

- per-leg and overall caps do **not** turn a failed leg (`0` rate) into a non-zero price; a `0` composed result remains a failure unless the alt path applies
- in the alt-source path, a primary composed price of `0` is treated as a failure sentinel

### 11.3 Source caps and overall caps

**Source caps** (`OracleKeyConfig.sourceCapMode` + per-leg `SourceConfig.capOperand`): for each configured primary leg in the resolved mapping, if `capOperand > 0` and the mode is `SOURCE_CAP_MIN` or `SOURCE_CAP_MAX`, the leg’s normalized rate is clamped before multiplication into the composed price. A leg that read as `0` (failure sentinel on the non-reverting path: stale / invalid / rounded to 0) is **not** capped — it stays `0` so the composed price stays `0` and the staleness revert / alt fallback still triggers (a `SOURCE_CAP_MAX` floor must never mask a failed leg). Mode `SOURCE_CAP_NONE` ignores operands. Validation ties mode to collateral vs debt (`isCollateral`) as enforced in `setSourceCapMode`.

**Overall caps** (`OracleKeyConfig.overallCapMode` + `overallCapOperand`): after the composed price is known, operand modes clamp against `overallCapOperand * 1e25`; cross-path modes combine the resolved price with a second composed price. For PEG tokens that second price is the other mapping’s primary (`_tokenSources` vs `_additionalTokenSources`). For VOLATILE and STABLE MARKET keys it is `_tokenSources.altSrc`. Operate CROSS_PATH reads the ref with `doRevert_=true` (fail-closed, including VOLATILE/STABLE). Liquidate CROSS_PATH reads the ref with `doRevert_=false`; a `0` ref skips the cap and returns the resolved price so a dead other path cannot halt liquidations (never `min(price, 0)`). `setOverallCap` requires that second-leg **ref** to exist (PEG: both `primarySrc` and additional, same as deviation; else `altSrc`), rejects STABLE PEG keys (constant `$1` skips overall cap), and still ties MIN/MAX to collateral vs debt. `setPriceMode(PEG)` on a STABLE token reverts while CROSS_PATH is live so MARKET→PEG cannot leave a dead depeg floor.

Operand scaling matches legacy 2-decimal USD: `100` = $1.00 → `100 * 1e25` at oracle precision.

---

## 12. Alt Source Flow

Fallback and deviation are not identical:

- **Fallback** always stays within the selected token+mode mapping and uses that mapping's alt sources.
- **Deviation check** depends on token type:
  - non-PEG tokens: compare the resolved primary mapping against that same mapping's alt sources
  - PEG tokens: compare `_tokenSources.primarySrc` against `_additionalTokenSources.primarySrc`
- **CROSS_PATH overall cap** uses the same second composed price as deviation (PEG: other mapping primary; else `altSrc`). `_getResolvedPrice` enters `_getPriceWithAlt` when CROSS_PATH is set. Operate reads the ref with `doRevert_=true`. Liquidate reads `doRevert_=false` and skips the cap when the ref is `0`.

Internally, the runtime reuses small helpers for fallback and deviation, while keeping PEG/non-PEG source selection explicit.

Primary price resolution uses `_readComposedPrice(... doRevert_=false)`, which returns `0` on any source failure instead of reverting. `0` is therefore overloaded as a failure sentinel in the alt path.

Exact behavior:

1. Attempt primary read.
2. If primary result is `0`:
   - if `isOperate` and `maxDeviationBPS > 0`, revert `UsdOracle__RateZero`
   - else if fallback flag is not set (in `OracleKeyConfig.flagsBitmap`), revert `UsdOracle__RateZero`
   - else if fallback flag **is** set but the selected mapping has **no** alt bucket configured (`!hasFallbackAlt_`), revert `UsdOracle__AltSourceNotConfigured` (distinct from fallback off → `RateZero`)
   - else read the selected mapping's alt price, require it to be non-zero, apply per-leg source caps and overall cap, return it
3. If primary result is non-zero:
   - if `isOperate` and `maxDeviationBPS > 0`, read the configured deviation reference and compare deviation
   - else if CROSS_PATH overall cap is set, read the same reference: `doRevert_=true` on operate; `doRevert_=false` on liquidate and skip the cap when the ref is `0`
   - apply per-leg source caps and overall cap (CROSS_PATH uses that `refPrice_`)

Deviation check details:

- only runs in operate mode
- for non-PEG tokens, compares raw primary vs raw alt before caps
- for PEG tokens, compares raw `_tokenSources.primarySrc` vs raw `_additionalTokenSources.primarySrc` before caps
- reverts `UsdOracle__MaxDeviation` if `(abs(primary - ref) * BPS_DENOMINATOR) / primary > maxDeviationBPS` (see `BPS_DENOMINATOR` in `variables.sol`)

Fallback details:

- applies in operate and liquidate mode
- only triggers when the primary result is `0`
- fallback never jumps across mappings
- alt read is strict in this path: if it returns `0`, the call reverts with `UsdOracle__RateZero`

Combined behavior:

| Mode | Primary non-zero | Primary zero |
|---|---|---|
| Operate, deviation only | Compare with the configured deviation reference, may revert | Revert |
| Operate, fallback only | Return primary | Use selected mapping alt |
| Operate, deviation + fallback | Compare with the configured deviation reference, may revert | Revert |
| Liquidate, fallback off | Return primary | Revert |
| Liquidate, fallback on | Return primary | Use selected mapping alt |

---

## 13. `getPrice()` Flow

Base contract flow:

1. Read token metadata from `_tokenSources.primarySrc` slot 0 (pauseState, tokenType, flagsBitmap).
2. Revert `UsdOracle__TokenPaused` if the requested mode is paused.
3. Load `OracleKeyConfig` for `(token, eMode, isOperate, isCollateral)`.
4. If absent, retry with `eMode = 0`.
5. If still absent, revert `UsdOracle__NoConfig`.
6. **STABLE + PEG fast path**: return `ORACLE_PRECISION` ($1). Source/overall caps are not applied (peg is exactly $1). No source reads.
7. Resolve source mapping based on `priceMode` + `tokenType`:
   - VOLATILE/STABLE + MARKET: read from `_tokenSources`
   - PEG + PEG mode: read from `_tokenSources`
   - PEG + MARKET mode: read from `_additionalTokenSources`
8. For non-PEG tokens, route through `_tokenSources.primarySrc` and `_tokenSources.altSrc`.
9. For PEG tokens:
   - PEG mode reads `_tokenSources.primarySrc`
   - MARKET mode reads `_additionalTokenSources.primarySrc`
   - fallback always stays on that selected mapping's alt sources
   - deviation always compares `_tokenSources.primarySrc` vs `_additionalTokenSources.primarySrc`
10. Apply per-leg source caps (where configured), then overall cap (operand or CROSS_PATH vs the second composed price), and return.

Notes:

- `getPrice()` does not consult `configsMap`
- fallback to `eMode = 0` happens only in the read path
- the implementation is `public` and **not** `view` (intentionally matches `IUSDOracle` — non-view for future flexibility). Use `getPriceView()` / `getPriceDetailedView()` for `view` callers. The interface declares `getPrice` as `external` without `view`.

---

## 14. `getPriceRawForMode()` Flow

`getPriceRawForMode(address token_, uint8 priceMode_)` returns the raw composed price for the given mode plus token metadata (decimals, tokenType). No caps, no deviation, no reverts. It returns 0 for `priceRaw_` on failure and will use alt-source fallback when configured for the selected token+mode mapping.

Flow:

1. Validate inputs (returns 0 if priceMode is NOT_SET, token not listed, or PEG mode on non-PEG token).
2. Resolve the same primary mapping selection as `getPrice`.
3. If the selected primary bucket is unset, return 0.
4. Read composed price using raw source readers.
5. If the raw primary result is 0 and the selected mapping has alt sources, retry on that selected alt mapping.

Source reading differences from `getPrice`:

- **Capped rate / Fluid oracle**: calls the uncapped `getExchangeRate()` getter (`_readFluidSourceRaw`) instead of the directional `getExchangeRate*` methods — no operate/liquidate/collateral/debt distinction and no `_INVERT_CENTER_PRICE` apply on this path.
- **Chainlink / RedStone**: uses liquidate (lenient) staleness timespan, returns 0 instead of reverting.
- **Stable**: returns `ORACLE_PRECISION` (same).

---

## 15. L2 Variant

`FluidUsdOracleL2` overrides the `_beforeGuardedPriceRead()` hook to gate guarded price reads (getPrice, getPriceView, getPriceDetailed, getPriceDetailedView, getPriceRawForMode, getPricesRawForMode) behind `_ensureSequencerUpAndValid()`. Unguarded reads (getPriceDetailedViewRaw) skip the sequencer check; `_getPriceImplNoWrite` rejects external callers (`UsdOracle__OnlySelf`).

### 15.1 Sequencer status

`_sequencerUpStatus()`:

- reads `latestRoundData()` from the sequencer uptime feed
- if `answer != 0`, reports sequencer down
- if `answer == 0`, walks backward through consecutive "up" rounds to find the current uptime start

### 15.2 Dynamic grace period

`_gracePeriod()`:

- computes current uptime duration
- if `uptimeStartedAt == 0`, returns `(MAX_GRACE_PERIOD, true, 0)`
- if uptime duration already exceeds `MAX_GRACE_PERIOD`, also returns passed = `true`
- otherwise finds the last outage start and sets:
  - `gracePeriod = min(uptimeStartedAt - outageStartedAt, MAX_GRACE_PERIOD)`
  - `passed = uptimeDuration > gracePeriod`

### 15.3 Enforcement

`_ensureSequencerUpAndValid()`:

- reverts `UsdOracle__SequencerDown` when the sequencer is down
- reverts `UsdOracle__SequencerGracePeriod` when the grace period has not passed

This check is applied identically to operate and liquidate calls. The code does not special-case operate mode here.

### 15.4 `sequencerL2Data()`

Returns:

| Return | Meaning |
|---|---|
| `sequencerUptimeFeed_` | feed address |
| `maxGracePeriod_` | constant `45 minutes` |
| `isSequencerUp_` | current feed-reported status |
| `lastUptimeStartedAt_` | start timestamp of current uptime streak |
| `gracePeriod_` | computed grace period |
| `gracePeriodPassed_` | whether current uptime exceeded the grace period |
| `lastOutageStartedAt_` | last detected outage start |
| `isSequencerUpAndValid_` | `isSequencerUp_ && gracePeriodPassed_` |

When the sequencer is down, `sequencerL2Data()` sets `gracePeriod_` to the max grace period and leaves `gracePeriodPassed_` at its default `false` value.

---

## 16. View Methods

| Method | Intended consumers | Exact behavior |
|---|---|---|
| `getPrice(token, eMode, isOperate, isCollateral)` | DexV2, MoneyMarket | Returns the resolved price after pause checks, eMode fallback, source resolution, alt/deviation/fallback logic, and caps |
| `getPriceView(token, eMode, isOperate, isCollateral)` | Vault oracles and other read-only consumers that only need the final headline price | View-only variant of `getPrice()` with the same pause/eMode/alt/deviation/fallback/cap behavior |
| `getPriceDetailedView(token, eMode, isOperate, isCollateral)` | Vault oracles and other read-only consumers | View-only detailed pricing path. Returns (price, decimals, tokenType) and reverts with the same errors as `getPriceView()`. Internally, the headline `price` is obtained via `getPriceView()` |
| `getPriceRawForMode(token, priceMode)` | Limit handlers, auth contracts, and other consumers that always need a resolved price | Returns (priceRaw, decimals, tokenType). Raw composed price for the given mode. No caps or deviation checks; includes alt-source fallback when configured. Uses uncapped `getExchangeRate()` for capped rate sources and lenient Chainlink staleness. |
| `getPriceDetailed(token, eMode, isOperate, isCollateral)` | V1 vault wrappers (T1-T4) | Returns (price, decimals, tokenType). `price` uses `getPrice()` semantics and reverts on failure. Raw-price access lives on `getPriceRawForMode()`. |
| `getConfiguredTokenOracles(token)` | Enumerates only explicitly stored configs from `configsMap`; returns raw per-leg rates, priceMode, and composed primary/alt prices |
| `isEmodeValid(emode, token)` | Vault oracle factory, indexers | Returns `true` iff `configsMap[token]` contains at least one `ConfigMap` entry with `eMode == emode` (implementation: `_tokenHasEmodeInConfigsMap`). Does not consult pause flags or evaluate whether `getPriceView` would succeed for a given operate/collateral tuple |
| `isGuardian(addr)` | `true` iff `_guardians[addr] == 1` |
| `getTokenConfig(token)` | Returns operate pause, liquidate pause, token type, and decimals |

Important details for `getConfiguredTokenOracles()`:

- it does not apply eMode fallback
- it does not resolve the effective alt/deviation/fallback decision
- its `primary.price` and `alt.price` fields are raw composed prices from `_readSourcesWithRates()`
- those raw prices are not capped
- any failed per-leg read is surfaced as `0`
- `primary` / `alt` hold the mapping this row's `priceMode` resolves to: `_additionalTokenSources` only for `TOKEN_TYPE_PEG` + `PRICE_MODE_MARKET`, `_tokenSources` otherwise
- `additionalPrimary` / `additionalAlt` always hold `_additionalTokenSources` (market price for PEG tokens), zeroed when the corresponding `FLAG_HAS_ADDITIONAL_*` bit is unset. They are reported on every row because `OVERALL_CAP_MIN/MAX_CROSS_PATH` reads that mapping on PEG-mode keys, whose `primary` resolves to the peg path instead. For `PRICE_MODE_MARKET` PEG keys they duplicate `primary` / `alt`
- `symbol` comes from `TokenSymbolResolver._tokenSymbol()`:
  - **Native asset (only the sentinel address `0xEeee…EeeE`, same as Liquidity):** chain-specific ticker string — `ETH`, `POL`, `BNB`, `XPL`, …
  - **Any other token:** `IERC20Metadata.symbol()`; if that call **reverts** (non-compliant ERC20, non-ERC20 contract, etc.), the string is **`"UNK"`**. The literal **`"NATIVE"` is not used** anywhere in this resolver.

---

## 17. Admin Methods

The admin interface is split to match the verify-once architecture (section 1.2). Source feeds are configured per-token once, validated at write time, and then referenced by any number of per-key configs via a price mode. Per-key methods use the transient session pattern (section 7) so the key tuple is specified only once per transaction.

### 17.1 Token-Level Source Config (no transient session)

Source validation happens here — each `setSourceConfig` / `setAltSourceConfig` call validates the provided source addresses against the Chainlink or capped-rate interfaces. Once validated and stored, these sources are shared by all keys for this token+mode combination, avoiding redundant re-validation on every key config change.

| Method | Access | Requirements / Notes |
|---|---|---|
| `setSourceConfig(token, src1, src2, src3)` | governance or multisig | Token must be listed. Sets primary sources in `_tokenSources`. For VOLATILE/STABLE this is market price; for PEG this is peg price. Multisig may only create, not modify an existing primary config. Updates `FLAG_GOVERNANCE_APPROVED` (governance sets, multisig clears). |
| `removeSourceConfig(token)` | governance only | Also clears alt sources if they exist. Sets `FLAG_GOVERNANCE_APPROVED`. Removing the primary breaks every key, so it carries the same per-key preconditions as `removeAltSourceConfig` (fallback / deviation / CROSS_PATH all off). |
| `setAltSourceConfig(token, alt1, alt2, alt3)` | governance or multisig | Requires primary sources to exist. Sets `FLAG_HAS_ALT_SOURCE`. Multisig may only create, not modify an existing alt config. Updates `FLAG_GOVERNANCE_APPROVED` (governance sets, multisig clears). |
| `removeAltSourceConfig(token)` | governance only | Clears `FLAG_HAS_ALT_SOURCE`. Sets `FLAG_GOVERNANCE_APPROVED`. **Requires** that every per-key config for `token` has `KEY_FLAG_FALLBACK` off, `maxDeviationBPS == 0`, and no CROSS_PATH overall cap (call `disableFallback` / `disableDeviationCheck` / `setOverallCap(NONE)` per key first). Not required when alt is cleared implicitly by `removeSourceConfig`. |
| `setAdditionalSourceConfig(token, src1, src2, src3)` | governance or multisig | Only for PEG tokens. Sets market price sources in `_additionalTokenSources`. Sets `FLAG_HAS_ADDITIONAL_SOURCES`. Multisig may only create, not modify an existing additional source config. Updates `FLAG_GOVERNANCE_APPROVED` (governance sets, multisig clears). |
| `removeAdditionalSourceConfig(token)` | governance only | Also clears additional alt sources. Clears `FLAG_HAS_ADDITIONAL_SOURCES`. Sets `FLAG_GOVERNANCE_APPROVED`. Same per-key preconditions as `removeAltSourceConfig` (fallback / deviation / CROSS_PATH). |
| `setAdditionalAltSourceConfig(token, alt1, alt2, alt3)` | governance or multisig | Requires additional primary sources to exist. Sets `FLAG_HAS_ADDITIONAL_ALT_SOURCES`. Multisig may only create, not modify an existing additional alt config. Updates `FLAG_GOVERNANCE_APPROVED` (governance sets, multisig clears). |
| `removeAdditionalAltSourceConfig(token)` | governance only | Clears `FLAG_HAS_ADDITIONAL_ALT_SOURCES`. Sets `FLAG_GOVERNANCE_APPROVED`. Same per-key preconditions as `removeAltSourceConfig`. Not required when cleared implicitly by `removeAdditionalSourceConfig`. |
| `setTokenConfigGovernanceApproved(token, approved)` | governance only | Sets or clears `FLAG_GOVERNANCE_APPROVED` without changing sources (e.g. stamp a multisig-created config). |
| `isTokenConfigGovernanceApproved(token)` | view | Returns whether `FLAG_GOVERNANCE_APPROVED` is set. Also exposed per row in `getConfiguredTokenOracles` as `governanceApproved`. |

### 17.2 Per-Key Config (transient session required)

Each method below operates on the key set by `registerTransientOracleKey()`. The key's `priceMode` determines which token-level source mapping to use — the admin never specifies source feeds here, only the mode reference and key-specific parameters (caps, deviation, fallback).

| Method | Access | Requires registered key | Other requirements / notes |
|---|---|---|---|
| `setTokenType` | governance or multisig | No | `token != 0`, `tokenType` in `[1,3]`, fetches decimals. Multisig may only list a token that is not yet listed (`tokenType == NOT_SET`); changing type after listing is governance-only (`UsdOracle__Unauthorized` for multisig). A change crossing the PEG boundary reverts while any key still uses fallback, deviation check, or CROSS_PATH. |
| `registerTransientOracleKey` | governance or multisig | No | token must be listed, `isOperate` and `isCollateral` must be `0` or `1` |
| `setPriceMode(priceMode)` | governance or multisig | Yes | Creates or updates key config. Validates priceMode vs tokenType and source existence. If the key already has CROSS_PATH, `setPriceMode(PEG)` on a STABLE token reverts (`$1` skips overall cap). Multisig can only create new. When creating, multisig cannot shadow an existing eMode-0 leg on a governance-approved token. |
| `removeConfig` | governance only | Yes | Existing config required; removes ConfigMap entry and clears transient key |
| `setSourceCapMode(sourceCapMode)` | governance or multisig-on-new-config | Yes | Existing config required; validates mode vs `isCollateral` and token type |
| `setOverallCap(overallCapMode, overallCapOperand)` | governance or multisig-on-new-config | Yes | Existing config required; validates mode vs `isCollateral`; CROSS_PATH requires the ref mapping (PEG: primarySrc and additional; else alt) and is rejected on STABLE PEG keys; operand rules for operand modes |
| `enableDeviationCheck` | governance or multisig-on-new-config | Yes | Existing config required. Non-PEG: requires alt sources for the resolved mapping. PEG: requires both `_tokenSources.primarySrc` and `_additionalTokenSources.primarySrc`, because deviation compares those two primary mappings. |
| `disableDeviationCheck` | governance or multisig-on-new-config | Yes | Existing config required |
| `enableFallback` | governance or multisig-on-new-config | Yes | Existing config + alt sources for the resolved mapping required. Fallback never jumps across mappings. |
| `disableFallback` | governance or multisig-on-new-config | Yes | Existing config required |
| `setGuardian` | governance only | No | Guardian address must be non-zero |
| `setPausedState` | governance, multisig, or guardian | No | Guardian may not change the liquidate bit |

---

## 18. Error Codes

| Error ID | Constant | Exact trigger in current code |
|---|---|---|
| 310001 | `UsdOracle__AddressZero` | Zero address where explicitly rejected |
| 310002 | `UsdOracle__Unauthorized` | Caller lacks role, guardian attempts to change liquidate pause, or team multisig calls `setTokenType` for an already-listed token |
| 310003 | `UsdOracle__InvalidMultiplier` | Multiplier outside `[-12, 21]` |
| 310004 | `UsdOracle__InvalidSource` | Invalid source type, wrong source address for the type, or failed source-interface validation |
| 310005 | `UsdOracle__NoConfig` | No exact config and no `eMode = 0` fallback config |
| 310006 | `UsdOracle__InvalidSourceType` | Stored source type is not `1`, `2`, `3`, or `4` during a read |
| 310007 | `UsdOracle__RateZero` | Source read normalized to zero, alt fallback returned zero, or operate+deviation had no usable primary price |
| 310008 | `UsdOracle__ChainlinkStale` | From `_readChainlink(..., doRevert_=true)` when the feed is stale for the operate/liquidate window. With `doRevert_=false`, returns `0` instead. `getPriceRawForMode` uses `_readChainlinkRaw()` which returns `0` |
| 310009 | `UsdOracle__InvalidParams` | Invalid `isOperate`, `isCollateral`, `tokenType`, `priceMode`, zero `maxDeviationBPS`, or `maxDeviationBPS` above 100% (`BPS_DENOMINATOR`) |
| 310010 | `UsdOracle__RateInvalid` | From `_readChainlink(..., doRevert_=true)` for `updatedAt == 0` (including failed `latestRoundData`) or negative answers. With `doRevert_=false`, returns `0`. Raw path: `_readChainlinkRaw()` returns `0` |
| 310011 | `UsdOracle__ConfigDoesNotExist` | Admin method requires a registered existing key config |
| 310012 | `UsdOracle__InvalidCapConfig` | Invalid source cap mode, overall cap mode, operand, collateral/debt pairing, STABLE PEG + CROSS_PATH (`setOverallCap` or `setPriceMode` onto PEG while CROSS_PATH is live) |
| 310013 | `UsdOracle__AltSourceNotConfigured` | Alt-dependent **admin** method (`enableFallback`, `enableDeviationCheck` on non-PEG, `setOverallCap` CROSS_PATH on non-PEG) without alt sources; **or** `_getPriceWithAlt` when primary price is `0`, `KEY_FLAG_FALLBACK` is set, but the selected mapping has no alt bucket |
| 310014 | `UsdOracle__TokenPaused` | Requested price mode is paused |
| 310015 | `UsdOracle__KeyNotRegistered` | Per-key admin method called before `registerTransientOracleKey()` |
| 310016 | `UsdOracle__TokenNotListed` | `registerTransientOracleKey()` or source config called for token with `tokenType == TOKEN_TYPE_NOT_SET` (0) |
| 310017 | `UsdOracle__SequencerDown` | L2 sequencer currently down |
| 310018 | `UsdOracle__SequencerGracePeriod` | L2 sequencer is up but the grace period has not passed |
| 310019 | `UsdOracle__MaxDeviation` | Operate-mode primary/alt deviation exceeds threshold |
| 310020 | `UsdOracle__PriceModeNotAllowed` | `setPriceMode(PEG)` on VOLATILE token |
| 310021 | `UsdOracle__AdditionalNotAllowedForNonPeg` | `setAdditionalSourceConfig` on VOLATILE/STABLE token |
| 310022 | `UsdOracle__SourceConfigNotSet` | Config references mode with no sources, remove called on non-existent sources, or CROSS_PATH on PEG without `primarySrc` or additional |
| 310023 | `UsdOracle__FallbackMustBeDisabled` | `removeAltSourceConfig` / `removeAdditionalAltSourceConfig` / `removeSourceConfig` / `removeAdditionalSourceConfig` while some per-key config for the token still has `KEY_FLAG_FALLBACK` set |
| 310024 | `UsdOracle__DeviationCheckMustBeDisabled` | `removeAltSourceConfig` / `removeAdditionalAltSourceConfig` / `removeSourceConfig` / `removeAdditionalSourceConfig` while some per-key config for the token still has `maxDeviationBPS > 0` |
| 310025 | `UsdOracle__OnlySelf` | `_getPriceImplNoWrite` called by an external account |
| 310026 | `UsdOracle__CrossPathMustBeDisabled` | `removeAltSourceConfig` / `removeAdditionalSourceConfig` / `removeAdditionalAltSourceConfig` / `removeSourceConfig`, or `setTokenType` across the PEG boundary, while some per-key config still has CROSS_PATH overall cap |

---

## 19. Inheritance Hierarchy

```text
Structs (storage/memory/view struct definitions)
  Events is Structs   (events.sol: abstract contract Events is Structs)

Constants (+ TokenTypes, SourceTypes, PriceModes, …)
TransientVariables
Immutables
Variables = Constants + Structs + TransientVariables + Immutables

Error
ChainlinkSourceReader
FluidSourceReader  (implements `_readFluidSource` / `_readFluidSourceRaw` / `_readFluidSourceWrite` for SOURCE_CAPPED_RATE and SOURCE_FLUID_ORACLE)

FluidUsdOracleCore is Variables, Error
  (holds the `configsMap` scans and the shared `_isCrossPath` / `_isStablePeg` predicates: it is the only
   common ancestor of the admin branch and the read branch, and sharing them rather than inlining is what
   keeps `mainL2.sol` under EIP-170 — see the size note in `hardhat.config.ts`)
  +- FluidUsdOracleAuthorization
      +- FluidUsdOracleUpgradeable
          +- FluidUsdOracleTokenSourceConfigs
              +- FluidUsdOracleKeyConfigs

FluidUsdOracleSourceRead is FluidUsdOracleCore, ChainlinkSourceReader, FluidSourceReader
  +- FluidUsdOracleAltPriceRead
      +- FluidUsdOracleViews

FluidUsdOracle is FluidUsdOracleKeyConfigs, FluidUsdOracleViews
FluidUsdOracleL2 is FluidUsdOracle, FluidUsdOracleSequencerL2
FluidUsdOracleProxy is ERC1967Proxy   (see `proxy.sol`)
```
