import {
  MaxUint256,
  TransactionRequest,
  addressOne,
  addressToBytes32,
  addressZero,
  ethers,
  isLive,
  isOracleLib,
  network,
  provider,
  sleep,
  weiToString,
  ITestEnv,
  SafeContract,
  addresses,
  WETH_ABI,
  ERC20_ABI,
  getDeployer,
  resolveAddress,
} from "@astrolabs/hardhat";
import {
  ISwapperParams,
  ITransactionRequestWithEstimate,
  getAllTransactionRequests,
  getTransactionRequest,
  swapperParamsToString,
} from "@astrolabs/swapper";
import { assert } from "chai";
import {
  BigNumber,
  BigNumberish,
  Contract,
  Overrides
} from "ethers";
import { IStrategyDeploymentEnv } from "../src/types";

const maxTopup = BigNumber.from(weiToString(5 * 1e18));

export const indexes = Array.from({ length: 8 }, (_, index) => index);

/**
 * Overrides for different network chain IDs
 * @type {Object.<number, Overrides>}
 */
const networkOverrides: { [chainId: number]: Overrides } = {
  1: {
    gasLimit: 1e7,
  },
  56: {
    // gasLimit: 1e7,
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

export const ensureDeployer = (addr: string) =>
  getDeployer()
    .then(d => d.getAddress()
      .then(a => assert(a === addr, `Deployer address is not the expected one.`)));

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
    State ${step ?? ""
      }:\nBalances of ${tokenId}\n  - payer (eg. rescued strat): ${balances[0]
      }\n  - receiver (eg. rescuer): ${balances[1]}`);
  } else {
    if (typeof token === "string") token = await SafeContract.build(token);
    tokenId = `${token.sym} (${token.address})`;
    balances = await env.multicallProvider!.all([
      token.multi.balanceOf(payer),
      token.multi.balanceOf(receiver),
    ]);
    console.log(`
    State ${step ?? ""
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
    stratParams.slice(8, 8 + lastInputIndex),
    stratParams.slice(16, 16 + lastInputIndex),
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
    const asset = env.deployment!.asset;
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
    const inputs = await Promise.all(inputAddresses.map((input) => SafeContract.build(input))) as SafeContract[];
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
    available(): ${available / asset.weiPerUnit} (${available}wei) (${Math.round(totalAssets.lt(10) ? 0 : (available * 100) / totalAssets) / 100
      }%)
    totalRedemptionRequest(): ${strat.toAmount(
        totalRedemptionRequest,
      )} (${totalRedemptionRequest}wei)
    totalClaimableRedemption(): ${strat.toAmount(
        totalClaimableRedemption,
      )} (${totalClaimableRedemption}wei) (${Math.round(
        totalRedemptionRequest.lt(10)
          ? 0
          : (totalClaimableRedemption * 100) / totalRedemptionRequest,
      ) / 100
      }%)
    rewardsAvailable():\n${rewardTokens
        .map(
          (reward, index) =>
            `      -${reward.sym}: ${reward.toAmount(rewardsAvailable[index])} (${rewardsAvailable[index]
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
    input = new Contract(env.addresses!.tokens.WGAS, WETH_ABI, env.deployer);

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
    input = new Contract(o.input, ERC20_ABI, env.deployer);
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

  const output = new Contract(o.output, ERC20_ABI, env.deployer);
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
  const output = new Contract(asset, ERC20_ABI, env.deployer!);
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
      `Funding ${env.deployer.address} from ${env.gasUsedForFunding || "(auto)"
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
        env
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
  env?: IStrategyDeploymentEnv,
): Promise<number> {
  return (
    Number(
      (await getSwapperEstimate(from, to, inputWei, chainId, chainId, env))
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
  env?: IStrategyDeploymentEnv,
): Promise<BigNumber> {
  return BigNumber.from(
    (await getSwapperEstimate(from, to, inputWei, chainId, outputChainId, env))
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
  env?: IStrategyDeploymentEnv,
): Promise<ITransactionRequestWithEstimate | undefined> {
  const [input, output] = await Promise.all([from, to].map((s) => resolveAddress(s, env)));
  if (!input || !output)
    throw new Error(
      `Token ${from} or ${to} not found in addresses`,
    );
  if (input == output)
    return {
      estimatedOutputWei: inputWei,
      // estimatedOutput: Number(simulatedSwapSizeWei.toString()) / (10 ** (await (new Contract(input, ERC20_ABI, provider)).decimals()).toNumber?.()),
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

  while ((leftoverPositive - leftoverNegative) > 0) {
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
