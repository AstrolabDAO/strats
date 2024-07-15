import { IDeployment, Erc20Metadata, SafeContract, ITestEnv } from "@astrolabs/hardhat";
import { Contract } from "ethers";

export interface CoreAddresses {
  wgas: string;
  asset: string;
  feeCollector?: string;
  swapper?: string;
  agent?: string;
  oracle?: string;
  allocator?: string;
}

export interface Fees {
  perf: number;
  mgmt: number;
  entry: number;
  exit: number;
  flash: number;
}

export interface IStrategyDesc {
  name: string;
  symbol: string;
  version: number;
  contract: string;
  asset: string;
  inputs: string[];
  inputWeights: number[];
  seedLiquidityUsd: number;
}

// construction params
export interface IStrategyConstructorParams {
  accessController: string;
}

// init params
export interface IStrategyParams {
  erc20Metadata: Erc20Metadata;
  coreAddresses: Partial<CoreAddresses>;
  fees: Fees;
  inputs: string[];
  inputWeights: number[];
  lpTokens: string[];
  rewardTokens: string[];
  extension?: string;
}

export interface IPythParams {
  pyth: string;
  assets: string[];
  feeds: string[];
  validities: number[];
}

export interface IChainlinkParams {
  assets: string[];
  feeds: string[];
  validities: number[];
}

export interface IStrategyDeployment extends IDeployment {
  // constructor/init params
  initParams: IStrategyParams;
  // compilation/verification dependencies
  Swapper: Contract;
  StrategyV5Agent: Contract;
  AccessController: Contract;
  PriceProvider: Contract;
  libraries: { [name: string]: string };
  // product of deployment
  strat: SafeContract;
  asset: SafeContract;
  inputs: SafeContract[];
  rewardTokens: SafeContract[];
}

export interface IStrategyDeploymentEnv extends ITestEnv {
  deployment: IStrategyDeployment;
}
