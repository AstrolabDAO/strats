import { network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import * as ethers from "ethers";
import { BigNumber } from "ethers";
import chainlinkOracles from "../../../src/chainlink-oracles.json";
import addresses from "../../../src/implementations/Hop/addresses";
import { Fees, IStrategyChainlinkParams, IStrategyDeploymentEnv, IStrategyDesc } from "../../../src/types";
import { IFlow, deposit, seedLiquidity, setupStrat, testFlow } from "../flows";
import { ensureFunding, ensureOracleAccess, getEnv } from "../utils";

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  10: {
    name: `Astrolab Hop MetaStable`,
    symbol: `as.HMS`,
    version: 1,
    contract: "HopMultiStake",
    asset: "USDC",
    inputs: ["USDCe", "USDT", "DAI"],
    inputWeights: [3500, 3500, 2000], // 90% allocation, 10% cash
    seedLiquidityUsd: 10,
  },
  100: {
    name: `Astrolab Hop MetaStable`,
    symbol: `as.HMS`,
    version: 1,
    contract: "HopMultiStake",
    asset: "USDC",
    inputs: ["USDC", "WXDAI", "USDT"],
    inputWeights: [3000, 3000, 3000], // 90% allocation, 10% cash
    seedLiquidityUsd: 10,
  },
  137: {
    name: `Astrolab Hop MetaStable`,
    symbol: `as.HMS`,
    version: 1,
    contract: "HopMultiStake",
    asset: "USDC",
    inputs: ["USDCe"],
    inputWeights: [9000], // 90% allocation, 10% cash
    seedLiquidityUsd: 10,
  },
  42161: {
    name: `Astrolab Hop MetaStable`,
    symbol: `as.HMS`,
    version: 1,
    contract: "HopMultiStake",
    asset: "USDC",
    inputs: ["USDCe", "USDT", "DAI"],
    inputWeights: [3000, 3000, 3000], // 90% allocation, 10% cash
    seedLiquidityUsd: 10,
  },
};

const desc = descByChainId[network.config.chainId!];


const testFlows: Partial<IFlow>[] = [
  { fn: seedLiquidity, params: [10], assert: (n: BigNumber) => n.gt(0) },
  { fn: deposit, params: [1], assert: (n: BigNumber) => n.gt(0) },
  // { fn: invest, params: [], assert: (n: BigNumber) => n.gt(0) },
  // { fn: liquidate, params: [11], assert: (n: BigNumber) => n.gt(0) },
  // { fn: withdraw, params: [10], assert: (n: BigNumber) => n.gt(0) },
  // { fn: requestWithdraw, params: [11], assert: (n: BigNumber) => n.gt(0) },
  // { fn: liquidate, params: [10], assert: (n: BigNumber) => n.gt(0) },
  // liquidate usually lowers the sharePrice, we hence can't withdraw the full requestWithdraw amount (eg. [10]->[10]), full amounts can be tested with requestRedeem[10]->redeem[10]
  // { elapsedSec: 30, revertState: true, fn: withdraw, params: [10], assert: (n: BigNumber) => n.gt(0) },
  // { elapsedSec: 60*60*24*7, revertState: true, fn: harvest, params: [], assert: (n: BigNumber) => n.gt(0) },
  // { elapsedSec: 60*60*24*7, revertState: true, fn: compound, params: [], assert: (n: BigNumber) => n.gt(0) },
];

describe(`test.${desc.name}`, () => {

  const addr = addresses[network.config.chainId!];
  const protocolAddr: { [name: string]: string }[] = <any>desc.inputs.map(i => addr.Hop[i]);
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
        rewardTokens: Array.from(new Set(protocolAddr.map(i => i.rewardTokens).flat())), // keep unique reward token: HOP
      }, {
        // chainlink oracle params
        assetPriceFeed: oracles[`Crypto.${desc.asset}/USD`],
        inputPriceFeeds: desc.inputs.map(i => oracles[`Crypto.${i}/USD`]),
      }, {
        // strategy specific params
        lpTokens: protocolAddr.map(i => i.lp), // hop lp token
        rewardPools: protocolAddr.map(i => i.rewardPools), // hop reward pool
        stableRouters: protocolAddr.map(i => i.swap), // stable swap
        tokenIndexes: desc.inputs.map(i => 0), // h{INPUT} tokenIndex in pool
      }] as IStrategyChainlinkParams,
      desc.seedLiquidityUsd, // seed liquidity in USD
      ["AsMaths", "AsAccounting", "ChainlinkUtils"], // libraries to link and verify with the strategy
      env, // deployment environment
      false, // force verification (after deployment)
    );
    assert(ethers.utils.isAddress(env.deployment.strat.address), "Strat not deployed");
    // ensure deployer account is funded if testing
    await ensureFunding(env);
    await ensureOracleAccess(env);
  });
  describe("Test flow", async () => {
    (testFlows as IFlow[]).map(f => {
      it(`Test ${f.fn.name}`, async () => { f.env = env; assert(await testFlow(f)); });
    });
  });
});
