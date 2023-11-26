import { ethers, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { IHopStrategyV5 } from "src/implementations/Hop/types";
import { IStrategyDeploymentEnv } from "src/types";
import addresses from "../../../src/implementations/SyncSwap/addresses";
import { deposit, ensureFunding, invest, liquidate, seedLiquidity, setupStrat, swapDeposit, withdraw } from "../flows";
import { addressZero, getEnv } from "../utils";
import { ISyncSwapStrategyV5 } from "src/implementations/SyncSwap/types";

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

    const ssAddresses = env.addresses[`SyncSwap.${pair.join("-")}`];
    if (!ssAddresses) {
      console.error(`SyncSwap.${pair.join("-")} addresses not found for network ${env.network.name} (${env.network.config.chainId})`);
      continue;
    }
    describe(`Test ${++i}: SyncSwap ${pair}`, function () {
      this.beforeAll("Deploy and setup strat", async function () {

        // load environment+deploy+verify the strategy stack
        env = await getEnv({}, addresses) as IStrategyDeploymentEnv;
        env = await setupStrat(
          "SyncSwapStrategy",
          `Astrolab SyncSwap ${pair.join("-")}`,
          "init((uint64,uint64,uint64,uint64),address,address[4],address[],uint256[],address[],address,address,address,address,address)",
          {
            underlying: env.addresses.tokens[underlyingSymbol],
            erc20Metadata: [name, `as.ss${pair.join("")}`, "1"],
            inputs: pair.map(s => env.addresses.tokens[s]) as string[],
            rewardTokens: [env.addresses.tokens.KNC],
            router: ssAddresses.router,
            pool: ssAddresses.pool,
          } as ISyncSwapStrategyV5,
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
