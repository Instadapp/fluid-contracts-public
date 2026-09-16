# Oracle V2 — Default Config Reference

Internal guide for choosing oracle key configurations when setting up new vaults.
Every vault creates oracle configs for its collateral token and debt token across four contexts:
`(isOperate=true, isCollateral=true)`, `(isOperate=true, isCollateral=false)`,
`(isOperate=false, isCollateral=true)`, `(isOperate=false, isCollateral=false)`.

---

## 1. Token Type Classification

Each token is assigned one of three oracle token types. The type is set per token
via `setTokenType` and determines which price paths are available.

**Access:** Governance may list a token or **change** an existing token’s type. The team multisig may only call `setTokenType` for a token that is **not yet listed**; after the first listing, type changes are governance-only. That prevents silent mis-pricing if per-key configs already exist and the type would change how `priceMode` resolves sources.

### VOLATILE — independent USD market price

| Token | Notes                               |
| ----- | ----------------------------------- |
| ETH   | Native token                        |
| WBTC  | BTC on Ethereum (Chainlink BTC/USD) |
| cbBTC | Coinbase BTC (Chainlink BTC/USD)    |
| PAXG  | Gold (Chainlink XAU/USD)            |
| XAUt  | Gold (Chainlink XAU/USD)            |

### STABLE — USD-pegged ($1 constant peg)

| Token | Notes        |
| ----- | ------------ |
| USDC  | Fiat-backed  |
| USDT  | Fiat-backed  |
| GHO   | Aave GHO     |
| USDe  | Ethena USDe  |
| USDtb | Ethena USDtb |
| reUSD | Resolv reUSD |

### PEG — tracks a reference asset via exchange rate

#### ETH-pegged

| Token  | Peg chain example                                        | Notes              |
| ------ | -------------------------------------------------------- | ------------------ |
| wstETH | wstETH/stETH → stETH/ETH → ETH/USD                       | Lido wrapped stETH |
| weETH  | weETH/eETH → eETH/ETH → ETH/USD (or weETH/ETH → ETH/USD) | ether.fi           |
| weETHs | same pattern as weETH                                    | Symbiotic variant  |
| rsETH  | rsETH/ETH → ETH/USD                                      | Kelp               |
| ezETH  | ezETH/ETH → ETH/USD                                      | Renzo              |
| osETH  | osETH/ETH → ETH/USD                                      | StakeWise          |
| mETH   | mETH/ETH → ETH/USD                                       | Mantle             |

#### USD-pegged (yield-bearing)

| Token     | Peg chain example                         | Notes              |
| --------- | ----------------------------------------- | ------------------ |
| sUSDe     | sUSDe/USDe (exchange rate) → USDe/USD     | Staked USDe        |
| sUSDS     | sUSDS/USDS (exchange rate) → USDS/USD     | Sky savings        |
| syrupUSDC | syrupUSDC/USDC (exchange rate) → USDC/USD | Maple              |
| syrupUSDT | syrupUSDT/USDT (exchange rate) → USDT/USD | Maple              |
| wstUSR    | wstUSR/USR (exchange rate) → USR/USD      | Wrapped staked USR |

#### BTC-pegged

| Token | Peg chain example                  | Notes         |
| ----- | ---------------------------------- | ------------- |
| eBTC  | eBTC/BTC (contract rate) → BTC/USD | ether.fi eBTC |
| LBTC  | LBTC/BTC (contract rate) → BTC/USD | Lombard       |
| tBTC  | tBTC/BTC (contract rate) → BTC/USD | Threshold     |

---

## 2. General Cap Direction Rules

The cap direction is determined by which side the token sits on. The goal is always
protocol safety: **don't overvalue collateral, don't undervalue debt.**

| Side                               | Goal           | sourceCapMode    | overallCapMode direction        |
| ---------------------------------- | -------------- | ---------------- | ------------------------------- |
| **Collateral** (isCollateral=true) | Minimize value | `SOURCE_CAP_MIN` | `MIN_*` (cross-path or operand) |
| **Debt** (isCollateral=false)      | Maximize value | `SOURCE_CAP_MAX` | `MAX_*` (cross-path or operand) |

These directions apply identically to both operate and liquidate modes.

On-chain, `setSourceCapMode` and `setOverallCap` enforce the same MIN/collateral and MAX/debt pairing (`UsdOracle__InvalidCapConfig` if misaligned); `SOURCE_CAP_NONE` / `OVERALL_CAP_NONE` remain allowed on any key for clearing.

### Operate vs Liquidate differences

| Setting         | Operate                                                                                            | Liquidate                                                                                |
| --------------- | -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Deviation check | **Off by default** (optional: e.g. 200 BPS via `enableDeviationCheck` when a second source exists) | **Off** (never enable on liquidate keys — liquidations must not be blocked by deviation) |
| Fallback        | **Off by default** (optional: `enableFallback` when an alt source chain is configured)             | Same                                                                                     |
| Caps            | Applied                                                                                            | Applied (same direction as operate)                                                      |

---

## 3. Default Configs by Token Type

### VOLATILE tokens

No caps needed. Market price is used as-is.

| Config                | priceMode | sourceCapMode | overallCapMode | overallCapOperand | deviation | fallback |
| --------------------- | --------- | ------------- | -------------- | ----------------- | --------- | -------- |
| Operate, Collateral   | MARKET    | NONE          | NONE           | 0                 | optional  | optional |
| Operate, Debt         | MARKET    | NONE          | NONE           | 0                 | optional  | optional |
| Liquidate, Collateral | MARKET    | NONE          | NONE           | 0                 | optional  | optional |
| Liquidate, Debt       | MARKET    | NONE          | NONE           | 0                 | optional  | optional |

**Deviation / fallback / CROSS_PATH:** **Optional**. Enable deviation only when a second source exists for comparison; enable fallback only when an alt chain is configured. Dual-feed VOLATILE min/max vs `altSrc` (ETH CL vs RS) is **not** launch default — `volatileKeysEMode0()` stays uncapped. That setup is Phase F2.

**Source setup:** Single source chain (e.g., ETH/USD Chainlink). Dual USD feeds go on primary + alt. No per-leg capOperands.

### STABLE tokens

**Operate:** Market price with operand caps against $1 (depeg-aware).

**Liquidate:** `PRICE_MODE_PEG` — constant **$1** (`ORACLE_PRECISION`). No per-leg caps and no
`overallCap*` needed; the contract short-circuits to $1 for `TOKEN_TYPE_STABLE` + PEG (no oracle
source reads on the hot path).

| Config                | priceMode | sourceCapMode | overallCapMode | overallCapOperand | deviation      | fallback      |
| --------------------- | --------- | ------------- | -------------- | ----------------- | -------------- | ------------- |
| Operate, Collateral   | MARKET    | NONE          | MIN_OPERAND    | 100               | off (optional) | no (optional) |
| Operate, Debt         | MARKET    | NONE          | MAX_OPERAND    | 100               | off (optional) | no (optional) |
| Liquidate, Collateral | **PEG**   | NONE          | NONE           | 0                 | off            | **no**        |
| Liquidate, Debt       | **PEG**   | NONE          | NONE           | 0                 | off            | **no**        |

**Fallback (liquidate + PEG on STABLE):** Leave disabled. Price is fixed at $1 with no source chain, so fallback does not apply.

**Source setup (operate only):** Configure a market source chain (e.g., USDC/USD Chainlink) so
`PRICE_MODE_MARKET` resolves. **Liquidate + PEG** does not use those sources for pricing (constant $1).

**What the caps do (operate, MARKET mode):**

- Collateral: `min(marketPrice, $1)` — if stable trades above $1, cap at $1. Depeg below $1 uses market.
- Debt: `max(marketPrice, $1)` — if stable depegs below $1, floor at $1. Above $1 uses market.

**Liquidate + PEG:** Price is always exactly $1; caps are not applicable.

### PEG tokens — collateral side

Per-leg caps on relevant legs + cross-path cap comparing peg and market prices.

| Config    | priceMode | sourceCapMode | overallCapMode | overallCapOperand | deviation      | fallback      |
| --------- | --------- | ------------- | -------------- | ----------------- | -------------- | ------------- |
| Operate   | PEG       | MIN           | MIN_CROSS_PATH | 0                 | off (optional) | no (optional) |
| Liquidate | PEG       | MIN           | MIN_CROSS_PATH | 0                 | off            | no (optional) |

**What this does:**

1. Per-leg MIN caps: each leg in the peg source chain is capped at `min(rate, capOperand)`.
   Only legs with `capOperand > 0` are affected.
2. Cross-path MIN: `min(pegPrice, marketPrice)` — use whichever is lower.
3. Deviation check (operate only, optional): when enabled, compares peg path vs market path (e.g. within 2%).

### PEG tokens — debt side

| Config    | priceMode | sourceCapMode | overallCapMode | overallCapOperand | deviation      | fallback      |
| --------- | --------- | ------------- | -------------- | ----------------- | -------------- | ------------- |
| Operate   | PEG       | MAX           | MAX_CROSS_PATH | 0                 | off (optional) | no (optional) |
| Liquidate | PEG       | MAX           | MAX_CROSS_PATH | 0                 | off            | no (optional) |

**What this does:**

1. Per-leg MAX caps: each leg is floored at `max(rate, capOperand)`.
2. Cross-path MAX: `max(pegPrice, marketPrice)` — use whichever is higher.

### PEG tokens — per-leg capOperand examples

Per-leg caps only affect legs with `capOperand > 0`. Set `capOperand = 0` on legs that
should NOT be capped (e.g., growing exchange rates, volatile USD price legs).

#### ETH-pegged (e.g., wstETH), 3-leg peg chain

| Leg | Source                             | capOperand | Rationale                        |
| --- | ---------------------------------- | ---------- | -------------------------------- |
| 1   | wstETH/stETH (capped rate, ~1.17+) | 0          | Growing exchange rate, don't cap |
| 2   | stETH/ETH (Chainlink, ~1.00)       | 100        | Should be ~1:1, cap at 1.00      |
| 3   | ETH/USD (Chainlink, volatile)      | 0          | Free-floating, don't cap         |

With `SOURCE_CAP_MIN` (collateral): stETH/ETH ≤ 1.00 → stETH never valued above 1 ETH.
With `SOURCE_CAP_MAX` (debt): stETH/ETH ≥ 1.00 → stETH never valued below 1 ETH.

#### ETH-pegged (e.g., wstETH), 2-leg peg chain

| Leg | Source                                | capOperand | Rationale                     |
| --- | ------------------------------------- | ---------- | ----------------------------- |
| 1   | wstETH/ETH (capped rate or Chainlink) | 0          | Full exchange rate, don't cap |
| 2   | ETH/USD (Chainlink)                   | 0          | Free-floating, don't cap      |

No per-leg caps apply here — rely on `MIN/MAX_CROSS_PATH` overall cap to compare
the composed peg price against the independent market price.

#### USD-pegged yield (e.g., sUSDe), 2-leg peg chain

| Leg | Source                          | capOperand | Rationale                        |
| --- | ------------------------------- | ---------- | -------------------------------- |
| 1   | sUSDe/USDe (capped rate, ~1.1+) | 0          | Growing exchange rate, don't cap |
| 2   | USDe/USD (Chainlink, ~1.00)     | 100        | Should be ~$1, cap at 1.00       |

With `SOURCE_CAP_MIN` (collateral): USDe/USD ≤ $1.00 during peg composition.
With `SOURCE_CAP_MAX` (debt): USDe/USD ≥ $1.00 during peg composition.

#### BTC-pegged (e.g., eBTC), 2-leg peg chain

| Leg | Source                          | capOperand | Rationale                   |
| --- | ------------------------------- | ---------- | --------------------------- |
| 1   | eBTC/BTC (contract rate, ~1.00) | 100        | Should be ~1:1, cap at 1.00 |
| 2   | BTC/USD (Chainlink, volatile)   | 0          | Free-floating, don't cap    |

---

## 4. Vault Combination Matrix

All possible collateral/debt token type combinations and which config rules to apply.

### Existing mainnet combinations

| #   | Collateral type | Debt type       | Example vaults                                             |
| --- | --------------- | --------------- | ---------------------------------------------------------- |
| 1   | VOLATILE        | STABLE          | ETH/USDC, WBTC/USDT, cbBTC/GHO, PAXG/USDC, XAUt/GHO        |
| 2   | STABLE          | VOLATILE        | USDC/ETH, USDC/WBTC, USDC/cbBTC                            |
| 3   | STABLE          | STABLE          | USDe/USDC, USDe/USDT, USDe/GHO                             |
| 4   | PEG             | STABLE          | wstETH/USDC, weETH/GHO, sUSDe/USDC, mETH/USDT, eBTC/GHO... |
| 5   | PEG             | VOLATILE        | wstETH/WBTC, weETH/cbBTC, wstETH/cbBTC                     |
| 6   | PEG             | PEG (same base) | weETH/wstETH, weETHs/wstETH, ezETH/wstETH, rsETH/wstETH    |
| 7   | PEG             | PEG (diff base) | wstETH/sUSDS, weETH/sUSDS                                  |
| 8   | VOLATILE        | PEG             | ETH/sUSDS, cbBTC/sUSDS                                     |
| 9   | VOLATILE        | VOLATILE        | ETH/WBTC, WBTC/ETH, cbBTC/ETH, ETH/cbBTC                   |

### Config summary per combination

#### 1. VOLATILE collateral / STABLE debt

| Token side            | priceMode                     | sourceCapMode | overallCap                              | deviation (operate) |
| --------------------- | ----------------------------- | ------------- | --------------------------------------- | ------------------- |
| Collateral (VOLATILE) | MARKET                        | NONE          | NONE                                    | optional            |
| Debt (STABLE)         | MARKET / **PEG on liquidate** | NONE          | MAX_OPERAND(100) op.; none on liquidate | optional            |

Debt STABLE: operate = MARKET + `MAX_OPERAND(100)`; liquidate = **PEG** ($1), no caps.

#### 2. STABLE collateral / VOLATILE debt

| Token side          | priceMode                     | sourceCapMode | overallCap                              | deviation (operate) |
| ------------------- | ----------------------------- | ------------- | --------------------------------------- | ------------------- |
| Collateral (STABLE) | MARKET / **PEG on liquidate** | NONE          | MIN_OPERAND(100) op.; none on liquidate | optional            |
| Debt (VOLATILE)     | MARKET                        | NONE          | NONE                                    | optional            |

Collateral STABLE: operate = MARKET + `MIN_OPERAND(100)`; liquidate = **PEG** ($1), no caps.

#### 3. STABLE collateral / STABLE debt

| Token side          | priceMode                     | sourceCapMode | overallCap                              | deviation (operate) |
| ------------------- | ----------------------------- | ------------- | --------------------------------------- | ------------------- |
| Collateral (STABLE) | MARKET / **PEG on liquidate** | NONE          | MIN_OPERAND(100) op.; none on liquidate | optional            |
| Debt (STABLE)       | MARKET / **PEG on liquidate** | NONE          | MAX_OPERAND(100) op.; none on liquidate | optional            |

Both sides: liquidate keys use **PEG** ($1), no operand caps.

#### 4. PEG collateral / STABLE debt

| Token side       | priceMode                     | sourceCapMode | overallCap                              | deviation (operate) |
| ---------------- | ----------------------------- | ------------- | --------------------------------------- | ------------------- |
| Collateral (PEG) | PEG                           | MIN           | MIN_CROSS_PATH                          | optional            |
| Debt (STABLE)    | MARKET / **PEG on liquidate** | NONE          | MAX_OPERAND(100) op.; none on liquidate | optional            |

#### 5. PEG collateral / VOLATILE debt

| Token side       | priceMode | sourceCapMode | overallCap     | deviation (operate) |
| ---------------- | --------- | ------------- | -------------- | ------------------- |
| Collateral (PEG) | PEG       | MIN           | MIN_CROSS_PATH | optional            |
| Debt (VOLATILE)  | MARKET    | NONE          | NONE           | optional            |

#### 6. PEG collateral / PEG debt (same base, e.g., both ETH-pegged)

| Token side       | priceMode | sourceCapMode | overallCap     | deviation (operate) |
| ---------------- | --------- | ------------- | -------------- | ------------------- |
| Collateral (PEG) | PEG       | MIN           | MIN_CROSS_PATH | optional            |
| Debt (PEG)       | PEG       | MAX           | MAX_CROSS_PATH | optional            |

#### 7. PEG collateral / PEG debt (different base, e.g., ETH-pegged / USD-pegged)

Same as #6. Each token's cap is independent (each has its own peg/market paths).

| Token side       | priceMode | sourceCapMode | overallCap     | deviation (operate) |
| ---------------- | --------- | ------------- | -------------- | ------------------- |
| Collateral (PEG) | PEG       | MIN           | MIN_CROSS_PATH | optional            |
| Debt (PEG)       | PEG       | MAX           | MAX_CROSS_PATH | optional            |

#### 8. VOLATILE collateral / PEG debt

| Token side            | priceMode | sourceCapMode | overallCap     | deviation (operate) |
| --------------------- | --------- | ------------- | -------------- | ------------------- |
| Collateral (VOLATILE) | MARKET    | NONE          | NONE           | optional            |
| Debt (PEG)            | PEG       | MAX           | MAX_CROSS_PATH | optional            |

#### 9. VOLATILE collateral / VOLATILE debt

| Token side            | priceMode | sourceCapMode | overallCap | deviation (operate) |
| --------------------- | --------- | ------------- | ---------- | ------------------- |
| Collateral (VOLATILE) | MARKET    | NONE          | NONE       | optional            |
| Debt (VOLATILE)       | MARKET    | NONE          | NONE       | optional            |

---

## 5. Complete Config Expansion (all 4 keys)

Expanding the full 4-key config for each token type on each side.

### VOLATILE on any side

```
Operate, Collateral:  priceMode=MARKET  sourceCapMode=NONE  overallCap=NONE  deviation=optional  fallback=optional
Operate, Debt:        priceMode=MARKET  sourceCapMode=NONE  overallCap=NONE  deviation=optional  fallback=optional
Liquidate, Collateral: priceMode=MARKET  sourceCapMode=NONE  overallCap=NONE  deviation=optional  fallback=optional
Liquidate, Debt:       priceMode=MARKET  sourceCapMode=NONE  overallCap=NONE  deviation=optional  fallback=optional
```

### STABLE on collateral side

```
Operate, Collateral:   priceMode=MARKET  sourceCapMode=NONE  overallCap=MIN_OPERAND(100)  deviation=off (opt.)  fallback=no (opt.)
Liquidate, Collateral: priceMode=PEG     sourceCapMode=NONE  overallCap=NONE              deviation=off           fallback=no
```

### STABLE on debt side

```
Operate, Debt:    priceMode=MARKET  sourceCapMode=NONE  overallCap=MAX_OPERAND(100)  deviation=off (opt.)  fallback=no (opt.)
Liquidate, Debt:  priceMode=PEG     sourceCapMode=NONE  overallCap=NONE              deviation=off           fallback=no
```

### PEG on collateral side

```
Operate, Collateral:   priceMode=PEG  sourceCapMode=MIN  overallCap=MIN_CROSS_PATH  deviation=off (opt.)  fallback=no (opt.)
Liquidate, Collateral: priceMode=PEG  sourceCapMode=MIN  overallCap=MIN_CROSS_PATH  deviation=off  fallback=no (opt.)
```

### PEG on debt side

```
Operate, Debt:    priceMode=PEG  sourceCapMode=MAX  overallCap=MAX_CROSS_PATH  deviation=off (opt.)  fallback=no (opt.)
Liquidate, Debt:  priceMode=PEG  sourceCapMode=MAX  overallCap=MAX_CROSS_PATH  deviation=off  fallback=no (opt.)
```

---

## 6. Capability Verification

Checking that the Oracle V2 cap system covers every case above.

### STABLE token caps (MIN/MAX_OPERAND) and liquidate PEG

- **Operate + MARKET:** `OVERALL_CAP_MIN_OPERAND` / `MAX_OPERAND` with `overallCapOperand=100` implements min/max vs $1 on the market price. ✓
- **Liquidate + PEG:** For `TOKEN_TYPE_STABLE`, `PRICE_MODE_PEG` returns constant $1 (`ORACLE_PRECISION`) with no operand caps and no source reads on that path. ✓

### PEG token per-leg caps (SOURCE_CAP_MIN/MAX)

- `SOURCE_CAP_MIN` + `capOperand=100` on a "should be 1:1" leg (e.g., stETH/ETH):
  applies `min(rate, 1.00 * 1e25)` during composition. ✓
- `SOURCE_CAP_MAX` + `capOperand=100` on same leg:
  applies `max(rate, 1.00 * 1e25)` during composition. ✓
- Legs with `capOperand=0` are unaffected. ✓
- Applied per-leg during `_readComposedPrice`, before the final price is assembled. ✓

### PEG token cross-path caps (MIN/MAX_CROSS_PATH)

- `OVERALL_CAP_MIN_CROSS_PATH`: `min(pegPrice, marketPrice)`. ✓
- `OVERALL_CAP_MAX_CROSS_PATH`: `max(pegPrice, marketPrice)`. ✓
- Reference price (the other path) is read once in `_getPriceWithAlt` and reused
  for both deviation check and cross-path cap — no duplicate reads. ✓

### VOLATILE / STABLE MARKET cross-path caps (MIN/MAX_CROSS_PATH)

- Same modes vs `altSrc` (primary vs alt USD feeds). ✓
- `setOverallCap` requires `FLAG_HAS_ALT_SOURCE`. STABLE PEG keys are rejected (constant `$1` skips overall cap). ✓
- PEG MARKET CROSS_PATH requires `primarySrc` (the ref); PEG PEG-mode requires additional. `setPriceMode(PEG)` on STABLE while CROSS_PATH is live reverts; `setTokenType` under live CROSS_PATH reverts `UsdOracle__CrossPathMustBeDisabled`. ✓
- Removing alt / primary sources while any key still has CROSS_PATH reverts `UsdOracle__CrossPathMustBeDisabled`. ✓
- A dead CROSS_PATH ref **reverts operate** (`doRevert_=true`). **Liquidate** reads the ref soft and skips the cap if it is `0` (primary stands).

### Deviation check

- Optional per-key via `enableDeviationCheck` / `maxDeviationBPS`. Only active for `isOperate=true`.
- For PEG tokens: compares peg path vs market path (cross-mapping comparison). ✓
- For non-PEG tokens: compares primary vs alt source chain (same-mapping comparison). ✓
- Deviation check reads the reference with the same `capDirection_` as the primary for
  consistent comparison. ✓

### Fallback

- Optional per-key via `enableFallback` (`KEY_FLAG_FALLBACK`).
- Falls back to alt source chain within the same mapping when primary fails. ✓
- After fallback, overall cap is still applied. ✓

### Edge cases covered

| Scenario                                                                  | How it works                                                                                        |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| STABLE depeg below $1 (collateral, operate)                               | `MIN_OPERAND(100)` on MARKET: market price < $1, market used → collateral devalued → protective ✓   |
| STABLE depeg below $1 (debt, operate)                                     | `MAX_OPERAND(100)` on MARKET: market price < $1, $1 used → debt not undervalued → protective ✓      |
| STABLE above $1 (collateral, operate)                                     | `MIN_OPERAND(100)`: market price > $1, $1 used → collateral not overvalued → protective ✓           |
| STABLE (liquidate)                                                        | PEG mode → always $1; depeg nuance applies on operate keys, not liquidate ✓                         |
| PEG token (e.g., stETH) depegs from ETH (collateral)                      | Per-leg MIN caps stETH/ETH ≤ 1.00; cross-path MIN picks lower of peg/market → protective ✓          |
| PEG token oracle has only a direct feed (2 legs, no decomposed stETH/ETH) | Per-leg caps don't apply (capOperand=0); cross-path MIN still compares peg vs market → protective ✓ |
| PEG token on debt side during depeg                                       | Per-leg MAX floors stETH/ETH ≥ 1.00; cross-path MAX picks higher of peg/market → protective ✓       |
| Two PEG tokens in same vault (weETH/wstETH)                               | Each token has independent config; collateral gets MIN caps, debt gets MAX caps → protective ✓      |
| VOLATILE/VOLATILE vault (ETH/WBTC)                                        | No caps on either side by default; market prices only. Deviation / fallback / CROSS_PATH vs alt optional when a second USD feed is configured ✓ |
| VOLATILE dual USD feeds (CL vs RS)                                        | Capability exists (CROSS_PATH vs `altSrc`). Launch keys stay uncapped (`volatileKeysEMode0`). Min/max + fallback is Phase F2 ✓ |

---

## 7. DEX LP Tokens (T2/T3/T4 vaults)

DEX LP tokens are composite tokens representing shares of a liquidity pool.
They follow the same classification based on their underlying composition:

| DEX pool type           | Token type | Examples                                            |
| ----------------------- | ---------- | --------------------------------------------------- |
| Stable/Stable           | STABLE     | DEX-USDC-USDT, DEX-GHO-USDC, DEX-USDe-USDT          |
| PEG/Volatile (ETH LSTs) | PEG        | DEX-wstETH-ETH, DEX-weETH-ETH, DEX-rsETH-ETH        |
| PEG/PEG (BTC)           | PEG        | DEX-WBTC-cbBTC, DEX-LBTC-cbBTC, DEX-eBTC-cbBTC      |
| PEG/Stable (yield)      | PEG        | DEX-sUSDe-USDT, DEX-syrupUSDC-USDC, DEX-wstUSR-USDC |
| Gold/Gold               | PEG        | DEX-PAXG-XAUt                                       |
| Volatile/Stable         | Composite  | DEX-USDC-ETH, DEX-cbBTC-USDT                        |

DEX tokens use the same oracle key config patterns as their effective type.
The pricing mechanism (DEX oracle) provides the source feeds; the cap configuration
follows the rules above based on which side the DEX token sits on.

---

## 8. Quick Reference

When creating a new oracle config, determine:

1. **Token type** → look up in Section 1
2. **Which side** → collateral or debt in the vault
3. **Apply the defaults** → from Section 3/5

| Token type | Collateral side                                                      | Debt side                                                            |
| ---------- | -------------------------------------------------------------------- | -------------------------------------------------------------------- |
| VOLATILE   | MARKET, no caps                                                      | MARKET, no caps                                                      |
| STABLE     | Operate: MARKET + MIN_OPERAND(100). Liquidate: **PEG** ($1), no caps | Operate: MARKET + MAX_OPERAND(100). Liquidate: **PEG** ($1), no caps |
| PEG        | PEG, SOURCE_CAP_MIN, MIN_CROSS_PATH                                  | PEG, SOURCE_CAP_MAX, MAX_CROSS_PATH                                  |

Deviation: off by default; optional on operate keys (e.g. 200 BPS) when a second source exists. Never on liquidate keys. Fallback: off by default; optional when alt sources exist.
