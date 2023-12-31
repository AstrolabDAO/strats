import { IDeployment, getDeployer } from "@astrolabs/hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Contract, providers } from "ethers";
import * as ethers from "ethers";
import { Network } from "hardhat/types";
import { NetworkAddresses } from "./addresses";
import {
  Provider as MulticallProvider,
  Contract as MulticallContract,
} from "ethcall";
import { erc20Abi } from "abitype/abis";

export type MaybeAwaitable<T> = T | Promise<T>;

export class SafeContract extends Contract {
  public multi: MulticallContract = {} as MulticallContract;
  public sym: string = "";
  public abi: ReadonlyArray<any> | any[] = [];
  public scale: number = 0;
  public weiPerUnit: number = 0;

  constructor(
    address: string,
    abi: ReadonlyArray<any> | any[] = erc20Abi,
    signer: SignerWithAddress | ethers.providers.JsonRpcProvider
  ) {
    super(address, abi, signer);
    this.abi = abi;
  }

  public static async build(
    address: string,
    abi: ReadonlyArray<any> | any[] = erc20Abi,
    signer?: SignerWithAddress
  ): Promise<SafeContract> {
    try {
      signer ||= (await getDeployer()) as SignerWithAddress;
      const c = new SafeContract(address, abi, signer);
      c.multi = new MulticallContract(address, abi as any[]);
      if ("symbol" in c) {
        // c is a token
        c.sym = await c.symbol?.();
        c.scale = await c.decimals?.() || 8;
        c.weiPerUnit = 10 ** c.scale;
      }
      return c;
    } catch (error) {
      throw new Error(`Failed to build contract ${address}: ${error}`);
    }
  }

  public async copy(signer: SignerWithAddress=(this.signer as SignerWithAddress)): Promise<SafeContract> {
    // return Object.assign(this, await SafeContract.build(this.address, this.abi, signer));
    return await SafeContract.build(this.address, this.abi, signer);
  }

  public safe = async (
    fn: string,
    params: any[],
    opts: any = {}
  ): Promise<any> => {
    if (typeof this[fn] != "function")
      throw new Error(`${fn} does not exist on the contract ${this.address}`);
    try {
      await this.callStatic[fn](...params, opts);
    } catch (error) {
      const txData = this.interface.encodeFunctionData(fn, params);
      throw new Error(`${fn} static call failed, tx not sent: ${error}, txData: ${txData}`);
    }
    console.log(`${fn} static call succeeded, sending tx...`);
    return this[fn](...params, opts);
  };

  public toWei = (n: number | bigint | string | BigNumber): BigNumber => {
    return ethers.utils.parseUnits(n.toString(), this.scale);
  };

  public toAmount = (n: number | bigint | string | BigNumber): number => {
    const weiString = ethers.utils.formatUnits(n, this.scale);
    return parseFloat(weiString);
  };
}

export interface Erc20Metadata {
  name: string;
  symbol: string;
  decimals?: number;
  version?: string;
}

export interface CoreAddresses {
  asset: string;
  feeCollector?: string;
  swapper?: string;
  agent?: string;
  allocator?: string;
}

export interface Fees {
  perf: number;
  mgmt: number;
  entry: number;
  exit: number;
  flash: number;
}

// fees, asset, feeCollector
export type As4626InitParams = [Erc20Metadata, CoreAddresses, Fees, string, string];

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

export interface IStrategyBaseParams {
  erc20Metadata: Erc20Metadata;
  coreAddresses: CoreAddresses;
  fees: Fees;
  inputs: string[];
  inputWeights: number[];
  rewardTokens: string[];
}

export interface IPythParams {
  pyth: string;
  assetPythId: string;
  inputPythIds: string[];
}

export interface IChainlinkParams {
  assetPriceFeed: string;
  inputPriceFeeds: string[];
}

export type IStrategyParams = [IStrategyBaseParams, any];
export type IStrategyPythParams = [IStrategyBaseParams, IPythParams, any];
export type IStrategyChainlinkParams = [
  IStrategyBaseParams,
  IChainlinkParams,
  any,
];

export interface IStrategyDeployment extends IDeployment {
  // constructor/init params
  initParams: [IStrategyBaseParams, ...any];
  // compilation/verification dependencies
  swapper: Contract;
  agent: Contract;
  libraries: { [name: string]: string };
  // product of deployment
  strat: SafeContract;
  asset: SafeContract;
  inputs: SafeContract[];
  rewardTokens: SafeContract[];
}

export interface ITestEnv {
  // env: chain/addresses
  network: Network; // hardhat inherited
  blockNumber: number;
  snapshotId: string;
  revertState: boolean; // should we revert state after test
  wgas: SafeContract; // wrapped gas == native token
  addresses: NetworkAddresses;
  // deployer
  deployer: SignerWithAddress; // provided by hardhat
  provider: providers.JsonRpcProvider;
  multicallProvider: MulticallProvider;
  // funding
  needsFunding: boolean;
  gasUsedForFunding: number;
}

export interface IStrategyDeploymentEnv extends ITestEnv {
  deployment: IStrategyDeployment;
}
