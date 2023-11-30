import { ethers, network, provider, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { Fees, IStrategyDeploymentEnv } from "../../../src/types";
import addresses from "../../../src/implementations/Hop/addresses";
import { deposit, invest, liquidate, requestWithdraw, seedLiquidity, setupStrat, swapDeposit, withdraw } from "../flows";
import { addressZero, ensureFunding, getEnv, isLive } from "../utils";

const inputSymbols: string[] = ["USDC"]; // "DAI", "USDT"];
const underlyingSymbol = "USDC";

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
          "init((uint64,uint64,uint64,uint64),address,address[3],address[],uint256[],address[],address,address,address,uint8)",
          env
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
      //   assert((await swapDeposit(env)).gt(0), "Failed to swap+deposit");
      // });
      it("Invest", async function () {
        assert((await invest(env, 10)).gt(0), "Failed to invest");
      });
      it("Liquidate (just enough for normal withdraw)", async function () {
        assert((await liquidate(env, 2.1)).gt(0), "Failed to liquidate");
      });
      it("Withdraw", async function () {
        assert((await withdraw(env, 2)).gt(0), "Failed to withdraw");
      });
      it("Request Withdraw", async function () {
        assert((await requestWithdraw(env, 5)).gt(0), "Failed to request withdraw");
      });
      it("Liquidate (0+pending requests)", async function () {
        assert((await liquidate(env, 0)).gt(0), "Failed to request withdraw");
      });
      it("Withdraw", async function () {
        // jump to a new block (1 week later)
        const params = [ethers.utils.hexValue(7 * 24 * 60 * 60)];
        if (!isLive(env))
          await provider.send('evm_increaseTime', params)
        assert((await withdraw(env, 5)).gt(0), "Failed to withdraw");
      });
    });
  }
});
