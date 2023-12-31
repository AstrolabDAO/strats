import { ethers, network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { BigNumber } from "ethers";
import chainlinkOracles from "../../../src/chainlink-oracles.json";
import addresses from "../../../src/implementations/Aave/addresses";
import {
  Fees,
  IStrategyChainlinkParams,
  IStrategyDeploymentEnv,
  IStrategyDesc,
} from "../../../src/types";
import { IFlow, deposit, invest, liquidate, requestWithdraw, seedLiquidity, setupStrat, testFlow, withdraw } from "../flows";
import { ensureFunding, ensureOracleAccess, getEnv } from "../utils";

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  10: {
    name: `Astrolab Aave MetaStable`,
    symbol: `as.AMS`,
    version: 1,
    contract: "AaveMultiStake",
    asset: "USDC",
    inputs: ["USDCe", "USDT", "DAI", "USDC",],
    inputWeights: [1500, 3000, 1500, 3000], // 90% allocation, 10% cash
    seedLiquidityUsd: 10,
  },
  100: {
    name: `Astrolab Aave MetaStable`,
    symbol: `as.AMS`,
    version: 1,
    contract: "AaveMultiStake",
    asset: "USDC",
    inputs: ["USDC", "WXDAI"], // ["DAI", "sUSD", "LUSD", "USDT", "USDC", "USDCe"],
    inputWeights: [4500, 4500], // 90% allocation, 10% cash
    seedLiquidityUsd: 10,
  },
  137: {
    name: `Astrolab Aave MetaStable`,
    symbol: `as.AMS`,
    version: 1,
    contract: "AaveMultiStake",
    asset: "USDC",
    inputs: ["USDCe", "USDT", "DAI"],
    inputWeights: [3000, 3000, 3000], // 90% allocation, 10% cash
    seedLiquidityUsd: 10,
  },
  8453: {
    name: `Astrolab Aave MetaStable`,
    symbol: `as.AMS`,
    version: 1,
    contract: "AaveMultiStake",
    asset: "USDC",
    inputs: ["USDC", "USDbC"],
    inputWeights: [7000, 2000], // 90% allocation, 10% cash
    seedLiquidityUsd: 10,
  },
  42161: {
    name: `Astrolab Aave MetaStable`,
    symbol: `as.AMS`,
    version: 1,
    contract: "AaveMultiStake",
    asset: "USDC",
    inputs: ["USDC", "USDCe", "USDT", "DAI", "LUSD", "FRAX"],
    inputWeights: [1500, 1500, 1500, 1500, 1500, 1500], // 90% allocation, 10% cash
    seedLiquidityUsd: 10,
  },
  43114: {
    name: `Astrolab Aave MetaStable`,
    symbol: `as.AMS`,
    version: 1,
    contract: "AaveMultiStake",
    asset: "USDC",
    inputs: ["USDC", "USDT", "DAI"],
    inputWeights: [2500, 4000, 2500], // 90% allocation, 10% cash
    seedLiquidityUsd: 10,
  },
};

const desc = descByChainId[network.config.chainId!];

const testFlows: Partial<IFlow>[] = [
  { fn: seedLiquidity, params: [10], assert: (n: BigNumber) => n.gt(0) },
  { fn: deposit, params: [5], assert: (n: BigNumber) => n.gt(0) },
  { fn: invest, params: [], assert: (n: BigNumber) => n.gt(0) },
  // { fn: liquidate, params: [10], assert: (n: BigNumber) => n.gt(0) },
  // { fn: withdraw, params: [9.9], assert: (n: BigNumber) => n.gt(0) },
  // { fn: requestWithdraw, params: [200], assert: (n: BigNumber) => n.gt(0) },
  // { fn: liquidate, params: [], assert: (n: BigNumber) => n.gt(0) },
  // { elapsedSec: 30, fn: withdraw, params: [100], assert: (n: BigNumber) => n.gt(0) },
  // { fn: withdraw, params: [100], assert: (n: BigNumber) => n.gt(0) },
  // { elapsedSec: 60*60*24*7, revertState: true, fn: harvest, params: [], assert: (n: BigNumber) => n.gt(0) },
  // { elapsedSec: 60*60*24*7, revertState: true, fn: compound, params: [], assert: (n: BigNumber) => n.gt(0) },
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
          erc20Metadata: { name: desc.name, symbol: desc.symbol, decimals: 8 }, // erc20Metadata
          coreAddresses: { asset: addr.tokens[desc.asset] }, // coreAddresses (use default)
          fees: {} as Fees, // fees (use default)
          inputs: desc.inputs.map((i) => addr.tokens[i]), // inputs
          inputWeights: desc.inputWeights, // inputWeights in bps (100% on input[0])
          rewardTokens: [],
        },
        {
          // chainlink oracle params
          assetPriceFeed: oracles[`Crypto.${desc.asset}/USD`],
          inputPriceFeeds: desc.inputs.map((i) => oracles[`Crypto.${i}/USD`]),
        },
        {
          // strategy specific params
          poolProvider: protocolAddr.poolProvider,
          aTokens: desc.inputs.map((i) => protocolAddr[i].aToken),
        },
      ] as IStrategyChainlinkParams,
      desc.seedLiquidityUsd, // seed liquidity in USD
      ["AsMaths", "AsAccounting", "ChainlinkUtils"], // libraries to link and verify with the strategy
      env, // deployment environment
      false // force verification (after deployment)
    );
    assert(
      ethers.utils.isAddress(env.deployment.strat.address),
      "Strat not deployed"
    );
    // ensure deployer account is funded if testing
    await ensureFunding(env);
    await ensureOracleAccess(env);
  });
  describe("Test flow", async () => {
    (testFlows as IFlow[]).map((f) => {
      it(`Test ${f.fn.name}`, async () => {
        f.env = env;
        assert(await testFlow(f));
      });
    });
  });
});
