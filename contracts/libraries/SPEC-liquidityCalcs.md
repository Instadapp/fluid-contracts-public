# Libraries — LiquidityCalcs SPEC

## 1. Purpose

`LiquidityCalcs` is the pure-math library behind every view-layer (resolvers, periphery) and every protocol that reads Fluid Liquidity state without issuing a delegatecall to the liquidity layer itself. It contains:

- **Exchange-price math** — continuous interest accrual for supply and borrow "with-interest" balances, using an annualised linear rate × elapsed seconds.
- **Revenue math** — collectible revenue given the packed total-amounts slot and the current ERC-20 balance held by Liquidity.
- **Withdrawal / borrow limit math** — decaying withdrawal limits (protects against mass outflows) and expanding borrow limits (smooth rate-independent ramp-up).
- **Borrow-rate math** — piecewise-linear rate curve evaluation for rate data versions 1 (one kink) and 2 (two kinks).
- **Total-supply / total-borrow readers** — expand the packed raw + interest-free amounts to normalised numbers.

All functions are `internal`, branch-free beyond the required piecewise segments, and allocate no storage. They are imported wherever gas matters (Liquidity itself, resolvers, fTokens, DEX / DexLite / vault rewards rebalancing).

## 2. External Interactions

None. `calcBorrowRateFromUtilization` can `emit BorrowRateMaxCap()` (defined on the library itself) when the rate is capped. No calls are made.

## 3. Constants and encoding

| Constant | Value | Meaning |
| --- | ---:| --- |
| `EXCHANGE_PRICES_PRECISION` | `1e12` | Exchange prices are stored/returned in 1e12 units (1.0 == 1e12). |
| `SECONDS_PER_YEAR` | `365 days` | Leap years intentionally ignored for determinism. |
| `DEFAULT_EXPONENT_SIZE / MASK` | 8 / `0xFF` | BigMath format used throughout Liquidity storage. |
| `FOUR_DECIMALS` | `1e4` | 100% == 10 000; 1% == 100. |
| `TWELVE_DECIMALS` | `1e12` | Internal precision for the y=mx+c rate math. |
| `X14 / X15 / X16 / X18 / X24 / X33 / X64` | Bit masks | For extracting packed fields. |

## 4. Methods

### `calcExchangePrices(exchangePricesAndConfig_) view → (supplyExchangePrice_, borrowExchangePrice_)`

Extracts the two 64-bit exchange prices, the 16-bit borrow rate, 14-bit fee, 14-bit utilization, 15-bit supply & borrow ratios, and 33-bit lastTimestamp from the packed slot. Then:

- If `supply` or `borrow` exchange price is 0 → `revert FluidLiquidityCalcsError(70001 ExchangePriceZero)` (token not yet configured).
- If `secondsSinceLastUpdate == 0` **or** `borrowRate == 0` **or** the packed `borrowRatio` sentinel is `1` (meaning "only borrowInterestFree exists, no yield to pay") → returns the stored prices unchanged (hot no-op path).
- Otherwise:
  - **Borrow exchange price** increases by `prev * borrowRate * Δt / (SECONDS_PER_YEAR * 1e4)`.
  - **Supply exchange price** is computed by deriving a `ratioSupplyYield` that captures (a) the utilisation, (b) the share of lenders that actually earn interest (`supplyRatio` sentinel), and (c) the share of borrowers that actually pay (`borrowRatio` sentinel). Formula in code is extensively commented with a worked example. Yield from borrowers-with-interest is redistributed only to lenders-with-interest; the `interest-free` legs are passed through.
  - Final `supplyExchangePrice += prev * supplyRate * Δt / (YEAR * 1e12)` with supply rate already net of the `revenueFee%`.

**Edge notes:**

- When supply ratio sentinel is `1` (no raw-interest suppliers), the function returns early after updating only the borrow price; the excess earnings accumulate as revenue.
- `borrowRate == 0` short-circuits both updates.
- Every divisor in the math is provably non-zero by construction (ratios use `FOUR_DECIMALS + x`, `expandDuration` in ratio-unrelated branches, etc.).
- `temp_` variable is reused across stages to minimise stack usage; invariants documented in-line.

### `calcRevenue(totalAmounts_, exchangePricesAndConfig_, liquidityTokenBalance_) view → revenueAmount_`

- Calls `calcExchangePrices` to get up-to-date prices.
- Computes `totalSupply_` via `getTotalSupply`. If 0 → the entire token balance held by Liquidity is revenue (nothing owed to users).
- Else `revenueAmount_ = liquidityTokenBalance_ + totalBorrow_ - totalSupply_`, saturating at 0. This captures interest-free-only vs with-interest gaps that can make the subtraction briefly negative due to BigMath rounding.
- Admin-only consumer; no need for ultra-optimized gas.

### `calcWithdrawalLimitBeforeOperate(userSupplyData_, userSupply_) view → currentWithdrawalLimit_`

Returns the **floor** a user's supply must not go below in the pending operation. This is the active, decayed limit that expanded over time since the last operate.

Flow:

1. Decode `lastWithdrawalLimit_` (BigMath `(coeff<<8)|exp`) from `PREVIOUS_WITHDRAWAL_LIMIT` bits. If zero, the limit is not activated (first interaction or user below base limit) → return 0 (max withdraw allowed).
2. `maxWithdrawableLimit_ = userSupply * expandPercent / 1e4` (14-bit expandPercent in 1e2).
3. `temp_ = block.timestamp - lastUpdateTimestamp`.
4. `decay = maxWithdrawableLimit_ * temp_ / expandDuration` — expandDuration is 24 bits and never 0 by config.
5. `currentWithdrawalLimit_ = lastWithdrawalLimit_ - decay`, saturating at 0 (if more than `expandDuration` elapsed).
6. Enforce floor: at full expansion, the limit is `userSupply - maxWithdrawableLimit_`. Overwrite if the current value drops below.

**Returned units:** *raw-with-interest* for with-interest mode, *normal amount* for interest-free mode (matches how it is compared at the caller).

**Edge notes (decay behaviour):**

- When a deposit shoots the supply above the previous withdrawal limit minus expansion, the limit is instantly set to "fully expanded" (see `calcWithdrawalLimitAfterOperate`). This is the mechanism that absorbs the so-called "decay limit" spike: large deposits do not generate withdraw capacity they did not have before.
- When `timeElapsed > expandDuration`, the theoretical decay exceeds the prior limit; the code saturates at 0 (which then gets bumped up to the floor `userSupply - maxWithdrawable`).
- Base withdrawal limit is not applied in the "before" step — it is only enforced in `calcWithdrawalLimitAfterOperate` when resetting storage.

### `calcWithdrawalLimitAfterOperate(userSupplyData_, userSupply_, newWithdrawalLimit_) pure → withdrawalLimit_`

Writes back the limit to be persisted after the operation resolves. Two enforcement rules:

1. If `userSupply_ < baseWithdrawalLimit` (18-bit BigMath-encoded) → return 0; limit is dormant when balances are tiny.
2. Else compute `minLimit = userSupply_ - userSupply_ * expandPercent / 1e4`. If `newWithdrawalLimit_` (the decayed value from step before, possibly reduced by a withdraw) is below this floor, bump to the floor (instant rebuild on deposit).

The combination prevents a "deposit now, withdraw max tomorrow" attack path: new supply doesn't open new withdrawal capacity beyond `expandPercent`.

### `calcBorrowLimitBeforeOperate(userBorrowData_, userBorrow_) view → currentBorrowLimit_`

- `maxExpansion_ = userBorrow_ * expandPercent / 1e4`.
- `maxExpanded_ = userBorrow_ + maxExpansion_` (i.e. the cap if fully expanded).
- `timeElapsed = now - lastUpdate`.
- `currentBorrowLimit_ = lastBorrowLimit (BigMath 64-bit) + maxExpansion_ * timeElapsed / expandDuration`.
- Saturate to `maxExpanded_` (covers also the cold case where `lastUpdate == 0`).
- If below `baseBorrowLimit` (18-bit BigMath) → use baseBorrowLimit.
- If above `maxBorrowLimit` (18-bit BigMath) → cap at maxBorrowLimit.

**Returned units:** raw-with-interest for with-interest mode, normal amount for interest-free mode.

### `calcBorrowLimitAfterOperate(userBorrowData_, userBorrow_, newBorrowLimit_) pure → borrowLimit_`

- Compute `fullyExpanded = userBorrow_ + userBorrow_ * expandPercent / 1e4`.
- If `< baseBorrowLimit` → use base. Else if `> maxBorrowLimit` → cap.
- If `newBorrowLimit_ > fullyExpanded` → return `fullyExpanded` (repayments shrink limit immediately).
- Else return `newBorrowLimit_`.

### `calcBorrowRateFromUtilization(rateData_, utilization_) → rate_`

Rate curve evaluation:

- `rateVersion = rateData & 0xF`.
- `1 → calcRateV1`, `2 → calcRateV2`, else revert `70002 UnsupportedRateVersion`.
- If resulting `rate_ > X16` (65 535), **cap at 65 535** and emit `BorrowRateMaxCap()` event to alert governance. This is a hard ceiling because the rate is packed into 16 bits upstream.

### `calcRateV1` / `calcRateV2` (pure)

Piecewise-linear y=mx+c with 12-decimal internal precision:

- **V1 layout** (4..67 bits of rateData): `rateAt0 | utilizationAtKink1 | rateAtKink1 | rateAtMax` (each 16 bits). One kink.
- **V2 layout** (4..99 bits): `rateAt0 | utilAtKink1 | rateAtKink1 | utilAtKink2 | rateAtKink2 | rateAtMax`. Two kinks.
- Pick the segment containing `utilization_`, compute `m = (y2-y1)*1e12 / (x2-x1)`, `c = y1*1e12 - m*x1`, `rate = (m*u + c) / 1e12`.
- If resulting rate is negative → revert `70003 BorrowRateNegative` (defensive: should not happen with configs satisfying the admin invariants, because rates are constrained `>= 0` in config).
- Utilisation can exceed 100% in pathological situations (e.g. reserves shrink due to revenue withdrawal). The math still evaluates; rate can exceed its upper bound and hits the global cap at the outer function.

### `getTotalSupply(totalAmounts_, supplyExchangePrice_) pure`

- Extracts `supplyInterestFree` (BigMath 64-bit at bit 64) and `supplyRawWithInterest` (BigMath 64-bit at bit 0).
- Decodes both via `(coeff << 8) << (val & 0xFF)` (in-lined, `BigMathMinified.fromBigNumber`-equivalent).
- Returns `interestFree + raw * supplyExchangePrice / 1e12`.

### `getTotalBorrow(totalAmounts_, borrowExchangePrice_) pure`

Same shape for borrow: `borrowInterestFree` (at 192) + `borrowRawWithInterest` (at 128). No mask required on the topmost bits because the slot ends at bit 255.

## 5. Errors

| Code | Name | When |
| --- | --- | --- |
| 70001 | `LiquidityCalcs__ExchangePriceZero` | supply or borrow exchange price is 0 (token not configured yet). |
| 70002 | `LiquidityCalcs__UnsupportedRateVersion` | rateData version not 1 or 2. |
| 70003 | `LiquidityCalcs__BorrowRateNegative` | curve segment produced negative rate (invariant violation in config). |

All are `FluidLiquidityCalcsError(errorId)`.

## 6. Events

- `BorrowRateMaxCap()` — emitted when the computed borrow rate exceeds the 16-bit storage cap of 65 535 (650.35%). Governance should rebalance parameters; no user funds are at risk when this fires, but utilisation is very high.

## 7. Invariants & Safety Notes

- **Rounding direction:** all exchange-price arithmetic floors; users never see more yield than the pool has earned. This aligns with the protocol-wide BigMath convention (supply rounds down, borrow rounds up; see [SPEC-bigMath.md](./SPEC-bigMath.md)).
- **No-op path short-circuits** preserve gas on reads (`secondsSinceLastUpdate == 0`, `borrowRate == 0`, supply/borrow ratio sentinel `1`).
- **Decay limit** (withdrawal): the protocol's mechanism to prevent a flash-deposit → max-withdraw attack. After a deposit the stored limit snaps to the fully expanded floor; it does **not** carry forward "unused" expansion from before.
- **Rate storage cap:** 16 bits means `65 535 / 10 000 = 655.35%` borrow rate is the hard on-chain ceiling. Governance is notified via `BorrowRateMaxCap`.
- **Utilisation can exceed 100%.** This happens briefly if revenue extraction reduces supply below borrow. The piecewise math does not special-case it; rates just grow linearly past the last kink.
- **Leap years ignored** — constant 365 days yields deterministic, predictable rate comparisons across chains.
- **All multiplications are bounded:** the in-line comments demonstrate the max intermediate values never exceed `uint256`. This was verified during the audit pass.

## 8. Audit Notes (absorbed)

- Precision / rounding behaviour in `calcExchangePrices` is intentional: when `supplyRatio == 1` (no interest-bearing suppliers), the borrow-side yield correctly accrues to revenue rather than being silently lost. Any discrepancy between `totalSupply` and `totalBorrow - balanceOf` after extraction is treated as revenue.
- The `BorrowRateMaxCap` event is the documented tripwire for governance to reconfigure rate data when markets pin utilisation at extreme values.
- `calcBorrowRateFromUtilization` is intentionally `internal` (not view / pure) because of the event emission; call sites are read-path but tolerate the subtle non-pure signature.
- Audit finding around `expandDuration == 0` is addressed by the admin-side validation in Liquidity; this library assumes the divisor is always non-zero.
