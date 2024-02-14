import { ethers, network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import chainlinkOracles from "../../src/chainlink-oracles.json";
import addresses from "../../src/implementations/Compound/addresses";
import {
  Fees,
  IStrategyChainlinkParams,
  IStrategyDeploymentEnv,
  IStrategyDesc,
} from "../../src/types";
import { getEnv } from "../utils";
import { IFlow, testFlow } from "../flows";
import { setupStrat } from "../flows/StrategyV5";
import { suite } from "../StrategyV5.test";

const baseDesc: IStrategyDesc = {
  name: `Astrolab CompoundV3 MetaStable`,
  symbol: `as.CMS`,
  asset: "USDC",
  version: 1,
  contract: "CompoundV3MultiStake",
  seedLiquidityUsd: 10,
} as IStrategyDesc;

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  1: { ...baseDesc, inputs: ["USDC", "WETH"], inputWeights: [4500, 4500] }, // 90% allocation, 10% cash
  137: { ...baseDesc, inputs: ["USDCe"], inputWeights: [9000] }, // 90% allocation, 10% cash
  8453: { ...baseDesc, inputs: ["USDbC"], inputWeights: [9000] },
  42161: { ...baseDesc, inputs: ["USDC", "USDCe"], inputWeights: [4500, 4500] },
};

const desc = descByChainId[network.config.chainId!];

describe(`test.${desc.name}`, () => {
  const addr = addresses[network.config.chainId!];
  const protocolAddr: { [name: string]: string }[] = <any>(
    desc.inputs.map((i) => addr.Compound[i])
  );
  const oracles = (<any>chainlinkOracles)[network.config.chainId!];
  let env: IStrategyDeploymentEnv;

  beforeEach(async () => {});
  after(async () => {
    // revert blockchain state to before the tests (eg. healthy balances and pool liquidity)
    if (env?.revertState) await revertNetwork(env.snapshotId);
  });

  before("Deploy and setup strat", async () => {
    env = (await getEnv(
      { revertState: false },
      addresses,
    )) as IStrategyDeploymentEnv;
    // load environment+deploy+verify the strategy stack
    env = await setupStrat(
      desc.contract,
      desc.name,
      [
        {
          // base params
          erc20Metadata: { name: desc.name, symbol: desc.symbol, decimals: 8 }, // erc20Metadata
          coreAddresses: { asset: addr.tokens[desc.asset] }, // coreAddresses (use default)
          fees: {} as Fees, // fees (use default)
          inputs: desc.inputs.map((i) => addr.tokens[i]), // inputs
          inputWeights: desc.inputWeights, // inputWeights in bps (100% on input[0])
          rewardTokens: Array.from(
            new Set(protocolAddr.map((i) => i.rewardTokens).flat()),
          ), // keep unique reward token: COMP
        },
        {
          // chainlink oracle params
          assetFeed: oracles[`Crypto.${desc.asset}/USD`],
          assetFeedValidity: 86400,
          inputFeeds: desc.inputs.map((i) => oracles[`Crypto.${i}/USD`]),
          inputFeedValidities: desc.inputs.map((i) => 86400),
        },
        {
          // strategy specific params
          cTokens: desc.inputs.map((input) => addr.Compound[input].comet),
          cometRewards: addr.Compound.cometRewards,
        },
      ] as IStrategyChainlinkParams,
      desc.seedLiquidityUsd, // seed liquidity in USD
      ["AsMaths", "AsAccounting", "ChainlinkUtils"], // libraries to link and verify with the strategy
      env, // deployment environment
      false, // force verification (after deployment)
    );
    assert(
      ethers.utils.isAddress(env.deployment.strat.address),
      "Strat not deployed",
    );
  });
  describe("Test flow", async () => {
    (suite as IFlow[]).map((f) => {
      it(`Test ${f.fn.name}`, async () => {
        f.env = env;
        assert(await testFlow(f));
      });
    });
  });
});
