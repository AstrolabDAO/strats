import { ethers, network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { Fees, IStrategyDeploymentEnv } from "../../../src/types";
import addresses from "../../../src/implementations/SyncSwap/addresses";
import { deposit, ensureFunding, invest, liquidate, seedLiquidity, setupStrat, swapDeposit, withdraw } from "../flows";
import { addressZero, getEnv } from "../utils";

const inputSymbols: string[][] = [["USDC", "USDT"]];
const underlyingSymbol = "USDC";

let env: IStrategyDeploymentEnv;

describe("test.strategy.syncswap", function () {
  this.beforeAll(async function () {});
  this.afterAll(async function () {
    // revert blockchain state to before the tests (eg. healthy balances and pool liquidity)
    if (env.revertState) await revertNetwork(env.snapshotId);
  });

  beforeEach(async function () {});

  let i = 0;
  for (const pair of inputSymbols) {

    const addr = addresses[network.config.chainId!][`SyncSwap.${pair.join("-")}`];
    const name = `Astrolab SyncSwap ${pair.join("-")}`;
    const symbol = `as.ss${pair.join("")}`;

    if (!addr) {
      console.error(`SyncSwap.${pair.join("-")} addresses not found for network ${network.name} (${network.config.chainId})`);
      continue;
    }
    describe(`Test ${++i}: SyncSwap ${pair}`, function () {
      this.beforeAll("Deploy and setup strat", async function () {

        // load environment+deploy+verify the strategy stack
        env = await getEnv({}, addresses) as IStrategyDeploymentEnv;
        env = await setupStrat(
          "SyncSwapStrategy",
          name,
          [[name, symbol, "1"]],
          [
            {} as Fees, // fees (use default)
            env.addresses.tokens[underlyingSymbol], // underlying
            [], // coreAddresses (use default)
            pair.map(s => env.addresses.tokens[s]) as string[], // inputs
            [50_000, 50_000], // inputWeights (50% on each) TODO: use proper estimates
            [env.addresses.tokens.KNC], // rewardTokens
            addr.router, // syncswap router
            addr.pool, // syncswap pool
          ],
          "init((uint64,uint64,uint64,uint64),address,address[4],address[],uint256[],address[],address,address,address,address,address)",
          env
        );
        assert(env.deployment.strat.address && env.deployment.strat.address !== addressZero, "Strat not deployed");
        await ensureFunding(env);
      });

      it("Seed Liquidity", async function () {
        assert((await seedLiquidity(env)).gt(0), "Failed to seed liquidity");
      });
      it("Deposit", async function () {
        assert((await deposit(env)).gt(0), "Failed to deposit");
      });
      it("Swap+Deposit", async function () {
        assert((await swapDeposit(env)).gt(0), "Failed to swap+deposit");
      });
      it("Invest", async function () {
        assert((await invest(env)).gt(0), "Failed to invest");
      });
      it("Withdraw", async function () {
        assert((await withdraw(env)).gt(0), "Failed to withdraw");
      });
      it("Liquidate", async function () {
        assert((await liquidate(env)).gt(0), "Failed to liquidate");
      });
    });
  }
});
