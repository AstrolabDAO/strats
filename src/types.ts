import { IDeployment } from "@astrolabs/hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Contract, providers } from "ethers";
import { Network } from "hardhat/types";
import { NetworkAddresses } from "./addresses";
import { Provider as MulticallProvider, Contract as MulticallContract} from "ethcall";

export interface Fees {
    perf: number;
    mgmt: number;
    entry: number;
    exit: number;
}

// name, symbol, version
export type Erc20Metadata = [string, string, string];

// fees, underlying, feeCollector
export type As4626InitParams = [Fees, string, string];

export interface IStrategyDesc {
    name: string;
    symbol: string;
    version: number;
    contract: string;
    underlying: string;
    inputs: string[];
    inputWeights: number[];
    seedLiquidityUsd: number;
}

export interface IStrategyBaseParams {
    fees: Fees,
    underlying: string,
    coreAddresses: string[],
    inputs: string[],
    inputWeights: number[],
    rewardTokens: string[]
};

export interface IPythParams {
    pyth: string;
    underlyingPythId: string;
    inputPythIds: string[];
}

export interface IChainlinkParams {
    underlyingPriceFeed: string;
    inputPriceFeeds: string[];
}

export type IStrategyParams = [IStrategyBaseParams, any];
export type IStrategyPythParams = [IStrategyBaseParams, IPythParams, any];
export type IStrategyChainlinkParams = [IStrategyBaseParams, IChainlinkParams, any];

export interface IStrategyDeployment extends IDeployment {
    // constructor/init params
    constructorParams: [Erc20Metadata];
    initParams: [IStrategyBaseParams, ...any];
    // compilation/verification dependencies
    swapper: Contract;
    agent: Contract;
    libraries: { [name: string]: string };
    // product of deployment
    strat: IToken;
    underlying: IToken;
    inputs: IToken[];
    rewardTokens: IToken[];
}

export interface IToken extends Contract {
    multi: MulticallContract;
    sym: string;
    scale: number;
    weiPerUnit: number;
    toWei: (n: number|bigint|string|BigNumber) => BigNumber;
    toAmount: (n: number|bigint|string|BigNumber) => number;
}

export interface ITestEnv {
    // env: chain/addresses
    network: Network; // hardhat inherited
    blockNumber: number;
    snapshotId: string;
    revertState: boolean; // should we revert state after test
    wgas: IToken; // wrapped gas == native token
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
