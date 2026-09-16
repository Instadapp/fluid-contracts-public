# Config — SPEC (top-level index)

## 0. Gas-optimisation tier

**Cold path, every file.** Config handlers run via permissionless `rebalance()` (gas matters only insofar as the caller is reimbursed by `Reserve`), and auth contracts are called by a multisig / operator once per governance window. Clarity, safety and richer event payloads are worth far more than saving ~1 kgas here. Freely add `require`s, registration checks (C-06), structured events, and parameter bounds.

Security always wins. All findings in `contracts/config/**` audit reports are implemented.

## 1. Purpose

`contracts/config/` holds the **peripheral governance contracts** that call admin / auth paths on Fluid Liquidity, DEX, DexLite and Vaults. They split the "root owner + team multisig" trust into narrower, scoped, rate-limited authorizations so day-to-day operational changes do not need a full governance transaction and do not grant blanket admin rights.

Two shapes live in this folder:

- **Config handlers** — permissionless `rebalance()` callers that move a single parameter toward a target the contract computes from on-chain state (e.g. read an oracle, compute delta, push to Liquidity). Implement `IFluidConfigHandler`.
- **Auth contracts** — narrow, multisig / operator-gated setters that call protocol admin methods on behalf of their caller (e.g. set DEX fee, pause a market, nudge withdraw limits). Always deployed as an `auth` at the target protocol.

This `SPEC.md` is the index + the detail reference for the small / trivial pieces. Heavy contracts have their own sub-specs.

## 2. Index

### Skipped (per plan)

- `bufferRateHandler/` — out of scope.
- `ethenaRateHandler/` — out of scope.
- `expandPercentHandler/` — out of scope.
- `maxBorrowHandler/` — out of scope.

### Dedicated sub-specs

| Path | Spec | Scope |
| --- | --- | --- |
| `pauseAuth/` | [pauseAuth/SPEC.md](./pauseAuth/SPEC.md) | Pause / unpause logic for Liquidity, DEX, DexLite. |
| `dexFeeHandler/` | [dexFeeHandler/SPEC.md](./dexFeeHandler/SPEC.md) | Permissionless fee rebalancer for DEX pools. |
| `limitsAuth/` | [limitsAuth/SPEC.md](./limitsAuth/SPEC.md) | Bounded supply/borrow limit changes on Liquidity. |
| `limitsAuthDex/` | [limitsAuthDex/SPEC.md](./limitsAuthDex/SPEC.md) | Bounded supply/borrow share-limit changes on DEX. |
| `withdrawLimitAuth/` | [withdrawLimitAuth/SPEC.md](./withdrawLimitAuth/SPEC.md) | Rate-limited withdraw-limit adjustment on Liquidity. |
| `withdrawLimitAuthDex/` | [withdrawLimitAuthDex/SPEC.md](./withdrawLimitAuthDex/SPEC.md) | Rate-limited withdraw-limit adjustment on DEX. |
| `rangeAuthDex/` | [rangeAuthDex/SPEC.md](./rangeAuthDex/SPEC.md) | Rate-limited upper/lower range shifts on DEX pools. |
| `ratesAuth/` | [ratesAuth/SPEC.md](./ratesAuth/SPEC.md) | Bounded update of Liquidity rate-data curve points. |
| `liquidityTokenAuth/` | [liquidityTokenAuth/SPEC.md](./liquidityTokenAuth/SPEC.md) | Two-step governance to list + configure a new token on Liquidity. |
| `vaultFeeRewardsAuth/` | [vaultFeeRewardsAuth/SPEC.md](./vaultFeeRewardsAuth/SPEC.md) | Team multisig nudges vault supply/borrow rate magnifiers. |

### Covered in this document

- `fluidConfigHandler.sol` + `interfaces/iFluidConfigHandler.sol` — base type for all config handlers.
- `error.sol` + `errorTypes.sol` — global config error type + code table.
- `collectRevenueAuth/` — one-method rebalancer/multisig gate to call `Liquidity.collectRevenue(tokens[])`.
- `dexFeeAuth/` — direct team-multisig fee + revenue-cut setter on DEX (permissioned, unlike `dexFeeHandler` which is permissionless rebalancing).
- `paybackOnBehalfAuth/` — team-multisig-only wrapper around `Liquidity.operateOnBehalfOf` for debt repayment.

## 3. Architectural conventions

### 3.1 Config handler pattern (`IFluidConfigHandler`)

All config handlers expose:

- `currentConfig() view` — reads the parameter's current stored value (16 / 18 / 64-bit BigMath etc.).
- `newConfig() view` — derives the target value from on-chain state / oracle.
- `absoluteConfigDiff() view` — absolute delta between the two.
- `relativeConfigPercentDiff() view` — `absoluteDiff / currentConfig` scaled 1e4 (100 == 1%, 1 == 0.01%).
- `rebalance()` — permissionless (or rebalancer-gated) setter that pushes `newConfig` into the target admin method. Reverts with `*__NoUpdate` if the diff is below the handler's threshold.

The [Reserve contract](../reserve/SPEC.md) whitelist-gates the callable rebalancers; handlers typically allow calls only from reserve rebalancers or team multisigs.

### 3.2 Auth contract pattern

Auth contracts are deployed as **auths** on the target Liquidity / DEX / Vault. They expose one or a few narrowly-scoped setters, each restricted to:

- `TEAM_MULTISIG` / `TEAM_MULTISIG2` (hardcoded),
- A reserve rebalancer,
- Or their own additional allowlist managed by the auth itself (for more granular roles).

The target protocol only trusts the auth as a whole — the fine-grained split is implemented inside the auth, not at the protocol layer. This keeps the target's on-chain auth mapping small and lets governance rotate operator sets by replacing the auth contract.

### 3.3 Common constants

- `TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e` (Avocado multisig, hard-coded across most config contracts).
- `TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219` (secondary multisig, used by `dexFeeAuth`).
- `NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`.
- `FOUR_DECIMALS = 1e4` (percentage scale: 100 == 1%).

### 3.4 Error convention

All config contracts share `contracts/config/error.sol`:

```solidity
contract Error {
    error FluidConfigError(uint256 errorId_);
}
```

Error IDs live in `contracts/config/errorTypes.sol`. Ranges in use:

| Range | Contract |
| --- | --- |
| 100001–100005 | `expandPercentConfigHandler` (out of scope) |
| 100011–100014 | `ethenaRateConfigHandler` (out of scope) |
| 100021–100024 | `maxBorrowConfigHandler` (out of scope) |
| 100031–100035 | `bufferRateConfigHandler` (out of scope) |
| 100041–100045 | `ratesAuth` |
| 100051–100053 | `liquidityTokenAuth` |
| 100061–100062 | `collectRevenueAuth` |
| 100071–100076 | `withdrawLimitAuth` |
| 100081–100083 | `dexFeeHandler` |
| 100091–100095 | `rangeAuthDex` |
| 100101–100105 | `limitsAuth` / `limitsAuthDex` |
| 100111 | `dexFeeAuth` |
| 100121–100122 | `vaultFeeRewardsAuth` |
| 100131–100132 | `pauseAuth` (Liquidity) |
| 100141–100142 | `pauseAuthDex` (DEX / DexLite) |
| 100151–100152 | `paybackOnBehalfAuth` |

## 4. `FluidConfigHandler` base

`contracts/config/fluidConfigHandler.sol` defines the abstract base implementing `IFluidConfigHandler`. It leaves all five functions virtual; concrete handlers override them with their specific parameter math. The interface is used by the Reserve contract and periphery resolvers to inspect pending config updates without calling into the underlying protocols.

## 5. `collectRevenueAuth`

One-function wrapper to trigger `IFluidLiquidity.collectRevenue(tokens_)`.

- **Roles:** `onlyRebalancerOrMultisig` — reserve rebalancer (from `IFluidReserveContract.isRebalancer`) or `TEAM_MULTISIG`. Revert: `100061 CollectRevenueAuth__Unauthorized`.
- **Construction:** `(liquidity, reserveContract)`; both must be non-zero. Revert: `100062 CollectRevenueAuth__InvalidParams`.
- **Method:** `collectRevenue(address[] calldata tokens_)` → iterates at Liquidity, emits `LogCollectRevenue(tokens_)`. Uses whatever revenue collector Liquidity itself is configured to forward to; this auth does not hold or route funds.
- **Invariant:** must be deployed as **auth** on Liquidity (otherwise Liquidity's `collectRevenue` auth check would revert).

## 6. `dexFeeAuth`

Team-multisig-only setter for DEX pool fee / revenue-cut (contrast with [`dexFeeHandler`](./dexFeeHandler/SPEC.md), which is a permissionless rebalancer keyed off-chain).

- **Roles:** `onlyMultisig` — `TEAM_MULTISIG` or `TEAM_MULTISIG2`. Revert: `100111 DexFeeAuth__Unauthorized`.
- **View:** `getDexFeeAndRevenueCut(dex_) view → (fee_, revenueCut_)` — reads `dexVariables2` slot directly via `DexSlotsLink.DEX_VARIABLES2_SLOT`, extracts 17-bit fee (bits 2..18) and 7-bit revenueCut (bits 19..25). Fee is in 4-decimal precision (10 000 == 1%).
- **Setters:**
  - `setDexFee(dex_, newFee_)` — calls `IFluidDexT1Admin(dex_).updateFeeAndRevenueCut(newFee_, currentRevenueCut_ * 1e4)`. Note the `* 1e4` multiplier on the revenue cut, which the DEX admin API expects in its wire format. Emits `LogSetFee(dex, oldFee, newFee)`.
  - `setDexRevenueCut(dex_, newRevenueCut_)` — analogous. `newRevenueCut_` is already in 4-decimal scale on the DEX side (100000 == 10%; 10% cut of a 1% fee = 0.1% of swap). Emits `LogSetRevenueCut(dex, oldRevenueCut, newRevenueCut)`.
- **Deployment requirement:** auth at the DEX admin module.

## 7. `paybackOnBehalfAuth`

Team-multisig-only path to repay someone else's Liquidity debt via `operateOnBehalfOf` (which is otherwise only usable by auths).

- **Roles:** `onlyMultisig` — `TEAM_MULTISIG` only. Revert: `100151 Unauthorized`.
- **Construction:** `(liquidity)`, non-zero. Revert: `100152 InvalidParams`. Initialises `_status = 1` (reentrancy not entered).
- **Method:** `paybackOnBehalf(token, paybackAmount, onBehalf) payable onlyMultisig → (supplyExchangePrice, borrowExchangePrice)`.
  - `paybackAmount_` **must be negative**; else `100152`.
  - Sets `_status = 2` (reentrancy armed), calls `LIQUIDITY.operateOnBehalfOf{value: msg.value}(onBehalf_, token_, 0, paybackAmount_, "")`, then sets `_status = 1`.
  - Native token: send `msg.value` equal to `|paybackAmount|`.
  - ERC-20: team multisig approves this contract beforehand; `liquidityCallback` pulls with `safeTransferFrom(token, multisig, liquidity, amount)`.
  - Emits `LogPaybackOnBehalf(token, paybackAmount, onBehalf)`.
- **Callback:** `liquidityCallback(token, amount, bytes)` — gated by `msg.sender == LIQUIDITY && _status == 2`.
- **Recovery:** `rescueTokens(token, amount, to)` — multisig only, `to != 0`. Transfers native via the 50 k-gas `safeTransferNative`, or ERC-20 via `safeTransfer`.
- **Deployment requirement:** must be set as an auth on Liquidity (needed for `operateOnBehalfOf` to succeed).

## 8. Trust Model & Safety Notes

- **Multisig is the root of trust** for all auth contracts. A compromised multisig can call `setDexFee`, `paybackOnBehalf`, etc. All auths scope the attack surface to their single method set; none hold material value (`paybackOnBehalfAuth` can receive native ETH and holds it only for the duration of a tx, with `rescueTokens` available for any residue).
- **Reserve rebalancer is a second root of trust**, delegated via [FluidReserveContract](../reserve/SPEC.md). Config handlers and `collectRevenueAuth` trust whoever `RESERVE_CONTRACT.isRebalancer()` returns true for.
- **Every auth must be configured as `auth` at the target protocol** (Liquidity, DEX, Vault). Without that registration the underlying `spell` / `updateX` calls revert at the protocol side.
- **The sub-spec for each contract** (pauseAuth, limitsAuth, ratesAuth, …) documents that contract's rate limits, cooldowns, and per-role allowlists where applicable.
- **Replacement is the upgrade path.** These contracts are not themselves upgradeable; to change their logic, governance deploys a new version, registers it as an auth, and removes the old one.

## 9. Audit Notes (absorbed)

- Config contracts are intentionally narrow: they constrain both *who* can move a parameter and *by how much*, making them safer than exposing raw `updateCoreSettings` to operators.
- Hardcoded multisig addresses eliminate storage-governance risk for the multisig address itself (no setter = no "governance-change bug"). Trade-off: rotating multisigs requires redeploying the auth.
- `paybackOnBehalfAuth` intentionally forbids positive `paybackAmount_` so it can never be used as a backdoor to *increase* someone else's debt. Confirmed in audit dispositions.
- `dexFeeAuth` and `dexFeeHandler` coexist deliberately: the first is a high-trust, high-frequency instant setter for ops; the second is the permissionless rebalancer keyed off governance parameters. Governance decides which to enable per-DEX.
