import { ethers, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { IHopStrategyV5 } from "src/implementations/Hop/types";
import { IStrategyDeploymentEnv } from "src/types";
import addresses from "../../../src/implementations/KyberSwap/addresses";
import { deposit, ensureFunding, invest, liquidate, seedLiquidity, setupStrat, swapDeposit, withdraw } from "../flows";
import { addressZero, getEnv } from "../utils";
import { IKyberSwapStrategyV5 } from "src/implementations/KyberSwap/types";

const inputSymbols: string[][] = [["USDC", "USDT"]];
const underlyingSymbol = "USDC";

let env: IStrategyDeploymentEnv;

describe("test.strategy.kyberswap", function () {
  this.beforeAll(async function () {});
  this.afterAll(async function () {
    // revert blockchain state to before the tests (eg. healthy balances and pool liquidity)
    if (env.revertState) await revertNetwork(env.snapshotId);
  });

  beforeEach(async function () {});

  let i = 0;
  for (const pair of inputSymbols) {

    const ksAddresses = env.addresses[`KyberSwap.${pair.join("-")}`];
    if (!ksAddresses) {
      console.error(`KyberSwap.${pair.join("-")} addresses not found for network ${env.network.name} (${env.network.config.chainId})`);
      continue;
    }
    describe(`Test ${++i}: KyberSwap ${pair}`, function () {
      this.beforeAll("Deploy and setup strat", async function () {

        // load environment+deploy+verify the strategy stack
        env = await getEnv({}, addresses) as IStrategyDeploymentEnv;
        env = await setupStrat(
          "KyberSwapStrategy",
          `Astrolab KyberSwap ${pair.join("-")}`,
          "init((uint64,uint64,uint64,uint64),address,address[4],address[],uint256[],address[],address,address,address,address,address)",
          {
            underlying: env.addresses.tokens[underlyingSymbol],
            erc20Metadata: [name, `as.ks${pair.join("")}`, "1"],
            inputs: pair.map(s => env.addresses.tokens[s]) as string[],
            rewardTokens: [env.addresses.tokens.KNC],
            router: ksAddresses.router,
            elasticLM: ksAddresses.elasticLM,
            tickfeesreader: ksAddresses.tickfeesreader,
            antisnip: ksAddresses.antisnip,
            pool: ksAddresses.pool,
          } as IKyberSwapStrategyV5,
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
