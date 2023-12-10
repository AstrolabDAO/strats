import { ethers, network, provider, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { BigNumber } from "ethers";
import chainlinkOracles from "../../../src/chainlink-oracles.json";
import addresses from "../../../src/implementations/Aave/addresses";
import { Fees, IStrategyChainlinkParams, IStrategyDeploymentEnv, IStrategyDesc } from "../../../src/types";
import { IFlow, compound, deposit, harvest, invest, liquidate, requestWithdraw, seedLiquidity, setupStrat, testFlow, withdraw } from "../flows";
import { ensureFunding, getEnv, isLive } from "../utils";

// strategy description to be converted into test/deployment params
const desc: IStrategyDesc = {
  name: `Astrolab Aave Metastable`,
  symbol: `as.AAM`,
  version: 1,
  contract: "AaveMultiStake",
  underlying: "USDC",
  inputs: ["DAI", "sUSD", "LUSD", "USDT", "USDC", "USDCe"],
  inputWeights: [2000, 2500, 2000, 2500, 1000, 0], // 90% allocation, 10% cash
  seedLiquidityUsd: 10,
};

const testFlows: Partial<IFlow>[] = [
  { fn: seedLiquidity, params: [10], assert: (n: BigNumber) => n.gt(0) },
  { fn: deposit, params: [9990], assert: (n: BigNumber) => n.gt(0) },
  { fn: invest, params: [], assert: (n: BigNumber) => n.gt(0) },
  { fn: liquidate, params: [11], assert: (n: BigNumber) => n.gt(0) },
  { fn: withdraw, params: [10], assert: (n: BigNumber) => n.gt(0) },
  { fn: requestWithdraw, params: [10], assert: (n: BigNumber) => n.gt(0) },
  { fn: liquidate, params: [10], assert: (n: BigNumber) => n.gt(0) },
  { elapsedSec: 30, revertState: true, fn: withdraw, params: [10], assert: (n: BigNumber) => n.gt(0) },
  { elapsedSec: 60*60*24*7, revertState: true, fn: harvest, params: [], assert: (n: BigNumber) => n.gt(0) },
  { elapsedSec: 60*60*24*7, revertState: true, fn: compound, params: [], assert: (n: BigNumber) => n.gt(0) },
];

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
    env = await getEnv({ revertState: false }, addresses) as IStrategyDeploymentEnv;
    // load environment+deploy+verify the strategy stack
    env = await setupStrat(
      desc.contract,
      desc.name,
      [[desc.name, desc.symbol, desc.version.toString()]], // constructor (Erc20Metadata)
      [{
        // base params
        fees: {} as Fees, // fees (use default)
        underlying: addr.tokens[desc.underlying], // underlying
        coreAddresses: [], // coreAddresses (use default)
        inputs: desc.inputs.map(i => addr.tokens[i]), // inputs
        inputWeights: desc.inputWeights, // inputWeights in bps (100% on input[0])
        rewardTokens: [], // keep unique reward token: HOP
      }, {
        // chainlink oracle params
        underlyingPriceFeed: oracles[`Crypto.${desc.underlying}/USD`],
        inputPriceFeeds: desc.inputs.map(i => oracles[`Crypto.${i}/USD`]),
      }, {
        // strategy specific params
        poolProvider: protocolAddr.poolProvider,
        aTokens: desc.inputs.map(i => protocolAddr[i].aToken),
      }] as IStrategyChainlinkParams,
      desc.seedLiquidityUsd, // seed liquidity in USD
      ["AsMaths", "AsAccounting", "ChainlinkUtils"], // libraries to link and verify with the strategy
      env // deployment environment
    );
    assert(ethers.utils.isAddress(env.deployment.strat.address), "Strat not deployed");
    // ensure deployer account is funded if testing
    await ensureFunding(env);
  });
  describe("Test flow", async () => {
    (testFlows as IFlow[]).map(f => {
      it(`Test ${f.fn.name}`, async () => { f.env = env; await testFlow(f); });
    });
  });
});
