import { BigNumber } from "ethers";

export interface Fees {
    perf: number;
    mgmt: number;
    entry: number;
    exit: number;
}

export interface IAs4626 {
    fees: Fees;
    underlying: string;
    feeCollector: string;
    erc20Metadata: string[];
}

export interface IStrategyV5 extends IAs4626 {
    fees: Fees;
    underlying: string;
    feeCollector: string;
    coreAddresses: string[], // feeCollector,swapper,allocator
    erc20Metadata: string[],
    inputs: string[],
    inputWeights: number[],
    rewardTokens: string[]
}
