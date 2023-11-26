import { IStrategyV5Params } from "../../types";

export interface ISyncSwapStrategyV5 extends IStrategyV5Params {
    router: string;
    pool: string;
}
