import { IStrategyV5 } from "../../types";

export interface IAaveV3StrategyV5 extends IStrategyV5 {
    iouToken: string;
    pool: string;
}
