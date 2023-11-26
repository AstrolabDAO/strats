import { IDeployment } from "@astrolabs/hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Contract, providers } from "ethers";
import { Network } from "hardhat/types";
import { NetworkAddresses } from "./addresses";

export interface Fees {
    perf: number;
    mgmt: number;
    entry: number;
    exit: number;
}

export interface IAs4626Params {
    fees: Fees;
    underlying: string;
    feeCollector: string;
    erc20Metadata: string[];
}

export interface IStrategyV5Params {
    fees: Fees;
    underlying: string;
    coreAddresses: string[], // feeCollector,swapper,allocator,agent
    erc20Metadata: string[],
    inputs: string[],
    inputWeights: number[],
    rewardTokens: string[]
}

export interface IStrategyDeployment extends IDeployment {
    // constructor/init params
    params: IStrategyV5Params;
    // compilation/verification dependencies
    swapper: Contract;
    agent: Contract;
    libraries: { [name: string]: string };
    // product of deployment
    strat: Contract;
    underlying: IToken;
    inputs: IToken[];
    rewardTokens: IToken[];
}

export interface IToken {
    contract: Contract;
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
    // funding
    needsFunding: boolean;
    gasUsedForFunding: number;
}

export interface IStrategyDeploymentEnv extends ITestEnv {
    deployment: IStrategyDeployment;
}
