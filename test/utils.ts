import {
  Log,
  TransactionReceipt,
  TransactionRequest,
  deploy,
  ethers,
  getDeployer,
  getSalts,
  loadAbi,
  network,
  provider,
  weiToString,
} from "@astrolabs/hardhat";
import {
  ISwapperParams,
  ITransactionRequestWithEstimate,
  getAllTransactionRequests,
  getTransactionRequest,
  swapperParamsToString,
} from "@astrolabs/swapper";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import chainlinkOracles from "../src/chainlink-oracles.json";
import { erc20Abi, wethAbi } from "abitype/abis";
import { assert } from "chai";
import crypto from "crypto";
import { Provider as MulticallProvider } from "ethcall";
import {
  BigNumber,
  BigNumberish,
  Contract,
  Overrides,
  constants,
} from "ethers";
import { merge } from "lodash";
import addresses, { Addresses, NetworkAddresses } from "../src/addresses";
import {
  IChainlinkParams,
  IStrategyDeploymentEnv,
  ITestEnv,
  MaybeAwaitable,
  SafeContract,
} from "../src/types";

export const addressZero = constants.AddressZero;
export const addressOne = "0x0000000000000000000000000000000000000001";
export const MaxUint256 = ethers.constants.MaxUint256;
export const keccak256 = (s: string) => ethers.utils.keccak256(ethers.utils.toUtf8Bytes(s));
const maxTopup = BigNumber.from(weiToString(5 * 1e18));

export const indexes = Array.from({ length: 8 }, (_, index) => index);

export function isLive(env: any) {
  const n = env.network ?? network;
  return !["tenderly", "localhost", "hardhat"].some((s) => n?.name.includes(s));
}

export function isAddress(s: string) {
  return /^0x[a-fA-F0-9]{40}$/.test(s);
}

export function addressToBytes32(address: string) {
  if (!isAddress(address)) throw new Error(`Invalid address: ${address}`);
  return ethers.utils.hexZeroPad(address, 32);
}

export function isAwaitable(o: any): boolean {
  return typeof o?.then === "function"; // typeof then = "function" for promises
}

export async function resolveMaybe<T = any>(o: MaybeAwaitable<T>): Promise<T> {
  return isAwaitable(o) ? await o : o;
}

export async function signerGetter(index: number): Promise<SignerWithAddress> {
  return (await ethers.getSigners())[index];
}

export async function signerAddressGetter(index: number): Promise<string> {
  return (await signerGetter(index)).address;
}

export function getAddresses(s: string) {
  return isAddress(s) ? s : addresses[network.config.chainId!].tokens[s];
}

/**
 * Retrieves the signature of the initialization function for a given contract
 * @param contract - Contract address or name
 * @returns The signature of the initialization function
 */
export const getInitSignature = async (contract: string) => {
  const fragments = (await loadAbi(contract) as any[]).filter(
    a => a.name === "init",
  );
  const dummy = new Contract(addressZero, fragments, provider!);
  return Object.keys(dummy)
    .filter((s) => s.startsWith("init"))
    .sort((s1, s2) => s2.length - s1.length)?.[0];
};

/**
 * Retrieves all the selectors for a contract
 * @param abi - ABI of the contract
 * @returns The selectors of the contract
 */
export function getSelectors(abi: any) {
  const i = new ethers.utils.Interface(abi);
  return Object.keys(i.functions).map((signature) => ({
    name: i.functions[signature].name,
    signature: i.getSighash(i.functions[signature]),
  }));
}

/**
 * Checks if two arrays are equal
 * @param a - The first array
 * @param b - The second array
 * @returns True if the arrays are equal, false otherwise
 */
export const arraysEqual = (a: any[], b: any[]) =>
  a === b ||
  (a && b && a.length === b.length && a.every((val, idx) => val === b[idx]));

/**
 * Checks if all elements in an array are duplicates of each other
 * @param a - The array to check
 * @returns `true` if all elements in the array are duplicates, `false` otherwise
 */
export const duplicatesOnly = (a: any[]) =>
  a.every((v) => v === a[0]);

/**
 * Overrides for different network chain IDs
 * @type {Object.<number, Overrides>}
 */
const networkOverrides: { [chainId: number]: Overrides } = {
  1: {
    gasLimit: 1e7,
  },
  100: {
    // gasLimit: 1e7,
    maxPriorityFeePerGas: 5e9,
    maxFeePerGas: 25e9,
    // gasPrice: 4e9,
  },
  137: {
    maxPriorityFeePerGas: 50e9,
    maxFeePerGas: 150e9,
    // gasPrice: 150e9,
  },
  8453: {
    gasLimit: 1e7,
  },
  42161: {
    gasLimit: 30e6,
  },
};

/**
 * Retrieves the overrides based on the provided environment
 * @param env - Partial ITestEnv object representing the environment
 * @returns The overrides object
 * @dev No overrides are used for live environments (mainnets)
 */
export const getOverrides = (env: Partial<ITestEnv>) => {
  const overrides = isLive(env)
    ? {}
    : networkOverrides[env.network!.config.chainId!] ?? {};
  return overrides;
};

export const sleep = (ms: number) =>
  new Promise((resolve) => setTimeout(resolve, ms));

export const isStable = (s: string) =>
  [
    "USDC",
    "USDCe",
    "USDbC",
    "xcUSDC",
    "lzUSDC",
    "sgUSDC",
    "axlUSDC",
    "whUSDC",
    "cUSDC",
    "USDT",
    "USDTe",
    "xcUSDT",
    "lzUSDT",
    "sgUSDT",
    "axlUSDT",
    "whUSDT",
    "BUSD",
    "DAI",
    "DAIe",
    "lzDAI",
    "axlDAI",
    "whDAI",
    "xcDAI",
    "XDAI",
    "WXDAI",
    "SDAI",
    "FRAX",
    "sFRAX",
    "LUSD",
    "USDD",
    "CRVUSD",
    "GHO",
    "DOLA",
    "USDP",
    "USD+",
    "USDD",
    "EURS",
    "EURT",
    "EURTe",
    "EURA",
    "cEUR",
    "USD",
    "EUR",
  ].includes(s.toUpperCase());

export const isStablePair = (s1: string, s2: string) =>
  isStable(s1) && isStable(s2);

/**
 * Checks if the given string contains the name of an oracle library
 * @param name - Name of the oracle
 * @returns True if the oracle matches
 */
export const isOracleLib = (name: string) =>
  ["Pyth", "RedStone", "Chainlink", "Witnet"].some((libname) =>
    name.includes(libname),
  );

/**
 * Logs the balances of the given token for the given addresses
 * @param env - Partial ITestEnv object representing the environment
 * @param token - Token address or symbol
 * @param receiver - Address of the receiver
 * @param payer - Address of the payer
 * @param step - Step of the test
 */
export async function logBalances(
  env: Partial<IStrategyDeploymentEnv>,
  token: SafeContract | string,
  receiver: string,
  payer?: string,
  step?: string,
) {
  payer ??= env.deployment!.strat.address;
  let balances: BigNumber[];
  let tokenId = "";
  if (token == addressOne) {
    tokenId = `native token`;
    balances = await env.multicallProvider!.all([
      env.multicallProvider!.getEthBalance(payer),
      env.multicallProvider!.getEthBalance(receiver),
    ]);
    console.log(`
    State ${
      step ?? ""
    }:\nBalances of ${tokenId}\n  - payer (eg. rescued strat): ${
      balances[0]
    }\n  - receiver (eg. rescuer): ${balances[1]}`);
  } else {
    if (typeof token === "string") token = await SafeContract.build(token);
    tokenId = `${token.sym} (${token.address})`;
    balances = await env.multicallProvider!.all([
      token.multi.balanceOf(payer),
      token.multi.balanceOf(receiver),
    ]);
    console.log(`
    State ${
      step ?? ""
    }:\nBalances of ${tokenId}\n  - payer (eg. rescued strat): ${token.toAmount(
      balances[0],
    )}\n  - receiver (eg. rescuer): ${token.toAmount(balances[1])}`);
  }
}

export const logRescue = logBalances;

/**
 * Retrieves the inputs, weights, and LP tokens from the given strategy deployment environment
 * @param env - The strategy deployment environment
 * @returns Array containing the current inputs, weights, and LP tokens
 */
export async function getInputs(env: Partial<IStrategyDeploymentEnv>): Promise<[string[], number[], string[]]> {
  const strat = await env.deployment!.strat;
  const indexes = [...Array(8).keys()];

  const stratParams = await env.multicallProvider!.all([
    ...indexes.map((i) => strat.multi.inputs(i)),
    ...indexes.map((i) => strat.multi.inputWeights(i)),
    ...indexes.map((i) => strat.multi.lpTokens(i)),
  ]);

  let lastInputIndex = stratParams.findIndex((input) => input == addressZero);

  if (lastInputIndex < 0) lastInputIndex = indexes.length; // max 8 inputs (if no empty address found)

  const [currentInputs, currentWeights, currentLpTokens] = [
    stratParams.slice(0, lastInputIndex),
    stratParams.slice(8, 8+lastInputIndex),
    stratParams.slice(16, 16+lastInputIndex),
  ] as [string[], number[], string[]];
  return [currentInputs, currentWeights, currentLpTokens];
}

/**
 * Logs the state of the given strategy deployment environment
 * @param env - Strategy deployment environment
 * @param step - Step of the test
 * @param sleepBefore - Number of milliseconds to sleep before logging state
 * @param sleepAfter - Number of milliseconds to sleep after logging state
 */
export async function logState(
  env: Partial<IStrategyDeploymentEnv>,
  step?: string,
  sleepBefore = 0,
  sleepAfter = 0,
) {
  const { strat, rewardTokens } = env.deployment!;
  if (sleepBefore) {
    console.log(`Sleeping ${sleepBefore}ms before logging state...`);
    await sleep(sleepBefore);
  }
  try {
    const asset = await SafeContract.build(await strat.asset());
    const [
      sharePrice,
      totalSupply,
      totalAccountedSupply,
      totalAssets,
      totalAccountedAssets,
      totalClaimableAssetFees,
      available,
      // totalDepositRequest,

      totalRedemptionRequest,
      totalClaimableRedemption,
      // totalAsset, // only available on strat.req() struct
      // totalClaimableAsset, // only available on strat.req() struct
      // previewInvest,
      // previewLiquidate,
      stratAssetBalance,
      deployerAssetBalance,
      deployerSharesBalance,
    ]: any[] = await env.multicallProvider!.all([
      strat.multi.sharePrice(),
      strat.multi.totalSupply(),
      strat.multi.totalAccountedSupply(),
      strat.multi.totalAssets(),
      strat.multi.totalAccountedAssets(),
      strat.multi.claimableTransactionFees(),
      strat.multi.available(),

      // strat.multicallContract.totalDepositRequest(),

      strat.multi.totalRedemptionRequest(),
      strat.multi.totalClaimableRedemption(),

      // strat.multicallContract.totalAsset(), // only available on strat.req() struct
      // strat.multicallContract.totalClaimableAsset(), // only available on strat.req() struct
      // strat.multi.previewInvest(0),
      // strat.multi.previewLiquidate(0),
      asset.multi.balanceOf(strat.address),
      asset.multi.balanceOf(env.deployer!.address),
      strat.multi.balanceOf(env.deployer!.address),
      // await assetTokenContract.balanceOf(strategy.address),
    ]);
    const [inputAddresses, inputWeights, lpTokenAddresses] = await getInputs(env);
    const inputs = await Promise.all(inputAddresses.map((input) => SafeContract.build(input)));
    const lpTokens = await Promise.all(lpTokenAddresses.map((lpToken) => SafeContract.build(lpToken)));
    const rewardsAddresses = rewardTokens.map((reward) => reward.address);
    // ethcall only knows functions overloads, so we fetch invested() first then multicall the details for each input
    const [invested, rewardsAvailable, previewInvest, previewLiquidate] = await Promise.all([
      strat["invested()"](),
      strat.callStatic.claimRewards?.() ?? strat.rewardsAvailable?.(),
      strat.callStatic.previewInvest(0),
      strat.callStatic.previewLiquidate(0),
    ]);
    const totalInvested: BigNumber[] = await env.multicallProvider!.all(
      inputs.map((input, index) => strat.multi.invested(index)),
    );

    console.log(
      `State ${step ?? ""}:
    asset: ${asset.sym} (${asset.address})
    inputs: [${inputs
      .map((input) => input.sym + " (" + input.address)
      .join("), ")})]
    inputWeights: [${inputWeights.join(", ")}]
    lpTokens: [${lpTokens
      .map((lpToken) => lpToken.sym + " (" + lpToken.address)
      .join("), ")})]
    rewardTokens: [${rewardsAddresses.join(", ")}]
    sharePrice(): ${strat.toAmount(sharePrice)} (${sharePrice}wei)
    totalSuply(): ${strat.toAmount(totalSupply)} (${totalSupply}wei)
    totalAccountedSupply(): ${strat.toAmount(
      totalAccountedSupply,
    )} (${totalAccountedSupply}wei)
    totalAssets(): ${asset.toAmount(totalAssets)} (${totalAssets}wei)
    totalAccountedAssets(): ${asset.toAmount(
      totalAccountedAssets,
    )} (${totalAccountedAssets}wei)
    totalClaimableAssetFees(): ${asset.toAmount(
      totalClaimableAssetFees,
    )} (${totalClaimableAssetFees}wei)
    invested(): ${asset.toAmount(invested)} (${invested}wei)\n${inputs
      .map(
        (input, index) =>
          `      -${input.sym}: ${<any>(
            asset.toAmount(totalInvested[index])
          )} (${totalInvested[index]}wei)`,
      )
      .join("\n")}
    available(): ${available / asset.weiPerUnit} (${available}wei) (${
      Math.round(totalAssets.lt(10) ? 0 : (available * 100) / totalAssets) / 100
    }%)
    totalRedemptionRequest(): ${strat.toAmount(
      totalRedemptionRequest,
    )} (${totalRedemptionRequest}wei)
    totalClaimableRedemption(): ${strat.toAmount(
      totalClaimableRedemption,
    )} (${totalClaimableRedemption}wei) (${
      Math.round(
        totalRedemptionRequest.lt(10)
          ? 0
          : (totalClaimableRedemption * 100) / totalRedemptionRequest,
      ) / 100
    }%)
    rewardsAvailable():\n${rewardTokens
      .map(
        (reward, index) =>
          `      -${reward.sym}: ${reward.toAmount(rewardsAvailable[index])} (${
            rewardsAvailable[index]
          }wei)`,
      )
      .join("\n")}
    previewInvest(0 == available()*.9):\n${inputs
      .map(
        (input, i) =>
          `      -${input.sym}: ${asset.toAmount(
            previewInvest[i],
          )} (${previewInvest[i].toString()}wei)`,
      )
      .join("\n")}
    previewLiquidate(0 == pendingWithdrawRequests + invested()*.01):\n${inputs
      .map(
        (input, i) =>
          `      -${input.sym}: ${inputs[i].toAmount(
            previewLiquidate[i],
          )} (${previewLiquidate[i].toString()}wei)`,
      )
      .join("\n")}
    stratAssetBalance(): ${asset.toAmount(
      stratAssetBalance,
    )} (${stratAssetBalance}wei)
    deployerBalances(shares, asset): [${strat.toAmount(
      deployerSharesBalance,
    )},${asset.toAmount(deployerAssetBalance)}]
    `,
    );
    if (sleepAfter) await sleep(sleepAfter);
  } catch (e) {
    console.log(`Error logging state ${step ?? ""}: ${e}`);
  }
}

/**
 * Completes the given strategy deployment environment
 * @param env - Strategy deployment environment
 * @param addressesOverride - Optional addresses override
 * @returns Completed strategy deployment environment
 */
export const getEnv = async (
  env: Partial<ITestEnv> = {},
  addressesOverride?: Addresses,
): Promise<ITestEnv> => {
  const addr = (addressesOverride ?? addresses)[network.config.chainId!];
  const oracles = (<any>chainlinkOracles)[network.config.chainId!];
  const deployer = await getDeployer() as SignerWithAddress;
  const multicallProvider = new MulticallProvider();
  await multicallProvider.init(provider);
  const live = isLive(env);
  if (live) env.revertState = false;
  let snapshotId = 0;
  try {
    snapshotId = live ? 0 : await provider.send("evm_snapshot", []);
  } catch (e) {
    console.error(`Failed to snapshot: ${e}`);
  }
  env = merge(
    {
      network,
      blockNumber: await provider.getBlockNumber(),
      snapshotId,
      revertState: false,
      wgas: await SafeContract.build(addr.tokens.WGAS, wethAbi, env.deployer!),
      addresses: addr,
      oracles,
      deployer,
      provider,
      multicallProvider,
      needsFunding: false,
      gasUsedForFunding: 0, // denominated in wgas decimal
    },
    env,
  );
  const rpc = (network.config as any)?.forking?.url ?? (network.config as any)?.url ?? "???";
  console.log(`Live: ${live}\nRpc: ${rpc}`);
  return env as ITestEnv;
};

/**
 * Swaps tokens using the specified parameters
 * @param env - Strategy deployment environment
 * @param o - Swapper parameters
 * @returns The swap proceeds
 */
async function _swap(env: Partial<IStrategyDeploymentEnv>, o: ISwapperParams) {
  if (o.inputChainId != network.config.chainId) {
    if (!isLive(env)) {
      console.warn(`Skipping case as not on current network: ${network.name}`);
      return;
    } else {
      console.warn(`Case requires hardhat network change to ${network.name}`);
    }
  }

  o.payer ||= env.deployer!.address;
  const amountWei = BigNumber.from(o.amountWei as any);
  o.amountWei = amountWei;
  o.inputChainId ??= network.config.chainId!;
  o.outputChainId ??= o.inputChainId;

  let input: Contract;
  const nativeBalance = await provider.getBalance(o.payer);

  if (!o.input) {
    o.input = env.addresses!.tokens.WGAS;
    input = new Contract(env.addresses!.tokens.WGAS, wethAbi, env.deployer);

    const symbol = await input.symbol();
    if (["ETH", "BTC"].some((s) => symbol.includes(s))) {
      // limit the size of a swap to 10 ETH/BTC
      if (amountWei.gt(maxTopup)) o.amountWei = BigNumber.from(maxTopup);
    }
    console.assert(nativeBalance.gt(amountWei));
    const wrappedBalanceBefore = await input.balanceOf(o.payer);
    await input.deposit({ value: o.amountWei });
    const wrapped = (await input.balanceOf(o.payer)).sub(wrappedBalanceBefore);
    console.log(`wrapped ${wrapped} ${o.input}`);
    console.assert(wrapped.eq(o.amountWei));
  } else {
    input = new Contract(o.input, erc20Abi, env.deployer);
  }
  if (o.inputChainId == o.outputChainId && o.input == o.output) {
    console.log(`input == output, skipping swap`);
    return;
  }
  console.log(swapperParamsToString(o));

  let inputBalance = await input.balanceOf(o.payer);

  if (inputBalance.lt(o.amountWei)) {
    console.log(
      `payer ${o.payer} has not enough balance of ${o.inputChainId}:\n${o.input}, swapping from gasToken to ${o.input}`,
    );
    await _swap(env, {
      payer: o.payer,
      inputChainId: o.inputChainId,
      output: o.input,
      amountWei: weiToString(nativeBalance.sub(BigInt(1e20).toString())),
    } as ISwapperParams);
    inputBalance = await input.balanceOf(o.payer);
  }

  const output = new Contract(o.output, erc20Abi, env.deployer);
  const outputBalanceBeforeSwap = await output.balanceOf(o.payer);

  await input.approve(env.deployment!.Swapper.address, MaxUint256.toString());
  const trs: TransactionRequest[] | undefined =
    (await getAllTransactionRequests(o)) as TransactionRequest[];
  assert(trs?.length);
  let received = BigNumber.from(0);
  for (const tr of trs) {
    assert(!!tr?.data);
    // console.log(`using request: ${JSON.stringify(tr, null, 2)}`);
    await ensureWhitelisted(
      env.deployment!.Swapper,
      [tr.from as string, tr.to!, o.input, o.output],
      env as IStrategyDeploymentEnv,
    );
    const ok = await env.deployment!.Swapper.swap(
      input.target ?? input.address,
      output.target ?? output.address,
      o.amountWei.toString(),
      "1",
      tr.to,
      tr.data,
      {
        gasLimit: Math.max(
          Number(tr.gasLimit ?? 0),
          (getOverrides(env)?.gasLimit as number) ?? 1e7,
        ),
      },
    );
    received = (await output.balanceOf(o.payer)).sub(outputBalanceBeforeSwap);
    console.log(`received ${received} ${o.output}`);
    if (received.gt(0)) break;
  }
  assert(received.gt(1));
}

/**
 * Funds the specified account with the given amount of a specified asset
 * @param env - Strategy deployment environment
 * @param amount - Amount to fund the account with
 * @param asset - Asset to fund the account with
 * @param receiver - Address of the account to fund
 * @returns The funding proceeds (amount received)
 */
export async function fundAccount(
  env: Partial<IStrategyDeploymentEnv>,
  amount: number | string | BigNumber,
  asset: string,
  receiver: string,
): Promise<void> {
  const output = new Contract(asset, erc20Abi, env.deployer!);
  const balanceBefore = await output.balanceOf(receiver);
  let balanceAfter = balanceBefore;
  let retries = 3;
  while (balanceAfter.lte(balanceBefore) && retries--) {
    await _swap(env, {
      inputChainId: network.config.chainId!,
      output: asset,
      amountWei: weiToString(amount),
      receiver,
      payer: env.deployer!.address,
      testPayer: env.addresses!.accounts!.impersonate,
      // maxSlippage: 5000,
    } as ISwapperParams);
    balanceAfter = await output.balanceOf(receiver);
  }
  return balanceAfter.sub(balanceBefore);
}

/**
 * Ensures that the given addresses are whitelisted by the contract
 * If the contract does not have the required whitelisting methods, an error is logged and the function returns
 * @param contract - Contract instance or object
 * @param addresses - Addresses to be whitelisted
 * @param env - Strategy deployment environment
 */
async function ensureWhitelisted(
  contract: SafeContract | any,
  addresses: string[],
  env: IStrategyDeploymentEnv,
) {
  // check if isWhitelisted and addToWhitelist exist on the contract
  for (const method of ["isWhitelisted", "addToWhitelist"]) {
    if (!(method in contract)) {
      console.error(
        `Skipping whitelisting as ${method} is not available on ${contract.address}`,
      );
      return;
    }
  }
  const whitelisted = await env.multicallProvider!.all(
    addresses.map((addr) => contract.multi.isWhitelisted(addr)),
  );
  whitelisted.map(async (isWhitelisted, i) => {
    if (!isWhitelisted) {
      console.log(`whitelisting ${addresses[i]}`);
      await contract.addToWhitelist(addresses[i]);
    }
  });
}

/**
 * Ensures that the funding is sufficient for the given strategy deployment environment (deployer funded with gas tokens and strategy underlying)
 * @param env The strategy deployment environment
 */
export async function ensureFunding(env: IStrategyDeploymentEnv) {
  if (isLive(env)) {
    console.log(
      `Funding is only applicable to test forks and testnets, not ${env.network.name}`,
    );
    return;
  }

  const assetSymbol = env.deployment!.asset.sym;
  const assetAddress = env.deployment!.asset.address;
  const minLiquidity = assetSymbol.includes("USDC") ? 1e8 : 2e18; // 10_000 USDC or 2 ETH
  const assetBalance = await env.deployment!.asset.balanceOf(
    env.deployer.address,
  );
  if (assetBalance.lt(minLiquidity)) {
    console.log(
      `${env.deployer.address} needs at least ${minLiquidity}wei ${assetSymbol} => funding required`,
    );
    env.needsFunding = true;
  }

  if (env.needsFunding) {
    console.log(
      `Funding ${env.deployer.address} from ${
        env.gasUsedForFunding || "(auto)"
      }wei ${env.wgas.sym} (gas tokens) to ${minLiquidity}wei ${assetSymbol}`,
    );
    let gas =
      env.gasUsedForFunding ||
      (await getSwapperOutputEstimate(
        "USDC",
        env.wgas.sym,
        50_010e6,
        network.config.chainId!,
        network.config.chainId!,
      )) ||
      0;
    if (!gas) {
      throw new Error(
        `Failed to get gas estimate for ${env.wgas.sym} => ${assetSymbol}`,
      );
    }
    console.log(`Balance before funding: ${assetBalance}wei ${assetSymbol}`);
    const nativeBalance = await provider.getBalance(env.deployer.address);
    if (nativeBalance.lt(gas)) {
      console.log(
        `Funding ${env.deployer.address} with ${gas}wei ${env.wgas.sym} (gas tokens)`,
      );
      // if not enough gas tokens, add it
      // await setBalances(gas, env.deployer.address);
      await env.provider.send("tenderly_setBalance", [
        [env.deployer.address],
        ethers.utils.hexValue(gas),
      ]);
    }
    const received = await fundAccount(
      env,
      gas,
      assetAddress,
      env.deployer.address,
    );
    console.log(
      `Balance after funding: ${assetBalance.add(
        received,
      )}wei ${assetSymbol} (+${received})`,
    );
  }
}

/**
 * Ensures oracle access for the given strategy deployment environment
 * For the "ChainlinkUtils" library, it sets the storage slot for Chainlink's "checkEnabled" to false,
 * deactivating access control
 * @param env - Strategy deployment environment
 * @returns A promise that resolves once the oracle access has been ensured
 * @dev Only applicable to test environment
 */
export async function ensureOracleAccess(env: IStrategyDeploymentEnv) {
  if (isLive(env)) {
    console.log(
      `Oracle access is only applicable to test forks and testnets, not ${env.network.name}`,
    );
    return;
  }
  const usedSymbols = env.deployment!.inputs.map(i => i.sym);
  const feeds = new Set(usedSymbols.map((sym) =>
    addressToBytes32(env.oracles![`Crypto.${sym}/USD`]),
  ));

  if (!env.network.name.includes("tenderly")) return;

  for (const lib of Object.keys(env.deployment!.units!)) {
    if (isOracleLib(lib)) {
      console.log(`Whitelisting oracle access for ${lib}`);
      switch (lib) {
        case "ChainlinkUtils": {
          for (const feed of feeds) {
            const storageSlot =
              "0x0000000000000000000000000000000000000000000000000000000000000031";
            // set the storage slot for Chainlink's "checkEnabled" to false, in order to deactivate access control
            const newValue =
              "0x0000000000000000000000000000000000000000000000000000000000000000";
            // Sending the tenderly_setStorageAt command
            await provider.send("tenderly_setStorageAt", [
              feed,
              storageSlot,
              newValue,
            ]);
          }
        }
      }
    }
  }
}

/**
 * Encodes the given values into their ABI-encoded form using the provided types
 * @param types Array of strings representing the types of the values to encode
 * @param values Array of values to encode
 * @param isTuple Indicates whether the values represent a tuple (default: false)
 * @returns ABI-encoded string representation of the values
 */
export function abiEncode(
  types: string[],
  values: any[],
  isTuple = false,
): string {
  return ethers.utils.defaultAbiCoder.encode(types, values);
}

/**
 * Decodes the given ABI-encoded data into its corresponding values using the provided types
 * @param types Array of strings representing the types of the values to decode
 * @param data ABI-encoded string representation of the values to decode
 * @param isTuple Indicates whether the values represent a tuple (default: false)
 * @returns Array of decoded values
 */
export function abiDecode(
  types: string[],
  data: string,
  isTuple = false,
): any {
  return ethers.utils.defaultAbiCoder.decode(types, data);
}


/**
 * Retrieves the data from a transaction log (used as flows return value)
 * @param tx - Transaction receipt
 * @param types - Array of types to decode the log data
 * @param outputIndex - Index of the decoded data to return
 * @param logIndex - Index or event name of the log to retrieve
 * @returns The decoded data from the log, or undefined if not found/parsing failure
 */
export function getTxLogData(
  tx: TransactionReceipt,
  types = ["uint256"],
  outputIndex = 0,
  logIndex: string | number = -1,
): any {
  const logs = (tx as any).events || tx.logs;
  let log: Log;
  try {
    if (!logs?.length) throw "No logs found on tx ${tx.transactionHash}";
    if (typeof logIndex === "string") {
      log = logs.find((l: any) => l?.event === logIndex) as Log;
    } else {
      if (logIndex < 0) logIndex = logs.length + logIndex;
      log = logs[logIndex];
    }
    if (!log) throw `Log ${logIndex} not found on tx ${tx.transactionHash}`;
    const decoded = ethers.utils.defaultAbiCoder.decode(types, log.data);
    return decoded?.[outputIndex];
  } catch (e) {
    console.error(
      `Failed to parse log ${e}: tx ${tx.transactionHash} probably reverted`,
    );
    return undefined;
  }
}

/**
 * Calculates the estimated exchange rate for swapping tokens
 * @param from The token to swap from
 * @param to The token to swap to
 * @param inputWei The amount of tokens to swap
 * @param chainId The chain ID (default: 1)
 * @returns The estimated exchange rate as a number
 */
export async function getSwapperRateEstimate(
  from: string,
  to: string,
  inputWei: BigNumberish | bigint,
  chainId = 1,
): Promise<number> {
  return (
    Number(
      (await getSwapperEstimate(from, to, inputWei, chainId))
        ?.estimatedExchangeRate,
    ) ?? 0
  );
}

/**
 * Calculates the estimated output amount for a given swap transaction
 * @param from - Token to swap from
 * @param to - Token to swap to
 * @param inputWei - Input amount in wei
 * @param chainId - Chain ID
 * @param outputChainId - Output chain ID (optional)
 * @returns The estimated output amount in wei
 */
export async function getSwapperOutputEstimate(
  from: string,
  to: string,
  inputWei: BigNumberish | bigint,
  chainId = 1,
  outputChainId?: number,
): Promise<BigNumber> {
  return BigNumber.from(
    (await getSwapperEstimate(from, to, inputWei, chainId, outputChainId))
      ?.estimatedOutputWei ?? 0,
  );
}

/**
 * Calculates the estimated transaction details for swapping tokens
 * @param from - Token to swap from
 * @param to - Token to swap to
 * @param inputWei - Amount of tokens to swap in wei
 * @param inputChainId - Chain ID of the input token
 * @param outputChainId - Chain ID of the output token. If not provided, it defaults to the input chain ID
 * @returns - Estimated transaction details or undefined if the tokens are the same
 * @throws An error if either the input or output token is not found in addresses.ts:ethereum
 */
export async function getSwapperEstimate(
  from: string, // "USDC"
  to: string, // "AVAX"
  inputWei: BigNumberish | bigint,
  inputChainId = 1,
  outputChainId?: number,
): Promise<ITransactionRequestWithEstimate | undefined> {
  const [input, output] = [from, to].map((s) => getAddresses(s));
  if (!input || !output)
    throw new Error(
      `Token ${from} or ${to} not found in addresses.ts:ethereum`,
    );
  if (input == output)
    return {
      estimatedOutputWei: inputWei,
      // estimatedOutput: Number(simulatedSwapSizeWei.toString()) / (10 ** (await (new Contract(input, erc20Abi, provider)).decimals()).toNumber?.()),
      estimatedExchangeRate: 1,
    };
  const tr = (await getTransactionRequest({
    input,
    output,
    amountWei: weiToString(inputWei as any), // 10k USDC
    inputChainId: inputChainId,
    outputChainId: outputChainId ?? inputChainId,
    payer: addresses[inputChainId].accounts!.impersonate,
    testPayer: addresses[inputChainId].accounts!.impersonate,
  })) as ITransactionRequestWithEstimate;
  return tr;
}

/**
 * Finds a function name in the given ABI (Application Binary Interface) based on its signature
 * @param signature - Function signature to search for
 * @param abi - ABI array to search in
 * @returns The name of the function matching the provided signature
 * @throws Error if the function signature is not found in the ABI
 */
export function findSignature(signature: string, abi: any[]): string {
  for (let item of abi) {
    // Ensure the item is a function and has an 'inputs' field
    if (item.type === "function" && item.inputs) {
      // Construct the function signature string
      const funcSig = `${item.name}(${item.inputs
        .map((input: any) => input.type)
        .join(",")})`;

      // Compute the hash of the function signature
      const hash = ethers.utils.id(funcSig).substring(0, 10); // utils.id returns the Keccak-256 hash, we only need the first 10 characters

      // Compare the hash with the provided signature
      if (hash === signature) {
        return item.name;
      }
    }
  }
  throw new Error(`Function signature ${signature} not found in ABI`);
}

/**
 * Converts a given text into a nonce (used for nonce determinism)
 * @param text - Text to be converted into a nonce
 * @returns The nonce as a number
 */
export function toNonce(text: string): number {
  // Hash the text using SHA-256
  const hash = crypto.createHash("sha256");
  hash.update(text);
  // Convert the hash into a hexadecimal string
  const hexHash = hash.digest("hex");
  // Convert the hexadecimal hash into an integer
  // NB: we use a hash substring to as js big numeric management is inacurate
  const nonce = parseInt(hexHash.substring(0, 15), 16);
  return nonce;
}

/**
 * Adjusts the values of an array by randomly decreasing them based on their sign
 * Positive values are decreased by a random percentage, while negative values are increased by a random percentage
 * The adjustment is distributed among the positive and negative values in the array
 * The function returns the adjusted array
 *
 * @param arr - The array of numbers to adjust
 * @returns The adjusted array
 */
export function randomRedistribute(arr: number[]): number[] {
  let positiveSum = 0, negativeSum = 0;

  let [totalPositive, totalNegative] = [0, 0];
  let [positiveCount, negativeCount] = [0, 0];
  arr.map((val, index) => {
    let adjustment = Math.random() * val * 0.9;
    if (Number.isInteger(val))
      adjustment = Math.round(adjustment);
    if (val > 0) {
      totalPositive += adjustment;
      positiveCount++;
    } else {
      totalNegative += adjustment;
      negativeCount++;
    }
    arr[index] -= adjustment;
    return adjustment;
  });

  let [leftoverPositive, leftoverNegative] = [totalPositive, totalNegative];

  while ((leftoverPositive-leftoverNegative) > 0) {
    for (let i = 0; i < arr.length; i++) {
      if (arr[i] > 0 && totalPositive > 0) {
        let adjustment = Math.random() * (totalPositive / positiveCount);
        if (Number.isInteger(arr[i]))
          adjustment = Math.round(adjustment);
        if (adjustment > leftoverPositive) {
          adjustment = leftoverPositive;
        }
        arr[i] += adjustment;
        leftoverPositive -= adjustment;
      } else if (arr[i] < 0 && totalNegative > 0) {
        let adjustment = Math.random() * (totalNegative / negativeCount);
        if (Number.isInteger(arr[i]))
          adjustment = Math.round(adjustment);
        if (adjustment > leftoverNegative) {
          adjustment = leftoverNegative;
        }
        arr[i] += adjustment;
        leftoverNegative -= adjustment;
      }
    }
  }
  return arr;
}

// cf. https://github.com/hujw77/safe-dao-factory/blob/07ae58dc5b9c90e962fe0c436557843987ce448f/src/SafeDaoFactory.sol#L8
export async function deployMultisig(
  env: Partial<ITestEnv>,
  name: string="Astrolab DAO Council",
  owners=[env.deployer!.address],
  threshold=1,
  overrides: Overrides = {
    gasLimit: 2_500_000,
  },
): Promise<Contract> {
  const addr: NetworkAddresses = addresses![network.config.chainId!];
  const params = {
    owners,
    threshold,
    to: addressZero,
    data: "0x",
    fallbackHandler: addr.safe!.compatibilityFallbackHandler,
    paymentToken: addr.tokens.WGAS,
    payment: 0,
    paymentReceiver: addressZero,
  };
  const [proxyFactoryAbi, safeAbi] = await Promise.all([loadAbi("SafeProxyFactory"), loadAbi("Safe")]) as any;
  const proxyFactory = new Contract(addr.safe!.proxyFactory, proxyFactoryAbi, env.deployer!);
  const creationCode = await proxyFactory.proxyCreationCode();
  // const create3Bytecode = ethers.utils.hexConcat([
  //   creationCode,
  //   ethers.utils.defaultAbiCoder.encode(['address'], [addr.safe!.singletonL2]),
  // ]);
  const create3Bytecode = ethers.utils.solidityPack(
    ['bytes', 'uint256'],
    [creationCode, BigNumber.from(addr.safe!.singletonL2)],
  );
  const salts = getSalts();
  if (!salts[name]) {
    throw new Error("Salt not found for " + name);
  }
  let safe = await deploy({
    contract: "Safe", // proxy
    name,
    deployer: env.deployer!,
    overrides,
    useCreate3: true,
    create3Salt: salts[name],
    create3Bytecode,
  });
  safe = new Contract(safe.address, safeAbi, env.deployer!);
  await safe.setup(params);
  return safe;
}

export async function isDeployed(env: Partial<ITestEnv>, address: string) {
  if (env.addresses!) {
    const actual = Object.keys(env.addresses!).find((key) => env.addresses![key]![address]);
    address = actual ?? address; // if address is an alias, use the actual address
  }
  try {
    await provider.getCode(address);
    return true;
  } catch (e) {
    return false;
  }
}

export function packBy(arr: any[], groupSize=2): any[] {
  const pairs = [];
  for (let i = 0; i < arr.length; i += groupSize) {
    pairs.push(arr.slice(i, i + groupSize));
  }
  return pairs;
}
