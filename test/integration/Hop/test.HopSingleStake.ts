import { ethers, network, provider, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { Fees, IStrategyDeploymentEnv, IStrategyBaseParams, IStrategyPythParams, IStrategyChainlinkParams } from "../../../src/types";
import addresses from "../../../src/implementations/Hop/addresses";
import pythIds from "../../../src/pyth-feed-ids.json";
import chainlinkOracles from "../../../src/chainlink-oracles.json";
import { deposit, invest, liquidate, requestWithdraw, seedLiquidity, setupStrat, swapDeposit, withdraw } from "../flows";
import { addressZero, ensureFunding, getEnv, isLive } from "../utils";

const contract = "HopSingleStake";
const underlyingSymbol = "USDC"; // Strategy underlying
const version = 1; // Strategy version
const inputSymbols: string[] = ["WETH"]; // "USDC", "DAI", "USDT" // Strategy input.s
const seedLiquidityUsd = 10; // Seed liquidity in USD

let env: IStrategyDeploymentEnv;

describe(`test.${contract}.${underlyingSymbol}`, function () {
  this.beforeAll(async function () {});
  this.afterAll(async function () {
    // revert blockchain state to before the tests (eg. healthy balances and pool liquidity)
    if (env?.revertState) await revertNetwork(env.snapshotId);
  });

  beforeEach(async function () {});

  let i = 0;
  for (const inputSymbol of inputSymbols) {
    // Naming strat
    const addr = addresses[network.config.chainId!];
    const protocolAddr = addr[`Hop.${inputSymbol}`];
    const strategyName = `Astrolab ${contract} ${inputSymbol}`;
    const symbol = `as.hss${inputSymbol}`;

    if (!protocolAddr) {
      console.error(`Hop.${inputSymbol} addresses not found for network ${network.name} (${network.config.chainId})`);
      continue;
    }
    describe(`Test ${++i}: ${strategyName} ${underlyingSymbol}->${inputSymbol}`, function () {
      this.beforeAll("Deploy and setup strat", async function () {

        env = await getEnv({
          revertState: false
        }, addresses) as IStrategyDeploymentEnv;

        // load environment+deploy+verify the strategy stack
        env = await setupStrat(
          contract,
          strategyName,
          [[strategyName, symbol, version.toString()]], // constructor (Erc20Metadata)
          [{
            // base params
            fees: {} as Fees, // fees (use default)
            underlying: addr.tokens[underlyingSymbol], // underlying
            coreAddresses: [], // coreAddresses (use default)
            inputs: [addr.tokens[inputSymbol]], // inputs
            inputWeights: [10_000], // inputWeights in bps (100% on input[0])
            rewardTokens: protocolAddr.rewardTokens, // rewardTokens
          }, {
            // chainlink oracle params
            underlyingPriceFeed: (chainlinkOracles as any)[network.config.chainId!][`Crypto.${underlyingSymbol}/USD`],
            inputPriceFeeds: [(chainlinkOracles as any)[network.config.chainId!][`Crypto.${inputSymbol}/USD`]],
          }, {
            // hop params
            lpToken: protocolAddr.lp, // hop lp token
            rewardPool: protocolAddr.rewardPools[0], // hop reward pool
            stableRouter: protocolAddr.swap, // hop stable swap pool
            tokenIndex: 0, // hop tokenIndex
          }] as IStrategyChainlinkParams,
          seedLiquidityUsd, // seed liquidity in USD
          ["AsAccounting", "AsMaths"], // libraries to link and verify with the strategy
          env // deployment environment
        );

        assert(env.deployment.strat.address && env.deployment.strat.address !== addressZero, "Strat not deployed");
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
  }
});
