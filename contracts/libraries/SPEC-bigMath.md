# Libraries — BigMath SPEC

## 1. Purpose

Fluid uses custom "big number" encodings to pack large magnitudes into very few bits. The encoding is a coefficient `c` plus exponent `e` such that the represented value is `c << e` (floor-shifted). Storing numbers this way is the key reason Liquidity, DEX, and Vault fit all user-balance / rate / debt-factor state into single `uint256` slots.

Two libraries implement the encoding:

- `bigMathMinified.sol` — generic `toBigNumber` / `fromBigNumber` with configurable coefficient + exponent sizes. Used by Liquidity, DEX, DexLite, fToken, stETHQueue.
- `bigMathVault.sol` — specialized fixed-parameter math (35-bit coefficient, 15-bit exponent, 16384-decimal PRECISION) used only by Fluid Vault to do the tick-branch / connection-factor arithmetic in constant gas.

Both are `pure internal` libraries; no storage, no external calls.

## 2. `BigMathMinified` (generic)

### 2.1 Encoding

- Format: `bigNumber = (coefficient << exponentSize) | exponent`.
- `fromBigNumber(bn, expSize, expMask) = coefficient << exponent`.
- When `exponent > 0` the coefficient is required to have its top bit set (max precision), i.e. after `toBigNumber` with round-down the trailing zeroes live in the exponent shift; this is the invariant BigMathVault relies on.

### 2.2 Methods

- `toBigNumber(normal, coefficientSize, exponentSize, roundUp) returns (bigNumber)`

  - Finds most significant bit of `normal`, sets `exponent = max(msb, coefficientSize) - coefficientSize`, `coefficient = normal >> exponent`.
  - **ROUND_DOWN (`false`)**: trailing bits truncated. Used for supply / balances where Liquidity must never report more assets than it custodies.
  - **ROUND_UP (`true`)**: coefficient += 1, with carry handling (if `coefficient == 1 << coefficientSize`, coefficient halves to `1 << (coefficientSize-1)` and exponent += 1). Used for debt / borrow where the protocol must not under-state liability.
  - **Edge**: if resulting `exponent >= 1 << exponentSize`, reverts (`revert(0,0)` with no data). Callers must pick `coefficientSize + exponentSize` large enough for their range. Empirically Liquidity uses 64-bit coefficient + 8-bit exponent (→ numbers up to `~2^320`).
  - **`normal == 0`** is handled by the happy path — last-bit loop yields 0, `exponent = 0`, `coefficient = 0`.
  - **Rounding is idempotent** for values already representable within `coefficientSize` bits (exponent==0 branch skips the `+1` carry).

- `fromBigNumber(bigNumber, exponentSize, exponentMask) returns (normal)` — pure bit-ops, cheap, no overflow check because `coefficient << exponent` can't exceed `uint256` for the ranges the callers use.

- `mostSignificantBit(normal) returns (uint lastBit)` — binary search, `0 → 0`, `1 → 1`, returns 1-indexed bit position.
- `leastSignificantBit(normal) returns (uint firstBit)` — binary search, `0 → reverts`, returns 1-indexed position.

### 2.3 Rounding conventions used across Fluid

| Site | Direction | Why |
| --- | --- | --- |
| User supply amount stored in Liquidity | ROUND_DOWN | Never custody less than reported. |
| User borrow amount stored in Liquidity | ROUND_UP | Never forgive debt below real liability. |
| `withdrawalLimit`, `borrowLimit` | ROUND_DOWN / ROUND_UP per direction | Same idea. |
| `rateData` packed entries | ROUND_DOWN | Rates truncate; user slightly favored at rounding boundary. |
| DEX / DexLite user supply / debt | Supply ROUND_DOWN, debt ROUND_UP | Same as Liquidity. |
| fToken `_tokenExchangePrice` reads (BigMath) | `updateExchangePrice` enforces monotonic non-decrease downstream. | — |
| stETHQueue `Claim.ethAmount` | ROUND_DOWN (stored) / ROUND_UP (debt written to Liquidity) | Queue custodies stETH; ETH debt at Liquidity rounds up. |

### 2.4 Audit dispositions (absorbed)

- Precision loss on very small positions is accepted; documented micro-dust amounts (typically below per-token `minOperate` floors) cannot be recovered through the user entry points.
- The revert on out-of-range `exponent` is by design and considered safer than silent truncation.

## 3. `BigMathVault` (vault specialization)

### 3.1 Fixed parameters (important)

- Coefficient size: **35 bits** → `17_179_869_184 ≤ coefficient ≤ 34_359_738_367` (top bit always 1 when exp > 0).
- Exponent size: **15 bits** → `exponent ≤ 32_767`, but most vault inputs cap at `16_384`.
- `DECIMALS_DEBT_FACTOR = 16384` — acts as implicit "decimal point" (i.e. 1.0 encoded as `bigNumber` with exponent `16384`).
- `PRECISION = 64`, `TWO_POWER_64 = 1 << 64`.
- `MAX_MASK_DEBT_FACTOR = (1 << 50) - 1` — all-ones 35+15 bits; used as a "fully liquidated" sentinel from `mulBigNumber`.

These are consensus values: Vault tick math depends on exactly these widths. Changing them silently breaks position accounting.

### 3.2 Methods

- `mulDivNormal(normal, bigNumber1, bigNumber2)` → `normal * bigNumber1 / bigNumber2`.

  - Invariants required by callers: `bigNumber2 >= bigNumber1`, both valid 35+15 BigNumbers, `bigNumber1` (debt factor) has `1 ≤ exp ≤ 16384`, `bigNumber2` (connection factor) has `1 ≤ exp ≤ 32767`, `normal` is raw position debt in `[10 000, type(int128).max]`.
  - If the exponent gap (`exp2 - exp1`) is `≥ 129`, result is guaranteed 0 (nominator < denominator by construction); returns `0`.
  - No explicit overflow check; safety comes from the bounded input ranges the vault enforces upstream.

- `mulDivBigNumber(bigNumber, number1)` → `bigNumber * number1 / TWO_POWER_64`.

  - Used by the vault to update branch debt factor after a liquidation. `number1` is a debt-factor delta, always `0 < number1 ≤ 2^64`.
  - Requires the vault invariant: starting exponent `16384`, so the exponent never collapses to 0. If it would (e.g. absurdly small `number1` + small `bigNumber`), the library `revert()`s rather than producing a BigNumber with exp ≤ 0. This is a safety stop, not a user-facing condition under normal trading.

- `mulBigNumber(bigNumber1, bigNumber2)` → BigNumber product.

  - Used when merging branches (combining connection factors): `c1*c2>>overflow, e1+e2+overflow-DECIMALS`.
  - On underflow of `resExponent_` (theoretically only reachable if debt factors are wildly out of band), `revert()`.
  - On overflow of `resExponent_` beyond 15 bits, returns `MAX_MASK_DEBT_FACTOR` (≈ "position ~100% liquidated"). The vault core treats this as a terminal/absorb state.

- `divBigNumber(bigNumber1, bigNumber2)` → BigNumber quotient.

  - Used to derive `connectionFactor_ = baseBranchDebtFactor / currentBranchDebtFactor`.
  - Invariant maintained upstream: connection factor is always `>= baseBranchDebtFactor` because debt factors are `≤ 1` (i.e. `x*100/y` with `x,y ∈ (0,1]` is always `≥ x`).
  - On underflow (would require pathological merge of an almost-liquidated base branch with a healthy branch), reverts.

### 3.3 Why it's a hard-coded specialization

Inlining the parameters saves ~10-15% gas on the liquidation hot path, but means: **these functions must not be called with different-sized BigNumbers**. The Vault core (`vaultTypesCommon/coreModule/helpersLiquidate.sol`) is the only caller and documents these prerequisites inline.

Out-of-scope: `bigMathUnsafe.sol` exists in the folder but is unused by production vault code and is explicitly not covered by this spec.

## 4. Errors

- `BigMathMinified.toBigNumber` reverts `revert(0, 0)` (no data) when out of range. Callers usually wrap in a higher-level error.
- `BigMathMinified.leastSignificantBit(0)` reverts `revert(0, 0)`.
- `BigMathVault.mulDivBigNumber` and `divBigNumber` / `mulBigNumber` — plain `revert()` on boundary cases that should never occur in normal operation.

## 5. Invariants & Safety

1. **Round direction is asymmetric:** supply rounds down, debt/borrow rounds up. Violating this convention (e.g. storing a borrow with ROUND_DOWN) is silently unsafe and is the root cause of multiple historical bugs in similar protocols. Any new caller must explicitly commit to a direction.
2. **Max-precision invariant:** when `exp > 0`, the 35th (or `coefficientSize`-th) bit of the coefficient is 1. `BigMathVault` assumes this unconditionally.
3. **No zero inputs** for `BigMathVault` arithmetic. The vault enforces non-zero debt factors and non-zero positions upstream; otherwise library calls may revert or produce undefined results.
4. **Out-of-range revert is by design.** Callers choosing `coefficientSize` / `exponentSize` too small will see `revert(0,0)` at `toBigNumber`. This is preferred over silent saturation.
5. **Encoding is not ABI-stable across protocols.** Liquidity packs with a different coefficient/exponent size than Vault's 35+15. Never pass a `bigNumber` from one protocol to another's library helpers.
6. **`ROUND_UP` with carry** can only bump the exponent by 1 and can never exceed the max exponent — provided `coefficientSize + exponentSize` was chosen with adequate margin, which all current callers do.

## 6. Audit Notes (absorbed)

- **L-03 / V-08 / V-09** (bigMathUnsafe): out of scope here; the production path does not rely on `bigMathUnsafe.sol`.
- Rounding-direction bugs and "ROUND_UP on supply causing inflation" style findings are prevented by the convention above and by tests in `bigMathVault.t.sol` (run whenever `BigMathVault` is modified — see library's own comment).
