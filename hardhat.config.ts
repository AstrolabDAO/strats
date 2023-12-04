import "@nomiclabs/hardhat-ethers";
import { config } from "@astrolabs/hardhat/dist/hardhat.config";

config.solidity!.compilers = [
  {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 150,
      },
      viaIR: false,
    },
  },
];
config.paths = {
  // registry
  sources: "./src",
  interfaces: "../registry/interfaces",
  abis: "../registry/abis",
  registry: "../registry",
  // tmp build files
  artifacts: "./artifacts",
  cache: "./cache",
  // local sources
  tests: "./test/integration",
} as any;

config.tenderly!.privateVerification = true;

export default config;
