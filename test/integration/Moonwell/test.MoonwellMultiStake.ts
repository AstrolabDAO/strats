import { ethers, network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { BigNumber } from "ethers";
import chainlinkOracles from "../../../src/chainlink-oracles.json";
import addresses from "../../../src/implementations/Moonwell/addresses";
import { Fees, IStrategyChainlinkParams, IStrategyDeploymentEnv, IStrategyDesc } from "../../../src/types";
import { IFlow, acceptRoles, deposit, grantRoles, harvest, invest, liquidate, requestRescue, requestWithdraw, rescue, emptyStrategy, revokeRoles, seedLiquidity, setupStrat, testFlow, withdraw } from "../flows";
import { ensureFunding, ensureOracleAccess, getEnv, signerAddressGetter, signerGetter } from "../utils";

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  8453: {
    name: `Astrolab Moonwell MetaStable`,
    symbol: `as.MMS`,
    version: 1,
    contract: "MoonwellMultiStake",
    asset: "USDC",
    inputs: ["USDC", "DAI", "USDbC"],
    inputWeights: [3000, 3000, 3000], // 90% allocation, 10% cash
    seedLiquidityUsd: 10
  },
  1284: {
    name: `Astrolab Moonwell MetaStable`,
    symbol: `as.MMS`,
    version: 1,
    contract: "MoonwellLegacyMultiStake",
    asset: "USDC",
    inputs: ["USDC", "FRAX", "xcUSDT"],
    inputWeights: [3000, 3000, 3000], // 90% allocation, 10% cash
    seedLiquidityUsd: 10
  }
};

const desc = descByChainId[network.config.chainId!];

const testFlows: Partial<IFlow>[] = [
  // { fn: seedLiquidity, params: [10], assert: (n: BigNumber) => n.gt(0) },
  // { fn: deposit, params: [4], assert: (n: BigNumber) => n.gt(0) },
  // { fn: invest, params: [], assert: (n: BigNumber) => n.gt(0) },
  // { fn: liquidate, params: [8], assert: (n: BigNumber) => n.gt(0) },
  // { fn: withdraw, params: [5], assert: (n: BigNumber) => n.gt(0) },
  // { fn: requestWithdraw, params: [18], assert: (n: BigNumber) => n.gt(0) },
  // { fn: liquidate, params: [1], assert: (n: BigNumber) => n.gt(0) },
  // { fn: withdraw, params: [17], assert: (n: BigNumber) => n.gt(0) },
  // { fn: harvest, params: [], assert: (n: BigNumber) => n.gt(0) },
  // liquidate usually lowers the sharePrice, we hence can't withdraw the full requestWithdraw amount (eg. [10]->[10]), full amounts can be tested with requestRedeem[10]->redeem[10]
  // { elapsedSec: 30, revertState: true, fn: withdraw, params: [10], assert: (n: BigNumber) => n.gt(0) },
  // { elapsedSec: 60*60*24*14, revertState: true, fn: harvest, params: [], assert: (n: BigNumber) => n.gt(0) },
  // { elapsedSec: 60*60*24*7, revertState: true, fn: compound, params: [], assert: (n: BigNumber) => n.gt(0) },
  { fn: emptyStrategy, params: [], assert: (n: BigNumber) => n.gt(0) },
];

describe(`test.${desc.name}`, () => {

  const addr = addresses[network.config.chainId!];
  const protocolAddr = addr.Moonwell;
  // const protocolAddr: { [name: string]: string }[] = <any>desc.inputs.map(i => addr.Moonwell[i]);
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
        rewardTokens: protocolAddr.rewardTokens, // WELL/GLMR/MOVR/MFAM
      }, {
        // chainlink oracle params
        assetPriceFeed: oracles[`Crypto.${desc.asset}/USD`],
        inputPriceFeeds: desc.inputs.map(i => oracles[`Crypto.${i}/USD`]),
      }, {
        // strategy specific params
        mTokens: desc.inputs.map(input => addr.Moonwell[`m${input}`]),
        unitroller: protocolAddr.Comptroller,
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
