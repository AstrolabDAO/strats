import { TransactionResponse, weiToString } from "@astrolabs/hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { IStrategyDeploymentEnv, MaybeAwaitable, SafeContract } from "../../src/types";
import {
  addressOne,
  fundAccount,
  getOverrides,
  logBalances,
  logRescue,
  resolveMaybe,
} from "../utils";

export async function transferAssetsTo(
  env: Partial<IStrategyDeploymentEnv>,
  amount: number | string | BigNumber,
  asset: string,
  receiver?: string,
): Promise<boolean> {
  amount = weiToString(amount);
  // the proxy receives the swap proceeds, then transfers back to the receiver
  const proxy = await env.deployer!.address;
  // if no receiver, sends it to the strategy
  receiver ??= await env.deployment!.strat.address;
  const token = asset != addressOne ? await SafeContract.build(asset) : asset;

  await logBalances(env, token, receiver, proxy, "Before transferAssetsTo");
  try {
    if (asset == addressOne) {
      await env.deployer!.sendTransaction({
        to: receiver,
        value: amount,
      });
    } else {
      await fundAccount(env, amount, asset, proxy);
      await (token as SafeContract)
        .transfer(receiver, amount, getOverrides(env))
        .then((tx: TransactionResponse) => tx.wait());
    }
    await logBalances(env, token, receiver, proxy, "After transferAssetsTo");
    return true;
  } catch (e) {
    console.error(`transferAssetsTo failed: ${e}`);
    return false;
  }
}

export async function requestRescue(
  env: Partial<IStrategyDeploymentEnv>,
  token: SafeContract,
  signer: MaybeAwaitable<SignerWithAddress> = env.deployer!, // == rescuer
): Promise<boolean> {
  signer = await resolveMaybe(signer);
  const strat = await env.deployment!.strat.copy(signer);
  await logRescue(
    env,
    token,
    signer.address,
    undefined,
    "Before RequestRescue",
  );
  const receipt = await strat
    .requestRescue(token, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  return true;
}

export async function rescue(
  env: Partial<IStrategyDeploymentEnv>,
  token: SafeContract,
  signer: MaybeAwaitable<SignerWithAddress> = env.deployer!, // == rescuer
): Promise<boolean> {
  signer = await resolveMaybe(signer);
  const strat = await env.deployment!.strat.copy(signer);
  await logRescue(env, token, signer.address, undefined, "Before Rescue");
  const receipt = await strat
    .safe("rescue", [token], getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logRescue(env, token, signer.address, undefined, "After Rescue");
  // return getTxLogData(receipt, ["uint256"], 0); // event removed for optimization purposes
  return true;
}
