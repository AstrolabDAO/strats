import { ethers, network, provider, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { utils as ethersUtils } from "ethers";
import chainlinkOracles from "../../../src/chainlink-oracles.json";
import addresses from "../../../src/implementations/Hop/addresses";
import { Fees, IStrategyChainlinkParams, IStrategyDeploymentEnv, IStrategyDesc } from "../../../src/types";
import { deposit, invest, liquidate, requestWithdraw, seedLiquidity, setupStrat, withdraw } from "../flows";
import { ensureFunding, getEnv, isLive } from "../utils";

// strategy description to be converted into test/deployment params
const desc: IStrategyDesc = {
  name: `Astrolab Hop TriStable`,
  symbol: `as.HTS`,
  version: 1,
  contract: "HopMultiStake",
  underlying: "USDC",
  inputs: ["USDC", "WXDAI", "USDT"],
  inputWeights: [3_000, 3_000, 3_000], // 90% allocation, 10% cash
  seedLiquidityUsd: 10,
};

describe(`test.${desc.name}`, () => {

  const addr = addresses[network.config.chainId!];
  const protocolAddr: { [name: string]: string }[] = <any>desc.inputs.map(i => addr[`Hop.${i}`]);
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
      [[desc.name, desc.symbol, desc.version.toString()]], // constructor (Erc20Metadata)
      [{
        // base params
        fees: {} as Fees, // fees (use default)
        underlying: addr.tokens[desc.underlying], // underlying
        coreAddresses: [], // coreAddresses (use default)
        inputs: desc.inputs.map(i => addr.tokens[i]), // inputs
        inputWeights: desc.inputWeights, // inputWeights in bps (100% on input[0])
        rewardTokens: Array.from(new Set(protocolAddr.map(i => i.rewardTokens[0]).flat())), // keep unique reward token: HOP
      }, {
        // chainlink oracle params
        underlyingPriceFeed: oracles[`Crypto.${desc.underlying}/USD`],
        inputPriceFeeds: desc.inputs.map(i => oracles[`Crypto.${i}/USD`]),
      }, {
        // strategy specific params
        lpTokens: protocolAddr.map(i => i.lp), // hop lp token
        rewardPools: protocolAddr.map(i => i.rewardPools[0]), // hop reward pool
        stableRouters: protocolAddr.map(i => i.swap), // stable swap
        tokenIndexes: desc.inputs.map(i => 0), // h{INPUT} tokenIndex in pool
      }] as IStrategyChainlinkParams,
      desc.seedLiquidityUsd, // seed liquidity in USD
      ["AsAccounting", "AsMaths"], // libraries to link and verify with the strategy
      env // deployment environment
    );
    assert(ethersUtils.isAddress(env.deployment.strat.contract.address), "Strat not deployed");
    // ensure deployer account is funded if testing
    await ensureFunding(env);
  });
  it("Seed Liquidity (if required)", async () => assert((await seedLiquidity(env, desc.seedLiquidityUsd)).gt(0)));
  it("Deposit", async () => assert((await deposit(env, 90)).gt(0)));
  // it("Swap+Deposit", async () => assert((await swapDeposit(env, 1)).gt(0)));
  it("Invest", async () => assert((await invest(env, 90)).gt(0)));
  it("Liquidate (for first withdraw)", async () => assert((await liquidate(env, 20)).gt(0)));
  it("Withdraw (ERC4626 without request)", async () => assert((await withdraw(env, 10)).gt(0)));
  // test erc7540 (asynchronous withdrawals)
  it("Request Withdraw (if required)", async () => assert((await requestWithdraw(env, 10)).gt(0)));
  it("Liquidate (0+pending requests)", async () => assert((await liquidate(env, 10)).gt(0)));
  it("Withdraw (using claimable request)", async () => {
    // jump to a new block to unlock request if testing
    if (!isLive(env)) await provider.send('evm_increaseTime', [ethers.utils.hexValue(60)]);
    assert((await withdraw(env, 10)).gt(0));
  });
});
