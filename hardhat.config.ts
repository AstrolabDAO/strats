import "@nomiclabs/hardhat-ethers";
// import "hardhat-contract-sizer";
// import "hardhat-storage-layout";
import { config } from "@astrolabs/hardhat/dist/hardhat.config";

config.solidity!.compilers = [
  {
    version: `0.8.25`,
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
(<any>config).contractSizer = {
    alphaSort: false, // alphabetically sort contracts vs by size
    disambiguatePaths: false,
    runOnCompile: true,
    strict: false, // throw error if contract size exceeds spurious dragon's bytecode size limit
    only: [],
};
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
