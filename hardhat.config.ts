import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();
import { HttpNetworkUserConfig } from "hardhat/types/config";
import "@nomicfoundation/hardhat-verify";
import "@typechain/hardhat";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";
import "hardhat-contract-sizer";
import "@nomicfoundation/hardhat-foundry";
import "solidity-docgen";
import "./scripts/plugins/kms-signer";

const {
  ALCHEMY_TOKEN_MAINNET,
  ALCHEMY_TOKEN_POLYGON,
  DEPLOYER_PRIVATE_KEY,
  ETHERSCAN_API_KEY,
  POLYGONSCAN_API_KEY,
  ARBITRUM_API_KEY,
  BASE_API_KEY,
  ETHERSCAN_APIV2_KEY,
  FLUID_KMS_KEY_ID,
  FLUID_KMS_EXPECTED_DEPLOYER,
  FLUID_KMS_ALLOW_LOCAL_KEYS,
} = process.env;

const sharedNetworkConfig: HttpNetworkUserConfig = {};

// public address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
// randomly generated for test purposes, do not use for actual deployment!
const DEFAULT_DEPLOYER_PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

if (FLUID_KMS_KEY_ID) {
  // deployer key lives in AWS KMS; never install a local accounts array so no
  // raw private key can shadow the KMS signer (see scripts/plugins/kms-signer).
  sharedNetworkConfig.kmsKeyId = FLUID_KMS_KEY_ID;
  sharedNetworkConfig.kmsExpectedDeployer = FLUID_KMS_EXPECTED_DEPLOYER;
  // hybrid mode (opt-in): KMS stays the deployer (account 0) while the legacy
  // local key remains usable for flows that still need it, routed by `from`.
  if (FLUID_KMS_ALLOW_LOCAL_KEYS === "1" && DEPLOYER_PRIVATE_KEY) {
    sharedNetworkConfig.kmsExtraAccounts = [DEPLOYER_PRIVATE_KEY];
  }
} else {
  sharedNetworkConfig.accounts = [DEPLOYER_PRIVATE_KEY || DEFAULT_DEPLOYER_PRIVATE_KEY];
}

const namedAccounts: any = {
  deployer: {
    default: 0, // use the first account (index = 0).
  },
};

const defaultContractSettings = {
  version: "0.8.21",
  settings: {
    optimizer: {
      enabled: true,
      runs: 10000000,
    },
  },
};

const newContractSettings = {
  version: "0.8.36",
  settings: {
    optimizer: {
      enabled: true,
      runs: 10000000,
    },
    evmVersion: "cancun", // Required for transient storage (tload/tstore)
  },
};

const config = {
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [defaultContractSettings, newContractSettings],
    overrides: {
      "contracts/periphery/resolvers/dex/main.sol": {
        ...defaultContractSettings,
        settings: {
          ...defaultContractSettings.settings,
          optimizer: {
            ...defaultContractSettings.settings.optimizer,
            runs: 1000,
          },
        },
      },
      "contracts/periphery/resolvers/vault/main.sol": {
        ...defaultContractSettings,
        settings: {
          ...defaultContractSettings.settings,
          optimizer: {
            ...defaultContractSettings.settings.optimizer,
            runs: 20000,
          },
        },
      },
      // permissioned shared vault implementation exceeds the EIP-170 24KB limit at 10M optimizer
      // runs (production FluidVaultT1 is already at ~23.5KB; the permissioned config/gating layer
      // adds ~2.5KB). Lower runs to fit under the limit, same pattern as the vault resolver above.
      "contracts/permissioned/vault/fluidVaultT1Permissioned.sol": {
        ...defaultContractSettings,
        settings: {
          ...defaultContractSettings.settings,
          optimizer: {
            ...defaultContractSettings.settings.optimizer,
            runs: 1000,
          },
        },
      },
      "contracts/liquidity/adminModule/mainMainnet.sol": {
        ...defaultContractSettings,
        settings: {
          ...defaultContractSettings.settings,
          optimizer: {
            ...defaultContractSettings.settings.optimizer,
            runs: 20000,
          },
        },
      },
      "contracts/liquidity/adminModule/mainOthers.sol": {
        ...defaultContractSettings,
        settings: {
          ...defaultContractSettings.settings,
          optimizer: {
            ...defaultContractSettings.settings.optimizer,
            runs: 20000,
          },
        },
      },
      // UsdOracle sizes measured after the CROSS_PATH admin-guard dedup (EIP-170 = 24,576 B):
      //   main.sol        440 -> 24,037 B (539 under; 450 runs was 24,597 B)
      //   mainL2.sol        1 -> 24,561 B (only 15 B under; runs already at the floor)
      //   bootstrap/main  200 -> 24,330 B (246 under)
      //   bootstrap/mainL2  1 -> 25,427 B (851 over); out of scope
      // mainL2 fits only because `_isCrossPath` / `_isStablePeg` are shared by the admin guards and the
      // resolving path; inlining `_isCrossPath` back costs 63 B and puts mainL2 over. Re-measure before
      // adding code here.
      // main.sol stays as high as fits — it is the hot read path on every vault price lookup.
      "contracts/oracleV2/usdOracle/main.sol": {
        ...newContractSettings,
        settings: {
          ...newContractSettings.settings,
          optimizer: {
            ...newContractSettings.settings.optimizer,
            runs: 440,
          },
        },
      },
      "contracts/oracleV2/usdOracle/mainL2.sol": {
        ...newContractSettings,
        settings: {
          ...newContractSettings.settings,
          optimizer: {
            ...newContractSettings.settings.optimizer,
            runs: 1,
          },
        },
      },
      "contracts/oracleV2/usdOracle/bootstrap/main.sol": {
        ...newContractSettings,
        settings: {
          ...newContractSettings.settings,
          optimizer: {
            ...newContractSettings.settings.optimizer,
            // 0.8.36 @ 1000 ≈ 24,713 B (over EIP-170); 200 fits for temp permissioned / general L1 Bootstrap.
            runs: 200,
          },
        },
      },
      // NOT CURRENTLY DEPLOYABLE. L2 Bootstrap is 25,427 B at runs 1 — the optimizer floor —
      // against a 24,576 B limit. Runs are left at the floor because that is the closest this gets. L2 is
      // out of scope for now; before any L2 deploy this needs a real fix (split the contract, drop the
      // bootstrap multicall, or adopt viaIR, which measured 24,011 B but is deliberately not used here).
      "contracts/oracleV2/usdOracle/bootstrap/mainL2.sol": {
        ...newContractSettings,
        settings: {
          ...newContractSettings.settings,
          optimizer: {
            ...newContractSettings.settings.optimizer,
            runs: 1,
          },
        },
      },
    },
  },
  networks: {
    hardhat: {
      forking: {
        // @dev uncomment whatever network you want to fork
        //
        // ETH MAINNET
        // url: "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_TOKEN_MAINNET,
        // blockNumber: 18827888,
        //
        // POLYGON
        // url: "https://polygon-mainnet.g.alchemy.com/v2/" + ALCHEMY_TOKEN_POLYGON,
        // blockNumber: 51352596, // e.g. on Polygon
        //
        url: process.env.MAINNET_RPC_URL || "https://1rpc.io/eth",
        enabled: true,
      },
    },
    localhost: {
      // local fork dry-runs of the permissioned deploy can exercise the KMS path too
      kmsKeyId: FLUID_KMS_KEY_ID,
      kmsExpectedDeployer: FLUID_KMS_EXPECTED_DEPLOYER,
      kmsExtraAccounts: sharedNetworkConfig.kmsExtraAccounts,
    },
    mainnet: {
      ...sharedNetworkConfig,
      url: process.env.MAINNET_RPC_URL || "https://rpc.flashbots.net",
    },
    // isolated permissioned test deployment on Ethereum mainnet: same chain, separate
    // hardhat-deploy artifact folder (deployments/mainnet-permissioned/) so it never
    // touches the production deployments/mainnet/ records.
    "mainnet-permissioned": {
      ...sharedNetworkConfig,
      chainId: 1,
      url: process.env.MAINNET_RPC_URL || "https://rpc.flashbots.net",
    },
    arbitrum: {
      ...sharedNetworkConfig,
      url: "https://arb1.arbitrum.io/rpc",
    },
    base: {
      ...sharedNetworkConfig,
      url: "https://base-rpc.publicnode.com",
    },
    polygon: {
      ...sharedNetworkConfig,
      url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_TOKEN_POLYGON || process.env.ALCHEMY_TOKEN_MAINNET}`,
      // gasPrice: 32_000_000_000,
    },
    plasma: {
      ...sharedNetworkConfig,
      url: "https://rpc.plasma.to",
    },
    bnb: {
      ...sharedNetworkConfig,
      url: "https://bsc.blockrazor.xyz",
    },
  },
  etherscan: {
    // blockchain explorers api keys from .env
    apiKey: {
      mainnet: ETHERSCAN_APIV2_KEY || "",
      "mainnet-permissioned": ETHERSCAN_APIV2_KEY || "",
      polygon: ETHERSCAN_APIV2_KEY || "",
      arbitrum: ETHERSCAN_APIV2_KEY || "",
      base: ETHERSCAN_APIV2_KEY || "",
      plasma: ETHERSCAN_APIV2_KEY || "",
      bnb: ETHERSCAN_APIV2_KEY || "",
    },
    customChains: [
      {
        network: "mainnet",
        chainId: 1,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=1",
          browserURL: "https://etherscan.io/",
        },
      },
      {
        network: "mainnet-permissioned",
        chainId: 1,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=1",
          browserURL: "https://etherscan.io/",
        },
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=8453",
          browserURL: "https://basescan.org/",
        },
      },
      {
        network: "arbitrum",
        chainId: 42161,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=42161",
          browserURL: "https://arbiscan.io/",
        },
      },
      {
        network: "polygon",
        chainId: 137,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=137",
          browserURL: "https://polygonscan.com/",
        },
      },
      {
        network: "plasma",
        chainId: 9745,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=9745",
          browserURL: "https://plasmascan.to/",
        },
      },
      {
        network: "bnb",
        chainId: 56,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=56",
          browserURL: "https://etherscan.io/",
        },
      },
    ],
  },
  namedAccounts,
  docgen: {
    outputDir: "./docs/contracts/src/contracts",
    exclude: [],
    pages: "files",
  },
};

export default config;
