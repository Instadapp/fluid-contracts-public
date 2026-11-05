# oracleV2 Test Coverage Report

> **Refreshed:** 2026-08-04. Counts are approximate; run `forge test --match-path 'test/foundry/oracleV2/*.t.sol' --list` for exact totals. Includes `SOURCE_FLUID_ORACLE` (5) coverage on L1/L2 UsdOracle suites.

---

## 1. Summary

| Test file | Tests | Notes |
|---|---:|---|
| `usdOracle.t.sol` | **182** | `FluidUSDOracleTest` — L1 `FluidUsdOracle` (harness on fork) |
| `usdOracleL2.t.sol` | **215** | `FluidUSDOracleL2Test` **extends** `FluidUSDOracleTest` → reruns the full L1 suite with **L2 `setUp`** plus `test_l2_*` additions |
| `vaultOracleFactory.t.sol` | **9** | `VaultOracleFactory` registration and T1–T4 deployments |
| `dexShareResolver.t.sol` | **10** | `DexShareResolver` / `VaultOracleBase` math and share resolution |
| `tokenAmtResolver.t.sol` | **10** | `TokenAmtResolver` USD ↔ token amounts |
| `vaultOracleFork.t.sol` | **9** | Mainnet fork: production parity + local `FluidUsdOracle` integration |
| `usdOracleStorageLayout.t.sol` | **1** | Storage layout sanity check |
| **Total** | **436** | |

**Quality:** All tests are written as **explicit assertions** (including exact `assertEq` where feasible). Historical “quality alerts” (probe-only parity, weak `> 0` checks, identical deviation feeds) were addressed in code; this report does not track open alerts.

**Listing test names locally:**

```bash
forge test --match-path 'test/foundry/oracleV2/<file>.t.sol' --list
```

---

## 2. `usdOracle.t.sol` — FluidUsdOracle (L1)

**Contract:** `FluidUSDOracleTest` (uses `FluidUsdOracleHarness`, mainnet fork in `setUp`).

**182 tests** covering, among other themes:

| Theme | What is covered |
|---|---|
| **Access & roles** | Governance vs `TEAM_MULTISIG` (new-config-only rules, approved eMode-0 shadow-create guard on `setPriceMode`), guardian, unauthorized callers |
| **OracleConfig / transient key** | `registerTransientOracleKey`, invalid params, admin methods without key, removeConfig, multisig vs governance on configs |
| **`getPrice` & sources** | Chainlink staleness (operate vs liquidate windows), invalid/zero rates, multipliers, stable/PEG, capped rate + **`SOURCE_FLUID_ORACLE`** (operate/debt/collateral paths, shared `_readFluidSource` / raw `getExchangeRate`), 2- and 3-source composition, mixed Chainlink + capped/fluid + stable |
| **`readSourceOrRevert` / harness** | Stable, capped-rate, **Fluid oracle** branches, invalid types, composed reads |
| **Deviation & fallback** | Matrix: deviation-only, fallback-only, combined; primary/alt failure; caps/min on alt; boundary BPS; `enableDeviationCheck` upper bound |
| **Alt / primary config lifecycle** | `setAltSourceConfig`, enable/disable fallback & deviation, **removal blocked** while fallback or deviation still on (incl. additional alt sources) |
| **Caps** | min/max, ordering reverts, zero disables floor/ceiling, both active mid-range |
| **Pause** | Guardian (operate bit only), governance/multisig, getPrice when paused, pause ordering vs other checks |
| **eMode** | Fallback to mode 0, boundary emodes, no-config revert |
| **Views** | `getPriceView`, `getPriceDetailed`, `getPriceDetailedView` (match `getPrice`, pause behavior) |
| **`getPriceRawForMode`** | Mode 0, unlisted, PEG vs market, fallback, **no caps**, bypass pause, Fluid oracle uses uncapped `getExchangeRate()` |
| **`getConfiguredTokenOracles`** | Multiple configs, alt info, empty unlisted, native symbol fallback for non-ERC20, additional (market) sources on PEG-mode keys, additional alt, zeroed for non-PEG |
| **PEG + additional sources** | Market/raw routing for PEG tokens |
| **TokenSymbolResolver** | Native symbol by `chainId` (ETH, POL, XPL, BNB) |
| **Events** | `vm.expectEmit` on admin/config/guardian/pause/alt events |
| **UUPS** | Governance-only upgrade; state after upgrade (`FluidUsdOracleHarness` includes `receive` for OZ UUPS empty-data delegatecall) |
| **Misc** | Constructor, proxy smoke, `verifySourceConfig_*` (incl. capped-rate `centerPrice` + shared `_isFluidOracleWithDebt` probe), Fluid oracle config accept/reject, transient multi-tx helpers, `isGuardian`, removeConfig isolation |

---

## 3. `usdOracleL2.t.sol` — FluidUsdOracleL2

**Contract:** `FluidUSDOracleL2Test is FluidUSDOracleTest` — **inherits all L1 tests** (they run against **`FluidUsdOracleL2`** + mock **sequencer** via overridden `setUp`).

**215 tests total** = inherited L1 cases + **L2-specific** `test_l2_*` (sequencer down, grace period / dynamic grace, `sequencerL2Data`, consecutive outages, pause-after-sequencer, **L2 overrides** for `getPriceView` / `getPriceDetailed` / `getPriceDetailedView` / `getPriceRawForMode`, and `test_l2_allBaseOracleTests_inheritCorrectly`).

---

## 4. `vaultOracleFactory.t.sol` — VaultOracleFactory

| # | Test | Verifies |
|---:|---|---|
| 1 | `test_constructor_revertsOnZeroAddress` | Reverts if USD oracle, vault factory, or deployer factory is `address(0)` |
| 2 | `test_registerVault_revertsForInvalidVault` | Non–Fluid vault → revert |
| 3 | `test_registerVault_revertsForUnsupportedType` | Unsupported `vaultType` → revert |
| 4 | `test_registerVault_revertsWhenAlreadyRegistered` | Second `registerVault` → revert |
| 5 | `test_registerVault_revertsOnDeployerMismatch_t234` | T2–T4: wrong deployer → revert |
| 6 | `test_registerVault_deploysT1OracleViaDeployerFactory` | T1 (`IFluidVaultT1`) via `FluidContractFactory`: address, immutables, `targetDecimals`, event |
| 7 | `test_registerVault_deploysT2OracleAndCachesDexParams` | T2 + DEX slots / pool |
| 8 | `test_registerVault_deploysT3OracleAndCachesDexParams` | T3 + debt DEX params |
| 9 | `test_registerVault_deploysT4OracleAndCachesBothDexSides` | T4 col + debt DEX |

---

## 5. `dexShareResolver.t.sol` — DexShareResolver / VaultOracleBase

**10 tests:** `_computeExchangeRate` / `targetDecimals` with `uint256` decimals, `_tokenDecimals` (native vs ERC20), normal collateral zero price, col/debt share pricing with peg buffers, invalid peg buffer, zero supply/borrow shares, interest-adjusted reserves on col/debt.

---

## 6. `tokenAmtResolver.t.sol` — TokenAmtResolver

**10 tests:** `getUsdValueForTokenAmount` / `getTokenAmountForUsdValue` for 18 / 6 / 8 decimals, zero-price reverts, 18-dec round-trip, 6-dec rounding bound.

---

## 7. `vaultOracleFork.t.sol` — Mainnet fork

**Goal:** Parity tests deploy a `MockUsdOracleDetailed` fed from **on-chain prices** (Chainlink, `stEthPerToken()`, mainnet `FluidCappedRate` where legacy uses them), register a new **VaultT1–T4** oracle via `VaultOracleFactory`, and assert **`getExchangeRate` / `getExchangeRateOperate` / `getExchangeRateLiquidate`** match the **deployed vault oracle** within **0.01%** (≤1 bp of reference), after **legacy peg-buffer normalization** where V1 and V2 buffers differ.

| # | Test | Verifies |
|---:|---|---|
| 1 | `test_mainnetFork_parity_t1_wbtcGho` | T1: mock prices = WBTC/BTC×BTC/USD + GHO/USD; `_assertOracleParity` |
| 2 | `test_mainnetFork_parity_t2_wbtcCbBtcUsdc` | T2: BTC/USD for WBTC+cbBTC; USDC/USD; buffer adjust **collateral** leg |
| 3 | `test_mainnetFork_parity_t3_wstEthDexUsdcUsdt` | T3: stETH/USD × stEthPerToken; USDC=USDT=1e27; buffer adjust **debt** leg |
| 4 | `test_mainnetFork_parity_t4_wstEthEth_wstEthEth` | T4: ETH/USD; wstETH = stEthPerToken × ETH/USD; buffer **both** legs |
| 5 | `test_mainnetFork_parity_t4_usdeUsdt_usdcUsdt` | T4: USDe/USDC/USDT from Chainlink USD feeds; buffer **both** legs |
| 6 | `test_mainnetFork_parity_t4_wstUsrUsdc_usdcUsdt` | T4: wstUSR from **CappedRate** operate/liquidate; stables 1e27; **split** col 5000 / debt 1000 ppm buffers |
| 7 | `test_mainnetFork_localUsdOracle_t1_marketCappedStableDebtAndFallbackCollateral` | Real `FluidUsdOracle` + mocks: market, fallback, deviation, GHO cap; T1 rates vs `getPriceDetailedView` |
| 8 | `test_mainnetFork_localUsdOracle_t4_pegTokenMatrix_operateAndLiquidateDiverge` | Local `FluidUsdOracle`, PEG matrix, operate vs liquidate divergence |

**Price inputs (parity mocks):**

| Case | Mock USD inputs | Legacy alignment |
|---|---|---|
| T1 WBTC/GHO | Composed WBTC/BTC × BTC/USD; GHO/USD | Same Chainlink paths as legacy |
| T2 | BTC/USD (both BTC assets); USDC/USD | Legacy peg: WBTC = cbBTC = BTC |
| T3 | stETH/USD × stEthPerToken; stables **1e27** | Legacy col: stETH/USD oracle; debt peg: $1 stables |
| T4 wstETH/ETH | ETH/USD; wstETH = stEthPerToken × ETH/USD | Legacy stETH≈ETH via wrapper |
| T4 USDe | Per-token Chainlink USD | Independent feeds per asset |
| T4 wstUSR | CappedRate operate/liquidate; stables **1e27** | Same capped-rate source as legacy conversion |

---

## 8. `usdOracleStorageLayout.t.sol`

**1 test:** `testStorageLayout_tokenSourcesPacksMetadataThenPlaceholderThenPrimarySlot1` — packed `tokenSources` layout.

---

## 9. Historical quality fixes (archive)

Earlier iterations fixed: weak `assertGt(0)` → exact `assertEq` where possible; deviation tests using **independent** alt feeds; fork parity no longer **probe-calibrated** — see §7. Section **9** tables in the pre-refresh report remain valid as a changelog; not duplicated here to avoid duplication.

---

## 10. Coverage gaps — follow-ups (optional)

| Area | Note |
|---|---|
| **`forge coverage`** | Often fails on unrelated contracts (e.g. stack depth); automated line coverage for `oracleV2/` may be unavailable |
| **Fuzzing** | Most tests use fixed inputs; fuzz on pure math (`_computeExchangeRate`, `TokenAmtResolver`) could add confidence |
| **Gas** | No snapshot regression suite for hot paths |

---

## 11. Quick reference — what each file is for

| File | Role |
|---|---|
| `usdOracle.t.sol` | Single source for **L1** USD oracle behavior (config, pricing, deviation, fallback, pause, views, raw mode, upgrades) |
| `usdOracleL2.t.sol` | **L2** = full L1 regression **plus** sequencer / grace / L2 entrypoints |
| `vaultOracleFactory.t.sol` | Deploy + register **VaultT1–T4** oracles |
| `dexShareResolver.t.sol` | DEX share USD valuation and peg buffers |
| `tokenAmtResolver.t.sol` | Token amount ↔ USD helpers |
| `vaultOracleFork.t.sol` | **Production parity** and heavy fork integration |
| `usdOracleStorageLayout.t.sol` | Storage packing regression |
