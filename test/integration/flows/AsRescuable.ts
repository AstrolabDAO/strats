import { TransactionResponse, weiToString, SafeContract, MaybeAwaitable, SignerWithAddress, addressOne, resolveMaybe } from "@astrolabs/hardhat";
import { BigNumber } from "ethers";
import { IStrategyDeploymentEnv } from "../../../src/types";
import {
  fundAccount,
  getOverrides,
  logBalances,
  logRescue
} from "../../utils";

/**
 * Transfers assets to a specified receiver
 * @param env Strategy deployment environment
 * @param amount Amount of assets to transfer
 * @param asset Asset to transfer
 * @param receiver Receiver's address (optional)
 * @returns Boolean indicating whether the transfer was successful
 */
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

/**
 * Requests a rescue for a specific token on a contract (admin only)
 * @param env Strategy deployment environment
 * @param token Token you want to rescue
 * @param signer Signer with address. Defaults to the deployer (rescuer) if not provided
 * @returns Boolean indicating the success of the rescue operation
 */
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

/**
 * Rescues the specified token from the contract after request (admin only)
 * @param env Strategy deployment environment
 * @param token Token you want to rescue
 * @param signer Signer with address. Defaults to the deployer (rescuer)
 * @returns Boolean indicating the success of the rescue operation
 */
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
