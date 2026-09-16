# Fluid Permissions And Mutability

## Summary

- Mainnet: governance timelock is the final owner / admin. Broad powers live there.
- Mainnet team multisig: limited auth powers only. No broad protocol admin by default.
- L2s: team multisig is the final owner / admin, so governance-level and auth-level powers collapse to the same actor.
- Core point: on mainnet, team multisig auths can tune scoped operational knobs, but cannot directly change live vault oracles or core live risk parameters.
- Core risk items: oracle, risk params, borrow limits.

## Upgradeability

- Liquidity layer: upgrade authority is governance only.
- For an upgrade, team multisig can roll back for 7 days if rollback was registered.
- Vaults, DEX pools, Smart Lending, fTokens, and other protocol contracts are not upgradeable in place.
- Factories are not proxy-upgradeable; owners can update auths / deployers / deployment logic.
- Auth contracts are replacement-only: deploy new auth, register it, remove old auth.
- Oracle source configuration is immutable after deployment. Vault oracle pointer is mutable only through vault admin / governance.

## Liquidity

Governance only:

- Add / remove auths.
- Add / remove guardians.
- Update revenue collector.
- Full raw rate curve and unscoped admin changes.

Liquidity auths:

- Usually controlled by team multisig or a configured rebalancer.
- Can call selected methods: token configs, rate data, user supply / borrow configs, user withdrawal limits, revenue collection, `operateOnBehalfOf`.
- Important limits: team multisig rate updates are rate-at-kink only; team multisig borrow-limit changes are bounded, e.g. 20% paths where the auth enforces that limit.

## Vault Protocol

Governance / vault factory auth:

- Oracle pointer.
- Risk params: collateral factor, liquidation threshold, liquidation max limit, liquidation penalty, borrow fee, withdraw gap.
- Rebalancer.
- Rescue / dust admin paths.

Team multisig auth:

- Vault fee / reward rate or magnifier knobs only.
- Not oracle, not core risk params.

## DEX Protocol

Governance / DEX factory owner:

- Global auths.
- Per-DEX auths.
- Deployers.
- Deployment logic.
- Factory `spell`.

DEX auths:

- Usually controlled by team multisig for limited operations.
- Can call selected pool admin methods: fee, revenue cut, ranges, thresholds, user limits, max shares, withdrawal limits, pause flows.
- Important limits: changes are capped to max percentage moves and cooldowns / shift windows apply, usually at least 2 days depending on the path.

## fTokens

LendingFactory auth:

- `updateRewards`.
- `updateRebalancer`.
- `rescueFunds`.
- Mainnet: governance only, not team multisig auth.

Rebalancer:

- `rebalance`.

Immutable:

- fToken implementation, asset, decimals, Liquidity address, LendingFactory address, storage-slot links.

## Oracles And Capped Rates

Immutable:

- Source configuration.

Governance / Liquidity guardians:

- Capped-rate knobs: max APR cap, down-from-max caps, debt up cap, avoid-forced-liquidation flags, force-reset max rate.
- Governance only: heartbeat, min-update-diff.

Important distinction:

- Changing a vault to use a different oracle is vault admin / governance.
- Changing capped-rate limits tunes an existing capped-rate oracle.
- Neither is a normal mainnet team-multisig auth power.

## Mainnet Team Multisig Can Adjust

- Rate-at-kink.
- Selected Liquidity limits.
- Token listing default path / reserve factor.
- DEX fee / revenue cut.
- DEX ranges / thresholds.
- DEX user limits / max shares.
- Vault fee / reward rate knobs.
- Pause flows, where configured.
- Revenue collection.
- Payback-on-behalf.

All above are scoped by the called auth contract.

## Mainnet Team Multisig Cannot Directly Adjust

- Liquidity-layer implementation upgrades.
- Factory ownership.
- Auth registries.
- Vault oracle pointer.
- Vault risk params: collateral factor, liquidation threshold, liquidation max limit, liquidation penalty, borrow fee, withdraw gap.
- Full Liquidity rate curve.
- Raw oracle source configuration.
- Core live protocol risk params outside explicit auth guardrails.

## Solana

- Three admin Squads multisigs today.
- Timelocked multisig: upgrade owner.
- Main team multisig: current day-to-day admin, no timelock today.
- Protocol init auth: zero-risk initialization only, e.g. initializing a new vault.
- No auth contracts currently.
- Main risky actions: setting oracle, risk params, borrow limits.

## Future Plans

- Likely add timelocks for team multisigs on L2s.
- Likely move more risky Solana actions toward the timelocked multisig.
- Tighten permissions over the next 1-2 months.
- Add new auth contracts mainly to simplify maintenance.
- New auth contracts will not introduce any new risk compared to today.
- No auth contract will let team multisig change oracles, risk params, or increase borrow limits beyond existing protected paths.
- Borrow-limit increases will remain protected by timelock / cooldown / max-percent increase constraints.
- Team multisig will not be able to make a new borrow-enabled protocol live by itself.
- Oracle system v2: upgradable by governance only.
- Oracle v2 adds no new team-multisig oracle risk: governance can already do anything, and oracle selection remains governance-controlled.
- Team multisig may list new oracles, but they are not usable for borrow limits or other borrow-side risk until governance approves them.

