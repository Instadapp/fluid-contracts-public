# Config / authGate — SPEC

## 1. Purpose

Central, upgradeable identity registry for privileged Fluid actors. Consumers ask the gate "what is this
address's security level?" / "does it clear level X?" instead of hardcoding multisig addresses locally.
Rotating a multisig or adjusting a level then means **one upgrade of this contract** instead of
redeploying every consumer (today ~15 auth contracts hardcode `TEAM_MULTISIG`, a subset also
`TEAM_MULTISIG2`).

| Contract | File | Role |
| --- | --- | --- |
| `FluidAuthGate` | `main.sol` | UUPS implementation. Identity + level checks. |
| `FluidAuthGateProxy` | `proxy.sol` | Thin ERC1967 proxy in front of it. |
| `IFluidAuthGate` + `FluidAuthLevels` | `interfaces/iAuthGate.sol` | Consumer import: interface plus the abstract `FluidAuthLevels` carrying the `SECURITY_LEVEL_*` constants. |
| `IFluidAuthGateLiquidity` | `interfaces/iAuthGate.sol` | The gate's `LIQUIDITY()` getter, kept apart because the gate inherits `LIQUIDITY` as a public immutable. Consumers read it in their constructor. |

Consumer usage:

```solidity
import { IFluidAuthGate, FluidAuthLevels } from ".../authGate/interfaces/iAuthGate.sol";

contract MyAuth is FluidAuthLevels {
    ...
    AUTH_GATE.requireAuthLevel(msg.sender, SECURITY_LEVEL_MID);
    // or the fixed-level helpers:
    AUTH_GATE.requireAuthLevelMid(msg.sender);
}
```

## 2. External Interactions

- Reads the **EIP-1967 admin slot** of the constructor-bound Liquidity proxy via `readFromStorage`
  (through `LiquidityGovernanceAuth` from `contracts/libraries/access/`) — that admin is governance.
- Nothing else: no calls out, no tokens, no ETH.

## 3. Roles & Access Control

- **Governance** (LL EIP-1967 admin) is the only privileged actor: it alone can upgrade
  (`_authorizeUpgrade` is `onlyGovernance` via `BasicUpgradeable`), and only to an implementation bound to the
  same `LIQUIDITY`. There is no other admin surface — no setters, no pause, no owner.
- All query methods are permissionless views.

## 4. Storage Layout

No own storage. Inherited: slot 0 = OZ `Initializable` (`uint8 _initialized; bool _initializing;`).
`LIQUIDITY`, `TEAM_MULTISIG`, `TEAM_MULTISIG2`, `TEAM_MULTISIG_TIMELOCK` are **immutables on the
implementation** — the upgrade path is the only mutation mechanism, by design. Security levels are
constants.

## 5. Security Levels

Named `uint256` internal constants on the abstract `FluidAuthLevels` (`interfaces/iAuthGate.sol`; no
getters on the gate — consumers inherit it) with spaced values; checks use `>=`, so future levels can
slot in without renumbering consumers:

| Constant | Value | Assigned to |
| --- | --- | --- |
| `SECURITY_LEVEL_LOW` | 1 | — (reserved) |
| `SECURITY_LEVEL_MID` | 5 | `TEAM_MULTISIG2` (constructor-set; prod `0x1e2e…4219`) |
| `SECURITY_LEVEL_HIGH` | 10 | `TEAM_MULTISIG` (constructor-set; prod `0x4F6F…D49e`) |
| `SECURITY_LEVEL_CRITICAL` | 15 | `TEAM_MULTISIG_TIMELOCK` (constructor-set — team multisig acting through its timelock; mainnet `0x4d6CE4…2346`). Reserved: no consumer requires it — see §8.2 |
| `SECURITY_LEVEL_MAX` | 20 | Governance (dynamic — LL's EIP-1967 admin) |

One ladder: `MAX` is governance-only; `CRITICAL` = team timelock and above; `HIGH` = main team MS and
above; `MID` = team MS2 and above.

## 6. Methods

| Method | Returns | Behaviour |
| --- | --- | --- |
| `governance()` | `address` | Current LL governance (EIP-1967 admin of `LIQUIDITY`). |
| `isGovernance(address)` | `bool` | `addr == governance()`. |
| `authLevel(address)` | `uint256` | The address's ladder level: `MAX` for governance, `CRITICAL` for the team timelock, `HIGH`/`MID` for the multisigs, `0` for unknown addresses. |
| `requireAuthLevel(address, uint256 minSecurityLevel)` | — | Reverts `Access__Unauthorized` unless `authLevel(address)` is non-zero and `>= minSecurityLevel`. One-call gate for consumer modifiers; `SECURITY_LEVEL_MAX` requests are governance-only. |
| `requireAuthLevelLow/Mid/High/Critical/Max(address)` | — | `requireAuthLevel` fixed at the respective level. |
| `initialize()` | — | Empty proxy initializer (from `BasicUpgradeable`); call once at proxy deployment. |
| `upgradeTo` / `upgradeToAndCall` | — | OZ UUPS, gated `onlyGovernance`; reverts `AuthGate__ImplementationLiquidityMismatch` if the new implementation's `LIQUIDITY()` differs. |

## 7. Events & Errors

No own events. Errors:
- `FluidBasicValidationsError(BasicValidations__AddressZero)` (shared `BasicValidations`) — a zero team
  identity at construction.
- `Access__Unauthorized` from `LiquidityGovernanceAuth` — zero liquidity, two equal team identities,
  `requireAuthLevel` failure, non-governance upgrade attempt.
- `AuthGate__ImplementationLiquidityMismatch` (own custom error) — upgrade to an implementation bound to another
  Liquidity.

No config error IDs.

## 8. Deployment Checklist

1. Deploy `FluidAuthGate(liquidity, teamMultisig, teamMultisig2, teamMultisigTimelock)` implementation
   (reverts `BasicValidations__AddressZero` on a zero team identity, `Access__Unauthorized` on two equal
   team identities). One team identity MAY equal
   governance — realistic on L2s — since `authLevel` resolves governance first to `MAX`; two cannot, as they would
   equal each other.
2. Deploy `FluidAuthGateProxy(implementation, abi.encodeCall(FluidAuthGate.initialize, ()))`.
3. Consumers bind the **proxy** address (immutable or constant). Their constructors read the gate's `LIQUIDITY()`:
   `FluidPauseAuth`, the three pause executors and `FluidRatesAuth` revert unless it is their own Liquidity;
   `FluidLimitsAuthDex` and `FluidRangeAuthDex`, which take no Liquidity, revert on a zero one.
4. Rotation / level change: deploy a new implementation with the new constructor args and the same `liquidity`,
   governance calls `upgradeTo` on the existing proxy. Re-running `deployAuthGate` does not do this: it deploys a
   second proxy, which the deployed consumers never read.

### 8.1 Per-chain identities

`governance` is read live from the Liquidity EIP-1967 admin slot and is never passed to the constructor.

| Chain | governance → MAX | `teamMultisigTimelock` → CRITICAL | `teamMultisig` → HIGH | `teamMultisig2` → MID |
| --- | --- | --- | --- | --- |
| mainnet | `0x2386DC45…1F4c` InstaTimelock (behind the INST Governor Bravo) | `0x4d6CE4F4…2346` (proposer = MS1) | `0x4F6F977a…D49e` MS1 | `0x1e2e1aeD…4219` MS2 |
| arbitrum, base, polygon, plasma | `0x4d6CE4F4…2346` — the MS1 TimelockController **is** governance | pass governance `0x4d6CE4F4…2346` | `0x4F6F977a…D49e` MS1 | `0x1e2e1aeD…4219` MS2 |
| bnb | `0x1c0FC15e…5cc0` FLUX MS, no timelock in the path | open decision — see below | open decision — see below | `0x1e2e1aeD…4219` MS2 |

Mainnet is the only chain where all four rungs are distinct principals. On the four L2s CRITICAL and MAX
are the same address and `authLevel` resolves governance first, so CRITICAL is never returned there. That
holds only while governance stays `0x4d6CE4F4…2346`: a Liquidity governance rotation on an L2 leaves that address
at CRITICAL (≥ HIGH), so it must ship with a gate upgrade.

DEX global auths are registered by the DexFactory owner, itself a global auth: governance on mainnet, MS1 directly
on the four L2s (so DEX-side registrations there are MS1 transactions outside the timelock) and the FLUX MS on bnb.

> **Do not invent a placeholder for `teamMultisigTimelock`.** Whatever is passed silently holds CRITICAL,
> and because checks are `>=` that clears every lower rung — including the `pauseAuth` `notPausable`
> bypass and the unpause tier. On a chain with no distinct team timelock, pass governance itself.

bnb is unresolved: governance is the FLUX MS with no timelock above it, and the bnb TimelockController
`0x470cB0Db…997c` has FLUX MS — not MS1 — as its proposer. MS1 is a Liquidity guardian there, and its
timelock `0x4d6CE4F4…2346` exists on bnb but is not governance. Decide the bnb mapping before deploying there
rather than reusing the L2 row.

### 8.2 CRITICAL is reserved and unwired

No consumer requires CRITICAL today — every check is MID or HIGH (`pauseAuth`, `limitsAuthDex`,
`ratesAuth`, `rangeAuthDex`). The rung exists so a future consumer can demand the team timelock; it is
not a live tier, and on the L2 rows above it is unreachable by construction.

## 9. Invariants & Safety Notes

- **The gate is a read oracle, not an authority.** It answers identity questions (`requireAuthLevel`
  merely reverts instead of returning false); enforcement stays in the consumer. A compromised gate can
  at most misclassify identities for consumers that trust it — which is exactly the governance-upgrade
  trust already inherent in the LL proxy itself.
- **Upgrade = governance action on LL's admin.** Same root of trust as every LL module upgrade; no new
  trust assumption is introduced.
- **`minSecurityLevel == 0` never admits strangers** — `requireAuthLevel` requires a non-zero
  `authLevel` first.
- Adoption is incremental: existing deployed auth contracts keep their hardcoded constants until next
  touched; new contracts consume the gate. Current consumers: `pauseAuth` (main contract uses HIGH for admin
  and unpause, MID for the user-pause pass-throughs; all three executors use MID for the one-shot
  `setPauseAuthContract` and HIGH is never required there), `limitsAuthDex`, `ratesAuth`, `rangeAuthDex`
  (MID tier).
- Input validation reuses the shared `BasicValidations` abstract from `contracts/libraries/utils/`.

## 10. Trust Model & Audit Notes

- Root of trust: LL governance (timelock). Governance can repoint identities via upgrade — intended.
- Only a gate upgrade removes an identity's tier: `pauseAuth` takes the max of its local level and the
  gate-implied one, and the other consumers ask the gate alone, so HIGH cannot demote MID.
- The implementation's constructor disables initializers (`BasicUpgradeable`), so the bare
  implementation cannot be initialized or used as a proxy target by third parties in any harmful way
  (it holds no state and grants nothing).
