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

const {
  ALCHEMY_TOKEN_MAINNET,
  ALCHEMY_TOKEN_POLYGON,
  DEPLOYER_PRIVATE_KEY,
  ETHERSCAN_API_KEY,
  POLYGONSCAN_API_KEY,
  ARBITRUM_API_KEY,
  BASE_API_KEY,
  ETHERSCAN_APIV2_KEY,
} = process.env;

const sharedNetworkConfig: HttpNetworkUserConfig = {};

// public address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
// randomly generated for test purposes, do not use for actual deployment!
const DEFAULT_DEPLOYER_PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

sharedNetworkConfig.accounts = [DEPLOYER_PRIVATE_KEY || DEFAULT_DEPLOYER_PRIVATE_KEY];

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
  version: "0.8.29",
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
        url: "https://1rpc.io/eth",
        enabled: true,
      },
    },
    localhost: {},
    mainnet: {
      ...sharedNetworkConfig,
      url: "https://1rpc.io/eth",
    },
    arbitrum: {
      ...sharedNetworkConfig,
      url: "https://arbitrum-one-rpc.publicnode.com",
    },
    base: {
      ...sharedNetworkConfig,
      url: "https://base-rpc.publicnode.com",
    },
    polygon: {
      ...sharedNetworkConfig,
      url: "https://1rpc.io/matic",
      gasPrice: 32_000_000_000,
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
          apiURL: "https://api.routescan.io/v2/network/mainnet/evm/9745/etherscan",
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
