# Config / dexFeeHandler — SPEC

## 1. Purpose

Permissionless dynamic-fee rebalancer for a single Fluid DEX pool. Reads the pool's last stored price (or the deviation of an arbitrary price from the center price), computes a target fee on a **smooth-step curve** bounded by `[MIN_FEE, MAX_FEE]`, and pushes the result into the DEX admin's `updateFeeAndRevenueCut(...)` — preserving the existing revenue cut unchanged. Intended to widen the fee as the pool drifts away from its pegged center and tighten it near the peg.

Counterpart to the multisig-only [`dexFeeAuth`](../SPEC.md#6-dexfeeauth): this handler is the **permissionless, continuously-running** fee setter; `dexFeeAuth` is the high-trust manual override. Only one is expected to be active as an auth on a given DEX at a time.

Single contract: `FluidDexFeeHandler` in `main.sol`, assembled as a diamond of abstract layers (`Events` → `Constants` → `DexHelpers` → `DynamicFee` → `FluidDexFeeHandlerHelpers` → `FluidDexFeeHandler`).

Cross-reference: [../SPEC.md](../SPEC.md) for the shared config-handler pattern, error layout and trust model.

## 2. Architecture & Data Flow

```mermaid
flowchart LR
    RB[Reserve rebalancer] -->|rebalance()| H[FluidDexFeeHandler]
    H -->|readFromStorage: dexVariables / dexVariables2 / centerPriceShift| DEX[(Fluid DEX pool)]
    H -. optional staticcall .-> CP[(Center price hook contract)]
    H -->|updateFeeAndRevenueCut newFee, currentRevenueCut*1e4| DEXA[DEX admin module]
    DEXA -->|writes fee bits 2..18 of dexVariables2| DEX
    H -. emit LogRebalanceFeeAndRevenueCut .-> LOG[(chain log)]
```

Per call:
1. `rebalance()` gated by `RESERVE_CONTRACT.isRebalancer(msg.sender)`.
2. Fetch `lastStoredPriceOfPool` (or `lastToLastStoredPrice` if the pool was already touched this block) from `dexVariables`.
3. Fetch / derive `centerPrice` from `dexVariables2` + `centerPriceShift` + (optionally) an external hook contract.
4. Compute deviation `(|price − center|) / center` in 1e27 scale (or `|price − 1|` if `CENTER_PRICE_ACTIVE == false`).
5. Map deviation to fee via smooth-step `3α² − 2α³` between `MIN_FEE` and `MAX_FEE`.
6. If the relative change vs. currently stored fee exceeds `UPDATE_FEE_TRIGGER_BUFFER` (fixed 10 = 0.1%), push via `IFluidDexT1Admin(DEX).updateFeeAndRevenueCut(newFee, currentRevenueCut * 1e4)`; otherwise revert `DexFeeHandler__FeeUpdateNotRequired`.

## 3. External Interactions

| Target | Call | Direction | Purpose |
| --- | --- | --- | --- |
| `DEX` (the configured Fluid DEX pool) | `readFromStorage(DEX_VARIABLES_SLOT)` | read | Pull last stored prices + last-interaction timestamp. |
| `DEX` | `readFromStorage(DEX_VARIABLES2_SLOT)` | read | Pull current fee, revenue cut, center-price hook pointer, min/max center price, shift-active bit. |
| `DEX` | `readFromStorage(DEX_CENTER_PRICE_SHIFT_SLOT)` | read | Shift start-time / percent / duration when a center-price shift is in progress. |
| Center-price hook contract (computed via `AddressCalcs.addressCalc(DEPLOYER_CONTRACT, nonce)`) | `centerPrice()` | staticcall | External peg source (e.g. wstETH → ETH rate). Nonce comes from bits 112..141 of `dexVariables2`. Reverts via `require(success_, "Static call failed")` if the staticcall fails. |
| `DEX` admin module (`IFluidDexT1Admin`) | `updateFeeAndRevenueCut(newFee, currentRevenueCut * 1e4)` | write | Only mutating external call; auth'd by the DEX's own auth registry (this handler must be registered as an auth on the DEX). |
| `RESERVE_CONTRACT` | `isRebalancer(sender)` | read | Gate on `rebalance()`. |

Implicit dependency: this handler must be set as an **auth on the DEX** for `updateFeeAndRevenueCut` to succeed; otherwise the DEX admin check reverts.

## 4. Roles & Access Control

| Method | Gate | Revert on fail |
| --- | --- | --- |
| `rebalance()` | `RESERVE_CONTRACT.isRebalancer(msg.sender) == true` | `DexFeeHandler__Unauthorized` (100083) |
| all view methods | open | — |
| constructor param validation | `validAddress(dex_)`, `validAddress(deployerContract_)`, `validAddress(reserveContract_)` | `DexFeeHandler__InvalidParams` (100082) |

There are no admin setters after construction: every parameter (min/max fee, min/max deviation, DEX address, deployer contract, reserve contract, `CENTER_PRICE_ACTIVE`, `UPDATE_FEE_TRIGGER_BUFFER`) is `immutable`. Rotating any parameter requires **redeploying** and re-registering the handler as DEX auth.

Trust lattice:

- **Reserve rebalancer** (delegated via [`FluidReserveContract`](../../reserve/SPEC.md)) — can trigger fee pushes at will, but every push is bounded by the immutable `[MIN_FEE, MAX_FEE]` and shaped by on-chain price state. Worst-case abuse is thus capped.
- **DEX governance** — owns `updateFeeAndRevenueCut` at the DEX layer; can de-register this handler at any time.

## 5. Storage Layout

`FluidDexFeeHandler` is **stateless** at runtime — every configuration value is `immutable` and set in the constructor.

### Immutables

| Name | Type | Meaning |
| --- | --- | --- |
| `DEX` | `address` | Target DEX pool this handler manages. |
| `DEPLOYER_CONTRACT` | `address` | Deployer used by `AddressCalcs` to derive the center-price hook contract address from its nonce. |
| `CENTER_PRICE_ACTIVE` | `bool` | If `true`, deviation is measured vs. the pool's center price; if `false`, vs. the constant `1e27` (SCALE) — i.e. used for pegged pools where center == 1. |
| `MIN_FEE` | `uint256` | Lower fee clamp in 4-decimal scale (10 000 == 1%). Enforced `> 0`. |
| `MAX_FEE` | `uint256` | Upper fee clamp. Enforced `> 0`, `< 1e4` (i.e. strictly below 1%), and `≥ MIN_FEE`. |
| `MIN_DEVIATION` | `uint256` | Deviation (1e27 scale) at or below which fee saturates to `MIN_FEE`. Enforced `> 0`. |
| `MAX_DEVIATION` | `uint256` | Deviation at or above which fee saturates to `MAX_FEE`. Enforced `> 0`, `≥ MIN_DEVIATION`. |
| `UPDATE_FEE_TRIGGER_BUFFER` | `uint256` | Hard-coded to `10` (0.1%). Minimum **relative** fee change (scaled 1e4) that allows a rebalance to push through; anything `≤ 10` reverts. |
| `RESERVE_CONTRACT` | `IFluidReserveContract` | Source of truth for rebalancer membership. |

### Bit layouts read from the DEX

| Field | Source slot | Bits | Notes |
| --- | --- | --- | --- |
| `lastToLastStoredPrice` | `dexVariables` | 1..40 | BigMath (coefficient<<exponent). |
| `lastStoredPriceOfPool` | `dexVariables` | 41..80 | BigMath. |
| `centerPrice` (in `_calcCenterPrice`) | `dexVariables` | 81..120 | BigMath. |
| `lastInteractionTimeStamp` / `fromTimeStamp` | `dexVariables` | 121..153 | 33 bits. |
| current fee | `dexVariables2` | 2..18 | 17 bits, 1e4 scale. |
| current revenue cut | `dexVariables2` | 19..25 | 7 bits, DEX internal units (see §2 of the top-level SPEC on the `* 1e4` wire convention). |
| center-price hook nonce | `dexVariables2` | 112..141 | 30 bits; if nonzero, points at an external center-price source. |
| maxCenterPrice | `dexVariables2` | 172..199 | 28 bits, BigMath. |
| minCenterPrice | `dexVariables2` | 200..227 | 28 bits, BigMath. |
| center-price shift active | `dexVariables2` | 248 | 1 bit — if set, `_calcCenterPrice` interpolates. |

There are **no cooldown or time-bucket slots** — rate limiting is exclusively magnitude-based (`UPDATE_FEE_TRIGGER_BUFFER`).

## 6. Public Methods

### `rebalance() external onlyRebalancer`

The only state-changing method.

1. `newFee = getDexDynamicFee()`.
2. `(currentFee, currentRevenueCut) = getDexFeeAndRevenueCut()`.
3. `change = _configPercentDiff(currentFee, newFee)` (returns `|new−current| * 1e4 / current`, `0` if equal).
4. If `change > UPDATE_FEE_TRIGGER_BUFFER` (10), call `IFluidDexT1Admin(DEX).updateFeeAndRevenueCut(newFee, currentRevenueCut * 1e4)` and emit `LogRebalanceFeeAndRevenueCut(DEX, newFee, currentRevenueCut * 1e4)`.
5. Else revert `DexFeeHandler__FeeUpdateNotRequired`.

**Edge cases:**
- `currentFee == 0` → division by zero inside `_configPercentDiff` → revert. In practice the DEX fee is non-zero on a live pool.
- The condition is **strict** `>` 0.1%, so a change of exactly 0.1% reverts — update threshold is "> 10", i.e. > 0.1%.
- The revenue cut is forwarded as `currentRevenueCut * 1e4` to match the DEX admin wire format — **the handler never changes the revenue cut**, only the fee.
- If the pool was touched in the current block (`lastInteractionTimeStamp == block.timestamp`), the fee is computed off `lastToLastStoredPrice` to avoid MEV-amplified feedback from a just-executed swap.

### Views (config-handler interface)

| Method | Returns |
| --- | --- |
| `currentConfig()` | Current fee (bits 2..18 of `dexVariables2`). |
| `newConfig()` | `getDexDynamicFee()` — the target fee. |
| `absoluteConfigDiff()` | `|newConfig − currentConfig|`. |
| `relativeConfigPercentDiff()` | `|diff| * 1e4 / currentFee` (100 == 1%, 1 == 0.01%). |

Note: `FluidDexFeeHandler` **matches** the `IFluidConfigHandler` shape but does not inherit from `contracts/config/fluidConfigHandler.sol` — the interface is satisfied by signature compatibility. Reserve / resolvers that cast to `IFluidConfigHandler` work against it unchanged.

### Other views

| Method | Purpose |
| --- | --- |
| `getDexDynamicFee()` | Target fee driven by the pool's last stored price. Uses `lastToLastStoredPrice` if `lastInteractionTimeStamp == block.timestamp` to defeat same-block manipulation. |
| `dynamicFeeFromPrice(price)` | Apply the curve to an arbitrary price — useful for off-chain simulation. |
| `dynamicFeeFromDeviation(dev)` | Apply the curve to a pre-computed deviation. |
| `getDeviationFromPrice(price)` | `|price − center| / center` in 1e27 scale if `CENTER_PRICE_ACTIVE`; else `|price − 1e27|`. |
| `getDexCenterPrice()` | `_fetchCenterPrice()` — resolves static vs. hook vs. in-progress shift, clamps to `[minCenterPrice, maxCenterPrice]`. |
| `getDexFeeAndRevenueCut()` | Raw read of current fee + revenue-cut from `dexVariables2`. |
| `getDexRevenueCut()` | Revenue-cut field only. |
| `getDexVariables()` | `(lastToLastStoredPrice, lastStoredPriceOfPool, lastInteractionTimeStamp)`. |

### The smooth-step curve

Given `d ∈ [MIN_DEVIATION, MAX_DEVIATION]`:

- `α = (d − MIN_DEVIATION) * 1e27 / (MAX_DEVIATION − MIN_DEVIATION)`
- `smooth = 3α² − 2α³` (all in 1e27 scale via `_scaleMul`)
- `fee = MIN_FEE + smooth * (MAX_FEE − MIN_FEE)`

Outside the window the curve saturates: `d ≤ MIN_DEVIATION ⇒ MIN_FEE`, `d ≥ MAX_DEVIATION ⇒ MAX_FEE`.

## 7. Admin Methods (setters)

**None.** Every knob is `immutable`. Governance "setters" happen by redeploy + re-register at the DEX as auth (and removal of the previous handler's auth registration).

## 8. Events

| Event | Emitted when |
| --- | --- |
| `LogRebalanceFeeAndRevenueCut(address dex, uint fee, uint revenueCut)` | `rebalance()` succeeds. `revenueCut` is the wire-format value actually written (`currentRevenueCut * 1e4`). |

No constructor / admin events — the contract has no mutable config.

## 9. Errors

All errors are raised as `FluidConfigError(errorId_)` from `contracts/config/error.sol`.

| Code | Name | When |
| --- | --- | --- |
| 100081 | `DexFeeHandler__FeeUpdateNotRequired` | `rebalance()` computed a change `≤ 0.1%` relative to the current fee. |
| 100082 | `DexFeeHandler__InvalidParams` | Constructor: `dex_ == 0`, `deployerContract_ == 0`, or `reserveContract_ == 0`; or any of `_minFee`, `_maxFee`, `_minDeviation`, `_maxDeviation` is `0`; or `_maxFee >= 1e4` (>= 1%); or `_minDeviation > _maxDeviation`; or `_minFee > _maxFee`. |
| 100083 | `DexFeeHandler__Unauthorized` | `rebalance()` called by a non-rebalancer. |

See [../SPEC.md §3.4](../SPEC.md#34-error-convention) for the shared error layout and the 100081–100083 range reservation.

## 10. Invariants & Safety Notes

- **Fee is always clamped to `[MIN_FEE, MAX_FEE]`.** The smooth-step curve returns exactly `MIN_FEE` below `MIN_DEVIATION` and exactly `MAX_FEE` above `MAX_DEVIATION`; in-between values are strictly increasing in deviation (monotone).
- **Max fee cannot reach 1%.** Constructor enforces `MAX_FEE < 1e4` so a buggy deploy cannot set a pathological cap.
- **Revenue cut is never mutated by this contract.** It is read from `dexVariables2` and passed straight back (after the `* 1e4` scale adjustment the DEX admin API expects). Any change to the revenue cut must come from [`dexFeeAuth`](../SPEC.md#6-dexfeeauth) or direct DEX governance.
- **Same-block MEV mitigation.** If the pool was touched in the current block, fee is derived from `lastToLastStoredPrice`, not the freshly-moved `lastStoredPriceOfPool`. This prevents a swap-then-rebalance sandwich from weaponising the fee curve.
- **Minimum-change gate.** `UPDATE_FEE_TRIGGER_BUFFER = 10` (0.1% relative) ensures trivial noise cannot spam fee writes or amplify oracle jitter into DEX state churn.
- **Center-price shift is respected.** `_calcCenterPrice` reproduces the DEX's own gradual-shift logic so that during an active shift the deviation is measured against the **in-motion target**, not a stale endpoint.
- **No funds held.** The handler never receives tokens or ETH, has no `receive` path and no `rescueTokens`.
- **Division-by-zero on `currentFee == 0`.** If governance ever sets the DEX fee to zero, `rebalance()` will revert at `_configPercentDiff`; this is safe (no bad state) and resolvable by governance nudging the fee off zero first via `dexFeeAuth`.
- **Staticcall to the center-price hook can revert.** `_getCenterPriceFromCenterPriceAddress` uses `require(success_, "Static call failed")`. A misconfigured or self-destructed hook therefore halts `rebalance()` and every price-dependent view. This is intentional fail-closed behaviour.

## 11. Trust Model

- **Root of trust: DEX governance + reserve-rebalancer set.** DEX governance chooses whether this handler is an auth on the pool at all; the reserve-rebalancer set controls who can trigger `rebalance()`.
- **Bounded damage model.** A rogue rebalancer can only oscillate the fee within `[MIN_FEE, MAX_FEE]`, and only when the on-chain deviation signal supports it (the pure-deviation variant cannot be set to an arbitrary value — it must correspond to the measured pool state or a static-call to the center-price hook). They cannot change the revenue cut, pause the pool, or touch user funds.
- **Oracle trust.** When `CENTER_PRICE_ACTIVE == true` and a non-zero center-price hook nonce is set on the DEX, the center price is whatever the hook returns. This pushes oracle trust into the hook contract selected by DEX governance; this handler merely forwards its output (subject to the DEX's own `[minCenterPrice, maxCenterPrice]` clamp, which `_fetchCenterPrice` applies).
- **No upgradability.** Because every knob is immutable, governance cannot silently change the fee curve. Every change in curve parameters is a visible redeploy + DEX auth rotation, auditable on-chain.

## 12. Deployment Checklist / Audit Notes

### Deploy
1. Choose `minFee`, `maxFee`, `minDeviation`, `maxDeviation` consistent with §5 constraints (all non-zero, `maxFee < 1e4`, `minDeviation ≤ maxDeviation`, `minFee ≤ maxFee`).
2. Set `centerPriceActive_` to match the DEX configuration: `true` for pools whose center price is a moving peg (wstETH/ETH, sUSDe/USDC, …), `false` for pools whose center is a hard 1 (stable/stable at parity).
3. Pass `dex_`, `deployerContract_` (the DEX deployer used for `AddressCalcs`), and the live `FluidReserveContract`.
4. Deploy `FluidDexFeeHandler`.
5. **Register** the handler as an **auth** on the target DEX (via DEX governance / `IFluidDexT1Admin`'s auth management). Without this, `rebalance()` reverts inside the DEX.
6. If a previous `FluidDexFeeHandler` (or `dexFeeAuth`) was active on the same DEX, de-register it to avoid two parameters drifting in opposition.
7. From the reserve-rebalancer side, ensure the expected ops addresses are rebalancers on `FluidReserveContract`.
8. Smoke-test: call `currentConfig()`, `newConfig()`, `relativeConfigPercentDiff()`, `getDexCenterPrice()` off-chain and confirm sensible values before enabling the rebalancer cron.

### Audit notes (absorbed)
- Coexistence with `dexFeeAuth` is deliberate but only one should drive a live pool at a time; the DEX auth registry is the enforcement point.
- The smooth-step curve (`3α² − 2α³`) gives C¹ continuity at the saturation boundaries, avoiding discontinuous fee jumps around `MIN_DEVIATION` / `MAX_DEVIATION` that would be front-runnable.
- Same-block price substitution (using `lastToLastStoredPrice` when the pool was just touched) is the specific mitigation against an attacker moving the pool's stored price and immediately calling `rebalance()` within the same transaction bundle.
- The `UPDATE_FEE_TRIGGER_BUFFER` is immutable and hard-coded to `10` — an audit point: the threshold cannot be tuned without redeploy. This is by design (one fewer governance surface) but means tight-spread pools may need a different handler variant.
- Division-by-zero on `currentFee == 0` is acceptable (reverts cleanly) but documented here so reviewers of new deployments remember to initialise the DEX with a non-zero fee before wiring up the handler.
- The `require(success_, "Static call failed")` string in `_getCenterPriceFromCenterPriceAddress` is the one place the contract does **not** use the `FluidConfigError` pattern; acceptable for a defensive require inside an internal helper but worth noting if the repo standardises on numeric error IDs everywhere.
