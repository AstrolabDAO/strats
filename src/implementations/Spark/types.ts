import { IStrategyV5Params } from "../../types";

export interface ISparkStrategyV5 extends IStrategyV5Params {
    iouToken: string;
    pool: string;
}
