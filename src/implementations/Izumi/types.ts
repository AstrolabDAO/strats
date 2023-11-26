import { IStrategyV5Params } from "../../types";

export interface IIzumiStrategyV5 extends IStrategyV5Params {
    iouToken: string;
    pool: string;
}
