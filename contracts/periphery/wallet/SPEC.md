# Periphery / wallet — SPEC

## 1. Purpose

Per-owner **smart wallet** for Fluid users that can custody vault NFT positions, fTokens and any arbitrary asset on behalf of a single EOA and execute **multi-action batches** (`call` / `delegatecall` / Instadapp flash-loan) in one tx.

Two usage modes:

- **Vault-NFT entry**: user calls `VaultT1Factory.safeTransferFrom(user, factory, nftId, abi.encode(actions))`. The factory receives the NFT, deterministically deploys the user's wallet if missing, forwards the NFT + actions to it, the wallet runs the actions, then returns the NFT + any residual vault tokens to the owner.
- **Direct cast**: once a wallet exists, its owner EOA calls `wallet.cast(actions[])` to run any batch of actions from the wallet address (delegatecalls, external calls, flash-loans).

The wallet address is a **deterministic function of the owner EOA** (`CREATE2` clone, salt = `keccak256(owner)`), so `owner → wallet` is 1:1 and address is known before deploy.

Implemented as **four contracts**:

| Contract | File | Role |
| --- | --- | --- |
| `FluidWalletFactory` | `factory/main.sol` | UUPS-upgradeable logic. Deploys / predicts wallets, handles vault-NFT entry callback, holds wallet-implementation pointer. |
| `FluidWalletFactoryProxy` | `factory/proxy.sol` | Stock `ERC1967Proxy` in front of the factory logic. |
| `FluidWallet` | `wallet/proxy.sol` | Per-user custom proxy. Minimal-clone target. Holds `owner` in slot 0; `fallback` delegatecalls to `factory.walletImplementation()`. |
| `FluidWalletImplementation` | `wallet/main.sol` | Wallet logic (ERC721 receive, `cast`, flash-loan callback, sweep). Executed via `delegatecall` from every wallet proxy. |

## 2. Architecture & Data Flow

```mermaid
flowchart LR
    EOA[Owner EOA] -->|safeTransferFrom NFT + actions| VF[(Vault T1 Factory)]
    VF -->|onERC721Received| FAC[FluidWalletFactory\nfactory/main.sol]
    FAC -->|Clones.cloneDeterministic\nsalt = keccak(owner)| W[FluidWallet proxy]
    FAC -->|safeTransferFrom NFT + actions| W
    VF -->|onERC721Received| W
    W -. delegatecall .-> IMPL[FluidWalletImplementation]
    IMPL -->|call / delegatecall / flashloan| TGT[(any target)]
    IMPL -->|sweep NFT + tokens| EOA
    EOA -->|cast actions[]| W
    ADMIN[Factory owner] -->|changeImplementation / upgradeTo / spell| FAC
```

Two indirections:

1. **Factory-side UUPS.** `FluidWalletFactoryProxy` (ERC1967) → `FluidWalletFactory` logic. Upgrade gated by factory `owner` (`_authorizeUpgrade`).
2. **Wallet-side double-hop.** Each user's `FluidWallet` is a minimal clone of the `WALLET_PROXY` singleton created in the factory constructor. The clone's `fallback` reads `factory.walletImplementation()` on every call and `delegatecall`s that implementation. Consequence: **one implementation swap upgrades every user's wallet atomically**.

Per-wallet deploy flow:

1. `Clones.predictDeterministicAddress(WALLET_PROXY, keccak(owner), factory)` → `wallet_`.
2. If `wallet_.code.length == 0`: `Clones.cloneDeterministic` then `FluidWallet(wallet_).initialize(owner)`. Else no-op.
3. `initialize` is one-shot (reverts if `owner != 0`).

## 3. External Interactions

| Target | Direction | Purpose |
| --- | --- | --- |
| `VAULT_T1_FACTORY` (ERC721) | Factory inbound `onERC721Received` | Entry point for NFT-bearing user flows. Also used to assert post-conditions (`ownerOf == params.owner`, `balanceOf(factory) == 0`). |
| `VAULT_FACTORY` (wallet-side) | Wallet inbound `onERC721Received` | Forwarded from `FluidWalletFactory` after clone is created; wallet executes actions then transfers NFT back. |
| `IFluidVault` / `IFluidVaultT1` | Wallet read + `_sweepTokens` | Reads `constantsView()` of the NFT's vault (resolved via `VAULT_FACTORY.readFromStorage(slot 3 mapping)`) to discover `supplyToken{0,1}` / `borrowToken{0,1}` to sweep. Handles both newer vaults (`TYPE()` present) and T1 (single tokens, fall-through via `try/catch`). |
| Instadapp Flash-loan Aggregator | Wallet outbound `.call` + inbound `executeOperation` | `Action.operation == 2` forwards `action.data` to a flash-loan aggregator; the aggregator re-enters the wallet via `executeOperation` which is gated by a per-tx `_transientAllowHash`. |
| **Any target** | Wallet outbound `.call` / `.delegatecall` | `Action.operation == 0` / `== 1`. **No allow-list.** The wallet will call/delegatecall any address with any payload, provided the caller passed owner validation. |

> There is **no registered-protocol allow-list**. Trust is entirely "owner says so" — see §11.

## 4. Roles & Access Control

### On `FluidWalletFactory`

| Modifier / check | Who passes | Applies to |
| --- | --- | --- |
| `onlyOwner` (OZ) | factory `_owner` | `spell`, `changeImplementation`, `_authorizeUpgrade`, `renounceOwnership` |
| `msg.sender == VAULT_T1_FACTORY` + `operator == from` + `data.length > 0` | Vault T1 Factory only | `onERC721Received` |
| (none) | anyone | `deploy`, `computeWallet`, `walletImplementation`, `initialize` (one-shot) |

- `initialize(owner_)` is `initializer`-guarded — callable exactly once at proxy deployment.
- `renounceOwnership` is **overridden to revert** (`FluidWalletFactory__InvalidOperation`) so the factory can never become ownerless.

### On `FluidWallet` / `FluidWalletImplementation`

| Entry point | Authorization |
| --- | --- |
| `cast(actions[])` | `_validateOwner(msg.sender)` — recomputes `predictDeterministicAddress(WALLET_PROXY, keccak(msg.sender), FLUID_WALLET_FACTORY)` and reverts unless it equals `address(this)`. Implicitly enforces **one wallet ↔ one owner EOA**. |
| `onERC721Received` | `msg.sender == VAULT_FACTORY` **and** `operator == from` **and** `operator == FLUID_WALLET_FACTORY`. Decodes `(owner, actions[])`; re-runs `_validateOwner(owner)` against `address(this)`. |
| `executeOperation` | `_transientAllowHash == keccak(data, block.timestamp)` **and** `initiator == address(this)`. |
| `initialize(owner)` | Callable by anyone but effectively only usable once (`if (owner == address(0)) set; else revert`). Called by the factory atomically with the clone deploy. |

There are no guardians, delegates, or session keys. The wallet's on-chain authority collapses to "is the deterministic clone address of `msg.sender`".

## 5. Storage Layout

### `FluidWalletFactory` (behind ERC1967 proxy)

Inheritance chain determines slots: `Initializable` (slot 0) → `ContextUpgradeable` (`__gap[50]`, slots 1–50) → `OwnableUpgradeable` (`_owner` slot 51, `__gap[49]` slots 52–100) → custom.

| Slot | Name | Notes |
| --- | --- | --- |
| 0 | `_initialized` / `_initializing` | packed, from `Initializable` |
| 51 | `_owner` | factory owner |
| 101 | `_implementation` | wallet implementation pointer; read by every `FluidWallet` fallback |

Immutables (baked into factory logic code, no slot): `VAULT_T1_FACTORY`, `WALLET_PROXY` (address of the clone-template `FluidWallet` deployed in the factory constructor with `FACTORY = fluidWalletFactoryProxy_`).

### `FluidWallet` proxy + `FluidWalletImplementation` (same layout)

| Slot | Name | Source | Notes |
| --- | --- | --- | --- |
| 0 | `owner` | `FluidWallet` proxy and `FluidWalletVariables` | **Must match** between proxy and implementation; both declare `address public owner` first. |
| 1 | `_transientAllowHash` | `FluidWalletVariables` | Per-tx flash-loan guard. Written only during op-2 execution; `_resetTransientStorage()` writes `1` (not `0`) — dirty, non-matching sentinel, cheaper than zeroing. |

Immutables (per-contract, not per-clone): on proxy side `FACTORY`; on implementation side `VAULT_FACTORY`, `FLUID_WALLET_FACTORY`. Clones inherit the proxy's immutables (baked into the singleton code the clone delegatecalls to? — *no*, minimal clones copy only the runtime stub; the immutables live in the `WALLET_PROXY` singleton that the clone delegatecalls into via the OZ Clones pattern — see §10).

Constants: `VERSION = "1.1.1"`, `ETH_ADDRESS = 0xEeee…EEeE`, `X32 = 0xffffffff`.

## 6. Public Capabilities (Wallet side)

### `cast(Action[] actions) payable`

Owner-only multi-action executor. `Action` shape:

```solidity
struct Action { address target; bytes data; uint256 value; uint8 operation; }
```

| `operation` | Meaning | Semantics |
| --- | --- | --- |
| `0` | `call` | `target.call{value: action.value}(data)`. Reverts if target reverts; revert reason re-encoded as `"{i}_..."` (see §9). |
| `1` | `delegatecall` | `target.delegatecall(data)`. Runs inside the wallet's context; `_resetTransientStorage()` is called *before* failure handling so a malicious delegatecall cannot leave the allow-hash primed. |
| `2` | `flashloan` | `target.call{value}(data)` where `target` is an Instadapp flash-loan aggregator. The wallet pre-computes `_transientAllowHash = keccak(innerActions, block.timestamp)` from `data_`'s decoded inner `actions` payload, calls the aggregator, which re-enters via `executeOperation` → the wallet decodes + runs the inner actions, then the aggregator returns and the wallet resets the hash. |
| other | — | Reverts `"{i}_FLUID__INVALID_ID_OR_OPERATION"`. |

After the batch, `_resetTransientStorage()` is always called. Emits `ExecutedCast(msg.sender)`.

### `onERC721Received(operator, from, tokenId, data)`

Entry point used by `FluidWalletFactory.onERC721Received` after it forwards the NFT to the freshly-deployed wallet. `data = abi.encode(owner, Action[] actions)`. The wallet:

1. Asserts `msg.sender == VAULT_FACTORY`, `operator == from == FLUID_WALLET_FACTORY`.
2. Validates the wallet is the deterministic clone of `owner`.
3. Runs `actions` through `_executeActions`.
4. Resets allow-hash.
5. Transfers `tokenId` back to `owner` if still held.
6. Sweeps `supplyToken0/1` + `borrowToken0/1` of the vault to `owner` via `_flushTokens` (native-ETH-aware).
7. Emits `Executed(owner, tokenId)` and returns the selector.

### `executeOperation(assets, amounts, premiums, initiator, data)`

Instadapp `InstaFlashReceiverInterface` callback. Guarded strictly by the transient allow-hash + self-initiator invariant (see §10). Returns `true`.

### `initialize(owner_)`

One-shot setter on the proxy. Only settable when `owner == address(0)`. Re-calls revert (empty `revert()`).

### `receive() payable`

Both the wallet proxy and factory accept bare ETH.

## 7. Factory Capabilities (Admin + deployment)

### Public / anyone

| Method | Behaviour |
| --- | --- |
| `computeWallet(address owner) view → address` | Returns `Clones.predictDeterministicAddress(WALLET_PROXY, keccak(owner), factory)`. Pure read, no deploy. |
| `deploy(address owner) → address wallet` | Predicts the address; if `wallet.code.length == 0`, `cloneDeterministic` + `wallet.initialize(owner)`. Idempotent. Not owner-gated — anyone can pre-deploy any user's wallet (safe: owner is fixed by salt). |
| `walletImplementation() → address` | Returns `_implementation`. Called by every `FluidWallet` fallback on every user action — **hot path**. |
| `onERC721Received(operator, from, tokenId, data)` | Vault-T1-Factory-only entry. Deploys the user's wallet (if needed) via `deploy(from_)`, forwards the NFT with `abi.encode(from_, actions)` payload, then asserts `ownerOf(tokenId) == from_` and `balanceOf(factory) == 0` to catch any action that tried to siphon the NFT or any other NFT. Emits `Executed(owner, nftId)`. |
| `initialize(address owner_)` | OZ `initializer`; sets factory owner. Called once by the ERC1967 proxy constructor. |
| `receive() payable` | Accepts ETH (for flash-loan premium staging etc., though not used directly by the factory). |

### Owner-only

| Method | Behaviour |
| --- | --- |
| `changeImplementation(address impl)` | Rotates `_implementation`, upgrading the logic every `FluidWallet` fallback targets. Emits `FluidImplementationUpdate(old, new)`. **Live global upgrade.** |
| `spell(address[] targets, bytes[] calldatas)` | Arbitrary `delegatecall` from the factory's context, unbounded loop. Recovery / migration escape hatch — can touch any factory storage slot, reinitialize, drain ETH, etc. |
| `_authorizeUpgrade(address newImpl)` | UUPS hook; owner-only factory logic upgrade (ERC1967 slot). |
| `renounceOwnership()` | Overridden to **always revert** (`FluidWalletFactory__InvalidOperation`). |

## 8. Events

### Factory (`FluidWalletFactoryErrorsAndEvents`)

| Event | When |
| --- | --- |
| `Executed(address indexed owner, uint256 indexed nft)` | End of `onERC721Received` after successful forward + post-conditions. |
| `FluidImplementationUpdate(address indexed old, address indexed new)` | `changeImplementation`. |

Plus OZ `Initialized`, `OwnershipTransferred`, `Upgraded` from inherited contracts.

### Wallet (`FluidWalletErrorsAndEvents`)

| Event | When |
| --- | --- |
| `Executed(address indexed owner, uint256 indexed tokenId)` | End of wallet-side `onERC721Received`. |
| `ExecutedCast(address indexed owner)` | End of `cast`. |

## 9. Errors

| Contract | Error | When |
| --- | --- | --- |
| Factory | `FluidWalletFactory__NotAllowed` | `onERC721Received` called from a non-VaultT1-Factory sender, `operator != from`, or empty `data`. |
| Factory | `FluidWalletFactory__InvalidOperation` | `renounceOwnership` called, or post-conditions fail (`ownerOf != owner` or `factory.balanceOf > 0`). |
| Wallet | `FluidWallet__NotAllowed` | `onERC721Received` auth mismatch, or `_validateOwner` mismatch. |
| Wallet | `FluidWallet__Unauthorized` | `executeOperation` with wrong allow-hash or initiator ≠ self. |
| Wallet | `FluidWallet__ToHexDigit` | Internal: invalid hex digit (unreachable in practice). |

Action failures revert with a **string** message, not a custom error, so the UI gets human-readable output:

- `"{i}_REASON_NOT_DEFINED"` — target returned < 4 bytes.
- `"{i}_TARGET_PANICKED: 0x{code}"` — target raised `Panic(uint256)`.
- `"{i}_{string}"` — target raised `Error(string)`.
- `"{i}_CUSTOM_ERROR: 0x{selector}"` — target raised a custom error (params stripped).
- `"{i}_FLUID__INVALID_ID_OR_OPERATION"` — `operation` not in `{0,1,2}`.

All reasons are **truncated to `REVERT_REASON_MAX_LENGTH (250)`** so the outer `Executed*` event is guaranteed gas-room to emit on revert paths handled upstream.

## 10. Invariants & Safety Notes

- **One owner, one wallet.** `_validateOwner` recomputes the CREATE2 address from `msg.sender` and checks equality with `address(this)`. An EOA cannot `cast` on a wallet that isn't its own deterministic clone, because the salt is the owner itself. Inversely, nobody other than `owner` can satisfy that check for a given wallet.
- **Vault-NFT entry is asymmetric and self-sealing.** The factory's `onERC721Received` only trusts the Vault T1 Factory, and asserts at the end that the NFT was returned to `from_` and that the factory holds zero NFTs. Any action that tried to re-route the NFT or that triggered additional NFT flows into the factory causes the whole tx to revert.
- **`operator == from` check** forbids the pattern where an operator-approved third party transfers *someone else's* NFT into the wallet system; only the NFT's own owner can initiate the flow.
- **Allow-hash reentrancy guard is minimal but sufficient.** `executeOperation` requires (a) a hash matching the currently-running flashloan op and (b) `initiator == address(this)`. `_resetTransientStorage()` writes `1` into slot 1 to burn the allow-hash after every op, and is called again after `delegatecall` / `call` sub-actions so no sub-action can leave a primed hash. The hash is derived from `keccak(data, block.timestamp)` — same-block replays only work if the same `data` is legitimately executing, which is gated by our own `cast` call.
- **Delegatecall is fully trusted to owner.** `Action.operation == 1` runs in the wallet's storage context, so the owner can overwrite slot 0 (`owner`), slot 1 (allow-hash), or anything else. This is by design — owner is root — but it means the owner must vet `target` of any delegatecall they sign.
- **Factory `spell` is unrestricted delegatecall.** Factory owner can arbitrarily modify factory storage, including `_implementation`, `_owner`, ERC1967 implementation slot, etc. Compromise of factory owner = compromise of every user wallet (see §11).
- **Live implementation rotation.** Because every `FluidWallet.fallback` reads `factory.walletImplementation()` *on every call*, a single `changeImplementation` tx changes the logic every wallet runs the next time it is called. There is no opt-in / per-user pin.
- **`renounceOwnership` is bricked** on the factory — prevents a mis-configured ownerless factory from locking wallet upgrades forever.
- **Initialize races.** `FluidWallet.initialize` is called inline with `cloneDeterministic` inside `deploy`; these are atomic. The `if (owner == 0)` check also hardens against a raw caller attempting to front-run by initializing a yet-to-be-cloned address (the clone is the actual code gate).
- **ETH handling.** Both proxy and factory accept ETH via `receive`. The wallet's `cast` is `payable` and forwards `action.value` per action from `msg.value`. Residual ETH after a flow stays in the wallet unless an action forwards it out; the vault-NFT path's `_sweepTokens` only sweeps the NFT's vault's four tokens, *including* native ETH if one of them is `ETH_ADDRESS` — other ETH is not auto-swept.
- **Flashloan slot re-use.** `_transientAllowHash` lives in real storage (pre-EIP-1153 style), so a reverted flashloan op leaves `_transientAllowHash = 1` (reset sentinel) not zero — harmless but visible on-chain.
- **No explicit reentrancy modifier.** Safety relies on: (a) allow-hash gate in `executeOperation`, (b) resets after every sub-action, (c) owner-validation on every `cast`, and (d) for the NFT path, the VaultT1-Factory-only + self-check sandwich.

## 11. Trust Model

- **Root of trust = factory owner.** Holds UUPS upgrade, `changeImplementation`, and `spell`. Can:
  - Swap wallet implementation for every user simultaneously.
  - Delegatecall from the factory to arbitrary code.
  - Upgrade the factory logic itself.
  - Cannot renounce ownership.
  The factory owner is therefore **fully trusted**: compromise implies full compromise of every user wallet's future state.
- **Each wallet owner is fully trusted *for their own wallet*.** `cast` with `operation=1` (delegatecall) permits arbitrary storage rewrites; `cast` with any operation permits arbitrary external calls. There is **no target allow-list, no value cap, no spend limits, no guardians, no pause, no timelock**. The wallet is a thin automation layer on top of the owner's EOA, not a recovery-hardened smart account.
- **Vault T1 Factory** is trusted as the only admissible `onERC721Received` caller on the factory. No other NFT contract can reach the wallet-deploy path.
- **Instadapp Flash-loan Aggregator** is trusted to behave like a flash-loan aggregator (i.e., call `executeOperation` with the same `data` payload in the same block); wallet safety does not depend on that trust because `executeOperation` requires `initiator == address(this)` — a malicious aggregator that calls back with a different initiator simply fails auth.
- **Vault contracts** are trusted to return sensible `constantsView()` shapes; `_getVaultConstants` has a `try/catch` around `TYPE()` to distinguish multi-token vaults from T1 single-token vaults. Non-contract vault addresses (`code.length == 0`) cause the sweep to no-op rather than revert.
- **Out of scope**: if the factory owner is lost / compromised, there is no on-chain recovery path for users; each wallet remains fully functional under its owner EOA with whatever implementation was last pinned.

## 12. Deployment / Audit Notes

### Deployment order

1. Deploy `FluidWalletFactory` logic with args `(vaultT1Factory, precomputedFactoryProxyAddress)`. Note: the logic constructor deploys the `WALLET_PROXY` singleton (`new FluidWallet(fluidWalletFactoryProxy_)`). Because `FluidWallet`'s `FACTORY` is an **immutable baked into the singleton code**, the factory-proxy address must be known before the logic is deployed — typically via CREATE2 prediction, or by deploying the logic at the constructor-computable address for `FluidWalletFactoryProxy`.
2. Deploy `FluidWalletFactoryProxy(logic, abi.encodeCall(initialize, (owner_)))`. ERC1967Proxy runs `initialize(owner_)` in the same tx.
3. Deploy a `FluidWalletImplementation(vaultFactory_, fluidWalletFactoryProxy_)`.
4. `factory.changeImplementation(walletImpl)` from factory owner.
5. Users are ready: they can call `factory.deploy(owner)` (or trigger the NFT flow) to mint their clone. The clone will delegatecall the newest implementation automatically.

### Upgrade paths

- **Wallet logic**: deploy new `FluidWalletImplementation`, call `factory.changeImplementation(new)`. Every existing wallet picks up the new logic on its next call. **No per-user migration required**, but also **no per-user opt-out**.
- **Factory logic**: standard UUPS — deploy new factory logic, call `upgradeTo` from factory owner (`_authorizeUpgrade` gate).

### Audit focus points

- **Storage alignment** between `FluidWallet` proxy and `FluidWalletImplementation`. Both declare `address public owner` at slot 0 and `bytes32 _transientAllowHash` at slot 1. Any new implementation must preserve this prefix; an accidental reorder would corrupt every existing wallet's owner.
- **Clone target code immutability.** Minimal clones (`EIP-1167`) delegatecall a fixed target (`WALLET_PROXY`). That target's code is immutable post-deploy; all logic mutability goes through `factory.walletImplementation()` instead. Auditors should verify `WALLET_PROXY` has no admin surface beyond `initialize` + `fallback`.
- **`spell` blast radius.** Factory owner's `spell` can delegatecall any target; combined with UUPS `upgradeTo`, any argument for restricting factory-owner power has to treat it as root authority.
- **NFT sandwich post-conditions.** `ownerOf(tokenId) == params_.owner` and `balanceOf(address(this)) == 0` are the only on-chain guarantees that actions did not redirect or accumulate NFTs through the factory; ensure no code path lets actions skip or fake these checks.
- **String reverts.** Action-failure reasons are constructed via string concatenation (`Strings.toString(i)` + hex digits). Length is capped at 250 bytes to keep room for the outer event, but callers parsing revert reasons should not rely on fixed layouts.
- **Flashloan guard is storage-slot-based** (slot 1), not EIP-1153 transient storage, despite the name `_transientAllowHash`. Reset writes `1` not `0` — watch for any future code path that compares against `bytes32(0)` instead of re-deriving `keccak(data, block.timestamp)`.
- **No reentrancy guard** on `cast` / `executeOperation` beyond the allow-hash. Any future additions (e.g., new `operation` types) must preserve the "reset allow-hash on every sub-action boundary" discipline.
- **`renounceOwnership` override** on the factory is intentional; do not restore default OZ behaviour.
