import { IStrategyV5 } from "../../types";

export interface IKyberswapStrategyV5 extends IStrategyV5 {
    router: string;
    elasticLM: string;
    tickfeesreader: string;
    antisnip: string;
    pool: string;
}
