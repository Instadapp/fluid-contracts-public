# Vault Types Common — SPEC

## 1. Purpose

`vaultTypesCommon` is the **shared implementation base** for Fluid vault types T2 / T3 / T4 (and conceptually mirrored by the standalone T1). It owns:

- The **packed storage layout** used by every vault (tick / branch liquidation engine, per-NFT `positionData`, rate magnifiers, exchange-price `rates` word).
- The **core `_operate` / `_liquidate` / `absorb` / `rebalance` implementations**, all centered on the tick / branch data structure.
- The **admin module** that writes risk parameters, oracle nonce, rebalancer, rate magnifiers, and rescue paths.
- The **delegatecall dispatch plumbing** (`_spell`, `_verifyCaller`, `_onlyDelegateCall`) that lets a vault proxy reuse the shared logic while keeping type-specific code (T2 / T3 / T4) thin.

The vault type contracts (see [vaultT2 SPEC](../vaultT2/SPEC.md), [vaultT3 SPEC](../vaultT3/SPEC.md), [vaultT4 SPEC](../vaultT4/SPEC.md)) inherit from here and add the DEX-side token-flow plumbing (T2: smart collateral; T3: smart debt; T4: both). The top-level [vault SPEC](../SPEC.md) gives the protocol overview. [vaultT1 SPEC](../vaultT1/SPEC.md) is structurally parallel — T1 predates this shared base and keeps its own storage file; semantics are documented to match.

## 2. Architecture

```mermaid
flowchart TB
    subgraph Typed[Vault type contracts]
      T2[FluidVaultT2]
      T3[FluidVaultT3]
      T4[FluidVaultT4]
      Op2[FluidVaultT2Operate]
      Op3[FluidVaultT3Operate]
      Op4[FluidVaultT4Operate]
    end

    subgraph Common[vaultTypesCommon]
      Core[FluidVault - main.sol]
      Sec[FluidVaultSecondary - main2.sol]
      Operate[FluidVaultOperate - mainOperate.sol]
      Helpers[Helpers / HelpersOperate / HelpersLiquidate]
      Admin[FluidVaultAdmin - adminModule/main.sol]
      Vars[Variables + ConstantVariables + Events + Structs]
    end

    T2 --> Core
    T3 --> Core
    T4 --> Core
    Op2 --> Operate
    Op3 --> Operate
    Op4 --> Operate
    Core -. delegatecall .-> Admin
    Core -. delegatecall .-> Sec
    T2 -. delegatecall .-> Op2
    T3 -. delegatecall .-> Op3
    T4 -. delegatecall .-> Op4
    Core -. shared storage .- Vars
    Admin -. shared storage .- Vars
    Sec -. shared storage .- Vars
    Op2 -. shared storage .- Vars
    Op3 -. shared storage .- Vars
    Op4 -. shared storage .- Vars
```

Files under `contracts/protocols/vault/vaultTypesCommon/`:

- `common/variables.sol` — `Variables`: packed storage words (`vaultVariables`, `vaultVariables2`, `rates`, `positionData`, `tickHasDebt`, `tickData`, `tickId`, `branchData`, `absorbedLiquidity`, `absorbedDustDebt`, `rebalancer`, `dexFromAddress`).
- `common/tokenTransfers.sol` — safe-transfer helpers (ETH-aware) used by helpers and secondary.
- `coreModule/constantVariables.sol` — immutables: `LIQUIDITY`, `VAULT_FACTORY`, `DEPLOYER_CONTRACT`, `TYPE` (one of `VAULT_T1 | VAULT_T2_SMART_COL | VAULT_T3_SMART_DEBT | VAULT_T4_SMART_COL_SMART_DEBT`), `SUPPLY`, `BORROW`, `SUPPLY_TOKEN0`, `SUPPLY_TOKEN1`, `BORROW_TOKEN0`, `BORROW_TOKEN1` (as `ILiquidityDexCommon`-typed addresses when smart), `OPERATE_IMPLEMENTATION`, `ADMIN_IMPLEMENTATION`, `SECONDARY_IMPLEMENTATION`, pre-computed Liquidity slot pointers, `NATIVE_TOKEN`, `DEAD_ADDRESS`, `EXCHANGE_PRICES_PRECISION = 1e12`, masks `X8..X128` (`X96` in place of "X48"), the raw-debt floors `MIN_BRANCH_DEBT = 1e2`, `MIN_TICK_DEBT = 1e3`, `MIN_DEBT = 1e4`, `MIN_OPERATE = 1e4`, and the T3/T4 liquidation share tolerance `MAX_LIQUIDATION_SHARES_ROUNDING_DIFF = 1e3`.
- `coreModule/structs.sol` — in-memory `Operate_`, `Liquidate_`, `Tick_`, `Branch_` etc.
- `coreModule/events.sol` — `LogOperate`, `LogUpdateExchangePrice`, `LogLiquidate`, `LogAbsorb`, `LogRebalance`.
- `coreModule/helpers.sol` — `Helpers`: `_dexFromAddress` modifier, `updateExchangePrices` (also read by the rewards contracts), `fetchLatestPosition`.
- `coreModule/helpersOperate.sol` — `HelpersOperate`: tick <-> branch math, top-tick transitions, `_setNewTopTick`, raw <-> share normalization.
- `coreModule/helpersLiquidate.sol` — `HelpersLiquidate`: small reusable liquidate helpers.
- `coreModule/main.sol` — `FluidVault`: inherits `Helpers + HelpersLiquidate`. Contains `_liquidate` (~700 LOC liquidation walker), `rebalance(int,int,int,int)` wrapper, `liquidityCallback`, `dexCallback`, `simulateLiquidate`, `fallback`, `_spell`.
- `coreModule/main2.sol` — `FluidVaultSecondary`: `absorb` (public), `rebalance` (delegatecalled), `updateExchangePrices` helpers used by rewards reads.
- `coreModule/mainOperate.sol` — `FluidVaultOperate`: the single shared `_operate` that computes new tick, CF, withdrawal gap, Liquidity / DEX calls, and emits `LogOperate`.
- `adminModule/main.sol` — `FluidVaultAdmin`: `_verifyCaller` (delegatecall only) + setters.
- `adminModule/events.sol` — one `LogUpdate...` event per setter, plus `LogRescueFunds`, `LogAbsorbDustDebt`.

Dispatch model mirrors DEX poolT1: the proxy vault owns all storage; `_spell(OPERATE_IMPLEMENTATION, msg.data)` dispatches the `operate` / `operatePerfect` path into the type-specific operate implementation; `fallback` dispatches admin calls to `ADMIN_IMPLEMENTATION`; `rebalance(int,int,int,int)` and absorb paths dispatch into `SECONDARY_IMPLEMENTATION`.

## 3. External Interactions

- **Fluid Liquidity** — `LIQUIDITY.operate(...)` for the non-smart side of the vault, plus `readFromStorage` for exchange prices / user-supply / user-borrow. `liquidityCallback(token, amount, data)` is accepted when `msg.sender == LIQUIDITY` and the vault is inside an in-flight op.
- **DEX (`SUPPLY` / `BORROW`)** — for smart sides the `ILiquidityDexCommon` addresses are actual DEX pools. `dexCallback(token, amount)` is accepted when `msg.sender ∈ {SUPPLY, BORROW}`; funds flow from `dexFromAddress` into Liquidity during the callback.
- **Oracle (`IFluidOracle`)** — resolved via `AddressCalcs.addressCalc(DEPLOYER_CONTRACT, oracleNonce)`. Called with `getExchangeRateOperate()` during CF-affecting ops, `getExchangeRateLiquidate()` inside the liquidation loop. Operate reverts `Vault__InvalidOraclePrice` on a price outside `[1e9, 1e54]`; liquidate only on `0` or above `1e54` (plus the zero `debtPerCol` check in §4). The exchange-price-adjusted ratio is capped at `1e45`.
- **Factory (`VAULT_FACTORY`)** — `mint(vaultId, user)` when `nftId_ == 0`; `ownerOf(nftId)` for owner checks; `isGlobalAuth(caller) || isVaultAuth(vault, caller)` inside `fallback`.
- **Callers**
  - Users via the type-specific `operate` / `operatePerfect`.
  - Liquidators via the type-specific `liquidate` / `liquidatePerfect`.
  - Rebalancer via `rebalance(int,int,int,int)` (T2/T3/T4) — T1 has a parameterless `rebalance()` on its core.
  - Factory-authorized admins via `fallback`.

## 4. Capabilities & Responsibilities

- **Own the storage contract.** Every vault instance's state — reentrancy bit, top tick, supply / borrow totals, per-NFT collateral / debt, tick / branch graph — lives in this layout.
- **Operate engine.** `_operate` normalizes signed collateral / debt deltas, enforces owner / dust / sign / msg.value constraints, updates `positionData`, reassigns ticks, walks branches where needed, does the outward Liquidity / DEX calls in the correct order, and runs CF + withdrawal-gap checks against the oracle. On borrow, the `borrowFee` is added to `debtRaw` with **ceiling** division so the protocol never under-charges the fee; a zero fee stays exactly zero.
- **Liquidation engine.** `_liquidate` walks from the current top tick down to the tick implied by `liquidationTick`, computing debt paid, collateral taken out, and updating branches when partial liquidations straddle a tick. Handles `absorb_ == true` (using the absorbed buffer first).
  - When **no top tick exists** but `absorb_` is set and `absorbedLiquidity` is non-zero, liquidation is still allowed and settles the absorbed buffer only; the current tick is set to `type(int256).min` so the absorb spell and the tick walk are both skipped. Without this, absorbed amounts were stranded until somebody re-created a top tick. The same sentinel is re-derived after the in-call absorb spell: when that absorb empties every tick, the post-absorb top-tick decode yields no tick and the walk is skipped, instead of running on a phantom tick 0 whose zero debt underflowed `debtLiquidated -= 1` with `Panic(0x11)`. Without `absorb_` such a call reverts `Vault__InvalidLiquidation`, as nothing is left to liquidate.
  - **Rounding directions are all protocol-favouring:** `colPerDebt` is derived from a **ceil**-rounded `debtPerCol` (both roundings are set to `1e45` when the floored value exceeds it) so it rounds down; the token debt amount charged to the liquidator uses **ceiling** division; collateral paid out floors. The dust adjustment `debtLiquidated -= 1` is applied **before** collateral is computed from it. If `debtPerCol` floors to zero the call reverts with `Vault__InvalidOraclePrice`.
- **Absorb.** Clears positions above the `liquidationMaxLimit` ratio, records absorbed amounts, and closes branches that cross the absorb tick.
- **Rebalance.** Reconciles vault-recorded supply / borrow (possibly denominated in shares for smart sides) against the actual Liquidity / DEX reserves; net drift is moved to / from the rebalancer address.
- **Exchange-price accrual.** `updateExchangePrices` advances vault supply / borrow exchange prices per-block, driven by `vaultVariables2` magnifiers / signed rates and Liquidity exchange price deltas. A negative signed rate can lower the vault price only down to `EXCHANGE_PRICES_PRECISION` (1e12), never below. On a Liquidity-backed debt leg the new vault borrow price rounds up, in favour of the protocol; supply prices and smart-debt rate accrual round down.
- **Admin settings.** Publishes a typed setter for every risk parameter. Each setter re-accrues exchange prices before the write so magnifier transitions are observed only from that moment forward.
- **Dust cleanup.** `absorbDustDebt` converts liquidated positions whose debt rounds to dust into supply-only NFTs, preventing the tick / branch graph from accumulating untouchable debt.

## 5. Roles & Access Control

- **Users** — call type-specific `operate` / `operatePerfect` on the vault. Only the NFT owner can perform risky-direction moves (withdraw collateral, borrow more debt).
- **Liquidators** — call type-specific `liquidate` / `liquidatePerfect` on any underwater NFT. `liquidate(..., to_=DEAD_ADDRESS, ...)` is the simulation revert path.
- **Rebalancer** — single address stored in `rebalancer`. Only caller of `rebalance(int,int,int,int)`.
- **`SUPPLY` / `BORROW` (DEX pools)** — only accepted callers of `dexCallback`. Fluid Liquidity is the only accepted caller of `liquidityCallback`.
- **Factory auths** — reach admin module via the vault's `fallback`. `_verifyCaller` in each admin method re-asserts the delegatecall origin (`address(this) != THIS_ADDRESS_SENTINEL`).
- **Factory owner** (resolved through `VAULT_FACTORY.isGlobalAuth`) — implicit super-auth.

## 6. Storage Layout

### `vaultVariables` (slot 0)

| Bits | Field |
| --- | --- |
| 0 | Reentrancy bit (1 while inside a vault op) |
| 1 | Active-branch-liquidated flag |
| 2–21 | Top tick (sign bit + 19-bit absolute tick index) |
| 22–51 | Current branch id |
| 52–81 | Total branch id (monotonic) |
| 82–145 | Total supply raw (BigNumber encoding) |
| 146–209 | Total borrow raw (BigNumber encoding) |
| 210–241 | Total positions (monotonic NFT count for this vault) |

### `vaultVariables2` (slot 1)

| Bits | Field |
| --- | --- |
| 0–15 | Supply-rate magnifier (T1 / T3) or signed supply rate (T2 / T4) |
| 16–31 | Borrow-rate magnifier (T1 / T2) or signed borrow rate (T3 / T4) |
| 32–41 | Collateral factor |
| 42–51 | Liquidation threshold |
| 52–61 | Liquidation max limit |
| 62–71 | Withdraw gap |
| 72–81 | Liquidation penalty |
| 82–91 | Borrow fee |
| 92–121 | Oracle nonce (`AddressCalcs.addressCalc(DEPLOYER_CONTRACT, nonce)`) |
| 122–154 | Last-update timestamp (used to advance exchange prices) |

### `rates` (slot 8)

Four 64-bit words (each at `1e12` precision): Liquidity supply exchange price, Liquidity borrow exchange price, vault supply exchange price, vault borrow exchange price.

### `positionData[nftId]`

Per-NFT packed: position type (supply vs borrow), tick sign + absolute value + local id, collateral raw (BigNumber), dust debt raw (BigNumber).

### Tick / branch mapping

- `tickHasDebt[parentId]` — bitset per 256 ticks indicating which ticks currently hold debt.
- `tickData[tick]` — liquidation flag, tick id counter, and either raw debt (active) or liquidation metadata (100% flag, branch id, debt factor) when liquidated.
- `tickId[tick][slot]` — up to three 85-bit historical liquidation records per slot, used when tick ids roll.
- `branchData[branchId]` — branch state (0 = not liquidated, 1 = liquidated, 2 = merged, 3 = closed), minima tick, two partials (interpolation between `tick` ratio and `tick-1`), branch debt, debt factor or connection factor, link to base branch and base minima tick.

### Auxiliary slots

- `absorbedLiquidity` — slot 2, one packed word: low 128 bits raw debt, high 128 bits raw collateral that the protocol has taken over and that the next `liquidate(…, absorb_ = true)` settles. Fed by `absorb()` (positions past `liquidationMaxLimit`). Both amounts remain inside `totalSupply` / `totalBorrow` until that liquidation removes them.
- `absorbedDustDebt` — vault-level counter for dust debt written off.
- `rebalancer` — address allowed to call `rebalance(int,int,int,int)`.
- `dexFromAddress` — transient address used during DEX callbacks; `DEAD_ADDRESS` when idle.

## 7. User / Public Methods

Note: the public, type-specific `operate` / `operatePerfect` live on each vault type contract (T2/T3/T4) and forward to the shared `_operate` via `_spell(OPERATE_IMPLEMENTATION, msg.data)`. The methods below are the ones callable directly on the core shared contract.

### rebalance

```solidity
function rebalance(
    int256 colToken0MinMax_,
    int256 colToken1MinMax_,
    int256 debtToken0MinMax_,
    int256 debtToken1MinMax_
) external payable returns (int256 supplyAmt_, int256 borrowAmt_)
```

- Access: `msg.sender == rebalancer` (set via `updateRebalancer`).
- Sets reentrancy bit, resolves `dexFromAddress`, accrues exchange prices.
- Compares vault-recorded vs live Liquidity / DEX reserves. If vault has less supply than it should, it pulls from the rebalancer (via DEX `depositPerfect` on smart col, or Liquidity `operate` otherwise). If vault has less borrow than it should, it pushes debt repayment; etc.
- Each leg's min / max bound comes from the four `int256` parameters. A value of `0` means "no rebalance on this leg"; positive / negative signs indicate direction; `try/catch` around individual DEX calls converts reverts to zero-movement (so a single-leg failure does not block the whole tx).
- Emits `LogRebalance`. Validates ETH equality (`_validateEth`).

### simulateLiquidate

```solidity
function simulateLiquidate(
    uint256 debtAmt_,
    bool absorb_
) external
```

Sets the reentrancy bit, then calls `_liquidate(X128, 0, DEAD_ADDRESS, absorb_, vaultVariables_)` (maximum debt amount, no slippage bound), which reverts with the quote as `FluidLiquidateResult`; the trailing `revert()` is only a safeguard. `debtAmt_` is accepted but has no effect: the quote is always for the maximum liquidatable amount, and `absorb_` (use the absorbed buffer first) is the only input that changes the result. Intended to be used as a staticcall from off-chain / resolvers; no state is persisted. T2/T3/T4 have no type-specific variant; they inherit this one.

### liquidityCallback

```solidity
function liquidityCallback(address token_, uint256 amount_, bytes calldata data_) external
```

Accepted only when `msg.sender == LIQUIDITY`, reentrancy bit is set, and the decoded `data` matches the protocol pattern. Settles token pulls during a vault-initiated Liquidity `operate`.

### dexCallback

```solidity
function dexCallback(address token_, uint256 amount_) external
```

Accepted only when `msg.sender ∈ {SUPPLY, BORROW}` and the vault's reentrancy bit is set. The vault then pulls `amount_` of `token_` from `dexFromAddress` to `LIQUIDITY`; the configured DEX is trusted to pass its own immutable token and amount.

### fallback

Delegatecall dispatcher for admin methods. Requires `VAULT_FACTORY.isGlobalAuth(msg.sender) || VAULT_FACTORY.isVaultAuth(address(this), msg.sender)`, then `_spell(ADMIN_IMPLEMENTATION, msg.data)`.

### readFromStorage

Inherited. Raw `sload(slot)`; no auth.

### absorb (on `FluidVaultSecondary`)

```solidity
function absorb(uint256 vaultVariables_, int256 maxTick_) public returns (uint256)
```

- Access: `_verifyCaller` — only reachable via `delegatecall` from the core `_liquidate` path.
- Walks ticks above `maxTick_`, marking them 100% liquidated, closing branches, accumulating `absorbedLiquidity` entries, and returning the new `vaultVariables_`.
- Emits `LogAbsorb`.

## 8. Admin / Governance Methods

All methods on `FluidVaultAdmin` (`adminModule/main.sol`). Each runs `_verifyCaller` (delegatecall only) and re-accrues exchange prices before the write (except `absorbDustDebt`, which only guards reentrancy).

- `updateCollateralFactor(uint256)` — bits 32–41. Input in 1e2, stored `/10`; must be `≥ 300` (3%) and `<` the liquidation threshold, else `VaultAdmin__ValueAboveLimit`. The floor exists so a CF of ~0 can no longer be used as an ad-hoc borrow freeze; use the borrow-only [`FluidPauseAuth.pauseVault(vaultId, false, false, true, false)`](../../../config/pauseAuth/SPEC.md) for that, which leaves withdrawals, paybacks and liquidations running.
- `updateLiquidationThreshold(uint256)` — bits 42–51. Must satisfy `CF < threshold < maxLimit`.
- `updateLiquidationMaxLimit(uint256)` — bits 52–61. Combined with the liquidation penalty, capped at 99.7%.
- `updateWithdrawGap(uint256)` — bits 62–71. `<=` 100%.
- `updateLiquidationPenalty(uint256)` — bits 72–81.
- `updateBorrowFee(uint256)` — bits 82–91.
- `updateOracle(uint256 newOracleNonce_)` — writes bits 92–121. Before the write, probes the oracle with both `getExchangeRateOperate()` and `getExchangeRateLiquidate()` to sanity-check.
- `updateRebalancer(address)` — stores `rebalancer`. Must be non-zero.
- `rescueFunds(address token_)` — sweeps any stuck balance on the vault to Liquidity (so normal accounting picks it up downstream).
- `absorbDustDebt(uint256[] nftIds_)` — reentrancy-guarded. For each liquidated position where remaining debt rounds to dust, converts it to a supply-only NFT and bumps `absorbedDustDebt` so `rebalance` can true up the total-borrow accounting.

Each setter emits a corresponding `LogUpdate...` event.

## 9. Events

Core (`coreModule/events.sol`):

- `LogOperate(user, nftId, colAmt, debtAmt, to)` — emitted inside `_operate`. For smart types, `colAmt` / `debtAmt` are **share deltas** (int, shares / 1e18-normalized), not token amounts.
- `LogUpdateExchangePrice(supplyExPrice, borrowExPrice)`
- `LogLiquidate(liquidator, debtAmt, colAmt, to)`
- `LogAbsorb(colAbsorbed, debtAbsorbed)`
- `LogRebalance(supplyDelta, borrowDelta)`

Admin (`adminModule/events.sol`): `LogUpdateCollateralFactor`, `LogUpdateLiquidationThreshold`, `LogUpdateLiquidationMaxLimit`, `LogUpdateWithdrawGap`, `LogUpdateLiquidationPenalty`, `LogUpdateBorrowFee`, `LogUpdateOracle`, `LogUpdateRebalancer`, `LogRescueFunds`, `LogAbsorbDustDebt`.

## 10. Errors

Raised as `FluidVaultError(uint256)` (from the top-level `contracts/protocols/vault/error.sol`). Relevant code groups for this module:

- `31001–31038` — vault core (reentrancy, amounts, msg.value, owner, tick, CF, slippage, rebalancer, NFT, Liquidity callback, delegate-call, transfers, exchange price, oracle, DEX callback, rebalance min/max).
- `33001–33009` — vault admin (limits, delegate-call, dust NFT / debt).
- `35001–35002` — DEX-type runtime (operate amount invalid on smart sides, debt shares paid beyond what the liquidation consumed).

Simulation revert `FluidLiquidateResult(uint256 colLiquidated, uint256 debtLiquidated)` is used as the return channel for `simulateLiquidate`.

## 11. Invariants & Safety Notes

- **Reentrancy on bit 0 of `vaultVariables`.** Every external mutating path sets it on entry and clears it on exit. `liquidityCallback` / `dexCallback` explicitly require the bit be set, so stray callbacks revert.
- **Liquidity exchange prices are monotonic non-decreasing.** `updateExchangePrices` asserts each new Liquidity supply / borrow price is `>=` the stored one; violation reverts `Vault__LiquidityExchangePriceUnexpected`.
- **Oracle ratio cap at 1e45.** In `getExchangeRateOperate` / `getExchangeRateLiquidate`, the ratio is clamped.
- **Tick math correctness depends on `TickMath`.** See [SPEC-tickMath](../../../libraries/SPEC-tickMath.md). Invariants include `type(int).min` / `type(int).max` tick paths being unreachable.
- **Branch debt haircut 0.01%.** `fetchLatestPosition` applies `branchDebt * 9999 / 10000` on merge walks, preventing branch debt from reaching zero and causing division errors. On top of that, `liquidate` reverts `Vault__InvalidLiquidation` if a partial liquidation would drive the branch's debt-factor delta to exactly 0, and `Vault__BranchDebtTooLow` below `MIN_BRANCH_DEBT` (1e2 raw); `operate` clamps a branch's debt at `MIN_BRANCH_DEBT` when removing a liquidated position from it instead of underflowing.
- **Raw-debt floors.** `MIN_OPERATE` (1e4): `|newCol_|` / `|newDebt_|` below it revert `Vault__InvalidOperateAmount`. `MIN_DEBT` (1e4): net position debt and tick debt on the write path revert `Vault__UserDebtTooLow` / `Vault__TickDebtTooLow` below it, and a liquidation `debtAmt_` below it reverts `Vault__InvalidLiquidationAmt`. The write path adds one wei of rounding before the check, so a net debt of `MIN_DEBT - 1` still passes. A liquidation can leave a position with net debt below `MIN_DEBT`. It stays with its owner, and any call that would leave it in that band reverts. On T1 / T2 the owner closes it with a max payback and a max withdraw, and a max payback from any address (payback needs no ownership) only clears its debt, leaving the collateral on the position. On T3 / T4 the dust payback is below the DEX's minimum burn of 1e-9 of total borrow shares (`DexT1__BurnAmtOverflow`), and on large 18-decimal debt it can be below Liquidity's BigMath rounding step (`UserModule__OperateAmountInsufficient`); there the owner first borrows back above `MIN_DEBT`, then closes. Nothing absorbs such a position: its collateral covers its debt until the price makes its branch liquidatable again, and past `liquidationMaxLimit` `absorb()` takes it like any other. A position liquidated down to or below its dust debt (`debtRaw <= dustDebtRaw`) counts as 100% liquidated in the position sync: the shortfall is added to `absorbedDustDebt` and the position is zeroed. `MIN_TICK_DEBT` (1e3): every `operate` on an unliquidated borrow position first removes its debt from its tick; if that leaves the tick below it, the tick's debt is zeroed and the tick removed from `tickHasDebt`. Only this removal can leave a tick between `MIN_TICK_DEBT` and `MIN_DEBT`.
- **Liquidation rounding favours the vault.** `actualDebtAmt` is rounded **up** (ceiling division, at most one wei above the floored conversion) and `actualColAmt` **down**. Because `totalDebtLiq` never exceeds the floored `debtAmt_ * 1e12 / borrowExPrice`, `actualDebtAmt` never exceeds `debtAmt_`; a defensive branch would otherwise scale `actualColAmt` by `debtAmt_ / actualDebtAmt` (multiply-before-divide) and clamp `actualDebtAmt` to `debtAmt_`. `actualDebtAmt < 2` reverts `Vault__InvalidLiquidation` (nothing of value was liquidated). Liquidator bots that size approvals from an off-chain replica must allow for the extra wei.
- **CF > current ratio on risky ops.** Any increase of debt or decrease of collateral must result in a ratio satisfying `< collateralFactor * oraclePrice`. Else reverts `Vault__PositionAboveCF`.
- **Payback / deposit direction guards.** If the position still has debt, a payback must not leave net debt above its pre-op level and a deposit-only op must not raise the net debt ratio, else `Vault__InvalidPaybackOrDeposit`; this is what lets any caller pay back or deposit without making a position riskier.
- **Withdrawal gap** subtracts a user-configured percentage from max withdraw on every op; smart-col adds back already-burned shares when needed so the current withdrawal is included.
- **Tick data layout is asymmetric for negative ticks.** `parentId = i / 256` for positive and `((i + 1) / 256) - 1` for negative; callers must respect the formula when reading `tickHasDebt` directly.
- **`rates` slot is authoritative.** Exchange prices written here are the source of truth for user-facing conversions; the vault supply / borrow exchange prices evolve via `vaultVariables2` magnifiers. Downstream resolvers must always read through `updateExchangePrices` (or its simulation helpers) rather than multiplying Liquidity prices naively.
- **Vault exchange prices never fall below `EXCHANGE_PRICES_PRECISION`.** They are initialised at exactly `1e12`, positive rates only raise them, and a negative signed rate (T2/T3/T4) clamps the decrease at the `1e12` floor instead of underflowing. Consequences: an admin method that re-accrues before writing can never be bricked by a steep negative rate, and a negative rate on a vault whose price still sits at `1e12` accrues nothing until a positive rate has lifted the price first. The `unchecked` clamp arithmetic in `helpers.sol` relies on this floor; no code path may write a price below it.
- **`dexFromAddress` must be reset.** Any path that sets it to a user address must reset to `DEAD_ADDRESS` on exit; callbacks check this to avoid cross-tx reuse.

## 12. Trust Model & Accepted Trade-offs

- **Operate ignores ERC-721 approvals.** Only the NFT owner may perform risky legs; approvals govern transfers but not vault operations. Intentional.
- **Same monotonic NFT id space across vault types.** Positions must be interpreted as `(vault, id)` pairs. Integrators relying on bare NFT ids break across vaults.
- **Liquidation of T2/T3/T4 uses live DEX for share conversion.** Oracle is used only for ratio / CF math. Listing discipline on the underlying DEX is therefore part of the trust model.
- **Smart-collateral withdrawal-gap parity.** T2/T4 compare the current share withdrawal against the same gap headroom as the normal-col form; `operate` adds back already-burned shares, while `operatePerfect` checks before the burn.
- **BigMath libraries are the safe minified / vault variants.** `BigMathUnsafe` is not used in production vault code.
- **`simulateLiquidate` uses dead-address + revert for quoting.** Integrators must catch and decode; this is by design.
- **Bad-debt absorption is governance-driven.** No live user-facing incentive for `absorbDustDebt` / absorb; keepers / governance monitor and fire.
- **Rebalancer is a trusted role.** It can move real tokens between the vault and Liquidity / DEX within min / max bounds; there is no economic cap on single-call drift.
- **Class-0 Liquidity.** Production vaults configure themselves as Liquidity class 0 (standard); class 1 is reserved.
- **Oracle trust.** A mis-set oracle nonce can mis-price CF / liquidation; `updateOracle` probes both oracle call paths before committing, but on-chain probes do not catch oracle malice.

See also:

- [contracts/protocols/vault/SPEC.md](../SPEC.md) — protocol overview.
- [contracts/protocols/vault/vaultT1/SPEC.md](../vaultT1/SPEC.md), [vaultT2 SPEC](../vaultT2/SPEC.md), [vaultT3 SPEC](../vaultT3/SPEC.md), [vaultT4 SPEC](../vaultT4/SPEC.md) — per-type runtimes.
- [contracts/libraries/SPEC-tickMath.md](../../../libraries/SPEC-tickMath.md) — tick math.
- [contracts/libraries/SPEC-bigMath.md](../../../libraries/SPEC-bigMath.md) — BigNumber encoding used in `positionData`, `tickData`, `branchData`.
- [contracts/libraries/SPEC-liquidityCalcs.md](../../../libraries/SPEC-liquidityCalcs.md) — Liquidity exchange-price reads.
