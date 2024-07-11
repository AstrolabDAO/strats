import { network, revertNetwork } from "@astrolabs/hardhat";
import { assert } from "chai";

import addresses from "../../src/addresses";
import { deployMultisig, getEnv } from "../utils";
import { ITestEnv } from "../../src/types";

const name = "CouncilMultisig";
const owners = [
  "0x026E222AC6aD0BA8AD04efd7BCf6025e40457345",
  "0xaB7Bb2F7E39eaED8e5543220f43fa545ea780760"
];

describe(`test.${name}`, () => {
  const addr = addresses[network.config.chainId!];
  let env: ITestEnv;

  beforeEach(async () => {});
  after(async () => {
    if (env?.revertState) await revertNetwork(env.snapshotId);
  });

  before("Deploy and setup strat", async () => {
    env = await getEnv({ revertState: false }, addresses);
  });
  it("Test flow", async () => {
    const multisig = await deployMultisig(env, name, owners, 1);
    console.log(`Deployed ${name} multisig at ${multisig.address}`);
  });
});
