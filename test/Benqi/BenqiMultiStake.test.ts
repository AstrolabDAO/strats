import { ethers, network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import chainlinkOracles from "../../src/chainlink-oracles.json";
import addresses from "../../src/implementations/Benqi/addresses";
import { Fees, IStrategyChainlinkParams, IStrategyDeploymentEnv, IStrategyDesc } from "../../src/types";
import { getEnv } from "../utils";
import { IFlow, testFlow } from "../flows";
import { setupStrat } from "../flows/StrategyV5";
import { suite } from "../StrategyV5.test";

const baseDesc: IStrategyDesc = {
    name: `Astrolab Benqi MetaStable`,
    symbol: `as.BEMS`,
    version: 1,
    contract: "BenqiMultiStake",
    asset: "USDC",
    seedLiquidityUsd: 10,
} as IStrategyDesc;

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
    43114: { ...baseDesc, inputs: ["USDC", "USDCe"], inputWeights: [4500, 4500] }, // 90% allocation, 10% cash
};

const desc = descByChainId[network.config.chainId!];

describe(`test.${desc.name}`, () => {
    const addr = addresses[network.config.chainId!];
    const protocolAddr = addr.Benqi;
    // const protocolAddr: { [name: string]: string }[] = <any>desc.inputs.map(i => addr.Benqi[i]);
    const oracles = (<any>chainlinkOracles)[network.config.chainId!];
    let env: IStrategyDeploymentEnv;

    beforeEach(async () => { });
    after(async () => {
        // revert blockchain state to before the tests (eg. healthy balances and pool liquidity)
        if (env?.revertState) await revertNetwork(env.snapshotId);
    });

    before("Deploy and setup strat", async () => {
        env = await getEnv({ revertState: false }, addresses) as IStrategyDeploymentEnv;
        // load environment+deploy+verify the strategy stack
        env = await setupStrat(
            desc.contract,
            desc.name,
            [{
                // base params
                erc20Metadata: { name: desc.name, symbol: desc.symbol, decimals: 8 }, // erc20Metadata
                coreAddresses: { asset: addr.tokens[desc.asset] }, // coreAddresses (use default)
                fees: {} as Fees, // fees (use default)
                inputs: desc.inputs.map(i => addr.tokens[i]), // inputs
                inputWeights: desc.inputWeights, // inputWeights in bps (100% on input[0])
                rewardTokens: protocolAddr.rewardTokens, // QI/WAVAX
            }, {
                // chainlink oracle params
                assetPriceFeed: oracles[`Crypto.${desc.asset}/USD`],
                inputPriceFeeds: desc.inputs.map(i => oracles[`Crypto.${i}/USD`]),
            }, {
                // strategy specific params
                qiTokens: desc.inputs.map(inputs => addr.Benqi[`qi${inputs}`]),
                unitroller: protocolAddr.Comptroller,
            }] as IStrategyChainlinkParams,
            desc.seedLiquidityUsd, // seed liquidity in USD
            ["AsMaths", "AsAccounting", "ChainlinkUtils"], // libraries to link and verify with the strategy
            env, // deployment environment
            false, // force verification (after deployment)
        );
        assert(ethers.utils.isAddress(env.deployment.strat.address), "Strat not deployed");
    });
    describe("Test flow", async () => {
        (suite as IFlow[]).map(f => {
            it(`Test ${f.fn.name}`, async () => { f.env = env; assert(await testFlow(f)); });
        });
    });
});
