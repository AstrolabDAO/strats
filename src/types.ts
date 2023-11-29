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

// fees, underlying, coreAddresses, inputs, inputWeights, rewardTokens, ...strategyParams
export type StrategyV5InitParams = [Fees, string, string[], string[], number[], string[], ...any[]];

export interface IStrategyDeployment extends IDeployment {
    // constructor/init params
    constructorParams: [Erc20Metadata];
    initParams: StrategyV5InitParams;
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

export interface IToken {
    contract: Contract;
    multicallContract: MulticallContract;
    symbol: string;
    decimals: number;
    weiPerUnit: number;
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
