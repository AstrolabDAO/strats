import { IStrategyV5Params } from "../../types";

export interface IAaveV3StrategyV5 extends IStrategyV5Params {
    iouToken: string;
    pool: string;
}
