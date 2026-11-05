# Vault Oracle V2 — Technical Specification

## 1. Design Rationale

### 1.1 Gas-optimized runtime via per-vault vault oracles

Every vault `operate()` / `liquidate()` call invokes `getExchangeRateOperate()` or `getExchangeRateLiquidate()`. Minimizing oracle gas cost directly reduces user transaction costs.

The architecture deploys a dedicated vault oracle per vault with all configuration data cached as **Solidity immutables** (~3 gas per read). The vault points directly to its vault oracle — no router, no mapping lookup, no extra external calls to read configuration.

| Approach | T1 overhead | T2/T3/T4 overhead |
|---|---|---|
| Fresh reads (vault + DEX constantsView calls) | ~5,200 gas | ~13,000 gas |
| SSTORE2 single contract (mapping + EXTCODECOPY) | ~7,400 gas | ~7,500 gas |
| SLOAD packed storage | ~4,700–8,900 gas | ~8,900–11,000 gas |
| **Vault oracle with immutables (this design)** | **~2,600 gas** | **~2,640 gas** |

The dominant cost in the vault oracle approach is the single external CALL from the vault (~2,600 gas). All configuration reads are essentially free (PUSH from bytecode).

### 1.2 USD Oracle as common denominator

The old oracle V1 system required a **conversion price oracle** (Chainlink or FluidOracle) to express DEX reserves in a single quote token denomination, plus a **colDebt bridge oracle** to relate the share price to the vault's debt token, plus **RESULT_MULTIPLIER/DIVISOR** scaling.

This system eliminates all of that. The Fluid USD Oracle (`FluidUsdOracle`) already provides USD prices for every token. DEX reserves are valued directly in USD:

```
totalUsd = token0Reserves * token0UsdPrice + token1Reserves * token1UsdPrice
usdPerShare = totalUsd / totalShares
```

No conversion price oracle, no colDebt bridge oracle, no result scaling needed.

### 1.3 Factory deployment and eModes

A single `VaultOracleFactory` contract reads vault and DEX immutable data, then deploys the appropriate vault oracle via the shared `FluidContractFactory` (`DEPLOYER_FACTORY`). **`registerVault(vaultId, supplyEMode, borrowEMode)`** is **not** permissionless: the caller must be **Liquidity governance** (same resolver as UUPS), **`TEAM_MULTISIG`**, or an address with **`vaultOracleDeployer[caller] == true`** (set via **`setVaultOracleDeployer`**, callable by governance or **`TEAM_MULTISIG`**). Before deploy, the factory checks both eModes independently via **`IUSDOracle.isEmodeValid`**: `supplyEMode` against supply-relevant tokens and `borrowEMode` against borrow-relevant tokens. Missing exact per-key eMode rows may intentionally use the USD oracle runtime fallback to eMode `0`. **`registerVaultForce(vaultId, supplyEMode, borrowEMode)`** is **governance-only** and may redeploy even if a nonce was already recorded.

The factory must be allow-listed on `FluidContractFactory` (`updateDeployer`). The vault address is `VAULT_FACTORY.getVaultAddress(vaultId)`. The factory records each vault’s oracle deploy nonce (`vaultIdToOracleDeployNonce`); the oracle address is always `DEPLOYER_FACTORY.getContractAddress(nonce)`.

### 1.4 Reusable share resolution

DEX share-to-USD resolution logic lives in a separate `DexShareResolver` abstract contract under `oracleV2/common/`. This allows auth contracts, limit handlers, and other consumers to inherit the same share resolution logic without pulling in vault oracle boilerplate.

### 1.5 Library imports

The vault oracle contracts import `LiquidityCalcs`, `LiquiditySlotsLink`, and `DexSlotsLink` directly from `contracts/libraries/`. These libraries have a pragma range of `>=0.8.21 <=0.8.36`.

---

## 2. Vault Types

| Type | Collateral | Debt | vaultType constant |
|---|---|---|---|
| T1 | Normal token | Normal token | `VAULT_T1_TYPE` (10000) |
| T2 | DEX smart col (LP shares) | Normal token | `VAULT_T2_SMART_COL_TYPE` (20000) |
| T3 | Normal token | DEX smart debt (LP shares) | `VAULT_T3_SMART_DEBT_TYPE` (30000) |
| T4 | DEX smart col (LP shares) | DEX smart debt (LP shares) | `VAULT_T4_SMART_COL_SMART_DEBT_TYPE` (40000) |

The vault's `constantsView()` returns `vaultType` among other immutable fields. The factory reads this to determine which vault oracle type to deploy.

---

## 3. File Layout

```
contracts/oracleV2/
  common/
    dexShareResolver.sol        -- DexShareResolver abstract (share resolution)
    tokenAmtResolver.sol        -- TokenAmtResolver abstract (token <-> USD conversions)
    error.sol                   -- OracleV2CommonError
    errorTypes.sol              -- shared numeric error ids for oracleV2/common
  vaultOracle/
    base.sol                    -- VaultOracleBase abstract (inherits DexShareResolver)
    factory/
      main.sol                  -- VaultOracleFactory implementation (UUPS; deploy behind proxy)
      proxy.sol                 -- VaultOracleFactoryProxy (ERC1967; stable address + preserved storage)
      deploymentLogics/         -- per-type oracle creation-code holders (T1–T4)
    SPEC.md                     -- this file
    error.sol                   -- FluidVaultOracleError
    errorTypes.sol              -- shared numeric error ids for vault/factory
    vaultTypes/
      vaultT1Oracle.sol
      vaultT2Oracle.sol
      vaultT3Oracle.sol
      vaultT4Oracle.sol
  interfaces/
    iUSDOracle.sol              -- (existing, unchanged)
    iVaultOracle.sol            -- getExchangeRateOperate / Liquidate / getExchangeRate
```

---

## 4. Inheritance Hierarchy

```
DexShareResolver                          (oracleV2/common/dexShareResolver.sol)
  └── VaultOracleBase                     (oracleV2/vaultOracle/base.sol)
        ├── VaultT1Oracle                 (oracleV2/vaultOracle/vaultTypes/vaultT1Oracle.sol)
        ├── VaultT2Oracle                 (oracleV2/vaultOracle/vaultTypes/vaultT2Oracle.sol)
        ├── VaultT3Oracle                 (oracleV2/vaultOracle/vaultTypes/vaultT3Oracle.sol)
        └── VaultT4Oracle                 (oracleV2/vaultOracle/vaultTypes/vaultT4Oracle.sol)
```

`VaultOracleFactory` is standalone (does not inherit the vault-oracle hierarchy); it inherits OpenZeppelin `UUPSUpgradeable` for upgrades when deployed behind `VaultOracleFactoryProxy`. Creation code for each oracle type lives in `factory/deploymentLogics/`; the factory calls those logics and deploys via `DEPLOYER_FACTORY`.

### 4.1 eModes on vault oracles

Each deployed vault oracle stores two immutables on `VaultOracleBase`: **`SUPPLY_E_MODE`** and **`BORROW_E_MODE`**. Collateral-side pricing paths use `SUPPLY_E_MODE`; debt-side pricing paths use `BORROW_E_MODE` (normal-token and DEX-share legs alike). The factory chooses both values at registration time and rejects invalid combinations (`VaultOracleFactory__InvalidEMode`) when the corresponding side has no token with that eMode in USD oracle `configsMap`.

---

## 5. DexShareResolver

**Location**: `contracts/oracleV2/common/dexShareResolver.sol`

Reusable abstract contract for resolving DEX LP shares to USD prices. Inheritable by vault oracles, auth contracts, limit handlers, or any consumer that needs to price DEX shares.

### 5.1 Constants

| Name | Value | Purpose |
|---|---|---|
| `LIQUIDITY` | `0x52Aa...` | Fluid Liquidity Layer (fixed address, reads via `readFromStorage`) |
| `DEX_TOTAL_SUPPLY_SHARES_SLOT` | 2 | DEX storage slot for total supply shares |
| `DEX_TOTAL_BORROW_SHARES_SLOT` | 4 | DEX storage slot for total borrow shares |
| `X128` | `0xfff...f` (128 bits) | Mask for shares from DEX packed storage |
| `PEG_BUFFER_SCALE` | `1e6` | Denominator for optional peg buffer (ppm) |

### 5.2 Methods

#### `_resolveColShare(usdOracle, eMode, isOperate, dexParams, pegBufferPpm) → (priceUsd, decimals)`

Resolves DEX collateral LP shares to a USD price per share.

`pegBufferPpm`: optional peg buffer in parts per million (same scale as V1 `RESERVES_PEG_BUFFER_PERCENT`). `0` = no adjustment (use for limit handlers / true economic value). Non-zero: scale both collateral reserves by `(1e6 - pegBufferPpm) / 1e6` before step 3. Must be `< 1e6`.

Flow:
1. Read raw collateral reserves from Liquidity using `_getLiquidityCollateral()` for token0 and token1.
2. Apply peg buffer to reserve amounts when `pegBufferPpm > 0`.
3. Fetch USD prices for token0 and token1 via `USD_ORACLE.getPriceDetailedView(token, eMode, isOperate, true)`.
4. Compute `totalUsd = token0Reserves * token0Price + token1Reserves * token1Price`.
5. Read `totalSupplyShares` from DEX via `readFromStorage(DEX_TOTAL_SUPPLY_SHARES_SLOT) & X128`.
6. Return `(totalUsd * 1e6 / totalSupplyShares, 18)`.

#### `_resolveDebtShare(usdOracle, eMode, isOperate, dexParams, pegBufferPpm) → (priceUsd, decimals)`

Same as `_resolveColShare` but for the debt side:
- Reads debt reserves via `_getLiquidityDebt()` (uses borrow slots).
- Non-zero `pegBufferPpm`: scale both debt reserves by `(1e6 + pegBufferPpm) / 1e6` before pricing (V1 peg semantics: higher debt reserves → more conservative debt valuation).
- Passes `isCollateral=false` to `getPriceDetailedView` with the same **`eMode`**.
- Reads `totalBorrowShares` from DEX.

### 5.3 Internal Helpers

#### `_applyPegBufferToReserves(token0, token1, pegBufferPpm, isCollateralSide)`

Pure helper: applies V1-style peg buffer to reserve amounts; returns adjusted `(token0, token1)`.

#### `_getLiquidityCollateral(supplySlot, exchangePriceSlot, numPrecision, denPrecision) → tokenSupply`

Reads a single token's collateral amount from Liquidity:
1. `LIQUIDITY.readFromStorage(supplySlot)` — extract BigMath-encoded amount from bits 1..64.
2. Compute current supply exchange price via `LiquidityCalcs.calcExchangePrices()`.
3. If interest mode is enabled (low bit == 1), multiply amount by exchange price.
4. Normalize to 1e12 using `numPrecision / denPrecision`.

#### `_getLiquidityDebt(borrowSlot, exchangePriceSlot, numPrecision, denPrecision) → debtAmount`

Same pattern but reads borrow data and uses the borrow exchange price.

### 5.4 Decimal Handling

Reserves are normalized to 1e12 using `TOKEN_N_NUMERATOR/DENOMINATOR_PRECISION` from the DEX's `constantsView2()`. USD prices from the oracle are at 1e27 precision.

```
token0ValueUsd = token0Reserves_1e12 * token0PriceUsd_1e27     (result in ~1e39 range)
token1ValueUsd = token1Reserves_1e12 * token1PriceUsd_1e27

totalValueUsd  = token0ValueUsd + token1ValueUsd
usdPerShare    = totalValueUsd * 1e6 / totalSupplyShares_1e18   (result in 1e27 precision)
```

The `* 1e6` scaling factor compensates for the 1e12 reserve normalization: `1e39 * 1e6 / 1e18 = 1e27`.

---

## 6. VaultOracleBase

**Location**: `contracts/oracleV2/vaultOracle/base.sol`

Inherits `DexShareResolver`. Adds vault-specific logic for normal token resolution and exchange rate computation.

### 6.1 Methods

#### `_resolveNormal(usdOracle, token, isOperate, isCollateral, isRaw)`

View/raw: `getPriceDetailedView` / `Raw` with eMode based on `isCollateral_` (`SUPPLY_E_MODE` if true, `BORROW_E_MODE` if false). Reverts `VaultOracle__PriceZero` if price is 0.

#### `_resolveNormalWrite(usdOracle, token, isOperate, isCollateral)`

Write variant via `getPriceDetailed` (persists source state). Reverts `VaultOracle__PriceZero` if price is 0.

#### `_computeExchangeRate(colPriceUsd, colDecimals, debtPriceUsd, debtDecimals) → exchangeRate`

Computes the exchange rate (debt per collateral, 1e27 precision adjusted for token decimals):

```
exchangeRate = colPriceUsd * 10^(27 + debtDecimals - colDecimals) / debtPriceUsd
```

Example: ETH (18 dec) / USDC (6 dec) at $2000/$1:
- `2000e27 * 10^(27+6-18) / 1e27 = 2000e27 * 1e15 / 1e27 = 2000 * 1e15 = 2e18`
- targetDecimals = 15, so `2e18` represents 2000 USDC per ETH.

#### `getExchangeRateOperate()` / `getExchangeRateLiquidate()` / `getExchangeRate()`

Public entry points that call the abstract `_getExchangeRate(bool isOperate_, bool isRaw_)` which each vault oracle implements. `getExchangeRate()` delegates to operate. `IFluidOracleWrite` is on **VaultT1Oracle** only (via base `_resolveNormal*Write`). The smart vault oracles (T2–T4) are deliberately view-only: Write support there is planned for later, once a smart vault actually needs a write-capable source.

### 6.2 eModes

Each vault oracle deployment stores **`SUPPLY_E_MODE`** and **`BORROW_E_MODE`** as immutables set from factory constructor args. USD oracle reads use the side-appropriate eMode (see §4.1).

---

## 7. Vault Oracle Contracts

Each vault type has a dedicated vault oracle contract. The vault points directly to its vault oracle as the oracle address. All per-vault data is stored as Solidity immutables.

### 7.1 VaultT1Oracle

**Location**: `contracts/oracleV2/vaultOracle/vaultTypes/vaultT1Oracle.sol`

Normal collateral + normal debt.

| Immutable | Type | Source |
|---|---|---|
| `USD_ORACLE` | `address` | Factory constructor param |
| `SUPPLY_E_MODE` | `uint256` | Factory arg `supplyEMode` |
| `BORROW_E_MODE` | `uint256` | Factory arg `borrowEMode` |
| `SUPPLY_TOKEN` | `address` | `vault.constantsView().supplyToken.token0` |
| `BORROW_TOKEN` | `address` | `vault.constantsView().borrowToken.token0` |

`_getExchangeRate(isOperate)`:
1. `(colPrice, colDec) = _resolveNormal(USD_ORACLE, SUPPLY_TOKEN, isOperate, true)`
2. `(debtPrice, debtDec) = _resolveNormal(USD_ORACLE, BORROW_TOKEN, isOperate, false)`
3. Return `_computeExchangeRate(...)`

Write (T1): `_resolveNormalWrite` → same compose.

### 7.2 VaultT2Oracle

**Location**: `contracts/oracleV2/vaultOracle/vaultTypes/vaultT2Oracle.sol`

Smart collateral (DEX LP shares) + normal debt.

| Immutable | Type | Source |
|---|---|---|
| `USD_ORACLE` | `address` | Factory constructor param |
| `SUPPLY_E_MODE` | `uint256` | Factory arg `supplyEMode` |
| `BORROW_E_MODE` | `uint256` | Factory arg `borrowEMode` |
| `BORROW_TOKEN` | `address` | `vault.constantsView().borrowToken.token0` |
| `DEX_POOL` | `address` | `vault.constantsView().supply` |
| `TOKEN_0` | `address` | `dex.constantsView().token0` |
| `TOKEN_1` | `address` | `dex.constantsView().token1` |
| `SUPPLY_TOKEN_0_SLOT` | `bytes32` | `dex.constantsView().supplyToken0Slot` |
| `SUPPLY_TOKEN_1_SLOT` | `bytes32` | `dex.constantsView().supplyToken1Slot` |
| `EXCHANGE_PRICE_TOKEN_0_SLOT` | `bytes32` | `dex.constantsView().exchangePriceToken0Slot` |
| `EXCHANGE_PRICE_TOKEN_1_SLOT` | `bytes32` | `dex.constantsView().exchangePriceToken1Slot` |
| `TOKEN_0_NUM_PRECISION` | `uint256` | `dex.constantsView2().token0NumeratorPrecision` |
| `TOKEN_0_DEN_PRECISION` | `uint256` | `dex.constantsView2().token0DenominatorPrecision` |
| `TOKEN_1_NUM_PRECISION` | `uint256` | `dex.constantsView2().token1NumeratorPrecision` |
| `TOKEN_1_DEN_PRECISION` | `uint256` | `dex.constantsView2().token1DenominatorPrecision` |

`_getExchangeRate(isOperate)`:
1. `(colPrice, colDec) = _resolveColShare(USD_ORACLE, SUPPLY_E_MODE, isOperate, <col immutables>, _dexSharePegBufferPpm(isOperate))`
2. `(debtPrice, debtDec) = _resolveNormal(USD_ORACLE, BORROW_TOKEN, isOperate, false)`
3. Return `_computeExchangeRate(colPrice, colDec, debtPrice, debtDec)`

### 7.3 VaultT3Oracle

**Location**: `contracts/oracleV2/vaultOracle/vaultTypes/vaultT3Oracle.sol`

Normal collateral + smart debt (DEX LP shares).

| Immutable | Type | Source |
|---|---|---|
| `USD_ORACLE` | `address` | Factory constructor param |
| `SUPPLY_E_MODE` | `uint256` | Factory arg `supplyEMode` |
| `BORROW_E_MODE` | `uint256` | Factory arg `borrowEMode` |
| `SUPPLY_TOKEN` | `address` | `vault.constantsView().supplyToken.token0` |
| `DEX_POOL` | `address` | `vault.constantsView().borrow` |
| `TOKEN_0` | `address` | `dex.constantsView().token0` |
| `TOKEN_1` | `address` | `dex.constantsView().token1` |
| `BORROW_TOKEN_0_SLOT` | `bytes32` | `dex.constantsView().borrowToken0Slot` |
| `BORROW_TOKEN_1_SLOT` | `bytes32` | `dex.constantsView().borrowToken1Slot` |
| `EXCHANGE_PRICE_TOKEN_0_SLOT` | `bytes32` | `dex.constantsView().exchangePriceToken0Slot` |
| `EXCHANGE_PRICE_TOKEN_1_SLOT` | `bytes32` | `dex.constantsView().exchangePriceToken1Slot` |
| `TOKEN_0_NUM_PRECISION` | `uint256` | `dex.constantsView2().token0NumeratorPrecision` |
| `TOKEN_0_DEN_PRECISION` | `uint256` | `dex.constantsView2().token0DenominatorPrecision` |
| `TOKEN_1_NUM_PRECISION` | `uint256` | `dex.constantsView2().token1NumeratorPrecision` |
| `TOKEN_1_DEN_PRECISION` | `uint256` | `dex.constantsView2().token1DenominatorPrecision` |

`_getExchangeRate(isOperate)`:
1. `(colPrice, colDec) = _resolveNormal(USD_ORACLE, SUPPLY_TOKEN, isOperate, true)`
2. `(debtPrice, debtDec) = _resolveDebtShare(USD_ORACLE, BORROW_E_MODE, isOperate, <debt immutables>, _dexSharePegBufferPpm(isOperate))`
3. Return `_computeExchangeRate(colPrice, colDec, debtPrice, debtDec)`

### 7.4 VaultT4Oracle

**Location**: `contracts/oracleV2/vaultOracle/vaultTypes/vaultT4Oracle.sol`

Smart collateral + smart debt (both from same DEX pool).

| Immutable | Type | Source |
|---|---|---|
| `USD_ORACLE` | `address` | Factory constructor param |
| `SUPPLY_E_MODE` | `uint256` | Factory arg `supplyEMode` |
| `BORROW_E_MODE` | `uint256` | Factory arg `borrowEMode` |
| `DEX_POOL` | `address` | `vault.constantsView().supply` (same as `.borrow`) |
| `TOKEN_0` | `address` | `dex.constantsView().token0` |
| `TOKEN_1` | `address` | `dex.constantsView().token1` |
| `SUPPLY_TOKEN_0_SLOT` | `bytes32` | `dex.constantsView().supplyToken0Slot` |
| `SUPPLY_TOKEN_1_SLOT` | `bytes32` | `dex.constantsView().supplyToken1Slot` |
| `BORROW_TOKEN_0_SLOT` | `bytes32` | `dex.constantsView().borrowToken0Slot` |
| `BORROW_TOKEN_1_SLOT` | `bytes32` | `dex.constantsView().borrowToken1Slot` |
| `EXCHANGE_PRICE_TOKEN_0_SLOT` | `bytes32` | `dex.constantsView().exchangePriceToken0Slot` |
| `EXCHANGE_PRICE_TOKEN_1_SLOT` | `bytes32` | `dex.constantsView().exchangePriceToken1Slot` |
| `TOKEN_0_NUM_PRECISION` | `uint256` | `dex.constantsView2().token0NumeratorPrecision` |
| `TOKEN_0_DEN_PRECISION` | `uint256` | `dex.constantsView2().token0DenominatorPrecision` |
| `TOKEN_1_NUM_PRECISION` | `uint256` | `dex.constantsView2().token1NumeratorPrecision` |
| `TOKEN_1_DEN_PRECISION` | `uint256` | `dex.constantsView2().token1DenominatorPrecision` |

`_getExchangeRate(isOperate)`:
1. `pegBufferPpm = _dexSharePegBufferPpm(isOperate)`
2. `(colPrice, colDec) = _resolveColShare(USD_ORACLE, SUPPLY_E_MODE, isOperate, <col immutables>, pegBufferPpm)`
3. `(debtPrice, debtDec) = _resolveDebtShare(USD_ORACLE, BORROW_E_MODE, isOperate, <debt immutables>, pegBufferPpm)`
4. Return `_computeExchangeRate(colPrice, colDec, debtPrice, debtDec)`

---

## 8. VaultOracleFactory

**Location**: `contracts/oracleV2/vaultOracle/factory/main.sol` (implementation), `contracts/oracleV2/vaultOracle/factory/proxy.sol` (ERC1967 UUPS proxy).

### 8.0 Rationale: proxy (UUPS), not a monolithic factory

Production uses **`VaultOracleFactoryProxy`** (OpenZeppelin `ERC1967Proxy`) as the **only** address integrators should treat as “the vault oracle factory.” The implementation contract is upgradeable via **UUPS** (`VaultOracleFactory` inherits `UUPSUpgradeable`; **Liquidity governance** — same address resolved on `LIQUIDITY` via `readFromStorage` as for `FluidUsdOracle` — may call `upgradeTo` / `upgradeToAndCall`).

**Why a proxy:**

1. **Upgrades** — Implementation bytecode can be replaced to ship bugfixes or new behavior without abandoning the factory’s address.
2. **Registry continuity** — `vaultIdToOracleDeployNonce` is **contract storage at the proxy**. Replacing the implementation does **not** wipe that mapping; vault-ID → FluidContractFactory deploy nonce remains valid after an upgrade (the same reason we avoid redeploying a non-proxy factory whenever logic changes).
3. **Cross-network and integration stability** — Protocol contracts, deploy scripts, and `FluidContractFactory` allow-lists can reference **one stable factory address per chain**; upgrades do not force every consumer to update pointers.

This is **not** the protocol’s “infinite proxy” / generic meta-proxy; it is a normal **ERC1967** transparent-to-callers UUPS proxy, matching the pattern used elsewhere (e.g. `FluidUsdOracleProxy`).

Deploy the **implementation** once, then deploy **`VaultOracleFactoryProxy(implementation, initData)`** — typically `initData` is empty (`""`) because configuration is via constructor on the implementation (immutables live in implementation bytecode). **Integrators use the proxy address** so `vaultIdToOracleDeployNonce` and future state stay at a stable address across networks and upgrades.

### 8.1 Immutables (implementation constructor) and constants

| Name | Type | Purpose |
|---|---|---|
| `LIQUIDITY` | `address` | Protocol Liquidity contract; used to read current governance for UUPS upgrades (`readFromStorage` at the governance slot) |
| `USD_ORACLE` | `address` | Passed to all vault oracles; used for `isEmodeValid` checks at registration |
| `VAULT_FACTORY` | `IFluidVaultFactory` | Validates `isVault(vault)` |
| `DEPLOYER_FACTORY` | `IFluidContractFactory` | Deploys all vault oracle bytecode via `deployContract` so the address matches `AddressCalcs.addressCalc(deployer, nonce)` |
| `T1_ORACLE_LOGIC` … `T4_ORACLE_LOGIC` | deployment logic contracts | Hold each oracle type's `creationCode`; factory calls `creationCodeWithArgs` then `DEPLOYER_FACTORY.deployContract` |
| `TEAM_MULTISIG` | `address` (constant) | Hardcoded team multisig (`0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e`), same as `contracts/config` auth contracts; may call `setVaultOracleDeployer` with governance |

T2–T4 DEX share peg buffers are per-oracle immutables in `VaultOracleBase` (`PEG_BUFFER_PPM_OPERATE` / `PEG_BUFFER_PPM_LIQUIDATE`), set from the `pegBufferPpmOperate_` / `pegBufferPpmLiquidate_` arguments to `registerVault`. The factory bounds both at `MAX_PEG_BUFFER_PPM` (10 000 ppm = 1%, inclusive) and requires liquidate ≤ operate. T1 has no DEX share leg and is deployed with `0, 0`.

New implementations deployed with the **same** constructor arguments preserve the same immutables behavior; storage at the proxy address (mappings) is unchanged after upgrade.

### 8.2 Storage

| Name | Type | Purpose |
|---|---|---|
| `vaultIdToOracleDeployNonce` | `mapping(uint256 => uint256)` | vault factory `VAULT_ID` => `FluidContractFactory.totalContracts` nonce used for that vault’s oracle deployment |
| `vaultOracleDeployer` | `mapping(address => bool)` | Allow-listed addresses that may call `registerVault` (governance and `TEAM_MULTISIG` may always) |

**Use case:** The nonce is the global deploy index on `DEPLOYER_FACTORY`. The deployed vault oracle address is `DEPLOYER_FACTORY.getContractAddress(nonce)`. Off-chain handlers can verify that the oracle configured on the vault matches that address for the canonical deployment from this factory (wrong nonce would point at the wrong contract).

### 8.3 `setVaultOracleDeployer(address account, bool allowed)`

Callable by **Liquidity governance** or **`TEAM_MULTISIG`**. Sets `vaultOracleDeployer[account]`. Reverts if `account == address(0)`.

### 8.4 `registerVault(uint256 vaultId, uint256 supplyEMode, uint256 borrowEMode) → address vaultOracle`

**Authorized callers:** governance, **`TEAM_MULTISIG`**, or **`vaultOracleDeployer[msg.sender]`**. Reverts **`VaultOracleFactory__Unauthorized`** otherwise.

Deploys the appropriate vault oracle for the vault with `vaultId` at `VAULT_FACTORY`, passing **`supplyEMode`** and **`borrowEMode`** into the vault oracle constructor so both are immutable on the deployed contract.

Flow:
1. Revert if `vaultId == 0` (`VaultOracleFactory__VaultIdZero`).
2. Revert if `vaultIdToOracleDeployNonce[vaultId] != 0` (already registered).
3. Let `vault = VAULT_FACTORY.getVaultAddress(vaultId)`. Revert if `vault == address(0)` or `!VAULT_FACTORY.isVault(vault)` (`VaultOracleFactory__InvalidVault`).
4. Revert if `IFluidVault(vault).VAULT_ID() != vaultId` (`VaultOracleFactory__DeploymentInvariantFailed`).
5. **eMode validation:** require `IUSDOracle(USD_ORACLE).isEmodeValid(supplyEMode, token)` for at least one supply-relevant token, and `isEmodeValid(borrowEMode, token)` for at least one borrow-relevant token. Exact missing per-key rows may intentionally fall back to eMode `0` at USD-oracle runtime. Otherwise **`VaultOracleFactory__InvalidEMode`**.
6. **T1** (`IFluidVault.TYPE()` reverts **or** returns `VAULT_T1_TYPE`): read `IFluidVaultT1.constantsView()`; get initcode from `T1_ORACLE_LOGIC.creationCodeWithArgs(...)`; deploy via `DEPLOYER_FACTORY.deployContract(...)`. No deployer check on T1.
7. **T2–T4**: read `IFluidVault.TYPE()` and `IFluidVault.constantsView()`; revert unless `constantsView().deployer == address(DEPLOYER_FACTORY)`; get initcode from the matching `T*_ORACLE_LOGIC.creationCodeWithArgs(...)`; deploy via `DEPLOYER_FACTORY.deployContract(...)`.
8. Finalize registration: let `nonce = DEPLOYER_FACTORY.totalContracts()` after deploy; require `vaultOracle == DEPLOYER_FACTORY.getContractAddress(nonce)`; set `vaultIdToOracleDeployNonce[vaultId] = nonce`.
9. Emit `LogVaultOracleRegistered(vault, vaultOracle, vaultType, vaultId, deployNonce)`.
10. Return `vaultOracle` address.

The `FluidContractFactory` owner must allow-list the **proxy** address (the entrypoint used for `registerVault` / `registerVaultForce`) via `updateDeployer` so `deployContract` succeeds for non-owner senders.

### 8.5 `registerVaultForce(uint256 vaultId, uint256 supplyEMode, uint256 borrowEMode) → address vaultOracle`

**Governance only.** Same deploy path as **`registerVault`**, but does **not** revert when a nonce was already recorded; updates **`vaultIdToOracleDeployNonce`** to the new deploy nonce after a fresh deployment.

### 8.6 `getVaultOracleDeployment(uint256 vaultId) → (vault, oracleNonce, vaultOracle)`

View. Returns `VAULT_FACTORY.getVaultAddress(vaultId)`, the recorded oracle deploy nonce, and `DEPLOYER_FACTORY.getContractAddress(oracleNonce)`. Reverts with `VaultOracleFactory__NotRegistered` if nothing was registered for that `vaultId`, or if `VAULT_ID(vault) != vaultId`.

### 8.7 Helper: `_readDexData(address dexPool) → DexParams`

Internal function that reads:
- `dex.constantsView()`: token0, token1, supplyToken0Slot, supplyToken1Slot, borrowToken0Slot, borrowToken1Slot, exchangePriceToken0Slot, exchangePriceToken1Slot
- `dex.constantsView2()`: token0NumeratorPrecision, token0DenominatorPrecision, token1NumeratorPrecision, token1DenominatorPrecision

Returns a `DexParams` struct with all fields.

---

## 9. External Dependencies

### 9.1 Runtime (per oracle call)

| Contract | Call | Used by |
|---|---|---|
| `FluidUsdOracle` | `getPriceDetailedView(token, <side eMode>, isOperate, isCollateral)` | All vault oracles (for USD prices); collateral side uses `SUPPLY_E_MODE`, debt side uses `BORROW_E_MODE` |
| Liquidity Layer (`0x52Aa...`) | `readFromStorage(slot)` | T2/T3/T4 vault oracles (for reserves + exchange prices) |
| DEX Pool | `readFromStorage(slot)` | T2/T3/T4 vault oracles (for total supply/borrow shares) |

### 9.2 Deploy-time only (factory)

| Contract | Call | Purpose |
|---|---|---|
| Vault | `TYPE()`, `IFluidVault.constantsView()` or `IFluidVaultT1.constantsView()` | T2–T4: type, tokens, DEX pools, `deployer`. T1: `IFluidVaultT1` supply/borrow tokens only. |
| DEX Pool | `constantsView()` | Read Liquidity slot addresses |
| DEX Pool | `constantsView2()` | Read precision values |
| `FluidContractFactory` | `deployContract(bytecode)` | All vault oracle deployments (increments global `totalContracts` nonce) |

These calls return immutable data from the target contracts.

---

## 10. Error Codes

### 10.1 `oracleV2/common` (`OracleV2CommonError`)

Custom error is defined in `contracts/oracleV2/common/error.sol`; shared numeric ids live in `contracts/oracleV2/common/errorTypes.sol`. Used by `DexShareResolver`, `TokenAmtResolver`, and any other `oracleV2/common` consumer.

| Code | Constant | Meaning |
|---|---|---|
| 310201 | `OracleV2Common__PriceZero` | USD Oracle returned 0 for a token price (DEX share path or token amount resolver) |
| 310202 | `OracleV2Common__SharesZero` | DEX total supply/borrow shares are 0 |
| 310203 | `OracleV2Common__InvalidPegBuffer` | `pegBufferPpm` >= 1e6 |

### 10.2 Vault / factory errors

Custom error is defined in `contracts/oracleV2/vaultOracle/error.sol`; numeric ids live in `contracts/oracleV2/vaultOracle/errorTypes.sol`.

| Code | Constant | Meaning |
|---|---|---|
| 310101 | `VaultOracle__PriceZero` | USD Oracle returned 0 for a token price (normal col/debt path in `VaultOracleBase`) |
| 310102 | `VaultOracle__AddressZero` | Zero address passed to constructor |
| 310110 | `VaultOracleFactory__AlreadyRegistered` | Vault already has a vault oracle registered |
| 310111 | `VaultOracleFactory__UnsupportedType` | Factory received unsupported vault type |
| 310112 | `VaultOracleFactory__AddressZero` | Zero address passed to factory constructor |
| 310113 | `VaultOracleFactory__InvalidVault` | Address is not a valid vault at the vault factory |
| 310114 | `VaultOracleFactory__DeployerMismatch` | T2–T4: `IFluidVault.constantsView().deployer` ≠ `DEPLOYER_FACTORY` |
| 310115 | `VaultOracleFactory__VaultIdZero` | `IFluidVault.VAULT_ID()` returned zero |
| 310116 | `VaultOracleFactory__NotRegistered` | No oracle registered for `vaultId` |
| 310117 | `VaultOracleFactory__DeploymentInvariantFailed` | Oracle address / vault ID invariant failed |
| 310118 | `VaultOracleFactory__Unauthorized` | Caller is not governance, team multisig, or allow-listed deployer; also UUPS upgrade when `msg.sender` is not Liquidity governance |
| 310119 | `VaultOracleFactory__InvalidEMode` | Requested eMode has no `configsMap` entry on any relevant token |
| 310120 | `VaultOracleFactory__DexIsNotPeg` | DEX liquidity band too wide — pool is not a peg pool |
| 310121 | `VaultOracleFactory__DexPriceReadFailed` | Could not read DEX center/range prices at registration |

---

## 11. What This Replaces

All of these old oracle V1 contracts (from `contracts/oracle/`) become unnecessary:

| Old Contract | Replaced By |
|---|---|
| `DexSmartColCLOracle` | `VaultT2Oracle` |
| `DexSmartColPegOracle` | `VaultT2Oracle` |
| `DexSmartColNoBorrowOracle` | `VaultT2Oracle` |
| `DexSmartDebtCLOracle` | `VaultT3Oracle` |
| `DexSmartDebtPegOracle` | `VaultT3Oracle` |
| `DexSmartT4CLOracle` | `VaultT4Oracle` |
| `DexSmartT4PegOracle` | `VaultT4Oracle` |
| All L2 variants of above | Not needed (USD Oracle L2 handles sequencer checks) |
| `DexConversionPriceCL` | Not needed (USD Oracle prices both tokens in USD) |
| `DexConversionPriceFluidOracle` | Not needed |
| `DexConversionPriceDirectNoBorrow` | Not needed |
| `DexColDebtPriceFluidOracle` | Not needed |
| `DexReservesFromPEX` | Not needed (raw reserves for now; PEX-adjusted can be added later) |
| `DexReservesFromLiquidityPeg` | Replaced by V1-style peg-buffer semantics in `DexShareResolver` with protocol-fixed ppm from `VaultOracleBase` |
| Existing `FluidVaultT1Oracle` (oracleV2/vaultT1, now deleted) | `VaultT1Oracle` |

The entire `implementations/dex/`, `implementations/dex/conversionPriceGetters/`, `implementations/dex/reserveGetters/`, and `implementations/dex/colDebtPrices/` directories are no longer needed for new deployments.
