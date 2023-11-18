import { IStrategyV5 } from "../../types";

export interface ISparkStrategyV5 extends IStrategyV5 {
    iouToken: string;
    pool: string;
}
