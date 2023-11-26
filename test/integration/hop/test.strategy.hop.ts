import { ethers, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { IHopStrategyV5 } from "src/implementations/Hop/types";
import { IStrategyDeploymentEnv } from "src/types";
import addresses from "../../../src/implementations/Hop/addresses";
import { deposit, ensureFunding, invest, liquidate, seedLiquidity, setupStrat, swapDeposit, withdraw } from "../flows";
import { addressZero, getEnv } from "../utils";

const inputSymbols: string[] = ["USDC", "DAI", "USDT"];
const underlyingSymbol = "USDC";

let env: IStrategyDeploymentEnv;

describe("test.strategy.hop", function () {
  this.beforeAll(async function () {});
  this.afterAll(async function () {
    // revert blockchain state to before the tests (eg. healthy balances and pool liquidity)
    if (env.revertState) await revertNetwork(env.snapshotId);
  });

  beforeEach(async function () {});

  let i = 0;
  for (const inputSymbol of inputSymbols) {
    const hopAddresses = env.addresses[`Hop.${inputSymbol}`];
    if (!hopAddresses) {
      console.error(`Hop.${inputSymbol} addresses not found for network ${env.network.name} (${env.network.config.chainId})`);
      continue;
    }
    describe(`Test ${++i}: Hop ${inputSymbol}`, function () {
      this.beforeAll("Deploy and setup strat", async function () {

        // load environment+deploy+verify the strategy stack
        env = await getEnv({}, addresses) as IStrategyDeploymentEnv;
        env = await setupStrat(
          "HopStrategy",
          `Astrolab Hop h${inputSymbol}`,
          "init((uint64,uint64,uint64,uint64),address,address[4],address[],uint256[],address[],address,address,address,uint8)",
          {
            underlying: env.addresses.tokens[underlyingSymbol],
            erc20Metadata: [name, `as.h${inputSymbol}`, "1"],
            inputs: [env.addresses.tokens[inputSymbol]],
            rewardTokens: [env.addresses.tokens.HOP],
            lpToken: hopAddresses.lp,
            rewardPool: hopAddresses.rewardPools[0],
            stableRouter: hopAddresses.swap,
            tokenIndex: 0,
          } as IHopStrategyV5,
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