import { IStrategyV5 } from "../../types";

export interface IIzumiStrategyV5 extends IStrategyV5 {
    iouToken: string;
    pool: string;
}
