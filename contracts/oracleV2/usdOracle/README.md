# Fluid USD Oracle

The Fluid USD Oracle returns token prices in USD at `1e27` precision for the Money Market. This README describes what the code in this directory does today, including a few implementation quirks that matter when integrating with or reviewing it.

**Documentation:** [`SPEC.md`](./SPEC.md) — full technical specification of behavior and storage. [`default-oracle-configs.md`](./default-oracle-configs.md) — internal reference for default oracle key choices (token types, caps, deviation/fallback defaults, vault-side combinations).

## High-Level Behavior

`getPrice(token, eMode, isOperate, isCollateral)`:

- checks pause state first (from `_tokenSources.primarySrc` slot 0 metadata)
- loads the per-key `OracleKeyConfig` for that tuple
- falls back to `eMode = 0` if the requested `eMode` has no config
- resolves which source mapping to read based on `priceMode` + `tokenType`
- reads up to 3 primary sources from the resolved mapping
- optionally uses alt-source deviation or fallback logic
- applies per-leg source caps (`sourceCapMode` + each leg’s `capOperand`) and overall caps (`overallCapMode` + operand or CROSS_PATH vs the second composed price) before returning (except STABLE + PEG mode, which returns constant `$1` and skips source/overall caps)

`getPriceRawForMode(token, priceMode)`:

- returns the raw composed price for a given mode, plus token decimals and token type
- no caps, no deviation, no fallback, no reverts (returns 0 for priceRaw on failure)
- capped rate sources use `getExchangeRate()` (uncapped, no directional getters)
- Chainlink uses the liquidate (lenient) staleness timespan

On L2, `FluidUsdOracleL2` adds a sequencer-uptime check before every price method, including `getPrice()`, `getPriceView()`, `getPriceDetailed()`, `getPriceDetailedView()`, and `getPriceRawForMode()`.

### `isEmodeValid(emode, token)`

View helper: returns `true` if and only if `configsMap[token]` contains at least one stored row whose `eMode` equals `emode`. It does **not** check pause state or whether a full `getPriceView` would succeed for a specific operate/collateral leg — it only answers whether that token has any explicit per-key config for that eMode in the map. Integrators such as **`VaultOracleFactory`** call it when registering a vault oracle to ensure the chosen deployment eMode is listed for at least one token relevant to that vault.

## Design Goals

Two goals drive the architecture:

### 1. Gas-optimized price reads

`getPrice()` is the hot path — every Money Market operation calls it. The storage layout is designed so the most common price lookups resolve in **2 SLOADs**:

1. `_tokenSources[token]` storage slot 0 (`primarySrc`), which packs leg-1 source fields **and** token metadata (pause state, token type, decimals, existence flags) into a single 256-bit word.
2. `OracleKeyConfig` for the requested key (1 slot: priceMode, source/overall caps, deviation, fallback).

Without this packing, reading token metadata would require a third SLOAD on every price read. Only the uncommon case of PEG tokens requesting market price pays a third SLOAD (to read from `_additionalTokenSources`).

### 2. Verify-once admin model

Source feeds are configured **per-token**, not per-key. When governance sets up a Chainlink feed for ETH via `setSourceConfig()`, the feed addresses are validated once (the contract calls `latestRoundData()` for Chainlink and probes `centerPrice()` / `getExchangeRateOperateDebt()` for capped-rate sources), stored once, and then shared by every `(ETH, eMode, isOperate, isCollateral)` key that references `PRICE_MODE_MARKET`. There is no need to re-specify or re-validate the same source addresses when adding new keys for the same token.

Per-key configs are intentionally slim — they only store a `priceMode` reference (which source mapping to use) plus key-specific parameters (source/overall caps, deviation, fallback). This avoids duplicating feed data across potentially dozens of key combinations per token.

The transient admin session pattern further reduces admin overhead: `registerTransientOracleKey()` stores the key tuple once in transient storage, and all subsequent admin calls in the same transaction (`setPriceMode`, `setSourceCapMode`, `setOverallCap`, `enableFallback`, etc.) operate on that key without repeating it.

## Architecture

### Per-token source configuration

Source feeds are defined **per-token**, not per-key:

- **`_tokenSources`**: stores primary sources plus packed token metadata on `primarySrc` slot 0. For VOLATILE/STABLE tokens this is market price; for PEG tokens this is peg price (the primary/most-used price for PEG tokens).
- **`_additionalTokenSources`**: stores secondary sources for PEG tokens (market price). VOLATILE/STABLE tokens don't use this mapping.

This design stores peg price (not market price) as the primary for PEG tokens because peg price is the more commonly used price type, keeping the common `getPrice` lookup at 2 SLOADs.

### Per-key configuration

Each `(token, eMode, isOperate, isCollateral)` key gets a slim `OracleKeyConfig` (1 slot) containing:

- `priceMode`: MARKET or PEG (determines which source mapping to read)
- `sourceCapMode`: per-leg direction (`SOURCE_CAP_NONE` / `MIN` / `MAX`) paired with each source leg’s `capOperand` on the token
- `overallCapMode` / `overallCapOperand`: post-composition clamp — operand modes vs `$1` (2-decimal operand), or `MIN_CROSS_PATH` / `MAX_CROSS_PATH` (PEG: peg vs market; VOLATILE / STABLE MARKET: primary vs alt)
- `maxDeviationBPS`: deviation threshold
- `flagsBitmap`: fallback flag

### Gas optimization

Token metadata is packed into `primarySrc` storage slot 0 of `_tokenSources` alongside `source1` (flattened into `TokenSources`, not a nested struct on `TokenSourceConfig`). This eliminates a separate SLOAD for token metadata, achieving:

| Scenario | SLOADs |
|---|---|
| VOLATILE/STABLE | **2** (key config + `_tokenSources` slot 0) |
| PEG + peg price | **2** (key config + `_tokenSources` slot 0) |
| PEG + market price | **3** (key config + `_tokenSources` slot 0 + `_additionalTokenSources` slot 0) |

## Important Current-Code Caveats

### Stale or invalid Chainlink data becomes `RateZero`

The Chainlink reader accepts a `doRevert_` flag. In the main price path (`doRevert_=true`), stale or invalid data triggers `UsdOracle__ChainlinkStale` or `UsdOracle__RateInvalid`. In the primary-read path for fallback logic (`doRevert_=false`), those errors are silently converted to `0`, which the fallback/alt flow then handles.

### L2 grace period blocks both operate and liquidate

In `FluidUsdOracleL2`, the sequencer grace-period check runs before every price method and is not limited to operate mode. If the sequencer is up but still inside the computed grace period, both operate and liquidate reads revert.

## Core Concepts

### Token types

Before a token can be registered in an oracle key, it must be listed with `setTokenType()`:

| Type | Value |
|---|---|
| `PEG` | 1 |
| `STABLE` | 2 |
| `VOLATILE` | 3 |

`registerTransientOracleKey()` reverts if the token is still unlisted.

### Oracle key

Each key config is addressed by:

- `token`
- `eMode`
- `isOperate`
- `isCollateral`

That lets the oracle keep different price configurations for operate vs liquidate and collateral vs debt contexts. If a requested `eMode` config is missing, the read path retries with `eMode = 0`.

### Price modes

Each key config specifies a `priceMode` (MARKET or PEG) that determines which source mapping to read:

- VOLATILE tokens: only MARKET mode is valid
- STABLE tokens: MARKET mode reads from `_tokenSources`; PEG mode returns constant `$1` (`ORACLE_PRECISION`) with no source reads
- PEG tokens: both PEG and MARKET modes are valid; PEG mode reads from `_tokenSources`, MARKET mode reads from `_additionalTokenSources`

### Price sources

The read path supports up to 3 multiplicative sources:

| Type | Meaning |
|---|---|
| `SOURCE_CAPPED_RATE` | `IFluidCappedRate` exchange-rate source (requires `centerPrice()`) |
| `SOURCE_CHAINLINK` | Chainlink V3 feed |
| `SOURCE_STABLE` | Hardcoded `$1` (`1e27`) |
| `SOURCE_REDSTONE` | RedStone (same read path as Chainlink) |
| `SOURCE_FLUID_ORACLE` | `IFluidOracleWithDebt` (e.g. CLX; no `centerPrice()`) |

Multipliers are derived and stored internally on config writes:

- Chainlink/Redstone: `27 - feed.decimals()`
- Capped rate / Fluid oracle / stable: `0`

### Caps

**Per-leg source caps:** `setSourceCapMode` chooses `SOURCE_CAP_MIN` (collateral keys) or `SOURCE_CAP_MAX` (debt keys), or `SOURCE_CAP_NONE`. When active, each configured source leg uses its stored `capOperand` (2-decimal USD: `100` = $1.00) as the bound for `min(rate, cap)` or `max(rate, cap)` during composition.

**Overall caps:** `setOverallCap` sets `OVERALL_CAP_NONE`, operand modes (`MIN_OPERAND` / `MAX_OPERAND` vs `overallCapOperand`), or cross-path modes (`MIN_CROSS_PATH` / `MAX_CROSS_PATH`). PEG compares the composed price to the other mapping (requires both `primarySrc` and additional, same as deviation); VOLATILE and STABLE MARKET compare primary to `altSrc`. STABLE PEG keys cannot use CROSS_PATH. Operate CROSS_PATH fail-closes; liquidate skips the cap if the ref is dead. `setPriceMode(PEG)` on STABLE cannot leave a live CROSS_PATH key on an incompatible mode, and `setTokenType` cannot cross the PEG boundary while any key still uses CROSS_PATH, a deviation check, or fallback (STABLE <-> VOLATILE is unrestricted — both read `altSrc`).

### Alt sources

Fallback and deviation are not identical:

- **Fallback** always stays within the selected token+mode mapping and uses that mapping's alt sources.
- **Deviation check** depends on token type:
  - non-PEG tokens: compare the resolved primary mapping against that same mapping's alt sources
  - PEG tokens: compare `_tokenSources.primarySrc` against `_additionalTokenSources.primarySrc`
- **CROSS_PATH** uses that same second composed price as the overall-cap reference. Operate fail-closes. Liquidate: a dead ref skips the cap.

If fallback alt sources exist for the selected source mapping, the oracle enters the alt path:

- it first reads the primary composed price with `doRevert_=false` (returns `0` on any source failure)
- if that resolves to `0`, the code treats the primary as failed
- fallback can then use the selected mapping's alt source (read with `doRevert_=true`)
- deviation checks can compare the appropriate reference price in operate mode only
- internally, `_readSource` and `_readComposedPrice` accept a `doRevert_` flag to control whether they revert or return `0` on failure, avoiding external self-call overhead

Behavior by mode:

| Mode | Primary works | Primary fails / resolves to 0 |
|---|---|---|
| Operate + deviation only | compare to the configured deviation reference, may revert | revert |
| Operate + fallback only | return primary | use selected mapping alt |
| Operate + deviation + fallback | compare to the configured deviation reference, may revert | revert |
| Liquidate + fallback off | return primary | revert |
| Liquidate + fallback on | return primary | use selected mapping alt |

## L2 Sequencer Check

`FluidUsdOracleL2` uses a Chainlink sequencer uptime feed and enforces:

| Sequencer state | Effect |
|---|---|
| Down | all `getPrice()` calls revert |
| Up but within grace period | all `getPrice()` calls revert |
| Up and grace period passed | normal pricing |

The grace period is dynamic:

- outage duration is measured from sequencer-down rounds
- the required wait time equals that outage duration
- it is capped at `45 minutes`

`sequencerL2Data()` exposes the feed address, uptime start, outage start, computed grace period, whether it has passed, and the final "up and valid" boolean.

## Authorization Overview

The admin surface is intentionally split so the most powerful role is only needed for destructive or mutable follow-up actions:

| Role | What it can do | Why |
|---|---|---|
| Governance | Full control: upgrades, guardian management, token listing changes, create/modify/remove source configs, create/modify/remove key configs, all pause controls | Governance is the canonical owner resolved from Liquidity and remains the only role that can always mutate or remove existing config state |
| Team multisig | List **new** tokens (`setTokenType` only when the token is not yet listed), pause operate/liquidate, open a transient key session, create new key configs, and create new token-level source configs **while the token is not yet `FLAG_GOVERNANCE_APPROVED`** | Multisig can help onboard new configuration safely, but cannot mutate existing key/source config state once it already exists, cannot change a token’s type after listing (governance-only), cannot create an eMode≠0 key that would shadow an existing eMode-0 leg once the token is `FLAG_GOVERNANCE_APPROVED`, and cannot write **any** token-level source bucket on an approved token (which would otherwise clear the approval bit and disarm that guard) |
| Guardian | Toggle only the operate pause bit | Guardian is an emergency role with the narrowest possible scope |

## Roles

### Governance

Governance is resolved from the Liquidity contract's admin slot and can:

- upgrade the implementation
- manage guardians
- create, modify, and remove all configs
- set and remove all source configs
- pause operate and liquidate pricing

### Team multisig

The hardcoded team multisig can:

- list tokens with `setTokenType()` only for tokens that are not yet listed. Changing the type of an already-listed token is governance-only, so existing per-key configs cannot silently use the wrong price path after a type change.
- create new source configs (primary, alt, additional, additional alt), but not modify existing ones
- open a transient key session with `registerTransientOracleKey()`
- pause operate and liquidate pricing
- create new key configs only (not modify existing). Exception: after `FLAG_GOVERNANCE_APPROVED`, cannot create eMode≠0 for a `(token, isOperate, isCollateral)` leg that already has eMode 0 (would shadow live fallback). Unapproved tokens may still get more-specific eModes from MS during bootstrap.
- only act on the "new config in this tx" path when `_tIsNewConfig == 1`

### Bootstrap (temporary first-deploy impl)

`FluidUsdOracleBootstrap` / `FluidUsdOracleL2Bootstrap` treat `BOOTSTRAP_ADMIN` as governance while that implementation is live behind the proxy. They also expose a **bootstrap-only** `multicall(bytes[])`:

- callable only by `BOOTSTRAP_ADMIN`
- self-`delegatecall`s each payload so `msg.sender` stays the admin (external Multicall3 would become `msg.sender` and fail auth)
- enables same-tx token listing + `registerTransientOracleKey` + key setters (transient storage)

Upgrade to Final (`FluidUsdOracle` / `FluidUsdOracleL2`) removes both bootstrap privilege and `multicall`. Do not leave Bootstrap live in production.

### Guardians

Guardians are governance-managed addresses (in production, the same **`TEAM_MULTISIG`** set used for other Fluid admin flows) that may call **`setPausedState`** to set the operate pause bit to **on or off**. Any attempt by a guardian to change the liquidate bit reverts. Governance and **`TEAM_MULTISIG`** retain full pause control on both bits.

## Admin Session Pattern

The admin interface mirrors the verify-once model described in Design Goals above:

**Token-level source config methods** (`setSourceConfig`, `setAltSourceConfig`, `setAdditionalSourceConfig`, `setAdditionalAltSourceConfig` and their remove counterparts) take the token address directly and do NOT require a transient admin session. Source feeds are validated at this stage and stored per-token — every key that later references this token+mode inherits the validated sources automatically.

Access intent for token-level source config:

- governance may create, modify, and remove
- team multisig may create a source config only when that specific config slot does not already exist
- governance-only removals keep destructive cleanup and follow-up changes on the strongest role

**Per-key admin methods** use the transient session:

1. call `registerTransientOracleKey()` — the key tuple is confirmed once
2. call `setPriceMode(priceMode)` — references the already-stored token sources by mode, no feed addresses needed
3. call any combination of `setSourceCapMode`, `setOverallCap`, `enableDeviationCheck`, `enableFallback`, etc. — all operate on the same registered key

Access intent for the transient key session:

- `setPriceMode()` is the create-vs-modify gate: governance may create or update, multisig may create only
- if multisig creates a new key config, `_tIsNewConfig` is set to `1`
- when creating, multisig cannot add eMode≠0 that would intercept eMode-0 fallback for the same operate/collateral leg if `FLAG_GOVERNANCE_APPROVED` is set (approved token = eMode-0 fallback treated as live for create-only purposes)
- `setSourceCapMode`, `setOverallCap`, `enableDeviationCheck`, `disableDeviationCheck`, `enableFallback`, and `disableFallback` all reuse that flag through `onlyGovernanceOrMSNewConfig`
- this means multisig follow-up actions are limited to the same transaction and only for a freshly created key config
- `enableDeviationCheck()` enforces different prerequisites by token type:
  - non-PEG: requires alt sources on the resolved mapping
  - PEG: requires both `_tokenSources.primarySrc` and `_additionalTokenSources.primarySrc`, because deviation compares those two primary mappings
- `enableFallback()` always requires alt sources on the resolved mapping, because fallback never jumps across mappings

The key tuple is specified once, the source feeds are never re-specified (they live at the token level), and each call only stores the slim per-key parameters.

`removeConfig()` also clears the registered key immediately after removal.

## Views

Available read methods:

- `getPrice()` — full price with pause/cap/deviation/fallback. Intended for DexV2 and MoneyMarket.
- `getPriceView()` — explicit view-only variant of `getPrice()` for read-only consumers.
- `getPriceDetailedView()` — view-only detailed pricing path for vault oracles and other read-only consumers. Reverts with the same errors as `getPriceView()`.
- `getPriceRawForMode()` — (priceRaw, decimals, tokenType) for a given mode. Raw price path with fallback when alt sources are configured, but still no caps or deviation checks. On `FluidUsdOracleL2` it is sequencer-gated.
- `getPriceDetailed()` — (price, decimals, tokenType). Reverts with the same errors as `getPrice()`. Intended for V1 vault wrappers (T1-T4) that need both the price and token decimals.
- `getConfiguredTokenOracles()` — diagnostic view of all key configs for a token
- `isGuardian()` — guardian status check
- `getTokenConfig()` — pause state, token type, decimals

`getConfiguredTokenOracles()` is a diagnostic view, not an "effective getPrice preview":

- it enumerates only configs explicitly present in `configsMap`
- it returns raw source rates and raw composed primary/alt prices
- it does not apply source or overall caps to those reported `price` fields
- it does not resolve the effective deviation/fallback decision
- any failed per-source read is shown as `0`

`primary` / `alt` hold whichever mapping the row's `priceMode` resolves to. `additionalPrimary` / `additionalAlt` always hold `_additionalTokenSources` (market price for PEG tokens), zero when unset — these are reported for every row because `OVERALL_CAP_MIN/MAX_CROSS_PATH` reads them on PEG-mode keys, which never resolve `primary` to that mapping.

`IUSDOracle` intentionally keeps `getPrice()` / `getPriceDetailed()` non-view for future flexibility. `getPriceView()` and `getPriceDetailedView()` are the explicit read-only entrypoints for vault/common and other view-only consumers.

## File Layout

```text
contracts/oracleV2/usdOracle/
  README.md
  SPEC.md
  default-oracle-configs.md
  main.sol
  mainL2.sol
  proxy.sol
  structs.sol
  variables.sol
  events.sol
  error.sol
  errorTypes.sol
  sourceReaders/
    chainlinkSourceReader.sol
    fluidSourceReader.sol  # `_readFluidSource` / `_readFluidSourceWrite` for SOURCE_CAPPED_RATE + SOURCE_FLUID_ORACLE
```
