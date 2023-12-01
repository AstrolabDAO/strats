import { ethers, network, provider, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { Fees, IStrategyDeploymentEnv, IStrategyBaseParams, IStrategyPythParams } from "../../../src/types";
import addresses from "../../../src/implementations/Hop/addresses";
import pythIds from "../../../src/pyth-ids.json";
import { deposit, invest, liquidate, requestWithdraw, seedLiquidity, setupStrat, swapDeposit, withdraw } from "../flows";
import { addressZero, ensureFunding, getEnv, isLive } from "../utils";

// Strategy underlying
const underlyingSymbol = "USDC";
// Strategy input
const inputSymbols: string[] = ["USDC"]; // "DAI", "USDT"];

let env: IStrategyDeploymentEnv;

describe("test.strategy.hop", function () {
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
    const name = `Astrolab Hop h${inputSymbol}`;
    const symbol = `as.h${inputSymbol}`;

    if (!protocolAddr) {
      console.error(`Hop.${inputSymbol} addresses not found for network ${network.name} (${network.config.chainId})`);
      continue;
    }
    describe(`Test ${++i}: ${name}`, function () {
      this.beforeAll("Deploy and setup strat", async function () {

        env = await getEnv({}, addresses) as IStrategyDeploymentEnv;

        // load environment+deploy+verify the strategy stack
        env = await setupStrat(
          "HopStrategy",
          name,
          [[name, symbol, "1"]], // constructor (Erc20Metadata)
          [{
            // base params
            fees: {} as Fees, // fees (use default)
            underlying: addr.tokens[underlyingSymbol], // underlying
            coreAddresses: [], // coreAddresses (use default)
            inputs: [addr.tokens[inputSymbol]], // inputs
            inputWeights: [10_000], // inputWeights in bps (100% on input[0])
            rewardTokens: protocolAddr.rewardTokens, // rewardTokens
          }, {
            // pyth oracle params
            pyth: addr.oracles!.Pyth, // pyth oracle
            underlyingPythId: (pythIds as any)[`Crypto.${underlyingSymbol}/USD`], // pythId for underlying
            inputPythIds: [(pythIds as any)[`Crypto.${inputSymbol}/USD`]], // pythId for input
          }, {
            // hop params
            lpToken: protocolAddr.lp, // hop lp token
            rewardPool: protocolAddr.rewardPools[0], // hop reward pool
            stableRouter: protocolAddr.swap, // hop stable swap pool
            tokenIndex: 0, // hop tokenIndex
          }] as IStrategyPythParams,
          ["AsAccounting", "PythUtils"], // libraries to link and verify with the strategy
          env // deployment environment
        );

        assert(env.deployment.strat.contract.address && env.deployment.strat.contract.address !== addressZero, "Strat not deployed");
          await ensureFunding(env);
      });
      it("Seed Liquidity", async function () {
        assert((await seedLiquidity(env, 10)).gt(0), "Failed to seed liquidity");
      });
      it("Deposit", async function () {
        assert((await deposit(env, 5)).gt(0), "Failed to deposit");
      });
      // it("Swap+Deposit", async function () {
      //   assert((await swapDeposit(env, 1)).gt(0), "Failed to swap+deposit");
      // });
      it("Invest", async function () {
        assert((await invest(env, 18)).gt(0), "Failed to invest");
      });
      it("Liquidate (just enough for normal withdraw)", async function () {
        assert((await liquidate(env, 10)).gt(0), "Failed to liquidate");
      });
      // test erc4626 (synchronous withdrawals)
      it("Withdraw (erc4626 without request)", async function () {
        assert((await withdraw(env, 9.9)).gt(0), "Failed to withdraw");
      });
      // test erc7540 (asynchronous withdrawals)
      it("Request Withdraw (if no pending request)", async function () {
        assert((await requestWithdraw(env, 5)).gt(0), "Failed to request withdraw");
      });
      it("Liquidate (0+pending requests)", async function () {
        assert((await liquidate(env, 10)).gt(0), "Failed to liquidate");
      });
      it("Withdraw (using erc7540 claimable request)", async function () {
        // jump to a new block (1 week later)
        if (!isLive(env)) {
          const params = [ethers.utils.hexValue(7 * 24 * 60 * 60)];
          await provider.send('evm_increaseTime', params);
        }
        assert((await withdraw(env, 9.9)).gt(0), "Failed to withdraw");
      });
    });
  }
});
