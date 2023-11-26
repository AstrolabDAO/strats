import {
  ethers,
  getDeployer,
  network,
  provider
} from "@astrolabs/hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { erc20Abi } from "abitype/abis";
import { Contract, constants } from "ethers";
import { merge } from "lodash";
import {
  IStrategyDeploymentEnv,
  ITestEnv
} from "src/types";
import addresses, { Addresses } from "../../src/addresses";

export const addressZero = constants.AddressZero;
const MaxUint256 = ethers.constants.MaxUint256;

export async function logState(
  env: Partial<IStrategyDeploymentEnv>,
  step?: string
) {
  const { strat, underlying } = env.deployment!;
  try {
    const stratUnderlyingBalance = await underlying.contract.balanceOf(
      strat.address
    );
    const [
      inputsAddresses,
      rewardTokensAddresses,
      sharePrice,
      totalAssetsAfter,
      invested,
      // stratUnderlyingBalance,
    ] = await Promise.all([
      strat.inputs(0),
      strat.rewardTokens(0),
      strat.sharePrice(),
      strat.totalAssets(),
      strat.invested(),
      // await underlyingTokenContract.balanceOf(strategy.address),
    ]);
    console.log(
      `State ${step ? `after ${step}` : ""}:
      underlying: ${underlying.contract.address}
      inputs: ${inputsAddresses}
      rewardTokens: ${rewardTokensAddresses}
      sharePrice: ${sharePrice}
      totalAssets(): ${totalAssetsAfter}
      invested(): ${invested}
      stratUnderlyingBalance(): ${stratUnderlyingBalance}`
    );
  } catch (e) {
    console.log(`Error logging state ${step ?? ""}: ${e}`);
  }
}

export const getEnv = async (
  env: Partial<ITestEnv> = {},
  addressesOverride?: Addresses
): Promise<ITestEnv> => {
  const addr = (addressesOverride ?? addresses)[network.config.chainId!];
  const wgas = new Contract(addr.tokens.WGAS, erc20Abi, await getDeployer());

  return merge(
    {
      network,
      blockNumber: await provider.getBlockNumber(),
      snapshotId: await provider.send("evm_snapshot", []),
      revertState: false,
      wgas: {
        contract: wgas,
        symbol: await wgas.symbol(),
        decimals: await wgas.decimals(),
        weiPerUnit: 10 ** (await wgas.decimals()),
      },
      addresses: addressesOverride ?? addresses[network.config.chainId!],
      deployer: (await getDeployer()) as SignerWithAddress,
      provider: ethers.provider,
      needsFunding: false,
      gasUsedForFunding: 1e21,
    },
    env
  );
};
