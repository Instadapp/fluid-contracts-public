# Periphery / resolvers / smartLending — SPEC

## 1. Purpose

Read-only aggregator over the **Fluid Smart Lending protocol** — the ERC-20 wrappers (`fSL{dexId}`) that tokenize a single [`FluidDexT1`](../../../protocols/dex/poolT1/SPEC.md) pool's **smart-collateral** position (see [smart-lending protocol SPEC](../../../protocols/dex/smartLending/SPEC.md)). Callers get a single RPC surface to:

- enumerate all deployed `fSL` tokens (one per `dexId`) and look them up by `dexId`,
- fetch per-`fSL` metadata (name/symbol/decimals, underlying DEX + token pair, total supply, `exchangePrice`, `feeOrReward`, `lastTimestamp`, rebalancer, `rebalanceDiff`),
- compute derived values (`assetsPerShare`, `sharesPerAsset`, `totalUnderlyingShares`, and — when called with the underlying DEX loaded — `totalUnderlyingAssetsToken{0,1}`),
- read per-user positions (`fSL` share balance, underlying DEX-share equivalent, wallet token balances + allowances, and optionally per-token underlying asset amounts),
- compose cross-layer views by re-using the sibling [`FluidDexResolver`](../dex/SPEC.md) for the underlying pool's `UserSupplyData` and `DexEntireData`.

The resolver is **pure view in spirit**: it holds no state, no authority, and no balances. A handful of methods are declared non-`view` only because they call through to `FluidDexResolver.getDexEntireData` / `getDexState`, which in turn route through DEX estimator paths that `solc` cannot prove are view-only. In practice none of them write state — **callers must use `eth_call` / `callStatic`**.

## 2. Architecture & Data Flow

```mermaid
flowchart LR
    UI[Caller: UI / indexer / bot] --> SLR[FluidSmartLendingResolver]
    SLR -->|allTokens, getSmartLendingAddress| SLF[(FluidSmartLendingFactory)]
    SLR -->|ERC20 meta, exchangePrice, feeOrReward, rebalancer, rebalanceDiff, DEX, TOKEN0, TOKEN1| SL[(FluidSmartLending fSL{dexId})]
    SLR -->|getUserSupplyData, getDexState, getDexEntireData| DR[(FluidDexResolver)]
    SLR -->|balanceOf, allowance, native balance| T0T1[(token0 / token1 / native)]
```

Per-call flow for `getSmartLendingEntireViewData(fSL)`:

1. Read ERC-20 metadata from the `fSL` (`name`, `symbol`; `decimals` is hard-coded `18`).
2. Read `TOKEN0`, `TOKEN1`, `DEX` immutables from the `fSL`.
3. Read `lastTimestamp`, `feeOrReward`, `rebalancer`, `rebalanceDiff` from storage.
4. Call `getUpdateExchangePrice()` to get the `exchangePrice` **projected to `block.timestamp`** with `feeOrReward` accrual applied.
5. Compute `assetsPerShare = 1e36 / exchangePrice`, `sharesPerAsset = exchangePrice`, and `totalUnderlyingShares = totalSupply × exchangePrice / 1e18`.
6. Delegate to `DEX_RESOLVER.getUserSupplyData(dex, fSL)` to fill `dexUserSupplyData` — i.e. how much DEX smart-collateral the wrapper itself holds.

`getSmartLendingEntireData(fSL)` (non-view) additionally pulls `DEX_RESOLVER.getDexEntireData(dex)` and projects `totalUnderlyingAssetsToken{0,1}` from `dexState.token{0,1}PerSupplyShare`.

## 3. External Interactions

- **Reads only.** No state-changing calls anywhere in the contract.
- `FluidSmartLendingFactory`: `allTokens()`, `getSmartLendingAddress(dexId)`.
- `FluidSmartLending` (per instance): `name()`, `symbol()`, `totalSupply()`, `balanceOf(user)`, `TOKEN0()`, `TOKEN1()`, `DEX()`, `lastTimestamp()`, `feeOrReward()`, `getUpdateExchangePrice()`, `rebalancer()`, `rebalanceDiff()`.
- `FluidDexResolver`: `getUserSupplyData(dex, fSL)`, `getDexState(dex)`, `getDexEntireData(dex)`.
- `IERC20` on `TOKEN0` / `TOKEN1`: `balanceOf(user)`, `allowance(user, fSL)` — skipped (allowance untouched, balance replaced by native) when the token sentinel is `_NATIVE_TOKEN_ADDRESS`.
- Sentinel: `_NATIVE_TOKEN_ADDRESS = 0xEee…EEeE` — identifies the native-ETH leg of native-pair Smart Lending instances; triggers `address(user).balance` as the balance read and leaves `allowance` at zero.

## 4. Roles & Access Control

None. Every external / public method is callable by anyone, and none of them writes state. There is no owner, admin, guardian, pausable surface, or `onlyX` modifier in the contract. The resolver also exposes no factory-level auth passthroughs — consumers that need to introspect `FluidSmartLendingFactory` auth state should query the factory directly (see [protocols/dex/smartLending/SPEC.md](../../../protocols/dex/smartLending/SPEC.md)).

## 5. Storage Layout

The contract has **no mutable storage**. Two immutables set once in the constructor:

| Name | Type | Meaning |
| --- | --- | --- |
| `DEX_RESOLVER` | `FluidDexResolver` | Sibling resolver over the DEX layer. Used to pull `UserSupplyData`, `DexState`, and `DexEntireData` for the underlying pool. |
| `SMART_LENDING_FACTORY` | `FluidSmartLendingFactory` | Canonical Smart Lending factory. Source of `allTokens()` and `getSmartLendingAddress(dexId)`. |

Internal constants:

- `SECONDS_PER_YEAR = 365 days` (reserved for future APR derivation; currently unused in return values).
- `_NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` — sentinel marking the native-ETH leg of a native-pair instance.

Constructor reverts with `FluidSmartLendingResolver__AddressZero` if either immutable is zero. After construction no governance / owner / upgrade surface exists.

## 6. Enumeration Views

| Method | Returns | Notes |
| --- | --- | --- |
| `getAllSmartLendingAddresses()` | `address[]` | Every `fSL` ever deployed by `SMART_LENDING_FACTORY`. Order is factory-enumeration order; IDs are dense by `dexId`. |
| `getSmartLendingAddress(dexId)` | `address` | CREATE3-derived address for the given `dexId`; returns `address(0)` if no `fSL` has been deployed for that DEX yet. Does **not** check `code.length`. |

## 7. Smart Lending Detail Views

### View-only (safe for `eth_call`, no DEX-estimator round-trip)

| Method | Purpose |
| --- | --- |
| `getSmartLendingEntireViewData(fSL)` | Full `SmartLendingEntireData` **except** `dexEntireData` / `totalUnderlyingAssetsToken{0,1}` (both zeroed). Includes ERC-20 metadata, token pair, DEX address, projected `exchangePrice`, `feeOrReward`, `lastTimestamp`, `rebalancer`, `rebalanceDiff`, `totalUnderlyingShares`, `assetsPerShare`, `sharesPerAsset`, and the wrapper's own `dexUserSupplyData` (supply at the DEX). |
| `getSmartLendingEntireViewDatas(fSLs[])` | Batch: calls `getSmartLendingEntireViewData` for each input address. |
| `getAllSmartLendingEntireViewDatas()` | Batch over `getAllSmartLendingAddresses()`. |

### `callStatic` (routes through DEX `DexEntireData`)

| Method | Purpose |
| --- | --- |
| `getSmartLendingEntireData(fSL)` | As above **plus** `dexEntireData` and `totalUnderlyingAssetsToken{0,1}` derived from `dexState.token{0,1}PerSupplyShare`. Declared non-`view` solely because `FluidDexResolver.getDexEntireData` itself is non-`view`. |
| `getSmartLendingEntireDatas(fSLs[])` | Batch. |
| `getAllSmartLendingEntireDatas()` | Batch over `getAllSmartLendingAddresses()`. |

`exchangePrice` is always projected forward — it reflects `feeOrReward` accrual up to `block.timestamp`, not the last-stored value. `rebalanceDiff` is the storage-recorded delta between the DEX-side smart-lending shares and the wrapper's computed NAV (positive ⇒ fees to collect, negative ⇒ rewards to fund). `feeOrReward` is a signed `int256` in the wrapper's `1e6` units (positive ⇒ rewards to holders, negative ⇒ fee from holders).

## 8. User Position Views

### Per-instance

| Method | Returns | Notes |
| --- | --- | --- |
| `getUserPositionView(fSL, user)` | `UserPosition` with `underlyingAssetsToken{0,1}` zeroed. Fills `smartLendingAssets = fSL.balanceOf(user)`, `underlyingShares = smartLendingAssets × exchangePrice / 1e18` (projected), `underlyingBalanceToken{0,1}`, `allowanceToken{0,1}`. |
| `getUserPosition(fSL, user)` | Non-`view`; as above plus `underlyingAssetsToken{0,1} = underlyingShares × dexState.token{0,1}PerSupplyShare / 1e18`. |

### Portfolio

| Method | Returns | Notes |
| --- | --- | --- |
| `getUserPositionsView(user)` | `SmartLendingEntireDataUserPosition[]` built from `getAllSmartLendingEntireViewDatas()` + `getUserPositionView(...)` per entry. `dexEntireData` / `totalUnderlyingAssets*` / `underlyingAssetsToken*` are zeroed. |
| `getUserPositions(user)` | Non-`view`; uses `getAllSmartLendingEntireDatas()` + `getUserPosition(...)`, so every field is populated. |

**Native-pair quirk.** If `TOKEN0` (resp. `TOKEN1`) is `_NATIVE_TOKEN_ADDRESS`, the resolver substitutes `address(user).balance` for `underlyingBalanceTokenN` and leaves `allowanceTokenN` at `0` (no ERC-20 approval is needed for native-ETH deposits; Smart Lending's `depositPerfect` / `deposit` accept `msg.value` directly). Consumers rendering both tokens must treat a zero `allowance` on a native leg as "not applicable", not "approval required".

## 9. Errors

| Name | When |
| --- | --- |
| `FluidSmartLendingResolver__AddressZero` | Constructor called with `dexResolver_ == 0` or `smartLendingFactory_ == 0`. |

No other custom errors. Downstream reverts propagate unchanged:

- A revert from any `fSL` method (`balanceOf`, `getUpdateExchangePrice`, …) or the underlying ERC-20 (`balanceOf`, `allowance`) surfaces as-is.
- A revert from `FluidDexResolver` (e.g. DEX unconfigured) surfaces as-is.
- Querying `getSmartLendingAddress(dexId)` for a `dexId` that has no wrapper returns `address(0)`, **not** a revert; feeding that zero into any detail method will revert inside the first call against the zero address.

## 10. Deployment Checklist

1. Ensure `FluidSmartLendingFactory` is deployed and at least one `fSL` has been created (resolver works with zero, but most callers expect a non-empty `getAllSmartLendingAddresses()`).
2. Deploy `FluidDexResolver` first — it is an immutable constructor pointer and must exist at a stable address; it also transitively depends on `FluidLiquidityResolver` (see [resolvers/dex/SPEC.md](../dex/SPEC.md)).
3. Deploy `FluidSmartLendingResolver(dexResolver, smartLendingFactory)`. Constructor reverts on any zero address; no post-deploy wiring.
4. Register the resolver address in `deployments/*.md`; UIs / indexers point to it directly.
5. No privileged setup, no guardian or auth registration — the resolver never calls privileged methods.
6. Redeploys are free: a new resolver supersedes the old one by address. Old resolvers keep working as long as their `DEX_RESOLVER` + factory targets remain live and their storage layouts are unchanged.

## 11. Invariants & Safety Notes

- **Pure view in spirit.** No method mutates state; no payable fallback; no delegatecall; no assembly. The non-`view` labels on `getSmartLendingEntireData*` / `getUserPosition(s)` are inherited from `FluidDexResolver` and do **not** reflect any actual state change.
- **`eth_call` / `callStatic` only.** Sending a live tx to the non-`view` methods wastes gas and still produces a read-only result. Integrators must route those paths through static calls.
- **No balances.** The contract never holds ETH or tokens. There is no rescue path and none is needed.
- **Projected exchange price.** `exchangePrice` in every returned struct is `getUpdateExchangePrice()` — accrued to `block.timestamp`, not the last-stored value. Consumers doing historical math should call the `fSL` directly for the stored field.
- **`assetsPerShare = 1e36 / exchangePrice`** and **`sharesPerAsset = exchangePrice`.** Both are returned for explicitness; they carry the same information.
- **`totalUnderlyingShares = totalSupply × exchangePrice / 1e18`.** This is the wrapper's NAV in DEX-smart-collateral shares; it may diverge from the actual DEX-recorded share count by `rebalanceDiff` until `rebalance()` is called on the `fSL`.
- **`rebalanceDiff` sign convention is inverted vs the underlying storage.** The struct exposes it as `uint256`, matching `FluidSmartLending.rebalanceDiff()`'s storage type; consumers must combine it with `feeOrReward`'s sign to decide direction (fee collection vs reward funding).
- **Zero `dexEntireData` / `totalUnderlyingAssetsToken*` in view paths is intentional** — those fields require a DEX round-trip and are only filled by the non-`view` variants. Consumers rendering TVL in underlying asset terms must use the non-`view` path.
- **Batch methods scale linearly.** `getAllSmartLendingEntireViewDatas` / `getAllSmartLendingEntireDatas` / `getUserPositions*` do O(N) external round-trips where N = `allTokens().length`. With a DEX resolver round-trip per entry, the non-`view` batch is the heaviest; it is off-chain only.
- **No per-entry try/catch.** A revert from one `fSL` or DEX aborts the entire batch. Callers that need partial data should iterate `getAllSmartLendingAddresses()` off-chain.
- **Native-pair detection is immutable-based.** The `_NATIVE_TOKEN_ADDRESS` check is performed on `TOKEN0` / `TOKEN1` (the `fSL`'s immutables), so it cannot be spoofed post-deploy.
- **No re-hypothecation offset.** Smart Lending positions live on the DEX, not directly on Liquidity, so `ResolverHelpers` (see [resolvers/SPEC.md](../SPEC.md) §4) is not inherited here; any Liquidity-level offset is already applied by `FluidDexResolver` upstream.

## 12. Trust Model & Audit Notes

- **No trust placed in the resolver.** It is a stateless read aggregator; compromising it is equivalent to reading the same data directly from `FluidSmartLendingFactory` / each `fSL` / `FluidDexResolver` / the underlying ERC-20s. There is no privileged state to steal and no path that could mislead on-chain consumers into writes.
- **Off-chain-only consumer model.** UIs / indexers / bots treat resolver output as untrusted data that must pass their own sanity checks. On-chain contracts should **not** take resolver output as authoritative — they should read `fSL.exchangePrice` / `fSL.balanceOf` / DEX state directly.
- **Upgrade = redeploy.** Immutable constructor pointers and no storage mean governance has nothing to rotate. Improvements ship as new deployments with a new address; old resolvers continue to function until their targets' storage layouts change.
- **Audit focus points**: (a) the `getUpdateExchangePrice` call is made twice in some paths (once inside `getSmartLendingEntireViewData`, once inside `getUserPositionView`) — returned values may drift by exactly the block-level accrual between calls, which is acceptable for read-only output but worth noting for tight precision tests; (b) `userPosition.underlyingShares` uses the per-user-call `exchangePrice`, not the batch's parent call — ensure those are consistent in any cross-field invariant a consumer relies on; (c) native-pair `allowanceTokenN = 0` must not be misread as "user hasn't approved"; (d) batch loops use `unchecked { i++ }` safely.
- **Trust boundaries downstream.** Any misbehaviour in `FluidSmartLendingFactory`, an `fSL`, `FluidDexResolver`, or an underlying ERC-20 will surface in resolver output verbatim. The resolver does **not** normalise, reorder, or filter the data it aggregates.
- **Malicious underlying tokens** are a real concern for `getUserPosition*`: a bespoke `balanceOf` / `allowance` could return arbitrary values, loop, or consume all gas. Worst case is a failed RPC call — no funds at risk because the resolver is view-only and off-chain-called.
