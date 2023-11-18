import { IStrategyV5 } from "../../types";

export interface ISyncswapStrategyV5 extends IStrategyV5 {
    router: string;
    pool: string;
}
