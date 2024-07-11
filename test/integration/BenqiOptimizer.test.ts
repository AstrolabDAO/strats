import { network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import addresses from "../../src/implementations/Benqi/addresses";
import {
  Fees,
  IStrategyDeploymentEnv,
  IStrategyDesc,
} from "../../src/types";
import { suite } from "./StrategyV5.test";
import { IFlow, testFlow } from "./flows";
import { setupStrat } from "./flows/StrategyV5";
import { abiEncode, getEnv } from "../utils";

const baseDesc: IStrategyDesc = {
  name: `Astrolab Primitive Benqi USD`,
  symbol: `apBENQI.USD`,
  version: 1,
  contract: "BenqiOptimizer",
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
        erc20Metadata: { name: desc.name, symbol: desc.symbol }, // erc20Metadata
        coreAddresses: { asset: addr.tokens[desc.asset] }, // coreAddresses (use default)
        fees: {} as Fees, // fees (use default)
        inputs: desc.inputs.map((i) => addr.tokens[i]), // inputs
        inputWeights: desc.inputWeights, // inputWeights in bps (100% on input[0])
        lpTokens: desc.inputs.map((input) => addr.Benqi[`qi${input}`]), // LP tokens
        rewardTokens: protocolAddr.rewardTokens, // QI/WAVAX
        extension: abiEncode(["address"], [protocolAddr.Comptroller]), // strategy specific params
      },
      desc.seedLiquidityUsd, // seed liquidity in USD
      ["AsAccounting"], // libraries to link and verify with the strategy
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
