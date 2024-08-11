import { network, revertNetwork, abiEncode, getEnv } from "@astrolabs/hardhat";
import { assert } from "chai";
import addresses from "../../src/external/Compound/addresses";
import { Fees, IStrategyDeploymentEnv, IStrategyDesc } from "../../src/types";
import { suite } from "./StrategyV5.test";
import { IFlow, testFlow } from "./flows";
import { setupStrat } from "./flows/StrategyV5";

const baseDesc: IStrategyDesc = {
  name: `Astrolab Primitive CompoundV3 USD`,
  symbol: `apCOMP.USD`,
  asset: "USDC",
  version: 1,
  contract: "CompoundV3Optimizer",
  seedLiquidityUsd: 10,
} as IStrategyDesc;

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  1: { ...baseDesc, contract: "CompoundV3L1", inputs: ["USDC", "WETH"], inputWeights: [4500, 4500] }, // 90% allocation, 10% cash
  137: { ...baseDesc, inputs: ["USDCe"], inputWeights: [9000] }, // 90% allocation, 10% cash
  8453: { ...baseDesc, inputs: ["USDC", "USDbC", "WETH"], inputWeights: [3000, 3000, 3000] },
  42161: { ...baseDesc, inputs: ["USDC", "USDCe"], inputWeights: [4500, 4500] },
};

const desc = descByChainId[network.config.chainId!];

describe(`test.${desc.name}`, () => {
  const addr = addresses[network.config.chainId!];
  const protocolAddr: { [name: string]: string }[] = <any>(
    desc.inputs.map((i) => addr.Compound[i])
  );
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
      desc.symbol, // create3 identifier
      {
        // base params
        erc20Metadata: { name: desc.name, symbol: desc.symbol }, // erc20Metadata default to 12 decimals
        coreAddresses: { asset: addr.tokens[desc.asset] }, // coreAddresses (use default)
        fees: {} as Fees, // fees (use default)
        inputs: desc.inputs.map((i) => addr.tokens[i]), // inputs
        inputWeights: desc.inputWeights, // inputWeights in bps (100% on input[0])
        lpTokens: desc.inputs.map((input) => addr.Compound[input].comet), // lpTokens
        rewardTokens: Array.from(
          new Set(protocolAddr.map((i) => i.rewardTokens).flat()),
        ), // keep unique reward token: COMP
        extension: abiEncode(["address"], [addr.Compound.cometRewards]), // strategy specific params
      },
      desc.seedLiquidityUsd, // seed liquidity in USD
      ["AsAccounting"], // "ChainlinkUtils"], // libraries to link and verify with the strategy
      env, // deployment environment
      false, // force verification (after deployment)
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
