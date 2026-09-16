# Periphery / resolvers / dex — SPEC

## 1. Purpose

`FluidDexResolver` is the **read-only aggregator** for Fluid DEX T1 pools. It turns the DEX layer's heavily packed storage slots, factory registry, and runtime-simulation errors into ergonomic, struct-returning views consumable by front-ends, indexers, liquidation bots, and other on-chain resolvers (e.g. the Vault resolver, which calls into it for T2/T3/T4 smart collateral / smart debt data).

The resolver **holds no state, no funds, no admin, and emits no events**. It is purely a view / pure lens over [`FluidDexFactory`](../../../protocols/dex/SPEC.md) and individual `FluidDexT1` pool contracts, plus a bridge call-out to the Liquidity resolver for per-dex Liquidity-side user data. It is safe to redeploy and swap out as packing / struct layouts evolve.

See also: [protocols/dex/SPEC.md](../../../protocols/dex/SPEC.md), [protocols/dex/poolT1/SPEC.md](../../../protocols/dex/poolT1/SPEC.md), [libraries/SPEC.md](../../../libraries/SPEC.md).

## 2. Architecture

```mermaid
flowchart LR
    Caller[Front-end / indexer / VaultResolver] --> R[FluidDexResolver]
    R -->|totalDexes / getDexAddress| Factory[FluidDexFactory]
    R -->|readFromStorage / constantsView / oraclePrice / try-catch sim| Pool[FluidDexT1 pool]
    R -->|getUserSupplyData / getUserBorrowData| LR[FluidLiquidityResolver]
    R -. AddressCalcs.addressCalc .-> Derived[(deterministic dex / hook / centerPrice addresses)]
```

Files (all under `contracts/periphery/resolvers/dex/`):

- `variables.sol` — `abstract contract Variables`. Four immutables (`FACTORY`, `LIQUIDITY`, `LIQUIDITY_RESOLVER`, `DEPLOYER_CONTRACT`) and bitmask constants (`X2..X128`) used by the decoders.
- `structs.sol` — return structs: `DexState`, `ShiftChanges`/`ShiftData`/`CenterPriceShift`, `Configs`, `SwapLimitsAndAvailability`, `DexEntireData`, `UserSupplyData`, `UserBorrowData`.
- `main.sol` — five abstract mixins (`DexFactoryViews`, `DexStorageVars`, `DexActionEstimates`, `DexConstantsViews`, `DexPublicViews`, `DexUserViews`) composed into the concrete `FluidDexResolver` contract, which adds the high-level `getDexState` / `getDexConfigs` / `getDexSwapLimitsAndAvailability` / `getDexEntireData` aggregators.

All decoding uses `DexSlotsLink` bit offsets + `BigMathMinified.fromBigNumber` + `DexCalcs.calc{Withdrawal,Borrow}LimitBeforeOperate`. Deterministic addresses (dex / hook / center-price) are re-derived via `AddressCalcs.addressCalc`.

## 3. External reads (what it consumes)

- `FluidDexFactory.totalDexes()`, `getDexAddress(dexId)` — pool enumeration.
- `FluidDexT1.readFromStorage(slot)` — raw slots: `DEX_VARIABLES_SLOT`, `DEX_VARIABLES2_SLOT`, `DEX_TOTAL_SUPPLY_SHARES_SLOT`, `DEX_USER_SUPPLY_MAPPING_SLOT` (mapping → `keccak(user, slot)`), `DEX_TOTAL_BORROW_SHARES_SLOT`, `DEX_USER_BORROW_MAPPING_SLOT`, `DEX_RANGE_THRESHOLD_SHIFTS_SLOT`, `DEX_CENTER_PRICE_SHIFT_SLOT`. See [libraries/SPEC.md](../../../libraries/SPEC.md) §4 for the authoritative slot layout.
- `FluidDexT1.constantsView() / constantsView2()` — tokens, precisions, oracle nonce.
- `FluidDexT1.oraclePrice(secondsAgos)` — TWAP.
- `FluidDexT1.getPricesAndExchangePrices()` — reverts with `FluidDexPricesAndExchangeRates(...)`; decoded from the revert payload.
- `FluidDexT1.getCollateralReserves(...) / getDebtReserves(...)` — called with PEX outputs, then re-scaled from internal `1e12` precision to token decimals using `ConstantViews2.token{0,1}{Numerator,Denominator}Precision`.
- `FluidDexT1.{swapIn,swapOut,deposit,withdraw,borrow,payback,depositPerfect,withdrawPerfect,borrowPerfect,paybackPerfect,withdrawPerfectInOneToken,paybackPerfectInOneToken}` — called against `ADDRESS_DEAD` (`0x…dEaD`); values are decoded from the simulation-revert selectors (`FluidDexSwapResult`, `FluidDexLiquidityOutput`, `FluidDexPerfectLiquidityOutput`, `FluidDexSingleTokenOutput`).
- `FluidLiquidityResolver.getUserSupplyData(dex, token)` / `getUserBorrowData(dex, token)` — per-token Liquidity-side snapshots for the pool.

## 4. Roles / Access control

**None.** Every external method is callable by any address. There is no owner, guardian, auth, pause, or allow-list. The resolver is address-agnostic — it accepts a `dex_` parameter and trusts nothing about it except that it implements the `IFluidDexT1` interface. (A non-DEX address will simply revert or return zeros.)

## 5. Storage

**No storage.** Only four immutables set at construction:

| Name | Type | Meaning |
| --- | --- | --- |
| `FACTORY` | `IFluidDexFactory` | DEX factory for enumeration + address derivation. |
| `LIQUIDITY` | `IFluidLiquidity` | Liquidity layer — kept for ABI symmetry / future use. |
| `LIQUIDITY_RESOLVER` | `IFluidLiquidityResolver` | Source for per-token Liquidity-side user data. |
| `DEPLOYER_CONTRACT` | `address` | Deployer used to derive center-price / hook contract addresses from their nonces encoded into `dexVariables2`. |

Plus bitmask constants `X2..X128` used as masks during decoding. No mappings, no slots, no transient state.

## 6. Public view capabilities

All functions below are in `FluidDexResolver` (or inherited from a mixin). **Dev note:** methods marked *(callStatic)* are non-view because they `try/catch` on simulation reverts; off-chain callers must use `eth_call` / `callStatic`. They do not mutate state.

### 6.1 DEX enumeration (`DexFactoryViews`)

| Name | Inputs | Returns | Description |
| --- | --- | --- | --- |
| `getDexAddress` | `uint256 dexId` | `address` | Deterministic `AddressCalcs.addressCalc(FACTORY, dexId)`. Returns `address(0)` for `dexId == 0`. |
| `getDexId` | `address dex` | `uint256` | Calls `dex.DEX_ID()`. Reverts if not a DEX. |
| `getTotalDexes` | — | `uint256` | `FACTORY.totalDexes()`. |
| `getAllDexAddresses` | — | `address[]` | All `dexId`s 1..`totalDexes` passed through `getDexAddress`. |

### 6.2 Raw packed slots (`DexStorageVars`)

All take `address dex` and `sload` the corresponding slot via `readFromStorage` (plus mapping slot computation where needed). Used by decoders and exposed for advanced integrators.

| Name | Returns | Slot / bits |
| --- | --- | --- |
| `getDexVariablesRaw` | `uint` | `DEX_VARIABLES_SLOT` (prices, oracle, last-update). |
| `getDexVariables2Raw` | `uint` | `DEX_VARIABLES2_SLOT` (configs, pause bit, hook/center-price nonces, util limits). |
| `getTotalSupplySharesRaw` / `getTotalBorrowSharesRaw` | `uint` | Packed `currentShares` (low 128) / `maxShares` (high 128). |
| `getUserSupplyDataRaw(dex, user)` / `getUserBorrowDataRaw(dex, user)` | `uint` | Mapping slot `keccak(user, MAPPING_SLOT)`. |
| `getRangeShiftRaw` | `uint` | Low 128 bits of `DEX_RANGE_THRESHOLD_SHIFTS_SLOT`. |
| `getThresholdShiftRaw` | `uint` | High 128 bits of the same slot. |
| `getCenterPriceShiftRaw` | `uint` | `DEX_CENTER_PRICE_SHIFT_SLOT`. |

### 6.3 Constants / tokens (`DexConstantsViews`)

| Name | Inputs | Returns | Description |
| --- | --- | --- | --- |
| `getDexConstantsView` | `address dex` | `IFluidDexT1.ConstantViews` | Full immutables (tokens, Liquidity slot pointers, dexId). |
| `getDexConstantsView2` | `address dex` | `IFluidDexT1.ConstantViews2` | Token numerator / denominator precisions for 1e12 → decimals scaling. |
| `getDexTokens` | `address dex` | `(address token0, address token1)` | Shortcut for `(constantsView.token0, .token1)`. |

### 6.4 Prices, reserves, oracle (`DexPublicViews`) — *(callStatic)*

| Name | Inputs | Returns | Description |
| --- | --- | --- | --- |
| `getDexPricesAndExchangePrices` | `address dex` | `IFluidDexT1.PricesAndExchangePrice` | Center / geometric-mean / range / supply+borrow exchange prices. Decoded from `FluidDexPricesAndExchangeRates` revert. |
| `getDexCollateralReserves` | `address dex` | `IFluidDexT1.CollateralReserves` | Real + imaginary token reserves (decimals-scaled). Returns all-zeros if smart-col disabled (`dexVariables2 & 1 == 0`) or the call fails. |
| `getDexDebtReserves` | `address dex` | `IFluidDexT1.DebtReserves` | Symmetric for smart debt (`dexVariables2 & 2 == 0` → zeros). |
| `getDexOraclePrice` | `address dex, uint[] secondsAgos` | `(IFluidDexT1.Oracle[] twaps, uint currentPrice)` | Pass-through; the only genuinely `view` method in this group. |

### 6.5 Swap / liquidity simulations (`DexActionEstimates`) — *(callStatic, `payable`)*

All call the pool with `receiver = ADDRESS_DEAD` so the transaction always reverts with a simulation error; the resolver decodes the selector-tagged `uint`s from `returndata`. If selectors don't match, returns zero (does **not** propagate the real revert — see §9).

| Name | Key Inputs | Returns | Covers selector |
| --- | --- | --- | --- |
| `estimateSwapIn` | `dex, swap0to1, amountIn, amountOutMin` | `amountOut` | `FluidDexSwapResult` |
| `estimateSwapOut` | `dex, swap0to1, amountOut, amountInMax` | `amountIn` | `FluidDexSwapResult` |
| `estimateDeposit` / `estimateWithdraw` | `dex, token0Amt, token1Amt, minSharesAmt` / `maxSharesAmt` | `shares` | `FluidDexLiquidityOutput` |
| `estimateBorrow` / `estimatePayback` | `dex, token0Amt, token1Amt, maxSharesAmt` / `minSharesAmt` | `shares` | `FluidDexLiquidityOutput` |
| `estimateDepositPerfect` / `estimateWithdrawPerfect` | `dex, shares, maxT0 / minT0, maxT1 / minT1` | `(token0Amt, token1Amt)` | `FluidDexPerfectLiquidityOutput` |
| `estimateBorrowPerfect` / `estimatePaybackPerfect` | `dex, shares, minT0 / maxT0, minT1 / maxT1` | `(token0Amt, token1Amt)` | `FluidDexPerfectLiquidityOutput` |
| `estimateWithdrawPerfectInOneToken` | `dex, shares, minToken0, minToken1` | `withdrawAmt` | `FluidDexLiquidityOutput` |
| `estimatePaybackPerfectInOneToken` | `dex, shares, maxToken0, maxToken1` | `paybackAmt` | `FluidDexSingleTokenOutput` |

### 6.6 User positions (`DexUserViews`)

| Name | Inputs | Returns | Notes |
| --- | --- | --- | --- |
| `getUserSupplyData` | `address dex, address user` | `UserSupplyData` | Decodes DEX-side user supply (BigNumber amount, withdrawal limit via `DexCalcs.calcWithdrawalLimitBeforeOperate`, expand %, expand duration, base limit) + attaches per-token Liquidity-side user supply and overall token data. Returns zeros if user not configured. |
| `getUserSupplyDatas` | `address dex, address[] users` | `UserSupplyData[]` | Batch. |
| `getUserBorrowData` | `address dex, address user` | `UserBorrowData` | Same pattern: amount, `calcBorrowLimitBeforeOperate`, expand, base/max limits, plus Liquidity-side borrow + token data. |
| `getUserBorrowDatas` | `address dex, address[] users` | `UserBorrowData[]` | Batch. |
| `getUserBorrowSupplyDatas` | `address dex, address[] users` | `(UserSupplyData[], UserBorrowData[])` | Combined batch. |

### 6.7 Top-level aggregators (`FluidDexResolver`)

| Name | Inputs | Returns | Notes |
| --- | --- | --- | --- |
| `getDexState` *(callStatic)* | `address dex` | `DexState` | Decoded prices (BigMath expand-in-place), timestamps, oracle checkpoints, `totalSupply/BorrowShares`, `isSwapAndArbitragePaused` (bit 255 of `dexVariables2`), range/threshold/centerPrice shift state, and token0/1-per-share (18-decimal fixed). Internally calls `getDexCollateralReserves` + `getDexDebtReserves`. |
| `getDexConfigs` | `address dex` | `Configs` | Decodes `dexVariables2`: smart-col / smart-debt enable bits, fee (17 bits), revenue cut (7 bits), upper/lower range (20 bits each), upper/lower shift thresholds (10 bits each), shifting time (24 bits), maxCenterPrice / minCenterPrice (28-bit BigNumber each), utilization limits, plus `maxSupplyShares` / `maxBorrowShares` (high 128 of totals), plus `centerPriceAddress` / `hookAddress` re-derived from 30-bit nonces via `AddressCalcs.addressCalc(DEPLOYER_CONTRACT, nonce)`. |
| `getDexSwapLimitsAndAvailability` | `address dex` | `SwapLimitsAndAvailability` | Per-token Liquidity supply/borrow/withdrawable/borrowable, plus utilization limits (`liquiditySupply * cfg / 1e3`) and the derived `withdrawable/borrowableUntilUtilizationLimit` for both tokens. |
| `getDexEntireData` *(callStatic)* | `address dex` | `DexEntireData` | Composite of constants, configs, PEX, reserves, state, and limits — one call for dashboards. |
| `getDexEntireDatas` *(callStatic)* | `address[] dexes` | `DexEntireData[]` | Batch. |
| `getAllDexEntireDatas` *(callStatic)* | — | `DexEntireData[]` | `getDexEntireDatas(getAllDexAddresses())`. |

## 7. Admin / Governance

**N/A.** The resolver has no admin surface — no setters, no owner, no guardians, no upgrade path. To change behaviour, governance redeploys the resolver with new constructor args and consumers re-pin the address (see §11).

## 8. Events

**None.** The resolver never emits; it is a pure reader.

## 9. Errors

The resolver defines no custom errors. Behaviour on failure:

- **Non-DEX address / missing interface**: calls to `IFluidDexT1(dex_)...` revert with the pool's own error (or low-level revert for no-code addresses). Not caught.
- **Simulation fallback**: the `try/catch` blocks in `DexPublicViews` and `DexActionEstimates` are tolerant — if the revert selector does **not** match the expected simulation selector, the fallback returns **zeros** rather than propagating. Callers must therefore sanity-check returned zeros (e.g. paired with `getDexConstantsView` succeeding) before treating them as "no liquidity" rather than "wrong address / unexpected revert". This is intentional: off-chain dashboards prefer graceful degradation.
- **Smart-col / smart-debt disabled**: `getDexCollateralReserves` / `getDexDebtReserves` short-circuit to zero structs when `dexVariables2 & 1` / `& 2` are unset — not an error.

## 10. Invariants

- **Stateless / no mutation.** The resolver owns no mutable storage; every call is a read (even the `payable` simulation paths, because they always revert on the pool side; the resolver's own state never changes).
- **`payable` on estimates is only a forwarding affordance.** The resolver does not retain or forward native value; the pool revert burns the forwarded value only if the simulated path would consume it — and since `receiver = 0x…dEaD`, the pool always reverts, so `msg.value` never lands. Callers should still prefer `eth_call` (no value attached).
- **No token balances.** The resolver holds no ERC-20 or native balances. There is no `rescueTokens` and none is needed; accidentally-sent tokens are unrecoverable by design.
- **Immutables-only.** `FACTORY`, `LIQUIDITY`, `LIQUIDITY_RESOLVER`, `DEPLOYER_CONTRACT` are set in the constructor and never changed.
- **Decoder layout ≡ pool layout.** The bit offsets / masks used here are the same constants from `DexSlotsLink` that the pool writes; a layout change in the pool requires a new resolver.

## 11. Trust model

- **Consumers must pin the resolver address they depend on.** Resolvers are replaced on packing-layout or ABI-struct evolution; older resolvers remain on-chain but may decode newer pools incorrectly. Each deployment snapshot in `DEPLOYMENTS.md` lists the current `FluidDexResolver` — integrators should track the latest entry for the chain.
- **Resolver trusts downstream addresses.** No `isDex(dex_)` check is performed on the `dex_` argument; integrators that want that guarantee should pair the call with `FACTORY.isDex(dex_)` off-chain (or on-chain). This keeps the resolver cheap and protocol-agnostic.
- **Resolver trusts `LIQUIDITY_RESOLVER`.** The Liquidity-side user/token data returned for each DEX is only as correct as the configured resolver. Upgrading the Liquidity resolver may require a new DEX resolver pointing at it.
- **No authority on the protocol.** The resolver cannot pause, configure, or otherwise influence DEX or Liquidity state. Compromise of the resolver address (e.g. a phishing replacement) only poisons reads for consumers that follow the malicious pointer — the protocol itself is unaffected.

## 12. Deployment / audit notes

- **Constructor**: `FluidDexResolver(factory, liquidity, liquidityResolver, deployer)`. `deployer` here is the **contract deployer** used as the base for `AddressCalcs.addressCalc(DEPLOYER_CONTRACT, nonce)` when decoding hook / center-price nonces out of `dexVariables2`; it must match the deployer the pool's admin module used when it recorded those nonces. Wrong value → wrong `centerPriceAddress` / `hookAddress` in `Configs` (pure decoding bug, no on-chain damage).
- **Replacing**: safe — deploy a new resolver with updated struct layout, announce the new address, and consumers migrate. Old resolver remains callable (and correct for pools whose layout has not changed).
- **Audit scope**: the resolver contains no economic logic. Reviewers should focus on (i) slot / bit-offset correctness against `DexSlotsLink` and the pool's writers, (ii) `BigMath.fromBigNumber` parameter consistency with `DexCalcs` defaults (`DEFAULT_EXPONENT_SIZE` / `DEFAULT_EXPONENT_MASK`), (iii) `1e12 → decimals` scaling in `_getDexCollateralReserves` / `_getDexDebtReserves`, and (iv) selector-decoding in `DexActionEstimates._decodeLowLevelUint{1x,2x}` (offsets 36 / 68 after the 4-byte selector).
- **No upgradeability**: not behind an `InfiniteProxy`; plain deployment.

See also:

- [protocols/dex/SPEC.md](../../../protocols/dex/SPEC.md) — the protocol being read.
- [protocols/dex/poolT1/SPEC.md](../../../protocols/dex/poolT1/SPEC.md) — pool runtime and simulation-error ABI.
- [libraries/SPEC.md](../../../libraries/SPEC.md) §4 — `DexSlotsLink`, `AddressCalcs`, `BigMathMinified`, `BytesSliceAndConcat` contracts used here.
