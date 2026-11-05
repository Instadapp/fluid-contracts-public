# Resolvers / stakingMerkle — SPEC

## 1. Purpose

Read-only helper purpose-built for Merkle-drop snapshot scripts that need a **single combined fUSDC / fUSDT share balance per user** (normal fToken balance + staked fToken balance). A merkle-based reward distribution needs to treat an fToken that is sitting in a user's wallet and the same fToken staked inside `FluidLendingStakingRewards` as equivalent — both represent the same underlying lending exposure and must accrue rewards equally. This resolver does that accounting in one call for batches of users, per market.

Unlike the richer `stakingRewards/` resolver (which surfaces reward rates, periods, earned amounts, etc. for UI integration), `stakingMerkle/` is intentionally stripped to the minimum: one 4-field struct, three view methods, hard-coded per-chain addresses for the fUSDC and fUSDT markets. Offline snapshot scripts feed a list of addresses, get back `{ user, shares, normalShares, stakeShares }`, and build the merkle tree from `shares`.

Two implementations ship, one per supported chain (addresses are `constant`, not `immutable`):

| Contract | File | Chain |
| --- | --- | --- |
| `FluidStakingMerkleResolver` | `main.sol` | Ethereum mainnet |
| `FluidStakingMerkleResolver` | `mainArb.sol` | Arbitrum |

Both contracts share the identical ABI and logic; only the four hard-coded addresses differ.

## 2. External Interactions

- Calls `IFToken.balanceOf(user)` on `FUSDC` / `FUSDT` (fToken ERC-20 shares).
- Calls `IFluidLendingStakingRewards.balanceOf(user)` on the matching staking contract to read the user's staked fToken shares.
- No writes, no transfers, no delegate-calls, no re-hypothecation logic — both the fToken and the staking contract already return the staker's share claim directly.

Dependency graph: `FluidStakingMerkleResolver` → `IFToken` + `IFluidLendingStakingRewards`. It does **not** inherit `ResolverHelpers` from `common/` because neither dereferences Liquidity balances directly (the fToken's internal share accounting already handles the Liquidity side).

## 3. Roles & Access Control

- No owner, no admin, no governance, no pausable. Every method is externally callable by anyone.
- No constructor — there are no parameters to validate; all four target addresses are `constant`.
- Replaceable by redeploy: if an fToken or staking contract is rotated (e.g. a new fUSDC deployment), a new resolver must be deployed with updated constants. No setter exists and none is needed (see `../SPEC.md` §7 — immutability is deliberate).

## 4. Storage Layout

No mutable storage slots. Every target address is a compile-time `constant`:

### `main.sol` (mainnet)

| Constant | Value |
| --- | --- |
| `FUSDC` | `0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33` |
| `FUSDT` | `0x5C20B550819128074FD538Edf79791733ccEdd18` |
| `FUSDC_STAKING` | `0x2fA6c95B69c10f9F52b8990b6C03171F13C46225` |
| `FUSDT_STAKING` | `0x490681095ed277B45377d28cA15Ac41d64583048` |

### `mainArb.sol` (Arbitrum)

| Constant | Value |
| --- | --- |
| `FUSDC` | `0x1A996cb54bb95462040408C06122D45D6Cdb6096` |
| `FUSDT` | `0x4A03F37e7d3fC243e3f99341d36f4b829BEe5E03` |
| `FUSDC_STAKING` | `0x48f89d731C5e3b5BeE8235162FC2C639Ba62DB7d` |
| `FUSDT_STAKING` | `0x65241f6cacde58c03400Cb84542a2c197d6dE9C3` |

Because they are `constant`, they occupy zero storage and are inlined at every callsite.

## 5. Returned Struct

```solidity
struct UserPosition {
    address user;          // echoed from input, so results survive array reordering
    uint256 shares;        // normalShares + stakeShares (the number merkle scripts consume)
    uint256 normalShares;  // fToken.balanceOf(user)
    uint256 stakeShares;   // stakingContract.balanceOf(user)
}
```

`shares` is the sum and is the canonical field for merkle snapshots. `normalShares` / `stakeShares` are exposed for auditability so consumers can reconcile the split against the underlying contracts without a second RPC round-trip.

Units: raw fToken share units (i.e. `fToken.decimals()` ~ same precision as the underlying asset for `fUSDC` / `fUSDT`). No exchange-rate conversion to the underlying USDC / USDT happens here — snapshot scripts either (a) use shares directly (stable per-fToken scaling within a block) or (b) multiply by `fToken.convertToAssets(1e6)` off-chain if they want underlying amounts.

## 6. View Functions

All three methods are `view`; batching large user arrays is the normal usage pattern. Gas scales linearly at `~2 × SLOAD per user` (one `balanceOf` on the fToken, one on the staking contract).

| Method | Purpose |
| --- | --- |
| `getUsersPosition(users, fToken, stakingContract)` | Generic form. Accepts any fToken + staking-contract pair, so a caller can probe future markets without a redeploy as long as the pair follows the `IFToken` + `IFluidLendingStakingRewards` ABI. |
| `getUsersPositionFUSDC(users)` | Convenience wrapper — binds `fToken = FUSDC`, `stakingContract = FUSDC_STAKING`. |
| `getUsersPositionFUSDT(users)` | Convenience wrapper — binds `fToken = FUSDT`, `stakingContract = FUSDT_STAKING`. |

Per-entry logic (identical in all three):

```solidity
positions_[i].user         = users_[i];
positions_[i].normalShares = fToken_.balanceOf(users_[i]);
positions_[i].stakeShares  = stakingContract_.balanceOf(users_[i]);
positions_[i].shares       = normalShares + stakeShares;
```

Output array length always matches `users_.length` and preserves input ordering one-to-one.

## 7. Events

None. Resolvers are pure readers (see `../SPEC.md` §7).

## 8. Errors

None declared by this contract. There is no input validation:

- Empty `users_` array → returns an empty `UserPosition[]`.
- `address(0)` inside `users_` → returns `{ user: 0, shares: 0, normalShares: 0, stakeShares: 0 }`; the fToken / staking contract treats the zero address as any other holder with zero balance.
- `getUsersPosition` called with a bogus `fToken_` / `stakingContract_` that doesn't implement `balanceOf(address)` → the whole call reverts at the underlying call site. Not this resolver's responsibility.

This matches the resolver-family convention of "never revert for protocol-state reasons" (see `../SPEC.md` §2.6).

## 9. Deployment Checklist

1. Prerequisites: the target fToken (`fUSDC` / `fUSDT`) and its `FluidLendingStakingRewards` contract are deployed. Their addresses must match what is hard-coded in `main.sol` (mainnet) or `mainArb.sol` (Arbitrum).
2. Pick the right source file for the chain — the two files differ only in the four constants.
3. Deploy via the standard `scripts/deploy/deploy-scripts/resolvers/deploy-staking-merkle-resolver.ts` (mainnet) or `deploy-staking-merkle-resolver-arb.ts` (Arbitrum). Constructor takes no arguments.
4. Record the deployed address in `deployments/deployments.md` under `### StakingMerkleResolver` (see [deployments/deployments.md](../../../../deployments/deployments.md)).
5. If any of the four hard-coded addresses rotate on-chain, the resolver **must be redeployed** — there is no setter.

## 10. Invariants & Safety Notes

- **Stateless.** No storage slots, no funds held, no ETH receive. `selfdestruct` / `delegatecall` surface: none.
- **Idempotent.** Two calls at the same block return identical results. Between blocks, results drift only as `balanceOf` drifts on the underlying contracts (transfers, stake/withdraw, fToken rebases).
- **Sum invariant.** `shares == normalShares + stakeShares` always holds — asserted by the assignment order in the loop; no rounding, no fee haircut.
- **No double-counting.** Tokens in the staking contract are **held** by the staking contract (its `_balances[user]` maps to the user's staked shares; the fToken itself shows the staking contract as the holder of the underlying fToken balance). A user's `fToken.balanceOf` therefore does **not** include their staked shares. Summing the two is the correct account of the user's total fToken claim; there is no path where a share is counted on both legs at once.
- **Block consistency.** Both `balanceOf` reads happen inside the same tx at the same block, so the two legs are always consistent with each other.

## 11. Integration Guidance

- **Batch aggressively.** The gas cost is ~2 SLOADs per user plus memory; on a decent archive node, arrays of several thousand users complete in a single `eth_call`. For tens-of-thousands-user snapshots, chunk into batches of ~1–5k and aggregate off-chain.
- **Use the convenience wrappers.** `getUsersPositionFUSDC` / `getUsersPositionFUSDT` are cheaper calldata-wise and self-document the market in the call trace. Reserve the generic `getUsersPosition` for cases where the market isn't one of the two hard-coded ones.
- **Snapshot at a specific block.** Merkle scripts should pin `block` (via `--block <n>` or `archive=<n>`) for reproducibility. The resolver has no block-time semantics of its own; whatever block you read, you get that block's `balanceOf` values.
- **Do not consume on-chain.** Like every resolver, this is sized for off-chain RPC; calling it from another on-chain contract wastes gas (see `../SPEC.md` §6).

## 12. Trust Model & Audit Notes

- **No trust surface.** A malicious deployment can only return wrong numbers to its caller; it cannot move funds or alter state anywhere. The attack surface collapses to "snapshot operator pointed at the wrong resolver address and trusted the output".
- **Authoritative addresses live in `deployments/deployments.md`.** Snapshot tooling should resolve the resolver address from that registry rather than hard-coding it, so a future redeploy is picked up automatically.
- **Immutable by construction.** No upgradeability, no proxy, no setter. Replacement requires redeploy + registry update; the old resolver continues to work until the hard-coded fToken / staking addresses change on-chain (at which point it starts returning zero and must be retired).
- **No composition with other resolvers.** Unlike `stakingRewards/` (which embeds a `FluidLendingResolver`), `stakingMerkle/` stands alone — its only dependencies are the two low-level contract ABIs. This keeps the audit surface minimal: the only question worth asking is "do the four constants match the intended deployments on this chain?", which is a registry check, not a code check.
