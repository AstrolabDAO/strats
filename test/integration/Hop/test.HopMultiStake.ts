import { ethers, network, provider, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import chainlinkOracles from "../../../src/chainlink-oracles.json";
import addresses from "../../../src/implementations/Hop/addresses";
import { Fees, IStrategyChainlinkParams, IStrategyDeploymentEnv } from "../../../src/types";
import { deposit, invest, liquidate, requestWithdraw, seedLiquidity, setupStrat, withdraw } from "../flows";
import { addressZero, ensureFunding, getEnv, isLive } from "../utils";
import { utils  as ethersUtils } from "ethers";
import { NetworkAddresses } from "src/addresses";

// strategy metadata
const strategyName = `Astrolab Hop TriStable`;
const symbol = `as.HTS`;
const version = 1;

// strategy params
const contract = "HopMultiStake";
const underlying = "USDC";
const inputs = ["USDC", "DAI", "USDT"];
const weights = [3_000, 3_000, 3_000]; // 90% allocation, 10% cash
const seedLiquidityUsd = 10;

const addr = addresses[network.config.chainId!];
const hopAddresses = <any>inputs.map(i => addr[`Hop.${i}`]) as NetworkAddresses;

let env: IStrategyDeploymentEnv;

describe(`test.${strategyName}`, () => {

  beforeEach(async function () {});

  after(async function () {
    // revert blockchain state to before the tests (eg. healthy balances and pool liquidity)
    if (env?.revertState) await revertNetwork(env.snapshotId);
  });

  before("Deploy and setup strat", async function () {

    env = await getEnv({ revertState: false }, addresses) as IStrategyDeploymentEnv;

    // load environment+deploy+verify the strategy stack
    env = await setupStrat(
      contract,
      strategyName,
      [[strategyName, symbol, version.toString()]], // constructor (Erc20Metadata)
      [{
        // base params
        fees: {} as Fees, // fees (use default)
        underlying: addr.tokens[underlying], // underlying
        coreAddresses: [], // coreAddresses (use default)
        inputs: inputs.map(i => addr.tokens[i]), // inputs
        inputWeights: weights, // inputWeights in bps (100% on input[0])
        rewardTokens: inputs.map((i: string) => hopAddresses[i]!.rewardTokens).flat(), // rewardTokens
      }, {
        // chainlink oracle params
        underlyingPriceFeed: (<any>chainlinkOracles)[network.config.chainId!][`Crypto.${underlying}/USD`],
        inputPriceFeeds: inputs.map(i => (<any>chainlinkOracles)[network.config.chainId!][`Crypto.${i}/USD`]),
      }, {
        // strategy specific params
        lpTokens: inputs.map(i => hopAddresses[i]!.lp),
        rewardPools: inputs.map(i => hopAddresses[i]!.rewardPools[0]), // hop reward pool
        stableRouters: inputs.map(i => hopAddresses[i]!.swap), // hop stable swap pool
        tokenIndexes: inputs.map(i => 0), // h{INPUT} tokenIndex in pool
      }] as IStrategyChainlinkParams,
      seedLiquidityUsd,
      ["AsAccounting", "AsMaths"], // libraries to link and verify with the strategy
      env // deployment environment
    );

    assert(ethersUtils.isAddress(env.deployment.strat.contract.address), "Strat not deployed");
    await ensureFunding(env);
  });
  it("Seed Liquidity", async function () {
    assert((await seedLiquidity(env, seedLiquidityUsd)).gt(0), "Failed to seed liquidity");
  });
  it("Deposit", async function () {
    assert((await deposit(env, 90)).gt(0), "Failed to deposit");
  });
  // it("Swap+Deposit", async function () {
  //   assert((await swapDeposit(env, 1)).gt(0), "Failed to swap+deposit");
  // });
  it("Invest", async function () {
    assert((await invest(env, 90)).gt(0), "Failed to invest");
  });
  it("Liquidate (just enough for normal withdraw)", async function () {
    assert((await liquidate(env, 250)).gt(0), "Failed to liquidate");
  });
  // test erc4626 (synchronous withdrawals)
  it("Withdraw (erc4626 without request)", async function () {
    assert((await withdraw(env, 10)).gt(0), "Failed to withdraw");
  });
  // test erc7540 (asynchronous withdrawals)
  it("Request Withdraw (if no pending request)", async function () {
    assert((await requestWithdraw(env, 10)).gt(0), "Failed to request withdraw");
  });
  it("Liquidate (0+pending requests)", async function () {
    assert((await liquidate(env, 10)).gt(0), "Failed to liquidate");
  });
  it("Withdraw (using erc7540 claimable request)", async function () {
    // jump to a new block (1 week later)
    if (!isLive(env)) {
      const params = [ethers.utils.hexValue(60)]; // 1min
      await provider.send('evm_increaseTime', params);
    }
    assert((await withdraw(env, 10)).gt(0), "Failed to withdraw");
  });
});
