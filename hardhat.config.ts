import "@nomiclabs/hardhat-ethers";
import { config } from "@astrolabs/hardhat/dist/hardhat.config";

config.solidity!.compilers = [
  {
    version: `0.8.22`,
    settings: {
      optimizer: {
        enabled: true,
        runs: 160
      },
      viaIR: false,
      evmVersion: `paris`
    }
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
config.mocha!.bail = true;

config.tenderly!.privateVerification = true;

export default config;
