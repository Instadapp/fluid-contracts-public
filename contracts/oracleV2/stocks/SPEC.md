# Stock oracles — SPEC

## 1. Purpose

Chainlink 24/5 equity feeds × Backed wrapped-xStock multipliers, with a shared US equity market-hours
schedule. `FluidCLXStockOracle` exposes a 1e27 rate through `IFluidOracle`, and is consumed as a price
**source** — like a capped rate — by the vault oracle, which applies any token-decimal adjustment on its
own side. `targetDecimals` is therefore fixed at 27 and the base rejects anything else.

| Path | Spec |
| --- | --- |
| [`usEquityMarketHours/`](./usEquityMarketHours/) — `FluidUsEquityMarketHours` | [`usEquityMarketHours/SPEC.md`](./usEquityMarketHours/SPEC.md) |
| [`clxStockOracle/`](./clxStockOracle/) — `FluidCLXStockOracle` | [`clxStockOracle/SPEC.md`](./clxStockOracle/SPEC.md) |

## 2. Base contract

`FluidCLXStockOracle` extends [`../common/fluidOracle.sol`](../common/fluidOracle.sol), the shared
vault-facing base. `Constants` / `Helpers` take the params struct rather than separate fields, because
reading all nine in the base-constructor list blows the stack at 0.8.36 — as `FluidCappedRate` does.

## 3. Errors

Raised as `FluidStockOracleError(uint errorId)` from [`error.sol`](./error.sol), with IDs in
[`errorTypes.sol`](./errorTypes.sol). The base rejects a `targetDecimals` other
than 27 with `OracleV2CommonError` (`310204`, see [`../common/errorTypes.sol`](../common/errorTypes.sol))
and defers `infoName` length validation to `StringBytes32Utils`.

| ID | Meaning |
| --- | --- |
| `310301` | `UsEquityMarketHours` (invalid week-session params) |
| `310311–310319` | `CLXStockOracle` (params, stale price, invalid price, storage overflow, multiplier needs confirmation, RTH reference not found, paused, scheduled multiplier pending, price gap break) |

## 4. Gas-optimisation tier

Warm path on `operate` / `liquidate` reads; cold path in the constructor and admin setters, where extra
validation is welcome.
