# Vault Oracle V2

Per-vault oracles that compute collateral/debt exchange rates using the Fluid USD Oracle as the common price source.

## Overview

Instead of per-vault-type oracle contracts with hardcoded Chainlink feeds, conversion oracles, and colDebt bridges (V1), this system:

1. Values every token in USD via the single `FluidUsdOracle` (per-deployment **`SUPPLY_E_MODE`** and **`BORROW_E_MODE`** on each vault oracle)
2. Caches all vault/DEX config as Solidity immutables in per-vault oracles
3. Deploys vault oracles via **`VaultOracleFactory`** (governance, team multisig, or allow-listed deployers; governance may **`registerVaultForce`** to redeploy)

## Why the factory uses a proxy (ERC1967 UUPS)

The **canonical entrypoint** is `VaultOracleFactoryProxy`, not the implementation contract.

1. **Upgradeability** — Factory logic can be fixed or extended (new vault types, validation, gas paths) by pointing the proxy at a new implementation **without** redeploying the factory at a new address.
2. **Persistent registry** — `vaultIdToOracleDeployNonce` (and any future factory state) lives in **storage at the proxy address**. Upgrades replace only implementation code; **vault-ID → oracle deploy nonce** tracking is **not** lost when the implementation changes.
3. **Stable integrations** — Other contracts, scripts, and allow-lists (e.g. `FluidContractFactory.updateDeployer`) can **keep a single well-known factory address per network** across upgrades, instead of migrating references whenever logic is redeployed.

This is the standard ERC1967 **UUPS** pattern (`VaultOracleFactory` inherits `UUPSUpgradeable`); it is **not** the “infinite proxy” / generic dispatcher pattern.

## Quick Start

```solidity
// import { VaultOracleFactory } from ".../vaultOracle/factory/main.sol";
// import { VaultOracleFactoryProxy } from ".../vaultOracle/factory/proxy.sol";

// 1. Deploy per-type deployment logics, then implementation + ERC1967 proxy.
//    T2–T4: deployerFactory must match vault.constantsView().deployer.
address t1Logic = address(new VaultT1OracleDeploymentLogic());
address t2Logic = address(new VaultT2OracleDeploymentLogic());
address t3Logic = address(new VaultT3OracleDeploymentLogic());
address t4Logic = address(new VaultT4OracleDeploymentLogic());
VaultOracleFactory impl = new VaultOracleFactory(liquidityAddress, usdOracleAddress, vaultFactoryAddress, deployerFactory, t1Logic, t2Logic, t3Logic, t4Logic);
VaultOracleFactory factory = VaultOracleFactory(address(new VaultOracleFactoryProxy(address(impl), "")));

// 2. Owner allow-lists the proxy on FluidContractFactory (so registerVault can call deployContract)
FluidContractFactory(deployerFactory).updateDeployer(address(factory), allowanceCount);

// 3. Register — caller must be Liquidity governance, TEAM_MULTISIG, or vaultOracleDeployer[caller] == true.
//    supplyEMode/borrowEMode must each be valid via IUSDOracle.isEmodeValid
//    for at least one token relevant to that side of the vault.
address vaultOracle = factory.registerVault(vaultId, supplyEMode, borrowEMode);
// Governance-only redeploy: factory.registerVaultForce(vaultId, supplyEMode, borrowEMode);

// Factory records vaultId => FluidContractFactory deploy nonce; use getVaultOracleDeployment(vaultId) → (vault, oracleNonce, vaultOracle) for validation.

// 4. Vault admin: T1 uses updateOracle(address); T2–T4 use updateOracle(nonce) where nonce is from LogContractDeployed
```

## Architecture

```
VaultOracleFactory (implementation; use behind VaultOracleFactoryProxy)
  ├── T1–T4_ORACLE_LOGIC (immutable deployment logics)
  ├── registerVault(vaultId, supplyEMode, borrowEMode)
  │   / registerVaultForce(...) → logic.creationCodeWithArgs → DEPLOYER_FACTORY.deployContract:
  │     ├── VaultT1Oracle   (normal col + normal debt)
  │     ├── VaultT2Oracle   (smart col + normal debt)
  │     ├── VaultT3Oracle   (normal col + smart debt)
  │     └── VaultT4Oracle   (smart col + smart debt)
  │
  └── Each vault oracle inherits:
        VaultOracleBase (immutable SUPPLY_E_MODE / BORROW_E_MODE) → DexShareResolver
```

## Gas Savings

Per-call overhead compared to fresh reads:
- **T1**: ~2,564 gas saved (from ~2,600 to ~36)
- **T2/T3/T4**: ~10,364 gas saved (from ~10,400 to ~36)

All vault/DEX configuration is read from Solidity immutables (~3 gas each).

## Files

| File | Description |
|---|---|
| `common/dexShareResolver.sol` | Abstract: DEX LP share → USD price resolution |
| `common/tokenAmtResolver.sol` | Token amount <-> USD value conversions |
| `common/error.sol` | Custom errors for shared `oracleV2/common` helpers |
| `common/errorTypes.sol` | Shared numeric error codes for `oracleV2/common` |
| `vaultOracle/base.sol` | Abstract: normal token resolution + exchange rate math |
| `vaultOracle/factory/main.sol` | VaultOracleFactory implementation (UUPS) |
| `vaultOracle/factory/proxy.sol` | ERC1967 proxy (stable address) |
| `vaultOracle/factory/deploymentLogics/vaultT{1,2,3,4}OracleLogic.sol` | Per-type oracle creation-code holders |
| `vaultOracle/error.sol` | Custom errors for vault oracle contracts |
| `vaultOracle/errorTypes.sol` | Shared numeric error codes for vault oracle contracts |
| `vaultOracle/vaultTypes/vaultT{1,2,3,4}Oracle.sol` | Per-vault-type oracles |
| `interfaces/iVaultOracle.sol` | Interface for vault oracle consumers |

## Key Design Decisions

- **Factory behind UUPS proxy** — See [Why the factory uses a proxy](#why-the-factory-uses-a-proxy-erc1967-uups) above.
- **Immutable dual eModes per vault oracle** — Set at factory deploy (`registerVault` / `registerVaultForce`): `SUPPLY_E_MODE` is used for collateral-side reads and `BORROW_E_MODE` for debt-side reads. The factory requires each side's eMode to pass `IUSDOracle.isEmodeValid` against that side's relevant token set. Exact missing per-key rows may intentionally fall back to eMode `0` at USD-oracle runtime.
- **Access:** `setVaultOracleDeployer` — governance or `TEAM_MULTISIG`; `registerVault` — governance, `TEAM_MULTISIG`, or allow-listed deployer; `registerVaultForce` — **governance only**.
- **Peg buffer (per-vault):** T2–T4 DEX share legs use immutables in `VaultOracleBase`, set per vault via `registerVault(..., pegBufferPpmOperate_, pegBufferPpmLiquidate_)`. The factory caps both at 1% and requires liquidate ≤ operate; the Polygon rollout default is 0.1% operate / 0.02% liquidate. Other `DexShareResolver` callers still pass their own `pegBufferPpm` (use `0` for limit handlers / true reserve value).
- **Raw liquidity reserves** (no PEX re-projection; see `vaultTypes/README-dexV1-oracles.md`)
- **Direct vault oracle pattern**: vault points directly to its vault oracle, no router overhead
- **Share decimals = 18** for all DEX LP shares

See [SPEC.md](SPEC.md) for the full technical specification.
