import { IStrategyV5 } from "../../types";

export interface IHopStrategyV5 extends IStrategyV5 {
    lpToken: string;
    rewardPool: string;
    stableRouter: string;
    tokenIndex: number;
}
