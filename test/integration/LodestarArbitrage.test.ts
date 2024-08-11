import { network, revertNetwork, abiEncode, getEnv } from "@astrolabs/hardhat";
import { assert } from "chai";
import addresses from "../../src/external/Lodestar/addresses";
import { Fees, IStrategyDeploymentEnv, IStrategyDesc } from "../../src/types";
import { suite } from "./StrategyV5.test";
import { IFlow, testFlow } from "./flows";
import { setupStrat } from "./flows/StrategyV5";

const baseDesc: IStrategyDesc = {
  name: `Astrolab Primitive: Lodestar Arbitrage USD`,
  symbol: `apUSD-LODE-A-2`,
  asset: "USDC",
  version: 1,
  contract: "LodestarArbitrage",
  seedLiquidityUsd: 10,
} as IStrategyDesc;

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  42161: { ...baseDesc, inputs: ["USDC", "USDCe"], inputWeights: [9200, 0] }, // 90% allocation, 10% cash
};

const desc = descByChainId[network.config.chainId!];

describe(`test.${desc.name}`, () => {
  const addr = addresses[network.config.chainId!];
  const protocolAddr = addr.Lodestar;
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
        lpTokens: desc.inputs.map((input) => protocolAddr[`l${input}`]), // LP tokens
        rewardTokens: protocolAddr.rewardTokens, // LODE+ARB
        extension: abiEncode(["address","address","uint16"], [
          protocolAddr.Unitroller,
          addr.Aave.poolProvider,
          4_00, // 4:1 leverage
        ]),
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
