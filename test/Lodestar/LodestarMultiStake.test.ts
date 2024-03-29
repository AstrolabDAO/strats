import { ethers, network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import chainlinkOracles from "../../src/chainlink-oracles.json";
import addresses from "../../src/implementations/Lodestar/addresses";
import {
  Fees,
  IStrategyChainlinkParams,
  IStrategyDeploymentEnv,
  IStrategyDesc,
} from "../../src/types";
import { suite } from "../StrategyV5.test";
import { IFlow, testFlow } from "../flows";
import { setupStrat } from "../flows/StrategyV5";

import { getEnv } from "../utils";

const baseDesc: IStrategyDesc = {
  name: `Astrolab Lodestar MetaStable`,
  symbol: `as.LOMS`,
  asset: "USDC",
  version: 1,
  contract: "LodestarMultiStake",
  seedLiquidityUsd: 10,
} as IStrategyDesc;

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  42161: { ...baseDesc, inputs: ["USDC", "USDCe", "USDT", "DAI"], inputWeights: [2250, 2250, 2250, 2250] },
};

const desc = descByChainId[network.config.chainId!];

describe(`test.${desc.name}`, () => {

  const addr = addresses[network.config.chainId!];
  // const protocolAddr: { [name: string]: string }[] = <any>desc.inputs.map(i => addr.Lodestar[i]);
  const protocolAddr = addr.Lodestar;
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
        rewardTokens: protocolAddr.rewardTokens, // LODE/ARB
      }, {
        // chainlink oracle params
        assetPriceFeed: oracles[`Crypto.${desc.asset}/USD`],
        inputPriceFeeds: desc.inputs.map(i => oracles[`Crypto.${i}/USD`]),
      }, {
        // strategy specific params
        lTokens: desc.inputs.map(inputs => addr.Lodestar[`l${inputs}`]),
        unitroller: protocolAddr.Unitroller,
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
