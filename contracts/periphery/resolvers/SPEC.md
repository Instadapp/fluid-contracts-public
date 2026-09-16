# Resolvers — SPEC (top-level index)

## 0. Gas-optimisation tier

**View-only — gas is not a design constraint.** Every resolver is called via `eth_call` / `callStatic` by UIs, indexers, liquidation keepers and rebalancer automation. Optimise for **clarity**, **correctness** and **richer return shapes** (structs with named fields rather than raw tuples, per-asset arrays rather than single-asset lookups). Do **not** trade a safety check for a gas save.

The same rule applies to every `resolvers/<module>/SPEC.md` below.

Security always wins.

## 1. Purpose

`contracts/periphery/resolvers/` holds Fluid's **read-only aggregator contracts**. They are the canonical data plane for off-chain consumers — UIs, indexers, bots, analytics, liquidation keepers, rebalancers, and integrators — and exist so callers can fetch a consistent, rich view of Liquidity / Vault / DEX / DexLite / Lending / StETH / Staking state in **one RPC call** instead of orchestrating dozens of protocol-level `readFromStorage` probes.

Key properties:

- **View / pure only.** All functions are `view` or `pure`. A handful of helpers are declared non-`view` purely so they can route through revert-for-data paths on the underlying protocols (e.g. vault liquidation simulation); in practice they must be called with `eth_call` / `callStatic` and never make state changes.
- **Stateless.** Resolvers hold no funds, no owner, no admin, no governance. The only storage is an immutable pointer to the target protocol (Liquidity, VaultFactory, DexFactory, etc.) set in the constructor.
- **Not consumed on-chain by Fluid itself.** Resolvers are intentionally external. Fluid's production protocols never call into a resolver — they read their own packed slots directly through `storageRead`. Resolvers layer *interpretation* on top of those slots.
- **Rich structs.** Instead of returning raw packed `uint256` slots, resolvers return named structs (`UserSupplyData`, `VaultEntireData`, `DexEntireData`, `SwapPath`, …) so consumers don't re-implement bit layouts off-chain.
- **Replaceable.** Because no other on-chain contract depends on a specific resolver address, governance is free to redeploy a newer version whenever the underlying protocol storage layout changes. Old versions keep working for pinned consumers until the storage layout diverges.

This `SPEC.md` is the **index** — it lists every subfolder and links to each resolver's own SPEC. The shared `common/` subfolder does not get its own SPEC and is documented inline below.

## 2. Architectural conventions

### 2.1 Shape of a resolver

Each resolver subfolder follows the same skeleton:

- `main.sol` — the deployed aggregator contract (e.g. `FluidLiquidityResolver`, `FluidVaultResolver`, `FluidDexResolver`). One contract per subfolder, sometimes composed from several `abstract` pieces defined in the same file.
- `structs.sol` — named output structs.
- `variables.sol` / `helpers.sol` — immutables (target protocol pointers, bit masks) and internal helpers.
- `i*Resolver.sol` — optional external interface for integrators that want to import just the ABI without pulling the implementation into their solc unit.

Most resolvers are gas-heavy (thousands of SLOADs per call) and are expected to be called off-chain, often batched through `Multicall3`. They are compiled the same way as the rest of the codebase (Solidity 0.8.21 for legacy pieces, 0.8.29 for DexLite) but are never part of a critical-path tx.

### 2.2 Reading strategy

Resolvers read target state via two paths:

1. **Raw `readFromStorage(slot)`** — using `liquiditySlotsLink` / `dexSlotsLink` / `dexLiteSlotsLink` (see [libraries/SPEC.md](../../libraries/SPEC.md)). This bypasses Liquidity/DEX delegate-call overhead entirely and lets the resolver assemble the same view that the protocol itself would compute.
2. **Typed getters** where the target contract already exposes a convenient view (e.g. `IFluidVault.constantsView()`, `IFluidVaultFactory.totalVaults()`).

Both paths produce the same numbers; resolvers mix them pragmatically.

### 2.3 Computed vs stored values

Many returned fields are *derived* — e.g. `supplyRate`, `utilization`, `liquidationPrice`, `withdrawableUntilLimit`, projected exchange prices. These are computed on the fly using the same libraries (`liquidityCalcs`, `dexCalcs`, `tickMath`, `bigMathMinified`) the protocols use, so resolver output matches what the protocol would produce at the same block/time.

### 2.4 Cross-resolver composition

Resolvers freely call each other when they need data from a different layer. Typical chains:

- `FluidVaultResolver` holds an immutable `liquidityResolver` and re-uses its `OverallTokenData` struct for each leg.
- `FluidVaultLiquidationResolver` / `FluidVaultTicksBranchesResolver` depend on `FluidVaultResolver` to iterate vaults.
- `FluidSmartLendingResolver` embeds a `FluidDexResolver`.
- `FluidStakingRewardsResolver` embeds a `FluidLendingResolver`.
- `FluidStETHResolver` embeds a `FluidLiquidityResolver`.

This produces a directed graph (liquidity → vault → vaultLiquidation / vaultTicksBranches / vaultPositions; dex → smartLending; lending → stakingRewards; steth → liquidity) with no cycles. Bootstrap order for a fresh chain follows that graph: `liquidity` first, then `vault` / `dex`, then the leaf resolvers that depend on them.

### 2.5 Naming

Contracts follow `Fluid<Scope>Resolver`; folders are the lower-camel scope (`vault/`, `dexLite/`, `vaultLiquidation/`, …). `vaultT1/` is the legacy-only resolver preserved for backwards compatibility — new integrations should prefer `vault/`.

### 2.6 Errors

Resolvers raise only trivial input-validation errors of the form `Fluid<Scope>Resolver__AddressZero` / `__InvalidParams`, thrown from constructors or when an integrator passes zero / inconsistent parameters. They never revert for protocol-state reasons — a token that isn't configured, a vault that doesn't exist, or a user without a position returns zero/empty structs, not a revert. This keeps batch calls from poisoning an entire multicall because one leg was misconfigured.

## 3. Subfolder index

Every subfolder listed below ships one `Fluid*Resolver` contract and has its own `SPEC.md`. `common/` is the only exception and is documented inline in §4.

| Subfolder | Contract | What it exposes | Spec |
| --- | --- | --- | --- |
| `liquidity/` | `FluidLiquidityResolver` | Per-token rates, utilization, exchange prices, total amounts, user supply/borrow positions, auths, guardians, revenue. Foundation for every other resolver that touches Liquidity. | [liquidity/SPEC.md](./liquidity/SPEC.md) |
| `vault/` | `FluidVaultResolver` | Unified resolver for all vault types (T1/T2/T3/T4). Vault list, constants, configs, per-NFT positions, limits, oracle prices, `VaultEntireData`. Use this for any new integration. | [vault/SPEC.md](./vault/SPEC.md) |
| `vaultT1/` | `FluidVaultT1Resolver` | Legacy resolver predating the multi-type vault shape. Kept for backwards-compatible integrations; superseded by `vault/`. | [vaultT1/SPEC.md](./vaultT1/SPEC.md) |
| `vaultPositions/` | `FluidVaultPositionsResolver` | Paged enumeration of NFT positions per vault (3000/page) plus batched position lookups, for chains where enumerating everything at once would OOG. | [vaultPositions/SPEC.md](./vaultPositions/SPEC.md) |
| `vaultLiquidation/` | `FluidVaultLiquidationResolver` | Available liquidation swap paths and amounts across all T1-shaped vaults, with and without absorb. Drives liquidation keepers. | [vaultLiquidation/SPEC.md](./vaultLiquidation/SPEC.md) |
| `vaultTicksBranches/` | `FluidVaultTicksBranchesResolver` | Walks vault tick bitmaps and branch chains, returning per-tick debt / per-branch state for debt-curve analytics and keeper targeting. | [vaultTicksBranches/SPEC.md](./vaultTicksBranches/SPEC.md) |
| `dex/` | `FluidDexResolver` | Full DEX (poolT1) state: reserves, prices, range/threshold shifts, swap estimates, per-user supply/borrow shares. | [dex/SPEC.md](./dex/SPEC.md) |
| `dexLite/` | `FluidDexLiteResolver` | Equivalent of `dex/` for the DexLite protocol (singleton multi-pool architecture keyed by `DexKey`). | [dexLite/SPEC.md](./dexLite/SPEC.md) |
| `dexReserves/` | `FluidDexReservesResolver` | Slimmer/faster subset of `dex/` focused on swap-estimation + reserves; used by routing integrators (1inch, Odos, etc.) that don't need user/borrow data. | [dexReserves/SPEC.md](./dexReserves/SPEC.md) |
| `smartLending/` | `FluidSmartLendingResolver` | Smart-lending tokens (DEX-backed yield wrappers). Lists tokens, pricing, user positions; embeds `FluidDexResolver`. | [smartLending/SPEC.md](./smartLending/SPEC.md) |
| `lending/` | `FluidLendingResolver` | fToken protocol view: per-fToken config, rewards rate model, user balances, permit / permit2 allowances; embeds `FluidLiquidityResolver`. | [lending/SPEC.md](./lending/SPEC.md) |
| `stakingRewards/` | `FluidStakingRewardsResolver` | fToken staking-rewards contracts: reward rate, duration, per-user earned / staked balance; embeds `FluidLendingResolver`. | [stakingRewards/SPEC.md](./stakingRewards/SPEC.md) |
| `stakingMerkle/` | `FluidStakingMerkleResolver` (mainnet) / `FluidStakingMerkleResolver` in `mainArb.sol` (Arbitrum) | Per-user fUSDC / fUSDT combined (normal + staked) share balance. Purpose-built for Merkle-drop snapshot scripts. Chain-specific addresses hard-coded per deployment. | [stakingMerkle/SPEC.md](./stakingMerkle/SPEC.md) |
| `revenue/` | `FluidRevenueResolver` | Currently-uncollected and future-projected revenue per Liquidity token and per vault, including time-simulated projections via `CalcsSimulatedTime` / `CalcsVaultSimulatedTime`. | [revenue/SPEC.md](./revenue/SPEC.md) |
| `steth/` | `FluidStETHResolver` | Fluid StETH withdrawal queue view: per-claim state, per-user claim IDs, aggregated ETH owed, plus underlying Lido withdrawal-queue data. | [steth/SPEC.md](./steth/SPEC.md) |
| `common/` | — (abstract base `ResolverHelpers`) | Shared base inherited by most resolvers. Documented inline below. | — |

## 4. `common/` — shared base (inline)

`contracts/periphery/resolvers/common/helpers.sol` defines a single tiny abstract:

### `abstract contract ResolverHelpers`

Re-hypothecation awareness for token balances that Liquidity has deposited into external yield venues. Without this helper, any resolver that divides `Liquidity.balanceOf(token)` by `totalSupply` would under-report because the balance has temporarily left the contract.

- Hard-coded mainnet addresses:
  - `WEETH   = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee`
  - `WEETHS  = 0x917ceE801a67f933F2e6b33fC0cD1ED2d5909D88`
  - `ZIRCUIT = 0xF047ab4c75cebf0eB9ed34Ae2c186f3611aEAfa6` (Zircuit `IZtakingPool`).
- `_getLiquidityExternalBalances(address token, address liquidity) internal view returns (uint256)` — returns `0` on any chain other than mainnet (`block.chainid != 1`); otherwise probes Zircuit for the `(token, liquidity)` tuple for `WEETH` / `WEETHS` and returns the re-hypothecated balance. Other tokens return `0`.
- Also declares the `IZtakingPool { balance(address,address) }` interface used for the lookup.

Inherited by: `FluidLiquidityResolver`, `FluidVaultResolver`, `FluidVaultT1Resolver`, `FluidVaultLiquidationResolver`, `FluidDexReservesResolver`, `FluidRevenueResolver`. Not used by resolvers that don't dereference Liquidity balances directly (DEX, DexLite, lending, staking, smart-lending, steth — those go through a lower-layer resolver that already accounts for it).

Design notes:

- The `block.chainid != 1` guard is cheap and lets the same artifact be deployed unchanged on every chain; non-mainnet deployments simply short-circuit to `0`.
- The Zircuit pool address is `constant`, not `immutable`: updating it requires a full resolver redeploy. This matches the "resolvers are replaceable" philosophy — no setter surface is preferable to a governance-gated setter.
- There are no shared structs or constants in `common/` today; every resolver declares its own `structs.sol`. If shared types are introduced in future, they belong in this folder.
- `common/` has no `SPEC.md` of its own because there is only one 33-LOC file in it and no public contract.

## 5. Access control & funds

- **No owner. No admin. No pausable.** Every resolver is a plain contract with an immutable constructor. There is nothing to rotate or revoke.
- **No funds held.** Resolvers never hold native ETH or ERC-20s. There is no `rescueTokens`, `withdraw`, or `sweep` path and none is needed.
- **Constructor sanity checks.** Each resolver reverts with `*__AddressZero` if its constructor is given `address(0)` for a required pointer. Beyond that, constructors do no validation — a resolver pointed at a non-Fluid target will simply return garbage.

## 6. Safety notes & integration guidance

- **Staleness on protocol upgrade.** Resolvers read packed slots by offset. A protocol upgrade that changes a slot layout silently breaks readers: fields return wrong numbers rather than reverting. Consumers **should pin a specific resolver deployment address per protocol version**, and governance **should deploy a new resolver whenever a target contract's storage layout changes**. The main `deployments.md` table is the source of truth for current vs deprecated resolver addresses.
- **Non-view-labelled methods.** `FluidVaultResolver.getVaultLiquidation`, the `FluidDexLiteResolver.getPricesAndReserves` family, and `FluidVaultLiquidationResolver`'s simulation paths are declared non-`view` because the underlying estimator re-enters the protocol through paths that can in principle write (they don't in resolver context, but solc still type-checks the call). **Callers must use `eth_call` / `callStatic`**; any integrator that sends a live tx to these paths is doing something wrong and will waste gas while still producing a read-only result.
- **Gas cost.** These are aggregator contracts. Single-method calls regularly SLOAD hundreds to thousands of slots. They are fine for off-chain RPC (~10-50 ms per call on a decent node) and unusable on-chain. Never consume a resolver from another on-chain contract unless you have quantified and budgeted the gas.
- **Re-hypothecation.** Only WEETH / WEETHS on mainnet are currently offset via `ResolverHelpers`. Adding a new re-hypothecation venue requires a resolver redeploy.
- **Chain specificity.** `stakingMerkle/main.sol` hard-codes mainnet addresses; `stakingMerkle/mainArb.sol` hard-codes Arbitrum addresses. Other resolvers are chain-agnostic (immutables supplied at deploy).
- **Multicall.** Resolvers are designed to be batched. Typical UI patterns fetch ~5-20 resolver calls in a single `Multicall3.aggregate` to produce a full dashboard state.
- **Precision.** Computed fields (rates, utilization, liquidation prices) share the target protocol's precision exactly: `EXCHANGE_PRICES_PRECISION = 1e12`, `FOUR_DECIMALS = 1e4` for percentages (100 == 1%), `SIX_DECIMALS = 1e6` for share accounting. BigMath-compressed fields are returned decompressed via `bigMathMinified` so consumers never see the packed form unless they explicitly asked for a `*Raw` slot getter.
- **Raw getters vs typed getters.** Most resolvers expose both: typed methods return rich structs; `*Raw` methods return the underlying `uint256` slot so advanced consumers can do their own bit-extraction. The typed methods are authoritative — the raw methods exist purely as an escape hatch.
- **Eventual-consistency for re-hypothecation.** `_getLiquidityExternalBalances` reads the external venue (currently Zircuit) at the same block as the Liquidity balance. If the external venue exposes a lagging view, the resolver will too. Consumers who need strictly-consistent accounting across a Liquidity-external transfer should avoid that block.

## 7. Trust model

- **No trust needed.** Resolvers are pure readers. A malicious or buggy resolver can return wrong numbers to a caller but cannot move funds, pause anything, change config, or affect on-chain state in any way. The attack surface is confined to "consumer integrated the wrong deployment address and trusted its output".
- **No governance surface.** There is no `setX`, no owner transfer, no auth mapping. Replacement is the only upgrade path: deploy a new resolver, update the deployment registry, and let integrators migrate.
- **Immutable constructor pointers.** Once deployed, a resolver cannot be re-pointed at a different target. This is deliberate: the resolver address on-chain is effectively a static alias for `(target protocol, storage-layout version, resolver-version)`.
- **No privileged callers.** Every method is externally callable by anyone. There is no "only-auth" or "only-multisig" path in the resolver layer — privileged operations belong in `contracts/config/` (see [config/SPEC.md](../../config/SPEC.md)).
- **Supply-chain risk.** The only external dependency outside Fluid's own contracts is OpenZeppelin's `IERC20` / `IERC20Permit` (for ABIs) and Solmate's `FixedPointMathLib` (used by `dexReserves/` and `dexLite/` for math). Both are pure / view and pose no trust surface at runtime.

## 8. Per-resolver details

### 8.1 DEX family (three resolvers, one protocol)

Three separate resolvers target the same DEX (`poolT1`) protocol at different levels of detail:

- `dex/` — the complete view (reserves, prices, shifts, user positions, action estimates).
- `dexReserves/` — a swap-routing focused subset (reserves + swap estimation only) used by external aggregators that want minimum RPC weight.
- `dexLite/` — targets the separate **DexLite** protocol (singleton contract, multiple pools keyed by `DexKey`), not a different view of the same DEX.

Consumers pick based on payload: a UI rendering a pool page uses `dex/`; a router quoting a swap uses `dexReserves/`; a DexLite integration has to use `dexLite/`.

### 8.2 Vault family (five resolvers, one protocol)

- `vault/` — canonical view covering all vault types.
- `vaultT1/` — legacy shape, retained for backwards compatibility.
- `vaultPositions/` — paged NFT-list enumeration (large vaults, L2 gas constraints).
- `vaultLiquidation/` — swap-path / liquidation-amount simulation.
- `vaultTicksBranches/` — per-tick / per-branch debt distribution.

A dashboard typically composes `vault/` with one or two of the satellites; keepers use `vaultLiquidation/` standalone.

### 8.3 Per-resolver detail

Each subfolder's `SPEC.md` documents its contract's:

1. Purpose (what slice of state it surfaces).
2. External dependencies (target protocols, other resolvers it composes).
3. Public methods and their returned structs.
4. Computed-value semantics (what each derived field means, how it's projected forward in time).
5. Gas and paging behaviour (where applicable).
6. Invariants and edge cases (e.g. zero-configured token returning `0` vs reverting, handling of paused tokens/users, absorb vs non-absorb liquidation paths).
7. Deployment dependencies (which pointers the constructor needs, in which order to deploy when bootstrapping a new chain).

Follow the link in the §3 table for the per-resolver detail.
