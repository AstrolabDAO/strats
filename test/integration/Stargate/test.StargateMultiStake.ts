import { network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import * as ethers from "ethers";
import { BigNumber } from "ethers";
import chainlinkOracles from "../../../src/chainlink-oracles.json";
import addresses from "../../../src/implementations/Stargate/addresses";
import stakingIdsByNetwork from "../../../src/implementations/Stargate/staking-ids.json";
import { Fees, IStrategyChainlinkParams, IStrategyDeploymentEnv, IStrategyDesc } from "../../../src/types";
import { IFlow, deposit, seedLiquidity, setupStrat, testFlow } from "../flows";
import { ensureFunding, ensureOracleAccess, getEnv } from "../utils";

// strategy description to be converted into test/deployment params
const desc: IStrategyDesc = {
  name: `Astrolab Stargate MetaStable`,
  symbol: `as.SMS`,
  version: 1,
  contract: "StargateMultiStake",
  asset: "USDC",
  inputs: ["USDCe", "USDT", "DAI"],
  inputWeights: [3000, 4000, 2000], // 90% allocation, 10% cash
  seedLiquidityUsd: 10,
};

const testFlows: Partial<IFlow>[] = [
  { fn: seedLiquidity, params: [10], assert: (n: BigNumber) => n.gt(0) },
  { fn: deposit, params: [1], assert: (n: BigNumber) => n.gt(0) },
  // { fn: invest, params: [], assert: (n: BigNumber) => n.gt(0) },
  // { fn: liquidate, params: [11], assert: (n: BigNumber) => n.gt(0) },
  // { fn: withdraw, params: [10], assert: (n: BigNumber) => n.gt(0) },
  // { fn: requestWithdraw, params: [10], assert: (n: BigNumber) => n.gt(0) },
  // { fn: liquidate, params: [10], assert: (n: BigNumber) => n.gt(0) },
  // { elapsedSec: 30, revertState: true, fn: withdraw, params: [10], assert: (n: BigNumber) => n.gt(0) },
  // { elapsedSec: 60*60*24*7, revertState: true, fn: harvest, params: [], assert: (n: BigNumber) => n.gt(0) },
  // { elapsedSec: 60*60*24*7, revertState: true, fn: compound, params: [], assert: (n: BigNumber) => n.gt(0) },
];

describe(`test.${desc.name}`, () => {

  const addr = addresses[network.config.chainId!];
  const protocolAddr: { [name: string]: any } = <any>addr.Stargate;
  const stakingIds = (<any>stakingIdsByNetwork)[network.config.chainId!];
  const oracles = (<any>chainlinkOracles)[network.config.chainId!];
  let env: IStrategyDeploymentEnv;

  beforeEach(async () => {});
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
        rewardTokens: [addr.tokens.STG]
      }, {
        // chainlink oracle params
        assetPriceFeed: oracles[`Crypto.${desc.asset}/USD`],
        inputPriceFeeds: desc.inputs.map(i => oracles[`Crypto.${i}/USD`]),
      }, {
        // strategy specific params
        lps: desc.inputs.map(i => protocolAddr.Pool[i]), // hop lp token
        lpStaker: protocolAddr.LPStaking ?? protocolAddr.LPStakingTime,
        stakingIds: desc.inputs.map(i => stakingIds[i]),
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
