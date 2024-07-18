import { ethers, isLive, increaseTime, getNetworkTimestamp } from "@astrolabs/hardhat";
import { IStrategyDeploymentEnv } from "../../../src/types";

export interface IFlow {
  elapsedSec: number; // seconds since last block
  revertState: boolean; // revert state after flow
  env: IStrategyDeploymentEnv;
  fn: Function;
  params: any[];
  assert: Function;
}

/**
 * Executes a test flow (suite unit)
 * @param flow - The flow object containing the necessary parameters for the test
 * @returns A promise that resolves with the result of the test flow
 */
export async function testFlow(flow: IFlow): Promise<any> {
  let { env, elapsedSec, revertState, fn, params, assert } = flow;
  const live = isLive(env);

  console.log(
    `Running flow ${fn.name}(${params.join(", ")}, elapsedSec (before): ${
      elapsedSec ?? 0
    }, revertState (after): ${revertState ?? 0})`,
  );
  let snapshotId = 0;

  if (!live) {
    if (revertState) snapshotId = await env.provider.send("evm_snapshot", []);
    if (elapsedSec) {
      const timeBefore = new Date(await getNetworkTimestamp() * 1000);
      await increaseTime(elapsedSec, env);
      const timeAfter = new Date(await getNetworkTimestamp() * 1000);
      console.log(
        `⏰🔜 Advanced blocktime by ${elapsedSec}s: ${timeBefore} -> ${timeAfter}`,
      );
    }
  }
  let result;
  try {
    result = await fn(env, ...params);
  } catch (e) {
    assert = () => false;
    console.error(e);
  }

  // revert the state of the chain to the beginning of this test, not to env.snapshotId
  if (!live && revertState) {
    const timeBefore = new Date(await getNetworkTimestamp() * 1000);
    await env.provider.send("evm_revert", [snapshotId]);
    const timeAfter = new Date(await getNetworkTimestamp() * 1000);
    console.log(`⏰🔙 Reverted blocktime: ${timeBefore} -> ${timeAfter}`);
  }

  if (assert) assert(result);

  return result;
}
