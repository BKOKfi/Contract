import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    bsc: {
      url: "https://rpc.ankr.com/bsc",
      allowUnlimitedContractSize: true,
      accounts: [],
    },
  },
  etherscan: {
    apiKey: { bsc: "" },
  },
};

export default config;
