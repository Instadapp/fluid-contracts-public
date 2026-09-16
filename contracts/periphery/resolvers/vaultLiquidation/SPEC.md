# Resolvers / vaultLiquidation — SPEC

## 1. Purpose

Read-only view over **available liquidation swaps on every T1-shaped Fluid vault**. A vault exposes a `liquidate(inAmt, colPerUnitDebt, receiver, absorb)` entry-point whenever one or more positions have crossed their liquidation threshold; the vault itself reports how much debt token it is willing to accept and how much collateral it will return in exchange. `FluidVaultLiquidationResolver` aggregates that per-vault view across the entire vault set and reshapes it into the shape liquidation keepers actually need.

Three jobs:

1. **Discovery.** Which vaults currently have any liquidatable size, and for which `(tokenIn = borrowToken, tokenOut = collateralToken)` pairs.
2. **Sizing.** For each such vault, the *effective* swap: both the bare `liquidate()` path and the `absorb`-first path, clamped by the real collateral side withdrawability at Liquidity (so keepers don't submit a tx that looks feasible but actually reverts on the Liquidity withdraw limit or on bare balance).
3. **Preview payload.** A ready-to-broadcast `(target, calldata)` pair with slippage already baked in, so a bot can go from "scan chain" → "submit tx" in one resolver round-trip.

Single deployed contract: `FluidVaultLiquidationResolver` (`main.sol`). Only targets **T1-shape vaults** (single Liquidity-backed supply token + single Liquidity-backed borrow token); T2/T3/T4 DEX-backed vaults have their own per-type liquidation paths and are not surfaced here. The resolver iterates `VaultFactory` and filters to `VAULT_T1_TYPE` via `FluidProtocolTypes.filterBy`.

## 2. Architecture & Data Flow

```mermaid
flowchart LR
    K[Keeper / bot] -->|eth_call / callStatic| R[FluidVaultLiquidationResolver]
    R -->|getAllVaultsAddresses| VR[FluidVaultResolver]
    R -->|getVaultLiquidation inAmt=0| VR
    VR -->|simulate revert-for-data| V[(Fluid VaultT1)]
    R -->|readFromStorage userSupply + exchangePrices| L[(Fluid Liquidity)]
    R -->|balanceOf / .balance| L
    R -->|_getLiquidityExternalBalances| Z[(Zircuit, mainnet only)]
    R -. abi.encodeWithSelector .-> TX[liquidate-calldata]
```

Inherits `ResolverHelpers` so the `balanceOf(LIQUIDITY)` used to clamp withdrawable amounts on WEETH / WEETHS includes the Zircuit re-hypothecated share. Without that offset, the resolver would under-report withdrawable collateral and return unnecessarily-small swaps.

## 3. External Interactions

- `VAULT_RESOLVER.getAllVaultsAddresses()` + `FluidProtocolTypes.filterBy(..., VAULT_T1_TYPE)` — enumerate T1 vaults.
- `IFluidVaultT1(vault).constantsView()` — resolve `(borrowToken, supplyToken)` per vault.
- `VAULT_RESOLVER.getVaultLiquidation(vault, 0)` — the core sizing call. Non-`view` because the underlying vault simulates a liquidation via a revert-for-data path; keepers must use `eth_call` / `callStatic`. Returns `(inAmt, outAmt, inAmtWithAbsorb, outAmtWithAbsorb)` — the maximum liquidation sizes with and without absorb.
- `LIQUIDITY.readFromStorage(slot)` — per-vault `userSupply` packed slot + per-token `exchangePricesAndConfig` slot, to compute the live withdrawal limit.
- `IERC20(token).balanceOf(LIQUIDITY)` or `address(LIQUIDITY).balance` for native + `_getLiquidityExternalBalances` — bare withdrawable ceiling.
- `abi.encodeWithSelector(IFluidVaultT1.liquidate.selector, ...)` — `getSwapTx` / `getSwapTxs` produce raw calldata; no on-chain dispatch.

No writes. No funds held. No auth.

## 4. Roles & Access Control

None. Every method is `public view` / `pure`, or declared non-`view` purely because it transitively calls the vault-resolver simulation path. No `onlyOwner`, no auth, no pausability. Constructor reverts with `FluidVaultLiquidationsResolver__AddressZero` on `vaultResolver_ == 0` or `liquidity_ == 0`.

## 5. Storage Layout

Two immutables, zero mutable storage:

| Slot | Type | Meaning |
| --- | --- | --- |
| immutable | `IFluidVaultResolver VAULT_RESOLVER` | Vault resolver used to enumerate vaults and run `getVaultLiquidation`. |
| immutable | `IFluidLiquidity LIQUIDITY` | Liquidity contract — source of user-supply / exchange-price slots and the token-balance clamp. |

Plus the inherited `WEETH` / `WEETHS` / `ZIRCUIT` `constant`s from `ResolverHelpers`, and local `NATIVE_TOKEN_ADDRESS = 0xEeee...EEeE`, `EXCHANGE_PRICES_PRECISION = 1e12`.

## 6. Swap-Path Discovery Methods

Pure path discovery — no liquidation sizes involved, just the `(vault, tokenIn, tokenOut)` tuple for every T1 vault matching the filter. All `public view`.

| Method | Returns | Behaviour |
| --- | --- | --- |
| `getAllSwapPaths()` | `SwapPath[]` | One entry per T1 vault. `tokenIn = borrowToken`, `tokenOut = supplyToken`. Length equals T1 vault count; includes vaults with zero liquidatable size. |
| `getSwapPaths(tokenIn, tokenOut)` | `SwapPath[]` | Subset whose `(borrowToken, supplyToken)` exactly matches. Returns empty array (not revert) if no pair matches. |
| `getAnySwapPaths(tokensIn[], tokensOut[])` | `SwapPath[]` | Cartesian match: any vault whose pair is in `tokensIn × tokensOut`. Right-sized result. |

## 7. Per-Vault Raw Liquidation Data

"Raw" methods surface **both** the bare and the absorb-first swap for each vault unchanged. Use these when the caller wants full control over ratio / target-amount optimisation. Non-`view` (transitively call the vault simulation).

| Method | Returns | Behaviour |
| --- | --- | --- |
| `getVaultSwapData(vault)` | `(SwapData withoutAbsorb, SwapData withAbsorb)` | Pulls `(inAmt, outAmt, inAmtWithAbsorb, outAmtWithAbsorb)` from `VAULT_RESOLVER.getVaultLiquidation(vault, 0)` and packages each leg with its own `ratio = outAmt * 1e27 / inAmt`. No withdrawable clamp applied. |
| `getVaultsSwapData(vaults[])` | `(SwapData[], SwapData[])` | Loop over `getVaultSwapData`. |
| `getAllVaultsSwapData()` | `(SwapData[], SwapData[])` | `getVaultsSwapData(_getVaultT1s())`. |
| `getVaultsSwapRaw(vaults[])` | `Swap[]` | Withdrawable-clamped. Skips vaults where `withAbsorb.inAmt == 0` (no liquidatable size) or `withdrawable == 0` (collateral can't leave Liquidity). De-duplicates trivially when `withAbsorb.inAmt == withoutAbsorb.inAmt` (emits only the cheaper non-absorb variant). |
| `getAllVaultsSwapRaw()` | `Swap[]` | `getVaultsSwapRaw(_getVaultT1s())`. |
| `getSwapsForPathsRaw(paths[])` | `Swap[]` | Same as `getVaultsSwapRaw` but path-scoped. |
| `getSwapsRaw(tokenIn, tokenOut)` | `Swap[]` | Compose `getSwapsForPathsRaw(getSwapPaths(...))`. |
| `getAnySwapsRaw(tokensIn[], tokensOut[])` | `Swap[]` | Compose with `getAnySwapPaths`. |

"Better-ratio-filtered" methods collapse each vault to a single `Swap` — whichever of bare / absorb has the better output-per-input ratio (with ties broken by the cheaper gas path). Same shape, narrower output.

| Method | Behaviour |
| --- | --- |
| `getSwapForProtocol(vault)` | Single-vault convenience; returns zero `Swap` on `vault == 0`. |
| `getVaultsSwap(vaults[])` / `getAllVaultsSwap()` | Per-vault best-ratio swap, skipping zero sizes. |
| `getSwapsForPaths(paths[])` | Same, path-scoped. |
| `getSwaps(tokenIn, tokenOut)` / `getAnySwaps(tokensIn[], tokensOut[])` | Compose with the discovery helpers. |

### Clamp semantics

Every swap is funneled through `_getSwapAccountingForWithdrawable`: if `withdrawable < outAmt`, both `inAmt` and `outAmt` are scaled down proportionally (`inAmt = inAmt * withdrawable / outAmt; outAmt = withdrawable`). `withdrawable` is itself the min of **(a)** Liquidity's expanded withdraw limit for the vault-as-supplier computed via `LiquidityCalcs.calcWithdrawalLimitBeforeOperate` (with raw→interest conversion when the supply side runs in with-interest mode) and **(b)** `LIQUIDITY.balance(token) + externalBalance`. This matches the exact check a real liquidation would hit on-chain.

### Absorb semantics

Vault docs: `inAmtWithAbsorb >= inAmt` always. If `inAmtWithAbsorb == inAmt`, the absorb path yields identical size at extra gas — the non-`Raw` variants drop it. If absorb has a strictly better ratio (e.g. because absorb cleans up partially-liquidated positions with improved collateralisation), the filtered method picks absorb; otherwise it picks non-absorb. The `Raw` methods emit both so callers can split a target amount across the two with custom logic.

## 8. Target-Amount Targeting & Tx Preview

These methods layer a target-size search on top of the raw swaps, sort by ratio descending, and optionally trim the last swap so the total hits the target exactly (on the input side) or approximately (on the output side).

| Method | Returns | Behaviour |
| --- | --- | --- |
| `exactInput(tokenIn, tokenOut, inAmt)` | `(Swap[] swaps, uint256 actualInAmt, uint256 outAmt)` | Best-ratio-first fill toward `inAmt`. `actualInAmt == inAmt` if liquidity suffices; else the full available amount with `actualInAmt < inAmt`. Last swap is re-sized via a second `getVaultLiquidation(vault, missingInAmt)` call so `actualInAmt` matches exactly (≈ ±1 wei from integer rounding). |
| `approxOutput(tokenIn, tokenOut, outAmt)` | `(Swap[] swaps, uint256 inAmt, uint256 approxOutAmt)` | Same strategy for a target output. Approximate because liquidation output is not a deterministic function of input (absorb mode + ratio shifts). Keepers should prefer `exactInput` with an output-slippage gate. |
| `filterToTargetInAmt(swaps[], targetInAmt)` | `(Swap[] filtered, uint256 actualInAmt, uint256 approxOutAmt)` | Takes caller-supplied `Raw` swaps; same sort-and-trim logic. Useful when the caller wants to mix vaults by hand before handing a bundle to the trimmer. |
| `filterToApproxOutAmt(swaps[], targetOutAmt)` | `(Swap[] filtered, uint256 actualInAmt, uint256 approxOutAmt)` | Output-side variant. |
| `getSwapTx(swap, receiver, slippage)` | `(address target, bytes calldata)` | `pure`. Encodes `IFluidVaultT1.liquidate(inAmt, colPerUnitDebt, receiver, withAbsorb)` with `colPerUnitDebt = outAmt * 1e18 / inAmt * (1e6 - slippage) / 1e6`. `slippage` is in 1e6 precision (1% = 10_000). Reverts `__AddressZero` on zero protocol/receiver, `__InvalidParams` on `slippage >= 1e6` or zero amounts. |
| `getSwapTxs(swaps[], receiver, slippage)` | `(address[], bytes[])` | Loop over `getSwapTx`. |

### Targeting details

`_filterToTarget` runs a two-phase fill: first it sorts by ratio (descending bubble-sort — O(n²) but n ≤ T1-vault count, fine for `eth_call`), then walks the list accumulating `sumInAmt` / `sumOutAmt` until either target is reached. While accumulating it *also* deduplicates cases where the same vault appears twice (once with-absorb, once without) — only the higher-inAmt leg is kept, and the fill restarts because the total is now lower. When a target is exceeded by the last swap, a dedicated recompute fetches a fresh `getVaultLiquidation(vault, missingInAmt)` and rewrites the last swap in place, honouring its `withAbsorb` flag. For output-target mode, the missing-in-amount derivation splits between the bare-liquidity ratio and the absorb-only ratio (absorb-only = `inAmtWithAbsorb - inAmt, outAmtWithAbsorb - outAmt`) depending on which covers the remaining gap best.

## 9. Errors

| Code | Name | When |
| --- | --- | --- |
| `FluidVaultLiquidationsResolver__AddressZero` | Constructor or `getSwapTx` zero protocol/receiver. |
| `FluidVaultLiquidationsResolver__InvalidParams` | `getSwapTx` with `slippage >= 1e6`, `inAmt == 0`, or `outAmt == 0`. |

No protocol-state revert paths: an unconfigured vault, a zero-liquidatable vault, or a fully-withdraw-limit-pinned vault all silently produce an empty `Swap` entry that downstream filters skip.

## 10. Deployment Checklist

1. `FluidVaultResolver` and `FluidLiquidity` must already be deployed — the two constructor pointers.
2. Deploy `FluidVaultLiquidationResolver(vaultResolver, liquidity)`. Constructor reverts on either zero.
3. No post-deploy wiring — no auth, no governance step. Register the address in `deployments.md`.
4. Re-deploy whenever **(a)** the vault-resolver `LiquidationStruct` shape changes, **(b)** Liquidity's `userSupply` or `exchangePricesAndConfig` slot layout changes, **(c)** `FluidProtocolTypes.VAULT_T1_TYPE` encoding changes, or **(d)** a new re-hypothecation venue is onboarded in `ResolverHelpers`.

## 11. Invariants & Safety Notes

- **T1 only.** The resolver filters by `VAULT_T1_TYPE` and uses `IFluidVaultT1.constantsView()` to resolve tokens. Calling it with a T2/T3/T4 vault address outside the filter path is not supported — those vaults need a DEX-aware liquidation resolver.
- **Call with `eth_call`.** `getVaultSwapData` and everything that composes it are non-`view` because the underlying vault-resolver liquidation simulation uses a revert-for-data path. Keepers must use `eth_call` / `callStatic`; submitting on-chain burns gas and produces no state change but is wasteful.
- **Clamp parity with Liquidity.** `_getVaultT1Withdrawable` is bit-for-bit the same check the vault would hit mid-`liquidate()`: it reads the packed `userSupplyData`, decompresses via `BigMathMinified`, runs `LiquidityCalcs.calcWithdrawalLimitBeforeOperate`, converts raw→interest if bit 0 is set, then mins with `balanceOf(LIQUIDITY) + externalBalance`. Keepers can trust that a post-clamp `Swap` will not fail the Liquidity limit check.
- **Ratio monotonicity vs absorb.** `inAmtWithAbsorb >= inAmt` and `outAmtWithAbsorb >= outAmt` always, but ratio is not monotone — absorb can have a worse ratio when absorbed bad debt dilutes recovery. `_getBetterRatioSwapData` picks ratio, falling back to non-absorb on tie.
- **Targeting is not guaranteed-exact on the output side.** Liquidation output is a stateful function of remaining bad debt, so `approxOutput` only approximates. Production bots should drive off `exactInput` with a `slippage`-gated `colPerUnitDebt`.
- **Bubble-sort in `_sortByRatio`.** O(n²) with an early-exit on no-swap passes. Sized for `n ≤ T1-vault count` (≤ 50 realistically); at that scale the simplicity is worth more than a quicksort.
- **Dedup rule.** Within `_filterSwapsUntilTarget`, two entries on the same vault collapse to just the `withAbsorb` entry (as it already includes the without-absorb liquidity); if only non-absorb was selected first but both were present, the non-absorb is the one dropped. This prevents double-counting because an on-chain `liquidate(..., absorb=true)` always consumes the bare liquidity first.
- **No re-hypothecation leak.** Withdrawable computation adds `_getLiquidityExternalBalances`, so WEETH / WEETHS liquidations are sized using the *total* Liquidity-owned collateral (balance + Zircuit stake), matching the Liquidity withdraw path.
- **Native token.** Pass `0xEeee...EEeE` — resolver dispatches to `address(LIQUIDITY).balance` instead of `balanceOf`. The `getSwapTx` caller is responsible for attaching `msg.value == inAmt` when broadcasting if `tokenIn` is native.

## 12. Trust Model & Audit Notes

- **No trust needed.** Pure read + calldata-assembler. A malicious resolver can return bad swap sizes (leading to reverts or suboptimal keeper fills) but cannot move funds or corrupt state. Keepers own the final tx and its slippage gate.
- **Calldata selector.** `getSwapTx` encodes against `IFluidVaultT1.liquidate.selector`; auditors should diff this selector against the current deployed T1 vault ABI on every T1 redeploy. A selector mismatch would silently produce non-executing calldata.
- **`colPerUnitDebt` slippage floor.** `colPerUnitDebt_ = (outAmt * 1e18 / inAmt) * (1e6 - slippage) / 1e6`. Integer division rounds toward zero twice; in the worst case the actual floor is one wei per 1e18 below the nominal. Keepers should choose `slippage` with that cushion in mind.
- **Non-view labelling is load-bearing.** Declaring the sizing paths as non-`view` prevents accidental usage inside on-chain contracts that expect `STATICCALL` semantics; composing another protocol on top of this resolver must go through `eth_call`.
- **Upgrade coupling.** Any change to `VaultResolver.getVaultLiquidation` return shape, `Liquidity` supply-slot layout, or `FluidProtocolTypes` encoding requires a coordinated resolver redeploy. The old resolver will continue returning numerically-wrong-but-non-reverting swaps until keepers migrate.
- **Gas.** `getAllVaultsSwap` is O(T1-vault count) `getVaultLiquidation` simulations plus two Liquidity SLOADs + one balance read per non-zero-size vault; the filter / sort layer is O(n²) on top. Always `eth_call`, never on-chain.
