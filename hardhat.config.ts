import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();
import { HttpNetworkUserConfig, HardhatUserConfig } from "hardhat/types/config";
import "@nomicfoundation/hardhat-verify";
import "@typechain/hardhat";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";
import "hardhat-contract-sizer";

const { ALCHEMY_TOKEN_MAINNET, ALCHEMY_TOKEN_POLYGON, DEPLOYER_PRIVATE_KEY, ETHERSCAN_API_KEY, POLYGONSCAN_API_KEY } =
  process.env;

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

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [defaultContractSettings],
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
        url: "https://polygon-mainnet.g.alchemy.com/v2/" + ALCHEMY_TOKEN_POLYGON,
        blockNumber: 51352596, // e.g. on Polygon
        //
        enabled: true,
      },
    },
    localhost: {},
    mainnet: {
      ...sharedNetworkConfig,
      url: "https://rpc.ankr.com/eth",
    },
    polygon: {
      ...sharedNetworkConfig,
      url: "https://rpc.ankr.com/polygon",
      gasPrice: 85_000_000_000,
    },
  },
  etherscan: {
    // blockchain explorers api keys from .env
    apiKey: {
      mainnet: ETHERSCAN_API_KEY || "",
      polygon: POLYGONSCAN_API_KEY || "",
    },
  },
  namedAccounts,
};

export default config;
