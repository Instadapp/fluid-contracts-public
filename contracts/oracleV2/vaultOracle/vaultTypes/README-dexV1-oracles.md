# Dex V1 oracles vs Vault Oracle V2 (T2–T4)

How legacy **Dex V1** smart-col/debt oracles relate to **`DexShareResolver`** + **`FluidUsdOracle`**, and why we do not port **PEX** into V2 for the pools we care about.

---

## What V2 does

[`DexShareResolver`](../../common/dexShareResolver.sol) reads **token0 / token1 amounts from Liquidity** (internal accounting, not `balanceOf`), prices each token with `getPriceDetailedView`, then:

`totalUsd = r0 * P0 + r1 * P1` → divide by supply or borrow shares.

`isOperate` and `isCollateral` are forwarded on each token price call.



## Peg buffer (V1 parity)

Optional **parts-per-million** buffer on reserve amounts before USD pricing: collateral leg `(1e6 - b) / 1e6`, debt leg `(1e6 + b) / 1e6`, same as V1 [`DexReservesFromLiquidityPeg`](../../../oracleV1_DEPRECATED/implementations/dex/reserveGetters/reservesFromLiquidityPeg.sol). **Vault oracles (T2–T4)** read per-oracle immutables from **`VaultOracleBase`**, chosen per vault at `registerVault` time (Polygon rollout default: **0.1%** operate, **0.02%** liquidate). **`DexShareResolver`** still takes `pegBufferPpm` as an argument — pass **`0`** for limit handlers / auth that need the true reserve split without a safety margin.

---

## V1 in two lines

| | Reserves | Why |
|---|---|---|
| **Peg** (wstETH/ETH, stables) | **Raw** from Liquidity (+ optional peg buffer) | Combine with a **conversion price** (Fluid oracle or ~1:1). |
| **Volatile** (e.g. ETH/USDC) | **PEX** ([`reservesFromPEX`](../../../oracleV1_DEPRECATED/implementations/dex/reserveGetters/reservesFromPEX.sol)) | Re-split reserves on the AMM curve at **Chainlink** so one quote leg matches the external price when Dex and oracle disagree. |

PEX is **not** for donation attacks — Liquidity balances are ledgered, not `balanceOf`.

---

## Why we skip volatile PEX in V2

- Production smart col/debt is **peg pools**; new **volatile** Dex V1 pools are **not** expected.
- Re-implementing PEX would pull full curve + PEX reads into the hot path for a rare case.

If a volatile pool were ever wired to V2 vaults, treat valuation vs V1 as a **known trade-off** or add a dedicated path.

---

## Peg pools: V2 ≈ V1 peg math (no PEX)

V1: `ethEq = ethAmt + wstAmt * conversionRate` (then debt bridge, etc.).

V2: `totalUsd = ethAmt * P(ETH) + wstAmt * P(wstETH)` with `P(wstETH)` consistent with the same rate — same economics, two USD legs instead of one conversion price.

V1 peg path also uses **raw** reserves, not PEX.

---

## Depeg on a **concentrated peg** pool — why this is not “volatile PEX”

Peg pools use **tight ranges**. When the market depegs, trading pushes the pool to the **range edge** until reserves are **essentially all one token** (e.g. almost only wstETH).

After that:

- **Reserves stop changing** in the Dex — even if the market depegs another 5%, 50%, or 90%, the **Liquidity-layer amounts stay stuck** at that one-sided position.
- So there is **no ongoing “wrong split”** to fix by re-projecting reserves at a live external price, the way volatile PEX does when Dex price and Chainlink diverge **while reserves still sit mid-curve**.
- The meaningful knob is **which price you use for that token** (market vs peg on `FluidUsdOracle` keys), not re-balancing reserve amounts to match a spot price.

So peg-based Dex share pricing does **not** need volatile-style PEX handling: once one-sided, **raw reserves already are the pool state**; adjusting ratios “to actual price” does not apply the same way it does for a wide-range volatile pool.

---

## Market vs peg (USD oracle)

`PRICE_MODE_MARKET` vs `PRICE_MODE_PEG` is set per **token key** on `FluidUsdOracle` (operate vs liquidate, collateral vs debt). Typical pattern: **market** on operate, **peg** on liquidate for LST-like assets — that is **price policy**, not reserve re-splitting.

---

## Quick reference

| | V1 | V2 |
|---|---|---|
| Reserves | Liquidity accounting | Same |
| Volatile + oracle/Dex mismatch | PEX re-split | Not in scope |
| Peg (wstETH/ETH, stables) | Raw + conversion (+ buffer) | Raw + USD per token; **vault oracles** apply fixed operate/liquidate ppm from `VaultOracleBase`; **limit handlers** pass `0` |

**Files:** [`dexShareResolver.sol`](../../common/dexShareResolver.sol) · V1 peg [`dexSmartColPegOracle.sol`](../../../oracleV1_DEPRECATED/oracles/dex/dexSmartColPegOracle.sol) · V1 volatile [`dexSmartColCLOracle.sol`](../../../oracleV1_DEPRECATED/oracles/dex/dexSmartColCLOracle.sol) · [`reservesFromPEX.sol`](../../../oracleV1_DEPRECATED/implementations/dex/reserveGetters/reservesFromPEX.sol) · [`dexOracleBase.sol`](../../../oracleV1_DEPRECATED/implementations/dex/dexOracleBase.sol) (`_getDexReservesCombinedInQuoteToken`)
