# Periphery — SPEC (top-level index)

## 0. Gas-optimisation tier

**View-only — gas is not a design constraint** for every contract in this folder (including every `resolvers/**` sub-folder). These are off-chain read aggregators and integrator / rebalancer helpers; callers are block-scanners, UIs, bots, or rebalancer automation. Optimise for **clarity**, **correctness** and **richer return shapes**, not for bytecode / gas cost. Do **not** trade a safety check for a gas save.

The only exception inside this folder is the **liquidation** path (see [`./liquidation/SPEC.md`](./liquidation/SPEC.md)) which is **warm** — liquidators compete on tx cost — but security still overrides.

Security always wins.

## 1. Purpose

`contracts/periphery/` holds Fluid's **user-facing helpers, integrators and rescuers**, plus the full **read-only resolver suite** that off-chain services (UI, subgraph, bots, reserve-rebalancer automation) use to inspect protocol state. None of these contracts are in the core liquidity / DEX / vault execution path — they sit *next to* the protocols and either:

- **wrap** a protocol method with a nicer ergonomic surface (WETH wrapping, one-tx vault-position migration, wallet-based strategy composer), or
- **execute flashloan-backed back-runs** on behalf of operator rebalancers (liquidations, migrations), or
- **redirect protocol revenue** into treasury-bound ERC-20 positions (buyback DSA), or
- **aggregate storage reads** into structured views (resolvers).

See the protocol-level SPECs under `contracts/protocols/` and `contracts/liquidity/` for the contracts these helpers target, and [`docs/docs.md`](../../docs/docs.md) for the high-level architecture overview.

This `SPEC.md` is the **index** — it maps each subfolder to a one-line purpose, access model, fund-custody flag, and link to its own sub-spec. Detail lives in the sub-specs.

## 2. Index

### Operational helpers (write-path)

| Path | Purpose | Key contracts | Access | Holds funds? | Spec |
| --- | --- | --- | --- | --- | --- |
| `buyback/` | Rebalancer-driven FLUID buyback via an owned DSA; swaps protocol revenue → FLUID and forwards to treasury. | `FluidBuyback` (UUPS), `FluidBuybackProxy`, owned `buybackDSA` (Insta DSA v2) | `onlyOwner` (admin) + `onlyRebalancer` (swap / collect) | Yes — transient; DSA + contract hold swap inputs/outputs until `collectTokensToTreasury` | [buyback/SPEC.md](./buyback/SPEC.md) |
| `liquidation/` | Flashloan-backed vault liquidator for T1–T4 vaults. V1 is a thin single-vault version; the proxy version whitelists rebalancers + swappable implementations. | `VaultT1Liquidator` (standalone), `VaultLiquidator` (proxy + implementation registry), `VaultLiquidatorImplementationV1` | `onlyOwner` (admin) + `isRebalancer` (execute) | Transiently (flashloan in, swap, flashloan out) — residual dust withdrawable by owner | [liquidation/SPEC.md](./liquidation/SPEC.md) |
| `migration/` | One-tx migrator that moves a user's T1 vault NFT position from the old vault factory to the new one, covered by a flashloan. | `VaultT1Migrator` | `onlyOwner` (configure flashloan routes), user-initiated via `safeTransferFrom(nft)` | Transiently (flashloan) | [migration/SPEC.md](./migration/SPEC.md) |
| `wallet/` | Per-user smart-wallet factory + clone implementation used to compose multi-action Vault T1 strategies via NFT transfer. | `FluidWalletFactory` (UUPS), `FluidWalletImplementation`, `FluidWallet` (minimal proxy clone) | `onlyOwner` on factory (implementation swap); wallet gated by `owner` (the user) | User's wallet holds the Vault NFT for the duration of the cast | [wallet/SPEC.md](./wallet/SPEC.md) |
| `wethWrapper/` | Aave-interface-shaped wrapper that lets a Vault T1 (native-ETH collateral) be interacted with using WETH. | `FluidWETHWrapper` (UUPS) | `onlyOwner` — single-user wrapper deployed per user/vault | Transient WETH/ETH wrap boundary | [wethWrapper/SPEC.md](./wethWrapper/SPEC.md) |

### Read-only resolvers (view-only)

| Path | Scope |
| --- | --- |
| `resolvers/` | All off-chain-consumed view contracts for Liquidity, DEX, DexLite, lending, vaults (T1–T4), positions, ticks/branches, liquidation simulation, reserves, revenue projection, smart lending, staking (mainnet + arb), and stETH. Read-only, stateless, no funds. |

See [resolvers/SPEC.md](./resolvers/SPEC.md) for the per-resolver breakdown. Resolvers are flagged separately from the write-path helpers because they are **pure read aggregators** — they own no storage beyond immutables (often just pointers to Liquidity / factories), hold no value, and are freely redeployable.

## 3. Shared Conventions

### 3.1 Proxy pattern

The upgradeable helpers (`buyback`, `wallet/factory`, `wethWrapper`) all use **OpenZeppelin UUPS** behind an `ERC1967Proxy`:

- Implementation's `constructor` calls `_disableInitializers()` (v4.x safety).
- `initialize(...)` is wrapped in `initializer` and sets `owner` / per-contract state.
- `_authorizeUpgrade` is `onlyOwner` — upgrades are under the team's control, not a separate governance path.
- `renounceOwnership` is overridden to revert (would brick the upgrade path).

Non-upgradeable helpers (`liquidation`, `migration`) use **solmate `Owned`** and expose an `onlyOwner` `spell(targets[], calldatas[])` escape hatch for delegate-calls — a standard Instadapp-wide rescue pattern.

### 3.2 Rebalancer allowlist

`buyback`, `liquidation` and the migration flashloan route all use the same pattern: `mapping(address => bool) rebalancer` plus an `onlyRebalancer` / `isRebalancer` modifier, toggled by the owner. This is an in-contract allowlist, independent of the [FluidReserveContract](../reserve/SPEC.md) rebalancer registry used by `contracts/config/` handlers (periphery predates that registry).

### 3.3 Flashloan integration

`liquidation/` and `migration/` both integrate with **InstaFlashInterface** (`InstaFlashInterface.flashLoan` / `executeOperation` callback). The contracts self-check `msg.sender == FLA && initiator == address(this)` in the callback; route / token / amount come from in-contract storage (`flashloanConfig` for migration, per-call params for liquidation).

### 3.4 Native ETH / WETH handling

All helpers that touch native ETH use:

- `SafeTransfer.safeTransferNative` (50k-gas stipend, from [`contracts/libraries/`](../libraries/SPEC.md)) for payouts, and
- `IWETH9.deposit` / `withdraw` for the wrap/unwrap boundary,
- `address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` as the pseudo-token sentinel.

### 3.5 Error surface

Each helper defines its own local `error` types (no shared `Error` base like `contracts/config/error.sol`). Naming follows `Fluid<ContractName>__<Reason>` or `<Contract>__<Reason>`. Codes are not globally allocated here; they're enum entries local to each contract (e.g. `wethWrapper/errorTypes.sol` defines `ErrorTypes.Weth_*`).

### 3.6 Reentrancy

Helpers that move funds across an external call boundary (`buyback`, `wethWrapper`) carry their own `nonReentrant` modifier with a simple storage-bit lock (`_status: 1=open, 2=entered`). The lock is initialised to `ENTERED` on the logic contract and flipped to `NOT_ENTERED` in `initialize()` on the proxy, so the logic contract can never be called directly.

### 3.7 Resolver conventions

Documented in [resolvers/SPEC.md](./resolvers/SPEC.md); briefly: resolvers are immutable-only, call `readFromStorage` + slot-link libraries directly for gas, and expose struct-heavy return shapes consumed by the Fluid frontend + subgraph.

## 4. Trust Model

- **Owner is the root of trust** for every write-path helper in this folder. Owner can upgrade (UUPS contracts), swap implementations (liquidator proxy, wallet factory), run arbitrary delegate-calls (`spell`), and withdraw residual balances. In production the owner is either a Fluid multisig or the `FluidReserveContract`, never an EOA.
- **Rebalancers are second-tier operators**: they can trigger swaps / liquidations / revenue-collection, but cannot drain funds, cannot change allowlists, and cannot upgrade.
- **Users are self-sovereign inside their own wallet clone** (`wallet/`) and inside their per-user `wethWrapper` — the owner of those contracts is the end user, not the team. The team can only change the *future* implementation on the factory; it cannot seize existing wallets.
- **Resolvers are trustless** (view-only, no privileged entry points, no funds).
- **Replacement, not upgrade, is the safe path for `liquidation/` and `migration/`** — they're non-upgradeable. A logic change means a new deploy + repointing whatever off-chain infra feeds them.

## 5. Deployment & Ownership

| Helper | Deployment shape | Typical owner in production |
| --- | --- | --- |
| `buyback/` | `FluidBuybackProxy(logic, initData)` → `initialize(owner, rebalancers[])` → builds owned DSA. | Fluid team multisig (can upgrade). |
| `liquidation/` (proxy) | Deploy implementation(s), then `VaultLiquidator(owner, rebalancers[], implementations[])`. | Fluid team multisig; rebalancers are bot addresses. |
| `liquidation/` (standalone) | `VaultT1Liquidator(owner, fla, weth, rebalancers[])`. | Legacy; still live for old T1 vaults. |
| `migration/` | `VaultT1Migrator(owner, fla, weth, oldFactory, newFactory)` + `setFlashloanConfig` per token. | Team multisig; user-triggered via NFT transfer. |
| `wallet/` factory | `FluidWalletFactory` (UUPS) + one shared `FluidWalletImplementation` + minimal `FluidWallet` clone per user. | Team multisig owns the factory; user owns their own clone. |
| `wethWrapper/` | `FluidWETHWrapper(vault, weth)` → `initialize()` — one per vault/user pair. | End user. |
| `resolvers/` | Plain constructor-only deploys, parameterized with Liquidity / DEX / factory addresses. | None — read-only, replaced by redeploy. |

## 6. Audit & Safety Notes

- Every helper that can hold tokens exposes an owner-gated `withdraw` / `collectTokensToTreasury` / `rescueTokens` path so stuck dust never becomes a permanent loss.
- The `spell` delegate-call in `liquidation` / `migration` / `wallet/factory` is an unbounded owner capability. It exists for upgrades-without-redeploy of immutable contracts; treat owner compromise as equivalent to full loss of any funds those contracts hold.
- `buyback`'s `buybackDSA` is built at `initialize` time with `address(this)` as both owner and auth; only the Buyback contract itself can `cast` on that DSA. A compromised Buyback owner can still rewrite the rebalancer set and drain via `collectTokensToTreasury(token)` — same trust ceiling as the contract itself.
- `wethWrapper` is **per-user, per-vault** and assumes the user controls the wrapper's owner key. It is not intended to be shared. See [wethWrapper/SPEC.md](./wethWrapper/SPEC.md) for the full param list and the Aave-shaped external surface.
- Legacy / V1 contracts (`VaultT1Liquidator`, the original migrator) target the **old T1 vault factory only**. The newer `VaultLiquidator` + `VaultLiquidatorImplementationV1` set supports T1–T4.

## 7. Cross-Links

- Protocols this folder wraps: [`contracts/liquidity/SPEC.md`](../liquidity/SPEC.md), [`contracts/protocols/dex/SPEC.md`](../protocols/dex/SPEC.md), [`contracts/protocols/vault/SPEC.md`](../protocols/vault/SPEC.md), [`contracts/protocols/lending/SPEC.md`](../protocols/lending/SPEC.md), [`contracts/protocols/steth/SPEC.md`](../protocols/steth/SPEC.md).
- Governance / auth side (separate folder, similar trust model): [`contracts/config/SPEC.md`](../config/SPEC.md).
- Shared math / safe-transfer / slot-link libraries used here: [`contracts/libraries/SPEC.md`](../libraries/SPEC.md).
- Architecture overview: [`docs/docs.md`](../../docs/docs.md).
