import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-chai-matchers";
import { config as envConfig } from "dotenv";

envConfig();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.7.6",
        settings: {
          viaIR: true,
        }
      },
      {
        version: "0.8.24",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 2000,
            details: {
              yulDetails: {
                stackAllocation: true,
                optimizerSteps: "dhfoDgvulfnTUtnIf"
              }
            }
          }
        }
      },
    ],
    overrides: {
      "node_modules/@uniswap/swap-router-contracts/contracts/interfaces/IApproveAndCall.sol":
      {
        version: "0.7.6",
      },
    },
  },
  networks: {
    base: {
      accounts: [process.env.LIQ_FUN_DEPLOYER!],
      url: "https://base-mainnet.g.alchemy.com/v2/OE4RpUmSAX2Nljzn-hZZPeH_pyE8hvTx",
    },
    localhost: {
      forking: {
        enabled: true,
        url: "https://base-mainnet.g.alchemy.com/v2/OE4RpUmSAX2Nljzn-hZZPeH_pyE8hvTx",
        blockNumber: 15372013,
      },
      mining: {
        interval: 2000,
      }
    }
  },
};

export default config;
