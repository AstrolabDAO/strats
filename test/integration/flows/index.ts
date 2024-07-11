// TODO: move generics to @astrolabs/hardhat

import { ethers } from "hardhat";
import { IStrategyDeploymentEnv } from "../../../src/types";
import { isLive } from "../../utils";

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

  // TODO: move this to @astrolabs/hardhat
  if (!live) {
    if (revertState) snapshotId = await env.provider.send("evm_snapshot", []);
    if (elapsedSec) {
      const timeBefore = new Date(
        (await env.provider.getBlock("latest"))?.timestamp * 1000,
      );
      await env.provider.send("evm_increaseTime", [
        ethers.utils.hexValue(elapsedSec),
      ]);
      if (env.network.name.includes("tenderly")) {
        await env.provider.send("evm_increaseBlocks", ["0x20"]);
      } else { // ganache
        await env.provider.send("evm_mine", []);
      }
      const timeAfter = new Date(
        (await env.provider.getBlock("latest"))?.timestamp * 1000,
      );
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
    const timeBefore = new Date(
      (await env.provider.getBlock("latest"))?.timestamp * 1000,
    );
    await env.provider.send("evm_revert", [snapshotId]);
    const timeAfter = new Date(
      (await env.provider.getBlock("latest"))?.timestamp * 1000,
    );
    console.log(`⏰🔙 Reverted blocktime: ${timeBefore} -> ${timeAfter}`);
  }

  if (assert) assert(result);

  return result;
}
