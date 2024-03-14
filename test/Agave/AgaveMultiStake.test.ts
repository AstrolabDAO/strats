import { ethers, network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";
import { BigNumber } from "ethers";
import chainlinkOracles from "../../src/chainlink-oracles.json";
import addresses from "../../src/implementations/Agave/addresses";
import { Fees, IStrategyDeploymentEnv, IStrategyDesc } from "../../src/types";
import { abiEncode, getEnv } from "../utils";
import { IFlow, testFlow } from "../flows";
import { setupStrat } from "../flows/StrategyV5";
import { suite } from "../StrategyV5.test";

// strategy description to be converted into test/deployment params
const baseDesc: IStrategyDesc = {
  name: `Astrolab Agave USD`,
  symbol: `apAGMS`,
  version: 1,
  contract: "AgaveMultiStake",
  asset: "USDC",
  seedLiquidityUsd: 10,
} as IStrategyDesc;

// strategy description to be converted into test/deployment params
const descByChainId: { [chainId: number]: IStrategyDesc } = {
  100: { ...baseDesc, inputs: ["USDC", "USDT", "WXDAI"], inputWeights: [3400, 3300, 3300] },
};

const desc = descByChainId[network.config.chainId!];

describe(`test.${desc.name}`, () => {

  const addr = addresses[network.config.chainId!];
  const protocolAddr = addr.Agave;
  // const protocolAddr: { [name: string]: string }[] = <any>desc.inputs.map(i => addr.Agave[i]);

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
      [
        {
          // base params
          erc20Metadata: { name: desc.name, symbol: desc.symbol }, // erc20Metadata
          coreAddresses: { asset: addr.tokens[desc.asset] }, // coreAddresses (use default)
          fees: {} as Fees, // fees (use default)
          inputs: desc.inputs.map(i => addr.tokens[i]), // inputs
          inputWeights: desc.inputWeights, // inputWeights in bps (100% on input[0])
          lpTokens: desc.inputs.map(input => addr.Agave[`ag${input}`]), // LP tokens
          rewardTokens: protocolAddr.rewardTokens, // GNO/AGVE
        }, {
          // chainlink oracle params
          assetPriceFeed: oracles[`Crypto.${desc.asset}/USD`],
          inputPriceFeeds: desc.inputs.map(i => oracles[`Crypto.${i}/USD`]),
        },
        // strategy specific params
        abiEncode(["address", "address", "address"], [
          protocolAddr.LendingPoolAddressesProvider,
          protocolAddr.BalancerVault,
          protocolAddr.RewardPoolId,
        ])
      ],
      desc.seedLiquidityUsd, // seed liquidity in USD
      ["AsAccounting"], // libraries to link and verify with the strategy
      env, // deployment environment
      false, // force verification (after deployment)
    );
  });
  describe("Test flow", async () => {
    (suite as IFlow[]).map(f => {
      it(`Test ${f.fn.name}`, async () => { f.env = env; assert(await testFlow(f)); });
    });
  });
});
