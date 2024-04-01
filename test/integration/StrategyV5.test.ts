import { network } from "hardhat";
import { BigNumber } from "ethers";
import addresses from "../../src/addresses";
import { IFlow } from "./flows";
import { addressOne, signerAddressGetter, signerGetter } from "./utils";
import { seedLiquidity, deposit, withdraw, redeem, requestWithdraw, requestRedeem, collectFees } from "./flows/As4626";
import { grantRoles, acceptRoles, revokeRoles } from "./flows/AsManageable";
import { transferAssetsTo, requestRescue, rescue } from "./flows/AsRescuable";
import { invest, liquidate, harvest, compound, updateAsset, shuffleInputs, updateInputs } from "./flows/StrategyV5";

const addr = addresses[network.config.chainId!];
const tokenAddress = addr.tokens;
const weth = tokenAddress.WETH;
const day = 60*60*24;

export const suite: Partial<IFlow>[] = [
  // sync ERC4626 deposit/withdraw/redeem
  { fn: seedLiquidity, params: [1000], assert: (n: BigNumber) => n.gt(0) }, // vault activation + min liquidity deposit
  { fn: deposit, params: [10000], assert: (n: BigNumber) => n.gt(0) }, // deposit
  { fn: withdraw, params: [1010], assert: (n: BigNumber) => n.gt(0) }, // partial withdraw
  { fn: redeem, params: [1000], assert: (n: BigNumber) => n.gt(0) }, // partial redeem

  // invest/liquidate (using live swapper's generated calldata)
  // { fn: invest, params: [5000], assert: (n: BigNumber) => n.gt(0) }, // partial invest
  { fn: invest, params: [], assert: (n: BigNumber) => n.gt(0) }, // invest full vault balance
  // { fn: liquidate, params: [1000], assert: (n: BigNumber) => n.gt(0) }, // partial liquidate

  // async ERC7540 withdrawal
  { fn: requestWithdraw, params: [1001], assert: (n: BigNumber) => n.gt(0) },
  { fn: liquidate, params: [0], assert: (n: BigNumber) => n.gt(0) },
  { fn: withdraw, params: [1000], elapsedSec: day, revertState: true, assert: (n: BigNumber) => n.gt(0) }, // request - slippage

  // async ERC7540 redemption
  { fn: requestRedeem, params: [2000], assert: (n: BigNumber) => n.gt(0) },
  { fn: liquidate, params: [0], assert: (n: BigNumber) => n.gt(0) },
  { fn: redeem, params: [2000], elapsedSec: day, revertState: true, assert: (n: BigNumber) => n.gt(0) }, // full request

  // claimRewards/harvest(claim+swap)/compound(harvest+invest)
  { elapsedSec: day*30, revertState: true, fn: harvest, params: [], assert: (n: BigNumber) => n.gt(0) }, // harvest all pending rewards
  { elapsedSec: day*30, revertState: true, fn: compound, params: [], assert: (n: BigNumber) => n.gt(0) }, // harvest + invest all pending rewards

  // collect fees
  { elapsedSec: day*30, revertState: true, fn: collectFees, params: [], assert: (n: BigNumber) => n.gt(0) }, // collect all pending fees with signer 1 (manager only)

  // change underlying assets/inputs (using live swapper's generated calldata)
  // { fn: updateAsset, params: [tokenAddress.WBTC], assert: (n: BigNumber) => n.gt(0) },
  // { fn: updateAsset, params: [tokenAddress.DAI], assert: (n: BigNumber) => n.gt(0) },
  // { fn: updateAsset, params: [tokenAddress.LINK], assert: (n: BigNumber) => n.gt(0) },
  // { fn: updateAsset, params: [tokenAddress.USDC], assert: (n: BigNumber) => n.gt(0) },
  // { fn: updateInputs, params: [[tokenAddress.WETH, tokenAddress.USDC], [7000,2000], ["0x46e6b214b524310239732D51387075E0e70970bf", "0xb125E6687d4313864e53df431d5425969c15Eb2F"]], assert: (n: BigNumber) => n.gt(0) },
  // { fn: updateInputs, params: [[tokenAddress.USDC], [20_00], ["0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf"]], assert: (n: BigNumber) => n.gt(0) },
  // { fn: shuffleInputs, params: [[9000,0], false], assert: (n: BigNumber) => n.gt(0) },
  // { fn: shuffleInputs, params: [], assert: (n: BigNumber) => n.gt(0) }, // partial redeem

  // AccessController tests
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
];
