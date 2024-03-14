import { ethers, network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import chainlinkOracles from "../../src/chainlink-oracles.json";
import addresses from "../../src/implementations/Aave/addresses";
import {
  Fees,
  IStrategyDeploymentEnv,
  IStrategyDesc,
  IStrategyParams,
} from "../../src/types";
import { abiEncode, getEnv } from "../utils";
import { IFlow, testFlow } from "../flows";
import { setupStrat } from "../flows/StrategyV5";
import { suite } from "../StrategyV5.test";

const baseDesc = {
  name: `Astrolab Aave USD`,
  symbol: `apAMS`,
  version: 1,
  contract: "AaveMultiStake",
  asset: "USDC",
  seedLiquidityUsd: 10,
} as IStrategyDesc;

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  10: { ...baseDesc, inputs: ["USDCe", "USDT", "DAI", "USDC",], inputWeights: [1500, 3000, 1500, 3000] }, // 90% allocation, 10% cash
  100: { ...baseDesc, inputs: ["USDC", "WXDAI"], inputWeights: [4500, 4500] },
  137: { ...baseDesc, inputs: ["USDCe", "USDT", "DAI"], inputWeights: [3000, 3000, 3000] },
  8453: { ...baseDesc, inputs: ["USDC", "USDbC"], inputWeights: [7000, 2000] },
  42161: { ...baseDesc, inputs: ["USDC", "USDCe", "USDT", "DAI", "LUSD", "FRAX"], inputWeights: [1500, 1500, 1500, 1500, 1500, 1500] },
  43114: { ...baseDesc, inputs: ["USDC", "USDT", "DAI"], inputWeights: [2500, 4000, 2500] },
};

const desc = descByChainId[network.config.chainId!];

describe(`test.${desc.name}`, () => {
  const addr = addresses[network.config.chainId!];
  const protocolAddr = addr.Aave;
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
      addresses
    )) as IStrategyDeploymentEnv;
    // load environment+deploy+verify the strategy stack
    env = await setupStrat(
      desc.contract,
      desc.name,
      [
        {
          // base params
          erc20Metadata: { name: desc.name, symbol: desc.symbol }, // erc20Metadata
          coreAddresses: { asset: addr.tokens[desc.asset] }, // coreAddresses (use default)
          fees: {} as Fees, // fees (use default)
          inputs: desc.inputs.map((i) => addr.tokens[i]), // inputs
          inputWeights: desc.inputWeights, // inputWeights in bps (100% on input[0])
          lpTokens: desc.inputs.map((i) => protocolAddr[i].aToken), // lpTokens
          rewardTokens: [],
        },
        {
          // chainlink oracle params
          assetPriceFeed: oracles[`Crypto.${desc.asset}/USD`],
          inputPriceFeeds: desc.inputs.map((i) => oracles[`Crypto.${i}/USD`]),
        },
        abiEncode(["address"], [protocolAddr.poolProvider]), // strategy specific params
      ],
      desc.seedLiquidityUsd, // seed liquidity in USD
      ["AsAccounting"], // libraries to link and verify with the strategy
      env, // deployment environment
      false // force verification (after deployment)
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
