# Libraries — SPEC

## 0. Gas-optimisation tier

**Hot path (for the functions used by Liquidity / DEX / DexLite hot paths).** `bigMathMinified`, `bigMathVault`, `liquidityCalcs`, `dexCalcs`, `tickMath` are called on every user-protocol tx. Every added branch in these files pays per-tx gas across the whole protocol surface. Keep pure, branch-minimal, single-precision where possible; do **not** refactor for readability at the cost of gas.

Small utility libraries (`addressCalcs`, `safeTransfer`, etc.) follow the same rule when their caller is on a hot path; a library used only by admin setters can take the **cold-path** treatment (extra `require`s welcome).

Security always wins: if a math bound closes a reachable overflow or precision-loss story, add it even if it costs a few units of gas.

## 1. Purpose

Shared pure/internal libraries used by every Fluid protocol. They exist to:

- Keep the protocols' on-chain bytecode below the 24 576 byte contract limit (libraries link as internal delegatecalls to their own deployed instance, or inline as Solidity `internal` functions).
- Centralize math / storage conventions so all protocols read / write packed slots the same way.
- Provide safe primitives (transfer, approve, reentrancy, etc.) that don't pull in OpenZeppelin or Solmate transitively.

This `SPEC.md` is the **index** — it lists every file in `contracts/libraries/` and links to the detailed sub-specs for the four heavy libraries. Small utility libraries are documented in-line here.

## 2. Index

### Heavy libraries (dedicated specs)

| File | LOC | Spec |
| --- | ---:| --- |
| `bigMathMinified.sol`, `bigMathVault.sol` | 215 + 205 | [SPEC-bigMath.md](./SPEC-bigMath.md) |
| `liquidityCalcs.sol` | 684 | [SPEC-liquidityCalcs.md](./SPEC-liquidityCalcs.md) |
| `dexCalcs.sol` | 254 | [SPEC-dexCalcs.md](./SPEC-dexCalcs.md) |
| `tickMath.sol` | 270 | [SPEC-tickMath.md](./SPEC-tickMath.md) |

### Skipped / out of scope

- `bigMathUnsafe.sol` — not used in production vault / DEX paths; deliberately unspec'd here.

### Small utility libraries (documented below)

| File | LOC | Purpose |
| --- | ---:| --- |
| `addressCalcs.sol` | 34 | Deterministic CREATE-address derivation (manual RLP). |
| `access/` | — | Access-control bases: Liquidity governance, auth allowlist, UUPS, team multisig (see §4). |
| `bytesSliceAndConcat.sol` | 144 | Memory-safe `bytes` slice + concat. |
| `dexLiteSlotsLink.sol` | 72 | DexLite storage slot / bit constants. |
| `dexSlotsLink.sol` | 67 | DEX (poolT1) storage slot / bit constants. |
| `errorTypes.sol` | 34 | Library-level error code table (`LibsErrorTypes`). |
| `fluidProtocolTypes.sol` | 52 | Protocol `TYPE()` constants + filter helper. |
| `liquiditySlotsLink.sol` | 110 | Liquidity storage slot / bit constants. |
| `reentrancyLock.sol` | 18 | Transient-storage reentrancy lock. |
| `safeApprove.sol` | 46 | Minimal safe approve. |
| `safeTransfer.sol` | 99 | Minimal safe `transfer` / `transferFrom` / native. |
| `storageRead.sol` | 11 | Base contract exposing `readFromStorage(slot)`. |
| `StringBytes32Utils.sol` | — | `string` ↔ `bytes32` helpers. |
| `utils/deviationHelpers.sol` | ~30 | Pure `isOutsideDeviation` percent-band check (bool). |

## 3. External Interactions

Most libraries in this folder are **pure or view**. They make no external calls (except `safeTransfer` / `safeApprove`, which make the ERC-20 / native token call being wrapped, and `storageRead.readFromStorage` which performs an `sload` on its own contract storage).

Exceptions: `LiquidityGovernanceAuth._governance()` (and anything using `onlyGovernance` / `BasicAuth.onlyAuth` / `BasicUpgradeable` upgrades / `TeamMultisigAuth.onlyTeamMultisig`) performs a view call to the **constructor-bound** Liquidity `readFromStorage` (team check is local to `TEAM_MULTISIG`; `onlyTeamMultisig` also allows governance).

## 4. Utility library details

### `addressCalcs.sol` — `library AddressCalcs`

`addressCalc(address deployedFrom, uint nonce) pure returns (address)` — manual RLP encoding of `(deployedFrom, nonce)` then `keccak256`, then truncated to an address. Implements the same five branches as vault / DEX factory's `getVaultAddress` / `getDexAddress` so off-chain and on-chain code produce identical addresses for `CREATE`-deployed contracts.

- Edge: `nonce == 0` → returns `address(0)` (contracts never deploy at nonce 0).
- Supports nonces up to `uint32.max`.

Used by: oracle-address resolution in vaults (from `oracleNonce`), the `MiniDeployer` nonce scheme, `VaultFactoryOwner._isPositionAboveRatioThreshold`.

### `bytesSliceAndConcat.sol` — `library BytesSliceAndConcat`

`bytesConcat(bytes memory pre, bytes memory post)` and `bytesSlice(bytes memory b, uint start, uint length)` — minimal assembly implementations copied from `solidity-bytes-utils` with custom memory layout. Used by deployment-logic contracts (e.g. `FluidVaultT1DeploymentLogic._bytesSlice`) to split SSTORE2'd creation code into two halves under the 24 576 byte SSTORE2 limit.

### `dexLiteSlotsLink.sol` — `library DexLiteSlotsLink`

Storage-slot and bit-offset constants for `FluidDexLite`:

- Slots: `DEX_LITE_IS_AUTH_SLOT = 0`, `DEX_LITE_DEXES_LIST_SLOT = 1`, `DEX_LITE_DEX_VARIABLES_SLOT = 2`, `DEX_LITE_CENTER_PRICE_SHIFT_SLOT = 3`, `DEX_LITE_RANGE_SHIFT_SLOT = 4`, `DEX_LITE_THRESHOLD_SHIFT_SLOT = 5`.
- Bit constants for the `DEX_LITE_DEX_VARIABLES` packed word (fee, revenue cut, rebalancing status, center-price, upper/lower percentages, etc.).

Used by: off-chain resolvers, admin modules, and integrators that `readFromStorage` directly for gas.

### `dexSlotsLink.sol` — `library DexSlotsLink`

Storage-slot and bit-offset constants for `FluidDexT1`:

- Slots: `DEX_VARIABLES_SLOT = 0`, `DEX_VARIABLES2_SLOT = 1`, `DEX_TOTAL_SUPPLY_SHARES_SLOT = 2`, `DEX_USER_SUPPLY_MAPPING_SLOT = 3`, `DEX_TOTAL_BORROW_SHARES_SLOT = 4`, `DEX_USER_BORROW_MAPPING_SLOT = 5`, `DEX_RANGE_THRESHOLD_SHIFTS_SLOT = 7`, `DEX_CENTER_PRICE_SHIFT_SLOT = 8`.
- Deprecated: `DEX_DEPRECATED_PREVIOUSLY_ORACLE_MAPPING_SLOT = 6` — unused in current deployments; listed so integrators don't mistakenly reuse the slot.
- Bit constants for `dexVariables`, `dexVariables2`, user supply / borrow packed words.

### `errorTypes.sol` — `library LibsErrorTypes`

Error-code table used by the libraries themselves:

- `70001 LiquidityCalcs__ExchangePriceZero`
- `70002 LiquidityCalcs__UnsupportedRateVersion`
- `70003 LiquidityCalcs__BorrowRateNegative`
- `71001 SafeTransfer__TransferFromFailed`
- `71002 SafeTransfer__TransferFailed`
- `81001 SafeApprove__ApproveFailed`

### `fluidProtocolTypes.sol`

- Constants: `VAULT_T1_TYPE = 10000`, `VAULT_T2_SMART_COL_TYPE = 20000`, `VAULT_T3_SMART_DEBT_TYPE = 30000`, `VAULT_T4_SMART_COL_SMART_DEBT_TYPE = 40000`.
- `filterBy(address[] memory addresses_, uint256 type_)` — probes each address's `TYPE()` (try/catch fallback to `VAULT_T1_TYPE` if unavailable) and filters. Used by resolvers to separate T1 vaults from DEX-backed types.

### `liquiditySlotsLink.sol` — `library LiquiditySlotsLink`

Authoritative slot / bit map for Fluid Liquidity storage:

- Slots: `status (1)`, `auths (2)`, `guardians (3)`, `userClass (4)`, `exchangePricesAndConfig (5)`, `rateData (6)`, `totalAmounts (7)`, `userSupply (8, double)`, `userBorrow (9, double)`, `listedTokens (10)`, `configs2 (11)`.
- Bit offsets per word (rate V1 / V2, exchange prices, user supply / borrow, configs2).
- Helpers: `calculateMappingStorageSlot(slot, key)` → `keccak256(abi.encode(key, slot))`; `calculateDoubleMappingStorageSlot(slot, k1, k2)` nested.

Used pervasively to skip Liquidity delegate-calls and do direct `sload`s.

### `reentrancyLock.sol` — `library ReentrancyLock` (transient storage)

- Slot: `REENTRANCY_LOCK_SLOT = bytes32(uint256(keccak256("FLUID_REENTRANCY_LOCK")) - 1)` = `0xb9cde7…8a2df7`.
- `lock()` — reverts if `tload(slot) != 0`, else `tstore(slot, 1)`.
- `unlock()` — `tstore(slot, 0)`.
- Requires Solidity 0.8.29 / `tstore` / `tload` (Cancun). Used by DexLite and newer protocols; older protocols still use storage-bit reentrancy.

### `safeApprove.sol` — `library SafeApprove`

- `safeApprove(token, spender, amount)` — emits `approve(spender, amount)` via low-level call, treats empty return as success (USDT-compatible), reverts `FluidSafeApproveError(81001)` otherwise.

### `safeTransfer.sol` — `library SafeTransfer`

- `MAX_NATIVE_TRANSFER_GAS = 50_000` — deliberately small stipend. Large enough for `WETH.receive()` (~10k), small enough to prevent griefing.
- `safeTransferFrom(token, from, to, amount)` — reverts `FluidSafeTransferError(71001)` on failure.
- `safeTransfer(token, to, amount)` — reverts `FluidSafeTransferError(71002)`.
- `safeTransferNative(to, amount)` — low-level `call` with 50 k gas; reverts `71002`.

### `storageRead.sol` — `contract StorageRead`

Single public function `readFromStorage(bytes32 slot) view returns (uint256)` performing one `sload`. Inherited by most of Fluid's public contracts (Liquidity, Vaults, DEX, DexLite, Factories) so anyone can read any storage slot without an explicit getter. This is the reason `liquiditySlotsLink` / `dexSlotsLink` / `dexLiteSlotsLink` exist: resolvers and integrators read raw packed slots through `readFromStorage`.

### `utils/deviationHelpers.sol` — `library DeviationHelpers`

`isOutsideDeviation(base, value, maxDeviationPercent, precision)` — true if `|value − base|` is strictly greater than the band (`precision` = 100% scale). Exact ±band in-band. `base * maxDeviationPercent` is checked (overflow reverts).

### `access/` — access-control bases

Shared bases for **new** contracts. Existing live protocols (CappedRate, DexLite, etc.) keep local copies and are not required to migrate.

#### `liquidityGovernanceAuth.sol` — `abstract contract LiquidityGovernanceAuth`

| Item | Visibility | Notes |
| --- | --- | --- |
| `LIQUIDITY` | `public immutable` | Set in constructor — prod / permissioned / test Liquidity; rejects `address(0)` |
| `_LIQUIDITY_GOVERNANCE_SLOT` | `internal constant` | EIP-1967 admin slot on Liquidity |
| `_governance()` | `internal view` | `address(uint160(LIQUIDITY.readFromStorage(slot)))` |
| `_isGovernance()` | `internal view` | `msg.sender == _governance()` |
| `onlyGovernance` | modifier | `!_isGovernance()` → `Access__Unauthorized` |

Makes one external view call to the bound Liquidity (`readFromStorage`). Owns the `LIQUIDITY` immutable only (no other storage).

#### `basicAuth.sol` — `abstract contract BasicAuth`

Extends `LiquidityGovernanceAuth` with a class-based auth allowlist API. **Does not own storage** — the inheriting contract overrides `_authClass` / `_setAuthClass` (typically a `mapping(address => uint256)` with `0` = none; do not name that mapping `_authClass` or it clashes with the virtual getter).

| Surface | Behaviour |
| --- | --- |
| `isAuth(address)` | Public view → `_authClass(auth_) != 0` |
| `authClass(address)` | Public view → `_authClass(auth_)` |
| `updateAuth(address, uint256)` | `onlyGovernance`; rejects `address(0)` with `Access__Unauthorized`; calls `_setAuthClass` then emits `LogUpdateAuth` |
| `onlyAuth` | Governance **or** any non-zero class; else `Access__Unauthorized` |
| `onlyAuthClassAbove(uint256 class_)` | Governance **or** class `≥ class_`; else `Access__Unauthorized` |
| `onlyAuthClass(uint256 class_)` | Governance **or** exact class `class_`; else `Access__Unauthorized` |
| `_authClass(address)` | `internal view virtual` — child reads storage |
| `_setAuthClass(address, uint256)` | `internal virtual` — child writes storage |

Example child wiring:

```solidity
mapping(address => uint256) internal _auths;

function _authClass(address auth_) internal view override returns (uint256) {
    return _auths[auth_];
}

function _setAuthClass(address auth_, uint256 authClass_) internal override {
    _auths[auth_] = authClass_;
}
```

Governance alone → inherit `LiquidityGovernanceAuth`. Auth allowlist / classes → inherit `BasicAuth` and implement the two hooks. Team multisig actions → inherit `TeamMultisigAuth`. UUPS proxy → inherit `BasicUpgradeable` **in place of** `Initializable` on the variables base (so Initializable stays slot 0).

#### `basicUpgradeable.sol` — `abstract contract BasicUpgradeable`

UUPS base on `LiquidityGovernanceAuth` + OZ `Initializable` / `UUPSUpgradeable`.

| Surface | Behaviour |
| --- | --- |
| `constructor(address liquidity_)` | Forwards to `LiquidityGovernanceAuth`; `_disableInitializers()` on the implementation |
| `initialize()` | `public virtual initializer` — empty by default; override to set proxy state |
| `_authorizeUpgrade(address)` | `internal virtual override onlyGovernance` |

Owns no extra storage beyond OZ `Initializable` (+ inherited `LIQUIDITY` immutable).

#### `teamMultisigAuth.sol` — `abstract contract TeamMultisigAuth`

Extends `LiquidityGovernanceAuth` with the hard-coded Fluid team Avocado multisig gate (plus governance).

| Surface | Behaviour |
| --- | --- |
| `TEAM_MULTISIG` | `public constant` `0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e` |
| `_isTeamMultisig()` | `internal view` | `msg.sender == TEAM_MULTISIG` |
| `onlyTeamMultisig` | `!_isTeamMultisig() && !_isGovernance()` → `Access__Unauthorized` |

Inheritors get both `onlyGovernance` and `onlyTeamMultisig`. Child constructors must call `LiquidityGovernanceAuth(liquidity_)`.

## 5. Roles & Access Control

Pure/view libraries are stateless and impose no access checks; their callers are responsible for invoking them in appropriate contexts.

`LiquidityGovernanceAuth` / `BasicAuth` / `BasicUpgradeable` / `TeamMultisigAuth` **are** access-control bases:

- **Liquidity governance** (`_governance()` via constructor-bound `LIQUIDITY`) — sole caller of `onlyGovernance` surfaces (e.g. `BasicAuth.updateAuth`, UUPS upgrades via `BasicUpgradeable`).
- **Auth allowlist** (child storage via `_authClass` / `_setAuthClass`) — together with governance, may call `onlyAuth` / `onlyAuthClassAbove(class)` / `onlyAuthClass(class)` surfaces on inheriting contracts.
- **Team multisig or governance** (`TEAM_MULTISIG` / `_governance()`) — `onlyTeamMultisig` surfaces; same unauthorized error.
- Existing live protocols are **not** required to adopt these abstracts.

## 6. Storage Layout

Pure libraries don't own storage. `StorageRead` is a base contract with no storage of its own. `ReentrancyLock` uses transient storage at a deterministic slot.

`LiquidityGovernanceAuth` / `BasicAuth` / `TeamMultisigAuth` own the `LIQUIDITY` immutable (and auth classes live in the inheriting contract via `_authClass` / `_setAuthClass`). `BasicUpgradeable` only adds OZ `Initializable` storage.
## 7. Errors

- `FluidSafeTransferError(71001)` — transferFrom failed.
- `FluidSafeTransferError(71002)` — transfer / native transfer failed.
- `FluidSafeApproveError(81001)` — approve failed.
- `Access__Unauthorized` — not governance (`onlyGovernance`), not governance/auth (`onlyAuth`), not team multisig or governance (`onlyTeamMultisig`), zero `LIQUIDITY` in constructor, or `updateAuth(address(0), …)`.
- Heavy-library errors documented in the per-library specs.

## 8. Invariants & Safety Notes

- **`SafeTransfer.safeTransferNative`** caps the stipend at 50 k gas. Recipients that need more gas (e.g. complex fallback logic) will revert by design; integrators should unwrap to WETH or use a proxy.
- **`AddressCalcs.addressCalc`** must be called with the real `CREATE` nonce, not `CREATE2` salt.
- **`ReentrancyLock`** requires Cancun (0.8.29 + `tstore`). Protocols that target older EVM versions must use `uint256` storage bits instead.
- **`LiquiditySlotsLink` / `DexSlotsLink` / `DexLiteSlotsLink`** bit layouts are consensus — changing a single offset silently corrupts every reader. Treat as freeze after deployment.
- **Error codes** are globally unique across `contracts/` per convention: libraries use 7xxxx / 8xxxx; Liquidity uses 1xxxx–3xxxx; DEX uses 5xxxx–6xxxx; Vault uses 3xxxx. See individual protocol specs for the precise ranges.

See the per-library specs linked above for detailed invariants on heavy libraries.
