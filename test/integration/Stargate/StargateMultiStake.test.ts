import { network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import addresses from "../../../src/implementations/Stargate/addresses";
import stakingIdsByNetwork from "../../../src/implementations/Stargate/staking-ids.json";
import { Fees, IStrategyDeploymentEnv, IStrategyDesc } from "../../../src/types";
import { suite } from "../StrategyV5.test";
import { IFlow, testFlow } from "../flows";
import { setupStrat } from "../flows/StrategyV5";
import { abiEncode, getEnv } from "../utils";

const baseDesc: IStrategyDesc = {
  name: `Astrolab Primitive Stargate USD`,
  symbol: `apSTG.USD`,
  asset: "USDC",
  version: 1,
  contract: "Stargate",
  seedLiquidityUsd: 10,
} as IStrategyDesc;

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  10: { ...baseDesc, inputs: ["USDCe", "USDT", "DAI"], inputWeights: [3000, 4000, 2000] }, // 90% allocation, 10% cash
  50: { ...baseDesc, inputs: ["USDT"], inputWeights: [9000] },
  137: { ...baseDesc, inputs: ["USDCe", "USDT", "DAI"], inputWeights: [3000, 4000, 2000] },
  8453: { ...baseDesc, inputs: ["USDbC", "WETH"], inputWeights: [4500, 4500] },
  42161: { ...baseDesc, inputs: ["USDCe", "USDT"], inputWeights: [4500, 4500] },
  43114: { ...baseDesc, inputs: ["USDCe", "USDT"], inputWeights: [4500, 4500] },
};

const desc = descByChainId[network.config.chainId!];

describe(`test.${desc.name}`, () => {
  const addr = addresses[network.config.chainId!];
  const protocolAddr: { [name: string]: any } = <any>addr.Stargate;
  const stakingIds = (<any>stakingIdsByNetwork)[network.config.chainId!];
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
      {
        // base params
        erc20Metadata: { name: desc.name, symbol: desc.symbol }, // erc20Metadata
        coreAddresses: { asset: addr.tokens[desc.asset] }, // coreAddresses (use default)
        fees: {} as Fees, // fees (use default)
        inputs: desc.inputs.map((i) => addr.tokens[i]), // inputs
        inputWeights: desc.inputWeights, // inputWeights in bps (100% on input[0])
        lpTokens: desc.inputs.map((i) => protocolAddr.Pool[i]), // lp tokens
        rewardTokens: [addr.tokens.STG],
        extension: abiEncode( // strategy specific params
          ["address", "uint16[]"],
          [
            protocolAddr.LPStaking ?? protocolAddr.LPStakingTime, // staking contract
            desc.inputs.map((i) => stakingIds[i]), // staking ids
          ],
        ),
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
