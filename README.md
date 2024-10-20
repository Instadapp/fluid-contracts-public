# Fluid

Instadapp Fluid is a combination of DeFi protocols with a Liquidity layer at the core. New protocols will be added to the architecture over time with liquidity automatically being available to those newer protocols.

See [docs.md](https://github.com/instadapp/fluid-contracts-public/blob/main/docs/docs.md) for technical docs.

## Development

Create a `.env` file and set the `MAINNET_RPC_URL` and other params like in `.env.example`.

### Install

Install [Foundry](https://github.com/foundry-rs/foundry).

Install dependencies

```bash
forge install foundry-rs/forge-std --no-git
forge install a16z/erc4626-tests --no-git
forge install transmissions11/solmate@b5c9aed --no-git
forge install OpenZeppelin/openzeppelin-contracts@v4.8.2 --no-git
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v4.8.2 --no-git
```

Install npm dependencies:
`npm i`

## Forge

### Build

```bash
forge build
```

### Test

```bash
forge test
```

or for full logs

```bash
forge test -vvvv
```

or in a certain folder

```bash
forge test -vvv --mp "test/foundry/liquidity/**/**.sol"
```

### Gas usage snapshot

Creates current gas usage for tests

```bash
forge snapshot
```

Create gas report and store it in file:

```bash
forge test --gas-report
```

Or to store in file:

```bash
forge snapshot > .gas-snapshot
```

```bash
forge test --gas-report > .gas-report
```

(or `make gas-report` if you have make installed)

### Contract size

With hardhat:

```
npx hardhat size-contracts
```

With foundry:

```
forge build --sizes
```

### Genearting docs

With foundry:

```
forge doc
```

See https://book.getfoundry.sh/reference/forge/forge-doc

## Deployment, dev internal docs etc.

See dev internal docs in `./docs/internal-dev/`
