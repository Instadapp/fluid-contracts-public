# Libraries — TickMath SPEC

## 1. Purpose

`TickMath` converts between two representations of price used across the Fluid Vault protocol:

- **tick** — a signed integer in the range `[-32767, 32767]`; a slot on a logarithmic price grid with a fixed step of `1.0015` per tick (15 bps). The vault tick/branch liquidation engine organises positions on these ticks.
- **ratioX96** — a `uint256` Q64.96 fixed-point number equal to `(1.0015 ^ tick) * 2^96`, representing `debtAmount / collateralAmount` (i.e. price in debt units per collateral unit).

The library exposes two pure functions:

- `getRatioAtTick(int tick) → uint256 ratioX96`
- `getTickAtRatio(uint256 ratioX96) → (int tick, uint perfectRatioX96)` — inverse mapping, rounded toward negative infinity, also returning the ratio at the returned tick (reconstructed from the residual, see §5) so callers can measure residual error.

## 2. External Interactions

None. Pure assembly math.

## 3. Constants

| Constant | Value | Meaning |
| --- | --- | --- |
| `MIN_TICK` | `-32767` | Smallest supported tick; `1.0015^-32767`. |
| `MAX_TICK` | `32767` | Largest supported tick. |
| `MIN_RATIOX96` | `37075072` | Lowest input `getTickAtRatio` accepts. One above `getRatioAtTick(MIN_TICK)` = `37075071`, so that exact output is rejected. |
| `MAX_RATIOX96` | `169307877264527972847801929085841449095838922544595` | `getRatioAtTick(MAX_TICK)`. |
| `ZERO_TICK_SCALED_RATIO` | `1 << 96` | `getRatioAtTick(0)` = `2^96`. |
| `FACTOR00 .. FACTOR15` | Precomputed `2^128 / 1.0015^(2^i)` | Used as multiply-shift ladder in `getRatioAtTick`. |
| `_1E26` | `1e26` | Precision anchor for `getTickAtRatio` ratio scaling. |

## 4. Methods

### `getRatioAtTick(int tick) pure → ratioX96`

Computes `ratioX96 = 2^96 * 1.0015 ^ tick` using a bit-decomposition of `|tick|` over 15 precomputed factors (one per power-of-2 from 1 through 16384).

- **Bounds check:** aborts via `revert(0, 0)` if `|tick| > MAX_TICK = 32767`. Matches Uniswap-v3-style tick bounds but with the 15-bp step.
- **Positive vs negative tick:** the ladder multiplies `2^128 / 1.0015^(2^i)` constants, so after it `factor_ = 2^128 * 1.0015^-|tick|`. Negative ticks use that directly; non-negative ticks invert via `div(type(uint256).max, factor_)` to get `2^128 * 1.0015^tick`.
- **Precision rounding:** on the non-negative path, when the inverted `factor_` has non-zero bits below the `>> 32` shift, `precision_ = 1` is added to the final `ratioX96`, so the shift rounds up instead of down. Negative ticks are plain truncation. This does **not** make the two functions exact inverses — see §5.
- **Output:** `ratioX96 = (factor_ >> 32) + precision_`. The `>> 32` shift moves from Q64.128 down to Q64.96.

Monotonicity: `getRatioAtTick` is strictly increasing in `tick` over the supported range.

### `getTickAtRatio(uint256 ratioX96) pure → (int tick, uint perfectRatioX96)`

Inverse mapping with **round-toward-negative-infinity** semantics (so a ratio matching 123.23 → tick 123; matching -123.23 → tick -124).

Algorithm (single-bit tick construction):

1. Revert (`revert(0,0)`) if `ratioX96` is outside `[MIN_RATIOX96, MAX_RATIOX96]`.
2. Compute `cond = ratioX96 < ZERO_TICK_SCALED_RATIO`.
3. Normalise `factor_`:
   - if `!cond` (positive tick): `factor_ = ratioX96 * 1e26 / ZERO_TICK_SCALED_RATIO`.
   - else: `factor_ = ZERO_TICK_SCALED_RATIO * 1e26 / ratioX96`.
4. For each power of two from 16384 down to 1, if `factor_ >=` the precomputed threshold for that tick step, set the corresponding bit in `tick` and divide `factor_` by that step's scaled ratio. This constructs `|tick|` bit by bit.
5. Compute `perfectRatioX96`:
   - `!cond`: `perfectRatioX96 = ratioX96 * 1e26 / factor_` (the ratio at the non-negative `tick`, reconstructed from the residual to roughly `1e-26` relative; not bit-identical to `getRatioAtTick(tick)`).
   - `cond`: `tick = not(tick)` (two's-complement negate + -1 for floor semantics), `perfectRatioX96 = ratioX96 * factor_ / 100150000000000000000000000` (the ratio at the negative `tick`, one-tick increment scale applied; same reconstruction caveat).
6. Safety assertion: if `perfectRatioX96 > ratioX96`, revert. Perfect ratio must be ≤ input, enforcing the floor semantics in full.

Returned units:

- `tick` is an `int` in `[-32768, 32767]` (note: `not(0) = -1`; the algorithm can return `MIN_TICK - 1 = -32768` only at the precision boundary — the code still accepts this in the `perfectRatioX96` check, but upstream callers in the vault stay within `[-32767, 32767]`).
- `perfectRatioX96` is `≤ ratioX96` by the safety check.

## 5. Invariants & Safety

- **Tick domain** is `[-32767, 32767]`. Outside → revert. Vault admin validates any user-facing tick inputs.
- **Accuracy of `getRatioAtTick`** (checked against the exact value for every tick): for `tick >= 0` the result is never below the exact value except at 13 ticks where it falls short by under `3e-35` relative, and it exceeds the exact value by at most about `1.0015^tick / 2^128` because the inverted factor keeps fewer significant bits as the tick grows (worst observed `2.9E-26` relative for `tick <= 20000`, `6.1E-18` overall). For `tick < 0` the result is the exact value truncated: never above it, at most one X96 ulp below (under `1e-28` for `|tick| < 1000`, `1.3e-16` at `-20000`, `2.6e-8` at `MIN_TICK`).
- **No exact round-trip.** `getTickAtRatio` resolves tick boundaries in `1e26` fixed point, so its boundaries carry an error of order `1e-26` relative of their own, on top of the `getRatioAtTick` error above. Feeding `getRatioAtTick(t)` back returns `t - 1` for 47,318 of the 65,534 ticks above `MIN_TICK` (for example `100 → 99`, `1000 → 999`, `-1 → -2`), and `getRatioAtTick(MIN_TICK)` itself is rejected as below `MIN_RATIOX96`. Callers must not depend on bit-exact agreement between the two functions or on `perfectRatioX96 == getRatioAtTick(tick)`. The vault does not: it books debt at `perfectRatioX96 * 1.0015` on write (`helpersOperate.sol`, T1 `helpers.sol`) and reads it back with `getRatioAtTick(tick)` after bumping the stored collateral up by one BigNumber quantum and adding 1 wei to the debt (`mainOperate.sol`, T1 `main.sol`). That bump is at least one collateral wei, a relative margin of `1 / collateral`, which exceeds the largest disagreement seen in a sweep of every tick (about `7e-26` relative, write ratio above read ratio) for any collateral below about `1e25` raw units.
- **Rounding direction:** `getTickAtRatio` rounds toward negative infinity, not toward zero. This is the contract the vault relies on for liquidation price comparisons — always conservative in the liquidator's favour on the boundary.
- **`perfectRatioX96 ≤ ratioX96`** is enforced at exit.
- **No overflow:** intermediate multiplications are bounded. The largest intermediate is around `2^128`; squaring factors with `shr(128, mul(...))` keeps the product within `uint256`.
- **Immutable constants:** changing any `FACTORxx` value silently invalidates all vault positions and oracles. Treat as frozen-forever.

## 6. Audit Notes (absorbed)

- Uniswap-v3-style tick math adapted for a 15-bp tick step (vs 0.01% in Uniswap v3). The `precision_ += 1` adjustment on the non-negative path is the accepted Uniswap-style rounding asymmetry between `+N` and `-N`; it does not deliver exact round-trip (§5).
- `getTickAtRatio`'s defensive revert when `perfectRatioX96 > ratioX96` is a belt-and-suspenders check; it is not expected to be reachable in correct inputs, but is kept to prevent silent mispricing on hypothetical rounding edge cases. Per audit review, the belt-and-suspenders revert is accepted as a deliberate trade-off of gas for safety.
- `MIN_RATIOX96` and `MAX_RATIOX96` define the entire on-chain price universe for Fluid vaults. Any oracle or caller feeding a ratio outside that band will revert at `getTickAtRatio`.
- The tick bounds `[-32767, 32767]` correspond to a price range of roughly `1.0015^-32767 ≈ 4.68e-22` to `1.0015^32767 ≈ 2.14e21` of the reference price — enough for any realistic collateral/debt pair in the vault.
