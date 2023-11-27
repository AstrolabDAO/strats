import { ethers, network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { Fees, IStrategyDeploymentEnv } from "../../../src/types";
import addresses from "../../../src/implementations/Hop/addresses";
import { deposit, ensureFunding, invest, liquidate, seedLiquidity, setupStrat, swapDeposit, withdraw } from "../flows";
import { addressZero, getEnv } from "../utils";

const inputSymbols: string[] = ["USDC"]; // "DAI", "USDT"];
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
    const addr = addresses[network.config.chainId!][`Hop.${inputSymbol}`];
    const name = `Astrolab Hop h${inputSymbol}`;
    const symbol = `as.h${inputSymbol}`;

    if (!addr) {
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
          [
            {} as Fees, // fees (use default)
            env.addresses.tokens[underlyingSymbol], // underlying
            [], // coreAddresses (use default)
            [env.addresses.tokens[inputSymbol]], // inputs
            [100_000], // inputWeights (100% on input[0])
            addr.rewardTokens, // rewardTokens
            addr.lp, // hop lp token
            addr.rewardPools[0], // hop reward pool
            addr.swap, // hop stable swap pool
            0, // hop tokenIndex
          ],
          // the above arguments should match the below contract init() signature
          "init((uint64,uint64,uint64,uint64),address,address[4],address[],uint256[],address[],address,address,address,uint8)",
          env
        );
        assert(env.deployment.strat.address && env.deployment.strat.address !== addressZero, "Strat not deployed");
        await ensureFunding(env);
      });

      it("Seed Liquidity", async function () {
        assert((await seedLiquidity(env, 50)).gt(0), "Failed to seed liquidity");
      });
      it("Deposit", async function () {
        assert((await deposit(env, 100)).gt(0), "Failed to deposit");
      });
      // it("Swap+Deposit", async function () {
      //   assert((await swapDeposit(env)).gt(0), "Failed to swap+deposit");
      // });
      it("Invest", async function () {
        assert((await invest(env, 100)).gt(0), "Failed to invest");
      });
      it("Liquidate", async function () {
        assert((await liquidate(env, 51)).gt(0), "Failed to liquidate");
      });
      it("Withdraw", async function () {
        assert((await withdraw(env, 50)).gt(0), "Failed to withdraw");
      });
    });
  }
});