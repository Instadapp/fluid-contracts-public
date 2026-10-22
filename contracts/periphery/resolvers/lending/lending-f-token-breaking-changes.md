# Lending & fToken — breaking changes (static rate + resolver)

**Audience:** Front-end, backend, indexer, and analytics integrators consuming **LendingResolver** / fToken data.  
**Applies when:** A new **`FluidLendingResolver`** deployment is live and/or fTokens are upgraded to bytecode that includes the **static rate model** branch (`isStaticRateModelActive`, `updateStaticRewards`).

**Canonical contracts:** `contracts/periphery/resolvers/lending/`, `contracts/protocols/lending/fToken/`, `contracts/protocols/lending/lendingStaticRateModel/`

**Related:** [`SPEC.md`](./SPEC.md) (resolver) · [`fToken/SPEC.md`](../../../protocols/lending/fToken/SPEC.md)

---

## Summary

| Area | Breaking? | Action |
|------|-----------|--------|
| `LendingResolver.getFTokenRewards` | **Yes** — ABI return tuple expanded | Decode `relativeModelRate_`, `staticModelRate_`, `isStaticRate_`, `liquidityRate_`, `totalRate_`, **`rewardsActive_`**; update ABI |
| `LendingResolver.getFTokenDetails` / `FTokenDetails` | **Yes** — struct fields renamed + added | Migrate to `relativeModelRate`, `staticModelRate`, `isStaticRate`, **`rewardsActive`**, `liquidityRate`, `totalRate`, **`accessType`**; read `totalRate` for display APR |
| `LendingResolver.getFTokensEntireData` / `getUserPositions` | **Yes** — nested `FTokenDetails` | Same struct migration |
| `LendingResolver.getDeploymentName` | **Additive** | Permissioned factory name, or `""` on production |
| `LendingResolver.getFTokenRewardsRateModelConfig` | **Yes** — 5th return `int256 maxRateOrStaticRate_`; last return renamed `initiator_` → `configurator_` | Streaming = ceiling (`>= 0`); static = signed Liquidity offset; static `|offset|` ceiling via `getStaticConfig().maxRate` |
| `LendingRewardsRateModel.getConfig` / static legacy `getConfig` | **Yes** — last return renamed `initiator_` → `configurator_` | Same address (CONFIGURATOR); regenerate ABI / named returns |
| fToken `rebalance()` | **No** (same selector / `uint256` return) | **Behavior** — bidirectional (rewards in / fees out) |
| fToken `LogRebalance` | **Yes** — `uint256` → `int256` (topic0 changes) | Positive = deposit/rewards (legacy-compatible); negative = withdraw/fees |
| `FluidLendingStaticRateModel.getStaticConfig` | **Yes** — 5th return `maxRate` | `(staticRate, duration, startTime, configurator, maxRate)`; also has legacy zero `getRate` / `getConfig` stubs |
| New fToken selectors | Additive on new bytecode | `updateStaticRewards`, `isStaticRateModelActive` |
| `FluidLendingStaticRateModel` | New contract | New ABI for governance / ops only |

---

## 1. LendingResolver — ABI breaking changes

Redeploying **`FluidLendingResolver`** changes the ABI for rewards reads and the `FTokenDetails` tuple. **Old decoders will mis-align every field after `convertToAssets`.** Field renames are intentional so integrators cannot silently use the old `rewardsRate + supplyRate` formula.

### 1.1 `getFTokenRewards`

**Legacy (pre-static)**

```solidity
returns (IFluidLendingRewardsRateModel rewardsRateModel_, uint256 rewardsRate_);
```

**Intermediate (static + legacy reshaping — do not use)**

```solidity
returns (IFluidLendingRewardsRateModel rewardsRateModel_, uint256 rewardsRate_, bool isStaticRate_);
```

**Current**

```solidity
function getFTokenRewards(IFToken fToken_)
    external
    view
    returns (
        IFluidLendingRewardsRateModel rewardsRateModel_,
        uint256 relativeModelRate_,
        int256 staticModelRate_,
        bool isStaticRate_,
        uint256 liquidityRate_,
        uint256 totalRate_,
        bool rewardsActive_
    );
```

| Return | Type | Meaning |
|--------|------|---------|
| `rewardsRateModel_` | `address` | Wired rate model (streaming **or** static — same storage slot on fToken) |
| `relativeModelRate_` | `uint256` | TVL-dependent streaming bonus APR (`100` = 1%). **`0` when static program is active** |
| `staticModelRate_` | `int256` | Signed Liquidity APR offset (`100` = 1%). **`0` when streaming program is active** (also `0` when static is wired but not currently accruing) |
| `isStaticRate_` | `bool` | `true` when fToken has a **static** rate model wired (`isStaticRateModelActive()`). Stays `true` after program end / stop until model is unwired |
| `liquidityRate_` | `uint256` | Liquidity-layer `supplyRate` (`100` = 1%, same as legacy `supplyRate`) |
| `totalRate_` | `uint256` | Combined holder APR in Liquidity scale (`100` = 1%) |
| `rewardsActive_` | `bool` | `true` while the wired program is **currently accruing** (`fToken.getData().rewardsActive_`). After stop / natural end this is `false` even if the model stays wired (`isStaticRate_` may still be `true`) |

**ethers / viem:** Regenerate types from the new resolver artifact. Do not decode the old `rewardsRate_` name — it no longer exists.

**Scale change (same function, different units):** legacy `rewardsRate_` was the raw on-chain model rate (`1e12` = 1%). Current `relativeModelRate_` is **rescaled** to Liquidity resolver units (`100` = 1%, i.e. `÷ 1e10`). Example: `3e12` on-chain → `300` in the resolver. **Do not** compare `relativeModelRate_` to `LendingRewardsRateModel.getRate()` without converting.

---

### 1.2 `FTokenDetails` struct (`getFTokenDetails`, `getFTokensEntireData`, `getUserPositions`)

**Legacy field order**

```
…, convertToAssets, rewardsRate, supplyRate, rebalanceDifference, liquidityUserSupplyData
```

(`supplyRate` was Liquidity-layer APR; total APR was often computed as `rewardsRate + supplyRate`.)

**Current field order**

```
…, convertToAssets,
relativeModelRate, staticModelRate, isStaticRate, rewardsActive, liquidityRate, totalRate,
rebalanceDifference, liquidityUserSupplyData, accessType
```

| Field | Meaning |
|-------|---------|
| `relativeModelRate` | Streaming bonus APR on top of Liquidity (`100` = 1%). **`0` when static is active**. Renamed from legacy `rewardsRate`; **rescaled** from on-chain `1e12` = 1% → resolver `100` = 1% (`÷ 1e10`) |
| `staticModelRate` | Signed Liquidity APR offset (`100` = 1%; may be negative). **`0` when streaming is active** or when static is wired but not currently accruing |
| `isStaticRate` | Static model wired on fToken (may stay `true` after program end / stop) |
| `rewardsActive` | Program currently accruing. After stop / natural end: `false` while `isStaticRate` may still be `true` (UI: show Static row + inactive) |
| `liquidityRate` | Liquidity-layer `supplyRate` (`100` = 1%, unchanged scale vs legacy `supplyRate`) |
| `totalRate` | Combined holder APR in Liquidity scale (`100` = 1%; `/ 100` for % display) |
| `accessType` | `ACCESS_TYPE()` on permissioned-stack fTokens: `0` = public/ungated (`fTokenPublic`), `1` = permission-gated. Defaults to `0` when the selector is missing (production fTokens). |

**Also additive (non-struct):** `LendingResolver.getDeploymentName()` — factory `deploymentName()` when present (permissioned stack); empty string on production factories.

**ABI encoding:** Tuple component count and field order both change. Any manual struct decoder must be rewritten — not patched incrementally.

---

### 1.3 `getFTokenRewardsRateModelConfig` — shared tuple; signed dual-purpose rate field

Return arity unchanged (7 values). The 5th field is **`int256 maxRateOrStaticRate_`** (**breaking** vs legacy / prior `uint256`):

```solidity
function getFTokenRewardsRateModelConfig(IFToken fToken_)
    external
    view
    returns (
        uint256 duration_,
        uint256 startTime_,
        uint256 endTime_,
        uint256 startTvl_,
        int256 maxRateOrStaticRate_, // streaming: ceiling (>= 0); static: signed Liquidity offset
        uint256 rewardAmount_,
        address configurator_
    );
```

#### APR scale (`maxRateOrStaticRate_`)

| Source | Scale | Example |
|--------|-------|---------|
| Streaming `getConfig().maxRate` | `1e12` = 1% | `50e12` (= 50% ceiling, always `>= 0`) |
| Static `getStaticConfig().staticRate` (mapped into this field) | `1e12` = 1% | e.g. `1e12` (= +1% offset) or `-3e12` (= −3% offset) |
| Static `getStaticConfig().maxRate` (ceiling on `\|offset\|`; **not** this field) | `1e12` = 1% | `50e12` |

**Note the scale difference vs the APR fields:** `relativeModelRate`, `staticModelRate`, `liquidityRate` and `totalRate` use Liquidity resolver scale (`100` = 1%), while this config field is raw model scale (`1e12` = 1%). Convert with `÷ 1e10` before comparing across the two.

#### Field mapping by model type

| Field | Streaming model | Static model |
|-------|-----------------|--------------|
| `duration_` | Program duration | Static program duration (seconds) |
| `startTime_` | Rewards start | Static rate period start |
| `endTime_` | `start + duration` | `startTime + duration` |
| `startTvl_` | Initial TVL (raw, unchanged) | **`0`** |
| `maxRateOrStaticRate_` | Max streaming APR **ceiling** (`>= 0`) | Signed Liquidity **offset** (may be negative) |
| `rewardAmount_` | Reward budget (raw, unchanged) | **`0`** |
| `configurator_` | Rate-model configurator | Static rate configurator |

For static programs: use `maxRateOrStaticRate_` as the signed offset (same raw value as `getStaticConfig().staticRate`); use `getStaticConfig().maxRate` for the 50% `\|offset\|` ceiling. Do **not** interpret `rewardAmount_` as a budget. Scaled display APR remains `staticModelRate` / `totalRate` on `getFTokenDetails` / `getFTokenRewards`.

---

### 1.4 Unified resolver APR scale (all rate fields)

All **percentage / APR** fields returned by the new resolver use **one scale**:

| Scale | Meaning | Used by |
|-------|---------|---------|
| **`100` = 1%** | Liquidity resolver units (`supplyRate`, vault rates) | `relativeModelRate`, `staticModelRate`, `liquidityRate`, `totalRate` |
| **`1e12` = 1%** | On-chain fToken / rate-model units | `LendingRewardsRateModel`, `FluidLendingStaticRateModel`, `fToken.getRate` paths, and **`maxRateOrStaticRate_`** in `getFTokenRewardsRateModelConfig` (raw pass-through) |

**Rule:** never mix scales in UI math. Convert on-chain reads with `÷ 1e10` before comparing to any resolver field.

**Renames + rescales (legacy → current):**

| Legacy | Current | Scale change |
|--------|---------|--------------|
| `rewardsRate` / `rewardsRate_` | `relativeModelRate` / `relativeModelRate_` | `1e12` → `100` (`÷ 1e10`) |
| `supplyRate` | `liquidityRate` | **unchanged** (`100` = 1%) |
| `getConfig().maxRate` / static signed offset (via resolver) | `maxRateOrStaticRate_` (`int256`) | **unchanged scale** (raw `1e12` = 1%); **static maps signed offset**, streaming maps ceiling |
| (n/a) | `staticModelRate` | new field, already at `100` scale |
| (n/a) | `totalRate` | new field, pre-combined at `100` scale |

## 2. Supply APR — display rules (critical)

**Do not** compute total holder APR as `relativeModelRate + liquidityRate` for static programs.

Use **`details.totalRate`** directly for display APR (`totalRate / 100` → %). **All resolver APR fields** use Liquidity resolver units (`100` = 1%).

**Streaming total is additive (matches fToken accrual):** `totalRate = liquidityRate + relativeModelRate`. The fToken compounds liquidity return % and rewards return % as a **sum** in percent space — not `liquidity × (1 + relative)`. `relativeModelRate` varies with TVL (`yearlyReward / totalAssets`); it is not a magnifier on `liquidityRate` (unlike vault `supplyRateVault = liquidity × magnifier / 10000`).

| Program state | `relativeModelRate` | `staticModelRate` | `liquidityRate` | **`totalRate` (display)** |
|---------------|----------------------|--------------|----------------------|----------------------------|
| Streaming active | streaming bonus (`100` scale) | `0` | Liquidity APR | `liquidity + relative` |
| Static active | `0` | signed offset (`100` scale) | Liquidity APR | **`max(0, liquidity + staticModelRate)`** |
| Static ended / no rewards | `0` | `0` | Liquidity APR | `liquidityRate` |

**Recommended UI (pseudocode):**

```typescript
function displaySupplyApr(details: FTokenDetails): bigint {
  return details.totalRate; // combined holder APR — no manual sum
}

// Optional breakdown labels:
// - Streaming: show relativeModelRate + liquidityRate as components (equals totalRate)
// - Static active: show staticModelRate as signed offset; totalRate = max(0, liquidity + staticModelRate)
// - Static ended: liquidityRate only
```

---

## 3. fToken protocol — behavior & new selectors

Applies to **new fToken bytecode** (permissioned beacons upgraded, or new production fToken types). Existing deployed fTokens without the static branch are unchanged until upgraded.

### 3.1 New view / admin selectors (additive)

| Method | Visibility | Notes |
|--------|------------|-------|
| `isStaticRateModelActive()` | `view` | `true` when static model wired |
| `updateStaticRewards(IFluidLendingStaticRateModel)` | admin (factory auth) | Wire static model; calls `updateRates()` first |

`updateRewards` still exists for **streaming** `LendingRewardsRateModel`. Wiring static clears the streaming flag and vice versa.

### 3.2 `rebalance()` — bidirectional (behavior change)

**Before:** Only topped up Liquidity when `totalAssets > liquidityBalance` (rewards direction). Underflow if Liquidity balance exceeded `totalAssets`.

**After:**

- `totalAssets > liquidityBalance` → deposit from **rebalancer** (rewards direction; native fToken: `msg.value`)
- `liquidityBalance > totalAssets` → withdraw excess to **rebalancer** (fees direction)
- Equal → no-op; refund excess `msg.value` on native

`LogRebalance(int256 assets)` emits a **signed** amount: **positive** = rewards / deposit into Liquidity (same direction as the legacy absolute `uint256` deposit amount), **negative** = fees / withdraw to rebalancer. Magnitude is the absolute amount moved. Topic0 changes vs `LogRebalance(uint256)` — update event ABIs / indexers.

**Integrators / ops:** Resolver `rebalanceDifference` (`liquiditySupply − totalAssets`) uses the **opposite** sign for the same gap: negative difference ⇒ rewards still owed (a successful funding `rebalance` then emits **positive** `LogRebalance`). Positive difference under static ⇒ fees to withdraw (successful fee `rebalance` emits **negative** `LogRebalance`).

### 3.3 Exchange price accrual (static)

When static model is active **and** `_rewardsActive`:

- Token exchange price compounds **Liquidity supply yield and the signed offset** additively (same shape as streaming). Negative offsets can reduce the net window return but never decrease the share EP below the prior value (floored at 0).
- Model rate is capped at ±`MAX_REWARDS_RATE` (50%) inside the fToken.
- When program ends (`getRateV2` → `ended = true`), the fToken settles accrual under the offset **exactly up to `endTime`**; Liquidity yield continues to compound for all subsequent time (no mid-window Liquidity pro-rate at static end). The next `updateRates()` sets `_rewardsActive = false` (while `isStaticRateModelActive` may still be `true` until unwired).
- `rebalance()` bidirectionally aligns Liquidity inventory with `totalAssets()` when the on-chain share price and raw Liquidity balance diverge.

---

## 4. `FluidLendingStaticRateModel` — new contract ABI

Governance / ops only (not end-user facing). Implements `IFluidLendingStaticRateModel`.

### Constructor (breaking vs early drafts)

```solidity
constructor(
    address configurator_,
    address fToken_,
    address fToken2_,      // optional, address(0) if unused
    address fToken3_,      // optional
    int256 initialRate_,  // signed offset, 1e12 = 1%
    uint256 duration_      // seconds; must be > 0. Use large value for open-ended
);
```

### Config / rate views

```solidity
// Accrual path (same shape as streaming getRateV2; totalAssets_ ignored)
function getRateV2(uint256 totalAssets_)
    external view returns (int256 rate_, bool ended_, uint256 startTime_, uint256 endTime_);

// Static-native config (includes 50% ceiling as maxRate_)
function getStaticConfig()
    external view returns (
        int256 staticRate_,
        uint256 duration_,
        uint256 startTime_,
        address configurator_,
        uint256 maxRate_       // MAX_RATE = 50e12; |offset| above this reverts at construct / setStaticRate
    );

// Legacy streaming stubs so old resolvers calling getRate/getConfig do not revert (always zeros)
function getRate(uint256 totalAssets_) external pure returns (uint256, bool, uint256);
function getConfig() external pure returns (uint256, uint256, uint256, uint256, uint256, uint256, address);
```

### Admin (configurator)

```solidity
function setStaticRate(int256 rate_, uint256 duration_) external;
function stopStaticRate() external;  // mirrors streaming stopRewards — settles via fToken.updateRates()
```

`setStaticRate` calls `updateStaticRewards(this)` on wired fTokens before writing the new rate. After the wired-model auth change, the model does **not** need `LendingFactory.setAuth`: first attach is `fToken.updateStaticRewards(model)` from a factory auth; later `setStaticRate` / `startRewards` self-auth as `_rewardsRateModel` (self or `address(0)` only).

**Ended semantics** (aligned with streaming `getRateV2`): after `startTime + duration`, `getRateV2` returns `ended_ = true` while `rate_` stays the configured offset and `endTime_` marks the program end — new fTokens use this to settle accrual exactly up to `endTime_`. (Streaming models additionally keep the legacy `getRate` with rate forced 0 when ended, for already deployed fTokens.)

---

## 5. Backward compatibility

| Consumer | Old fToken (no `isStaticRateModelActive`) | New resolver |
|----------|---------------------------------------------|--------------|
| `getFTokenRewards` | `staticModelRate_ = 0`; `relativeModelRate_` from `getRate(totalAssets) / 1e10` | Safe |
| `getFTokenDetails` | `isStaticRate = false`; streaming rate fields at `100` scale | Safe |
| `getFTokenRewardsRateModelConfig` | Streaming path; `maxRateOrStaticRate_` = ceiling (`int256`, raw `1e12`) | Safe |

| Consumer | Old resolver ABI | New fToken with static |
|----------|------------------|------------------------|
| Any | `rewardsRate` / old `supplyRate` field names | **Broken** — must upgrade resolver + regenerate types |
| `getFTokenRewardsRateModelConfig` only | 5th field was `uint256`; now `int256` signed offset for static | **Broken** — regenerate ABI; ceiling via `getStaticConfig().maxRate` |

**Rule:** Resolver and fToken static support should be upgraded **together** for any market that uses static rate programs.

---

## 6. Migration checklist

### Front end / analytics

- [ ] Point `LendingResolver` at the new deployment address (when redeployed).
- [ ] Regenerate ABI / TypeChain from `FluidLendingResolver` artifact.
- [ ] Replace `FTokenDetails` type: `relativeModelRate`, `staticModelRate`, `isStaticRate`, `rewardsActive`, `liquidityRate`, `totalRate`.
- [ ] Update `getFTokenRewards` decoder: `relativeModelRate_`, `staticModelRate_`, `isStaticRate_`, `liquidityRate_`, `totalRate_`, `rewardsActive_`.
- [ ] **`getFTokenRewardsRateModelConfig`:** 5th field is **`int256 maxRateOrStaticRate_`** (raw `1e12` = 1%). Streaming = ceiling (`>= 0`); static = signed Liquidity offset. Static `|offset|` ceiling: `getStaticConfig().maxRate`.
- [ ] Display APR from **`details.totalRate`** — do not sum legs manually (§2).
- [ ] Static UI: show Static rewards row when `isStaticRate`; label active vs ended/stopped via **`rewardsActive`** (do not treat `isStaticRate` alone as “currently accruing”).
- [ ] Remove any legacy `rewardsRate + supplyRate` helpers.
- [ ] Optional: show `rebalanceDifference` sign for ops health (negative = rewards owed; positive may mean fee withdrawal pending under static).

### Backend / indexers

- [ ] Re-decode `LogUpdateStaticRewards` on fTokens (new event).
- [ ] Index `isStaticRateModelActive` if reading fToken directly.
- [ ] `LogRebalance` is signed (`int256`); topic0 ≠ legacy `uint256`. Positive = rewards/deposit; negative = fees/withdraw (opposite sign to resolver `rebalanceDifference` for the same gap).
- [ ] `getStaticConfig` returns 5 values including `maxRate` (50% ceiling).

### Governance / ops

- [ ] Deploy `FluidLendingStaticRateModel` with `duration_` (not open-ended without a large duration).
- [ ] Wire via `fToken.updateStaticRewards(model)` (factory auth / deployer). Do **not** `LendingFactory.setAuth(model)` — subsequent `setStaticRate` self-auths as the wired model.

---

## 7. TypeScript / ethers example

```typescript
// After ABI upgrade — getFTokenRewards
const [model, relativeModelRate, staticModelRate, isStaticRate, liquidityRate, totalRate, rewardsActive] =
  await lendingResolver.getFTokenRewards(fTokenAddress);

// After struct upgrade — getFTokenDetails
const details = await lendingResolver.getFTokenDetails(fTokenAddress);
// details.relativeModelRate  — streaming bonus (0 when static active)
// details.staticModelRate     — signed Liquidity offset (0 when streaming active / static inactive)
// details.isStaticRate       — static model wired (may stay true after stop/end)
// details.rewardsActive      — program currently accruing
// details.liquidityRate  — Liquidity layer APR (renamed from legacy `supplyRate`)
// details.totalRate      — combined holder APR (use for display)

const displayApr = details.totalRate;

// getFTokenRewardsRateModelConfig — maxRateOrStaticRate_ raw on-chain scale (1e12 = 1%)
const [, , , , maxRateOrStaticRate, ,] = await lendingResolver.getFTokenRewardsRateModelConfig(fTokenAddress);
// streaming: 50e12 => 50% ceiling; static: e.g. 3e12 => +3% offset, -3e12 => -3% offset. Divide by 1e10 to compare vs totalRate etc.
```

---

## 8. FluidSwapPermissioned — native ETH sentinel (permissioned stack)

When FluidSwap is deployed on the permissioned stack, integrators must treat **native ETH** like other Fluid products:

| Constant | `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` |
|----------|-----------------------------------------------|
| Gate config | `PermissionGate.setSwapTokenRole(sentinel, role)` — roles 1=sell, 2=buy, 3=both |
| Sell native | `swap` is **payable**; `msg.value >= sellAmount`; excess refunded |
| Buy native | Payout via `safeTransferNative`; measure via balance delta |
| `callHash` | Includes full `swapData` bytes — quote must not change after sign |

Not a breaking change to fToken/resolver ABIs; listed here because static-rate launches often ship alongside swap. Full matrix: [`fluidSwapPermissioned/SPEC.md`](../../../permissioned/fluidSwapPermissioned/SPEC.md).

---

## Related docs

- [`SPEC.md`](./SPEC.md) — resolver internals (prefer this breaking-changes file for ABI migration)
- [`fToken/SPEC.md`](../../../protocols/lending/fToken/SPEC.md) — fToken rebalance / static-rate behavior
- [`lending/SPEC.md`](../../../protocols/lending/SPEC.md) — lending package overview (static model stubs)
