import { network, revertNetwork, abiEncode, getEnv } from "@astrolabs/hardhat";
import { assert } from "chai";
import addresses from "../../src/implementations/Sonne/addresses";
import { Fees, IStrategyDeploymentEnv, IStrategyDesc } from "../../src/types";
import { suite } from "./StrategyV5.test";
import { IFlow, testFlow } from "./flows";
import { setupStrat } from "./flows/StrategyV5";

const baseDesc: IStrategyDesc = {
  name: `Astrolab Primitive Sonne USD`,
  symbol: `apSONNE.USD`,
  asset: "USDC",
  version: 1,
  contract: "SonneOptimizer",
  seedLiquidityUsd: 10,
} as IStrategyDesc;

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  10: { ...baseDesc,inputs: ["USDCe", "DAI", "USDT"], inputWeights: [3000, 3000, 3000] }, // 90% allocation, 10% cash
  8453: { ...baseDesc,inputs: ["USDC", "USDbC", "DAI"], inputWeights: [3000, 3000, 3000] },
};

const desc = descByChainId[network.config.chainId!];

describe(`test.${desc.name}`, () => {
  const addr = addresses[network.config.chainId!];
  const protocolAddr = addr.Sonne;
  // const protocolAddr: { [name: string]: string }[] = <any>desc.inputs.map(i => addr.Sonne[i]);
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
        lpTokens: desc.inputs.map((input) => addr.Sonne[`so${input}`]), // LP tokens
        rewardTokens: protocolAddr.rewardTokens, // SONNE/OP
        extension: abiEncode(["address"], [protocolAddr.Unitroller]), // strategy specific params
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
