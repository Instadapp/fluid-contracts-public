# Fluid (Flux) on BSC Testnet — QA Guide

Deploy Fluid lending markets (fTokens) on BSC Testnet so the hub's **Flux** family can be QA'd.
Two scripts: **core** (deploy once) and **add-market** (run per asset).

---

## Already deployed (shared core — do NOT redeploy)

| Contract | Address |
|---|---|
| Liquidity | `0x94838d6805E6269Fa57A9517696eE0619dE89AdE` |
| LendingFactory | `0x399Ea487E3125AF7b871dDfC7E4d359F1DeeA9BE` |
| **LendingResolver** (hub adapter reads this) | `0x477a0b09030f755D006daE6d8D90430AA0Fe7768` |
| fUSDT (first market) | `0x52217232e12A1c906aB8DEf58532a3618970D025` |
| Owner / governance | `0x2Ce1d0ffD7E869D9DF33e28552b12DdDed326706` |

Every new market reuses this core. The `LendingResolver` is the same for **all** assets.

---

## Prerequisites

- `npm install` in this repo (once).
- The **core owner key** (`0x2Ce1…`) — listing an asset is governance-gated.
- Deployer funded with a little tBNB (~0.005 per market).

---

## Add a market (per asset)

**Step 1 — set these in `.env`** (repo root; foundry auto-loads it):

```
DEPLOYER_PRIVATE_KEY=0x<core-owner-key>
UNDERLYING=0x<asset-token-address>
MARKET_LABEL=USDC
# SMOKE_DEPOSIT=1000     # optional, faucet tokens only
```

**Step 2 — run:**

```bash
cd fluid-contracts-public

forge script script/AddFluidMarketBscTestnet.s.sol:AddFluidMarketBscTestnet \
  --rpc-url https://bsc-testnet-rpc.publicnode.com --broadcast --slow
```

**Next asset:** change `UNDERLYING` + `MARKET_LABEL` in `.env`, run again.

**Output:** prints the new **fToken** address and saves
`deployments/bsctestnet-fluid-market-<LABEL>.json`.

### Env flags

| Flag | Required | Meaning |
|---|---|---|
| `DEPLOYER_PRIVATE_KEY` | yes | Must be the core owner |
| `UNDERLYING` | yes | ERC20 asset (e.g. WBNB `0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd`) |
| `MARKET_LABEL` | no | Output filename label (default = token address) |
| `SMOKE_DEPOSIT` | no | Whole tokens to faucet + deposit as a check; default `0` |
| `FLUID_CORE` | no | Core JSON path (default `./deployments/bsctestnet-fluid-lending.json`) |

---

## Wire into the hub (per asset)

Take the two values the script gives you into `venus-liquidity-hub`:

1. `deploy/config/bsctestnet.json` → `fluxLendingResolver` = `0x477a0b09030f755D006daE6d8D90430AA0Fe7768` (same for all).
2. Register the printed **fToken** as the Flux resource on that asset's `FluxSource_<ASSET>`.

---

## Key notes

- **Owner key only.** QA's own key will fail with auth error `10003`. Either share the throwaway testnet key or have the owner run the script.
- **`SMOKE_DEPOSIT` needs a faucet.** Works for `allocateTo` tokens (USDC/USDT). Leave `0` for WBNB and others; fund test wallets manually.
- **Any ERC20 works**, including WBNB — no native variant needed for hub QA.
- **First market is fUSDT** (already live). Do not create a second fUSDT — same asset reverts (`TokenExists`).

---

## Re-deploy the core (only if starting fresh on a new chain/account)

Set `DEPLOYER_PRIVATE_KEY` in `.env`, then:

```bash
forge script script/DeployFluidLendingBscTestnet.s.sol:DeployFluidLendingBscTestnet \
  --rpc-url https://bsc-testnet-rpc.publicnode.com --broadcast --slow
```

Deploys the full stack + fUSDT + a 1000-USDT smoke deposit, and writes
`deployments/bsctestnet-fluid-lending.json`.
