import { network } from "hardhat";
import { BigNumber } from "ethers";
import addresses from "../src/addresses";
import { IFlow } from "./flows";
import { addressOne, signerAddressGetter, signerGetter } from "./utils";
import { seedLiquidity, deposit, withdraw, redeem, requestWithdraw, requestRedeem, collectFees } from "./flows/As4626";
import { grantRoles, acceptRoles, revokeRoles } from "./flows/AsManageable";
import { transferAssetsTo, requestRescue, rescue } from "./flows/AsRescuable";
import { invest, liquidate, harvest, compound, updateAsset, shuffleInputs } from "./flows/StrategyV5";

const weth = addresses[network.config.chainId!].tokens.WETH;
const day = 60*60*24;

export const suite: Partial<IFlow>[] = [
  // ERC4626 test
  { fn: seedLiquidity, params: [10], assert: (n: BigNumber) => n.gt(0) }, // vault activation + min liquidity deposit
  { fn: deposit, params: [50000], assert: (n: BigNumber) => n.gt(0) }, // deposit
  { fn: invest, params: [10000], assert: (n: BigNumber) => n.gt(0) }, // partial invest
  { fn: invest, params: [], assert: (n: BigNumber) => n.gt(0) }, // invest full vault balance
  { fn: liquidate, params: [1000], assert: (n: BigNumber) => n.gt(0) }, // partial liquidate
  { fn: withdraw, params: [490], assert: (n: BigNumber) => n.gt(0) }, // partial withdraw
  { fn: redeem, params: [500], assert: (n: BigNumber) => n.gt(0) }, // partial redeem
  // ERC7540 tests
  { fn: requestWithdraw, params: [1000], assert: (n: BigNumber) => n.gt(0) },
  { fn: liquidate, params: [0], assert: (n: BigNumber) => n.gt(0) },
  { fn: withdraw, elapsedSec: day, revertState: true, params: [990], assert: (n: BigNumber) => n.gt(0) }, // request - slippage
  { fn: requestRedeem, params: [2000], assert: (n: BigNumber) => n.gt(0) },
  { fn: liquidate, params: [0], assert: (n: BigNumber) => n.gt(0) },
  { fn: redeem, elapsedSec: day, revertState: true, params: [2000], assert: (n: BigNumber) => n.gt(0) }, // full request

  // StrategyV5 tests
  { elapsedSec: day*30, revertState: true, fn: harvest, params: [], assert: (n: BigNumber) => n.gt(0) }, // harvest all pending rewards
  { elapsedSec: day*60, revertState: true, fn: compound, params: [], assert: (n: BigNumber) => n.gt(0) }, // harvest + invest all pending rewards
  { elapsedSec: day*30, revertState: true, fn: collectFees, params: [], assert: (n: BigNumber) => n.gt(0) }, // collect all pending fees with signer 1 (manager only)

  // Manageable tests
  { fn: grantRoles, params: [["MANAGER", "KEEPER"], signerAddressGetter(1)] }, // grant roles to mnemonic signer 2 with signer 1
  { elapsedSec: day*3, fn: acceptRoles, params: [["MANAGER"], signerGetter(1)] }, // accept time-locked elevated role with signer 2
  { fn: revokeRoles, params: [["KEEPER"], signerAddressGetter(1)] }, // revoke roles from mnemonic signer 2 with signer 1

  // Rescuable tests
  { fn: transferAssetsTo, params: [1e18, addressOne], assert: (n: boolean) => n }, // transfer native assets from signer 1 to strat
  { fn: requestRescue, params: [addressOne] }, // request native assets rescual from signer 1 (manager only) on strat
  { elapsedSec: day*3, revertState: true, fn: rescue, params: [addressOne], assert: (n: boolean) => n }, // execute time-locked rescual from signer 1 (manager only)

  { fn: transferAssetsTo, params: [1e18, weth], assert: (n: boolean) => n }, // transfer erc20 assets from signer 1 to strat
  { fn: requestRescue, params: [weth] }, // request erc20 assets rescual from signer 1 (manager only) on strat
  { elapsedSec: day*3, revertState: true, fn: rescue, params: [weth], assert: (n: boolean) => n } // execute time-locked rescual from signer 1 (manager only)

  // WIP tests
  // { fn: updateAsset, params: ["USDCe"], assert: (n: BigNumber) => n.gt(0) }, // partial redeem
  // { fn: shuffleInputs, params: [], assert: (n: BigNumber) => n.gt(0) }, // partial redeem
];
