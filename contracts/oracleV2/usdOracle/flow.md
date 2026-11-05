# FluidUsdOracle — price resolution flow

This document describes the runtime flow for **`getPrice()`** / **`getPriceView()`** / the price part of **`getPriceDetailed()`**. It complements [`SPEC.md`](./SPEC.md).

## How to view this file

| Where | Mermaid diagrams |
|--------|------------------|
| **GitHub** | Renders Mermaid in `.md` files in the repo browser, PR descriptions, and issues. |
| **Cursor / VS Code** | Open preview (Markdown preview) — Mermaid often renders via built-in or extension support. |
| **Always works** | Paste the fenced `mermaid` block into [Mermaid Live Editor](https://mermaid.live/). |

If a diagram does not render in your viewer, use the link above.

## Legend

- **`cold SLOAD`** — first read of that storage slot in this call (EVM: first touch can be more expensive).
- **`warm SLOAD`** — same slot read again later in the same call (typically cheaper).
- **`external call`** — Chainlink `latestRoundData()` or Fluid capped-rate getters; **not** an `SLOAD`.
- Passing a **`storage` reference** (e.g. to `_readComposedPrice`) is **not** an `SLOAD` by itself; reads happen when fields are accessed.
- **Slot indices** below are **0-based** (same as EVM storage offsets and `vm.load(base + n)`).

## High-level flow (Mermaid)

GitHub’s Mermaid parser is strict: **do not use backticks or `==` inside node labels** (they cause “Lexical error”). Use plain text; see `SPEC.md` for exact symbol names.

```mermaid
flowchart TD

  A["Start: getPrice(token, eMode, isOperate, isCollateral)"]
  --> B["Load _tokenSources[token] slot 0<br/>cold SLOAD: primarySrc metadata + leg1 fields"]
  --> C{"Paused for this call type?"}

  C -->|yes| C1["Revert TokenPaused"]
  C -->|no| D["Load _configs key exact eMode<br/>cold SLOAD"]

  D --> E{"priceMode unset?"}
  E -->|yes| F["Load _configs key eMode 0 fallback<br/>cold or warm SLOAD"]
  E -->|no| G

  F --> G{"Still no config?"}
  G -->|yes| G1["Revert NoConfig"]
  G -->|no| H{"tokenType and priceMode branch"}

  H -->|STABLE plus PEG mode| H1["Return ORACLE_PRECISION constant"]
  H -->|non-PEG| I["_getResolvedPrice"]
  H -->|PEG| J["_getPegResolvedPrice"]

  subgraph nonPEG["Non-PEG VOLATILE or STABLE market"]
    I --> I0{"alt OR deviation OR fallback OR cross-path cap?"}
    I0 -->|no| I1["Strict _readComposedPrice primary doRevert true<br/>slot 0 warm; slots 1-2 if more legs"]
    I0 -->|yes| I2["_getPriceWithAlt"]

    I1 --> I1a["external calls, caps, return"]

    I2 --> I3["soft primary doRevert false"]
    I3 --> I4{"primary zero?"}
    I4 -->|op dev primary zero| I4a["Revert RateZero"]
    I4 -->|no fallback| I4b["Revert RateZero"]
    I4 -->|fallback but no alt| I4c["Revert AltSourceNotConfigured"]
    I4 -->|fallback with alt| I4d["strict altSrc slots 3-5"]
    I4 -->|primary ok| I5{"operate and deviation on?"}
    I5 -->|no| I6{"cross-path cap on?"}
    I5 -->|yes| I5b["strict alt as deviation ref, compare, caps"]

    I6 -->|no| I6a["caps return"]
    I6 -->|yes operate| I6b["strict ref; zero reverts, else min or max"]
    I6 -->|yes liquidate| I6c["soft ref; zero skips the cap and returns primary"]
  end

  subgraph peg["PEG token"]
    J --> J1{"key priceMode MARKET?"}
    J1 -->|no peg price mode| J2["primary _tokenSources.primarySrc<br/>alt _tokenSources.altSrc<br/>deviation ref _additional.primarySrc"]
    J1 -->|yes market mode| J3["primary _additional.primarySrc<br/>alt _additional.altSrc<br/>deviation ref _tokenSources.primarySrc"]

    J2 --> J4{"no alt dev fallback cross-path?"}
    J3 --> J4
    J4 -->|yes| J5["strict selected primary, caps"]
    J4 -->|no| J6["_getPriceWithAlt cross mapping"]

    J6 --> J7["soft primary then fallback or deviation or cross-path ref"]
  end
```

## Slot layout (reference)

Per-token main storage **`_tokenSources[token]`** (0-based slots; see `structs.sol` / `variables.sol`):

| Slot | Contents (conceptually) |
|------|-------------------------|
| 0 | `primarySrc` leg 1 + metadata (`pauseState`, `tokenType`, `decimals`, `flagsBitmap`) |
| 1 | `primarySrc` leg 2 |
| 2 | `primarySrc` leg 3 |
| 3 | `altSrc` leg 1 + types (metadata bytes zero) |
| 4 | `altSrc` leg 2 |
| 5 | `altSrc` leg 3 |

**`_additionalTokenSources[token]`** uses the same `TokenSourceConfig` shape (`primarySrc` slots 0–2, `altSrc` slots 3–5). Metadata bytes in `primarySrc` slot 0 are **unused** (zero).

Per-key config **`_configs[key]`** is a **single contract slot** (separate from the table above): `priceMode`, caps, `maxDeviationBPS`, `flagsBitmap` (fallback).

## Code entry points

- `_getPriceImpl` — pause, key load, STABLE+PEG fast path, then `_getPegResolvedPrice` or `_getResolvedPrice` (`main.sol`).
- `_getResolvedPrice` / `_getPegResolvedPrice` — choose strict path vs `_getPriceWithAlt`.
- `_getPriceWithAlt` — soft primary, fallback on zero, optional deviation, cross-path reference, caps
  (`main.sol`). The reference leg is read at most once and serves both the deviation check and the
  cross-path cap: `_additionalTokenSources.primarySrc` for PEG, `_tokenSources.altSrc` otherwise.
- `_readComposedPrice` / `_readSource` — storage reads for each `TokenSources` bucket + external oracle calls.

For exact error codes and admin constraints, see [`SPEC.md`](./SPEC.md).
