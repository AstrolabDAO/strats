import { IStrategyV5Params } from "../../types";

export interface IHopStrategyV5 extends IStrategyV5Params {
    lpToken: string;
    rewardPool: string;
    stableRouter: string;
    tokenIndex: number;
}
