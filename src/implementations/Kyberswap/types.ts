import { IStrategyV5Params } from "../../types";

export interface IKyberSwapStrategyV5 extends IStrategyV5Params {
    router: string;
    elasticLM: string;
    tickfeesreader: string;
    antisnip: string;
    pool: string;
}
