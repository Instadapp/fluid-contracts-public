# Libraries — DexCalcs SPEC

## 1. Purpose

`DexCalcs` is the DEX-layer counterpart of `LiquidityCalcs` for the **withdrawal-limit and borrow-limit** math on DEX `userSupply` / `userBorrow` packed slots. It applies to `FluidDexT1` user supply / borrow (share-denominated) data.

Structurally it is a near-verbatim mirror of `LiquidityCalcs`'s limit methods, reading from `DexSlotsLink` bit offsets instead of `LiquiditySlotsLink`. The DEX layer stores its user balances at a different slot layout, but the limit-decay and limit-expansion semantics are identical to Liquidity. A top-of-file header calls this out explicitly:

> `@DEV ATTENTION: ON ANY CHANGES HERE, MAKE SURE THAT LOGIC IN VAULTS WILL STILL BE VALID. SOME CODE THERE ASSUMES DEXCALCS == LIQUIDITYCALCS.`

That invariant — functional equivalence with `LiquidityCalcs` for the four limit functions — is **a hard contract** that Vault code (specifically the smart-col / smart-debt flows in T2 / T3 / T4) relies on.

## 2. External Interactions

None. Pure internal math.

## 3. Methods

All four methods are 1:1 mirrors of `LiquidityCalcs` methods of the same name, reading from `DexSlotsLink.BITS_USER_SUPPLY_*` / `DexSlotsLink.BITS_USER_BORROW_*` instead of the `LiquiditySlotsLink` equivalents:

- `calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply) view → currentWithdrawalLimit`
- `calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, newWithdrawalLimit) pure → withdrawalLimit`
- `calcBorrowLimitBeforeOperate(userBorrowData, userBorrow) view → currentBorrowLimit`
- `calcBorrowLimitAfterOperate(userBorrowData, userBorrow, newBorrowLimit) pure → borrowLimit`

Return semantics — and unit: *raw-with-interest amount for with-interest mode, normal amount for interest-free mode* — are identical to the Liquidity variants.

For the full decay / expansion semantics and edge-case behaviour (first interaction, `timeElapsed > expandDuration`, base-limit floor, max-limit ceiling, instant-full-expansion on deposit, etc.) see [`SPEC-liquidityCalcs.md`](./SPEC-liquidityCalcs.md) §4 "Calc Limits".

## 4. Storage fields consumed

- **User supply data (`userSupplyData_`):**

  - `BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT` (64 bits, BigMath)
  - `BITS_USER_SUPPLY_EXPAND_PERCENT` (14 bits, 1e2)
  - `BITS_USER_SUPPLY_EXPAND_DURATION` (24 bits, seconds, never 0)
  - `BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP` (33 bits)
  - `BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT` (18 bits, BigMath)

- **User borrow data (`userBorrowData_`):**

  - `BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT` (64 bits, BigMath)
  - `BITS_USER_BORROW_EXPAND_PERCENT` (14 bits)
  - `BITS_USER_BORROW_EXPAND_DURATION` (24 bits)
  - `BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP` (33 bits)
  - `BITS_USER_BORROW_BASE_BORROW_LIMIT` (18 bits, BigMath)
  - `BITS_USER_BORROW_MAX_BORROW_LIMIT` (18 bits, BigMath)

All BigMath decodes use `(coeff << 8) << (packed & 0xFF)` — the protocol-wide `DEFAULT_EXPONENT_SIZE=8, MASK=0xFF` convention. See [SPEC-bigMath.md](./SPEC-bigMath.md).

## 5. Constants

Identical to `LiquidityCalcs`:

- `DEFAULT_EXPONENT_SIZE = 8`, `DEFAULT_EXPONENT_MASK = 0xFF`.
- `FOUR_DECIMALS = 1e4` (1% == 100, 100% == 10000).
- Bit masks `X14 / X18 / X24 / X33 / X64`.

## 6. Errors

None emitted or raised directly; the functions can only fail on `unchecked` overflow, which is not reachable for any real-world token (`userSupply / userBorrow` would need to be ≥ 1e73 — impossible in practice because ERC-20 totalSupply constraints and DEX share scaling limits).

## 7. Invariants & Safety Notes

- **Parity with `LiquidityCalcs` is a maintenance contract.** If one of these four methods changes its semantics in Liquidity, this library **must** be updated in lockstep. Vault code assumes the returned quantities are interchangeable in shape.
- **`expandDuration` must never be 0.** Enforced upstream in DEX admin (factory / pool admin module). The library divides by it unchecked.
- **Returns 0 means "no floor"** for withdrawal-limit-before, or "base limit applies" for borrow-limit-before. Callers differentiate via the base-limit comparison that already exists in the library body.
- **First interaction (`lastUpdate == 0`)** is handled implicitly: for supply, `lastWithdrawalLimit_ == 0` short-circuits; for borrow, `userBorrow == 0` propagates into the comparison chain landing on the base borrow limit. No explicit initialisation is needed.

## 8. Audit Notes (absorbed)

- Audit findings relating to unexpected decay behaviour on DEX smart-col / smart-debt positions were traced back to callers computing in *share* units vs *token* units. The library is correct; caller-side share-math is documented in the DEX and Vault specs.
- Audit reminded that the `DEXCALCS == LIQUIDITYCALCS` invariant means any asymmetry between the two would quietly break Vault smart-col / smart-debt accounting. The present code preserves it.
