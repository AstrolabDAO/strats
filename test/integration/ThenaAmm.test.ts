import { network, revertNetwork, abiEncode, getEnv, packBy } from "@astrolabs/hardhat";
import { assert } from "chai";
import addresses from "../../src/implementations/Thena/addresses";
import { Fees, IStrategyDeploymentEnv, IStrategyDesc } from "../../src/types";
import { suite } from "./StrategyV5.test";
import { IFlow, testFlow } from "./flows";
import { setupStrat } from "./flows/StrategyV5";

const baseDesc: IStrategyDesc = {
  name: `Astrolab Primitive Thena USD`,
  symbol: `apUSD-THE-O`,
  asset: "USDC",
  version: 1,
  contract: "ThenaAmm",
  seedLiquidityUsd: 10,
} as IStrategyDesc;

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  56: { ...baseDesc, inputs: ["USDT", "USDC"], inputWeights: [9200, 0] }, // 92% allocation, 8% cash
};

const desc = descByChainId[network.config.chainId!];

describe(`test.${desc.name}`, () => {
  const addr = addresses[network.config.chainId!];
  const protocolAddr = addr.Thena!;
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
    const pools = <string[]>packBy(desc.inputs, 2).map((pair) => protocolAddr.algebraPools[pair.join("")]);
    const hypervisors = pools.map((pool) => protocolAddr.hypervisorByPool[pool]);
    const gauges = hypervisors.map((hypervisor) => protocolAddr.gaugeByHypervisor[hypervisor]);
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
        lpTokens: hypervisors, // lpTokens
        rewardTokens: protocolAddr.rewardTokens, // THE/WBNB
        extension: abiEncode(["address","address","address[]"], [
          protocolAddr.uniProxy,
          protocolAddr.voterV3Proxy,
          gauges,
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
