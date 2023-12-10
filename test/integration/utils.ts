import { assert } from "chai";
import {
  Log,
  TransactionReceipt,
  TransactionRequest,
  TransactionResponse,
  getDeployer,
  loadAbi,
  network,
  provider,
  setBalances,
  weiToString,
} from "@astrolabs/hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { erc20Abi, wethAbi } from "abitype/abis";
import {
  Contract,
  constants,
  BigNumber,
  BigNumberish,
  Overrides,
} from "ethers";
import * as ethers from "ethers";
import { merge } from "lodash";
import { IChainlinkParams, IStrategyDeploymentEnv, ITestEnv } from "../../src/types";
import addresses, { Addresses } from "../../src/addresses";
import {
  ISwapperParams,
  swapperParamsToString,
  getAllTransactionRequests,
  getTransactionRequest,
  ITransactionRequestWithEstimate,
} from "@astrolabs/swapper";
import {
  Provider as MulticallProvider,
  Contract as MulticallContract,
  Call,
} from "ethcall";

export const addressZero = constants.AddressZero;
const MaxUint256 = ethers.constants.MaxUint256;
const maxTopup = BigNumber.from(weiToString(5 * 1e18));


export function isLive(env: any) {
  const n = env.network ?? network;
  return !["tenderly", "localhost", "hardhat"].some((s) => n?.name.includes(s));
}

export function isAddress(s: string) {
  return /^0x[a-fA-F0-9]{40}$/.test(s);
}

export function getAddresses(s: string) {
  return isAddress(s) ? s : addresses[network.config.chainId!].tokens[s];
}


const networkOverrides: { [name: string]: Overrides } = {
  "gnosis-mainnet": {
    gasLimit: 1e7,
    maxPriorityFeePerGas: 2e9,
    maxFeePerGas: 4e9,
    // gasPrice: 4e9,
  },
  tenderly: {
    gasLimit: 1e7,
  },
};

type AbiFragment = { name: string; inputs: [{ type: string }] };

// TODO: move to @astrolabs/hardhat/utils
export const getInitSignature = (contract: string) => {
  const fragments = (loadAbi(contract) as AbiFragment[]).filter(
    (a) => a.name === "init"
  );
  const dummy = new Contract(addressZero, fragments, provider!);
  return Object.keys(dummy)
    .filter((s) => s.startsWith("init"))
    .sort((s1, s2) => s2.length - s1.length)?.[0];
};

export function getSelectors(abi: any) {
  const i = new ethers.utils.Interface(abi);
  return Object.keys(i.functions).map((signature) => ({
    name: i.functions[signature].name,
    signature: i.getSighash(i.functions[signature]),
  }));
}
export const getOverrides = (env: Partial<ITestEnv>) =>
  isLive(env) ? {} : networkOverrides[env.network!.name] ?? {};

export const sleep = (ms: number) =>
  new Promise((resolve) => setTimeout(resolve, ms));

export const isStable = (s: string) =>
  [
    "USDC",
    "USDCe",
    "USDT",
    "USDTe",
    "DAI",
    "DAIe",
    "XDAI",
    "WXDAI",
    "SDAI",
    "FRAX",
    "LUSD",
    "USDD",
    "CRVUSD",
    "GHO",
    "EURS",
    "EURT",
    "EURTe",
    "agEUR",
    "USD",
    "EUR",
  ].includes(s.toUpperCase());

export const isStablePair = (s1: string, s2: string) =>
  isStable(s1) && isStable(s2);

export const isOracleLib = (name: string) =>
  ["Pyth", "RedStone", "Chainlink", "Witnet"].some((libname) =>
    name.includes(libname)
  );

export async function logState(
  env: Partial<IStrategyDeploymentEnv>,
  step?: string,
  sleepBefore = 0,
  sleepAfter = 0
) {
  const { strat, underlying, inputs, rewardTokens } = env.deployment!;
  if (sleepBefore) {
    console.log(`Sleeping ${sleepBefore}ms before logging state...`);
    await sleep(sleepBefore);
  }
  try {
    const [
      sharePrice,
      totalSupply,
      totalAccountedSupply,
      totalAssets,
      totalAccountedAssets,
      totalClaimableUnderlyingFees,
      available,
      // totalDepositRequest,
      totalRedemptionRequest,
      totalClaimableRedemption,
      // totalUnderlying, // only available on strat.req() struct
      // totalClaimableUnderlying, // only available on strat.req() struct
      rewardsAvailable,
      previewInvest,
      previewLiquidate,
      stratUnderlyingBalance,
      deployerUnderlyingBalance,
      deployerSharesBalance,
    ]: any[] = await env.multicallProvider!.all([
      strat.multi.sharePrice(),
      strat.multi.totalSupply(),
      strat.multi.totalAccountedSupply(),
      strat.multi.totalAssets(),
      strat.multi.totalAccountedAssets(),
      strat.multi.claimableUnderlyingFees(),
      strat.multi.available(),
      // strat.multicallContract.totalDepositRequest(),
      strat.multi.totalRedemptionRequest(),
      strat.multi.totalClaimableRedemption(),
      // strat.multicallContract.totalUnderlying(), // only available on strat.req() struct
      // strat.multicallContract.totalClaimableUnderlying(), // only available on strat.req() struct
      strat.multi.rewardsAvailable(),
      strat.multi.previewInvest(0),
      strat.multi.previewLiquidate(0),
      underlying.multi.balanceOf(strat.address),
      underlying.multi.balanceOf(env.deployer!.address),
      strat.multi.balanceOf(env.deployer!.address),
      // await underlyingTokenContract.balanceOf(strategy.address),
    ]);

    const inputsAddresses = inputs.map((input) => input.address);
    // await env.multicallProvider!.all(inputs.map((input, index) => strat.multi.inputs(index)));

    const rewardsAddresses = rewardTokens.map((reward) => reward.address);
    // await env.multicallProvider!.all(rewardTokens.map((input, index) => strat.multi.rewardTokens(index)));

    // ethcall only knows functions overloads, so we fetch invested() first then multicall the details for each input
    const invested = await strat["invested()"](); // base function (not overloaded)
    const investedAmounts: BigNumber[] = await env.multicallProvider!.all(
      inputs.map((input, index) => strat.multi.invested(index))
    );

    console.log(
      `State ${step ?? ""}:
    underlying: ${underlying.address}
    inputs: [${inputsAddresses.join(", ")}]
    rewardTokens: [${rewardsAddresses.join(", ")}]
    sharePrice(): ${underlying.toAmount(sharePrice)} (${sharePrice}wei)
    totalSuply(): ${underlying.toAmount(totalSupply)} (${totalSupply}wei)
    totalAccountedSupply(): ${underlying.toAmount(
      totalAccountedSupply
    )} (${totalAccountedSupply}wei)
    totalAssets(): ${underlying.toAmount(totalAssets)} (${totalAssets}wei)
    totalAccountedAssets(): ${underlying.toAmount(
      totalAccountedAssets
    )} (${totalAccountedAssets}wei)
    totalClaimableUnderlyingFees(): ${underlying.toAmount(
      totalClaimableUnderlyingFees
    )} (${totalClaimableUnderlyingFees}wei)
    invested(): ${underlying.toAmount(invested)} (${invested}wei)\n${inputs
      .map(
        (input, index) =>
          `      -${input.sym}: ${<any>(
            underlying.toAmount(investedAmounts[index])
          )} (${investedAmounts[index]}wei)`
      )
      .join("\n")}
    available(): ${available / underlying.weiPerUnit} (${available}wei) (${
      Math.round(totalAssets.lt(10) ? 0 : (available * 100) / totalAssets) / 100
    }%)
    totalRedemptionRequest(): ${
      totalRedemptionRequest / underlying.weiPerUnit
    } (${totalRedemptionRequest}wei)
    totalClaimableRedemption(): ${
      totalClaimableRedemption / underlying.weiPerUnit
    } (${totalClaimableRedemption}wei) (${
      Math.round(
        totalRedemptionRequest.lt(10)
          ? 0
          : (totalClaimableRedemption * 100) / totalRedemptionRequest
      ) / 100
    }%)
    rewardsAvailable():\n${rewardTokens
      .map(
        (reward, index) =>
          `      -${reward.sym}: ${reward.toAmount(
            rewardsAvailable[index]
          )} (${rewardsAvailable[index]}wei)`
      )
      .join("\n")}
    previewInvest(0 == available()*.9):\n${inputs
      .map(
        (input, i) =>
          `      -${input.sym}: ${underlying.toAmount(
            previewInvest[i]
          )} (${previewInvest[i].toString()}wei)`
      )
      .join("\n")}
    previewLiquidate(0 == pendingWithdrawRequests + invested()*.01):\n${inputs
      .map(
        (input, i) =>
          `      -${input.sym}: ${input.toAmount(
            previewLiquidate[i]
          )} (${previewLiquidate[i].toString()}wei)`
      )
      .join("\n")}
    stratUnderlyingBalance(): ${underlying.toAmount(
      stratUnderlyingBalance
    )} (${stratUnderlyingBalance}wei)
    deployerBalances(shares, underlying): [${underlying.toAmount(
      deployerSharesBalance
    )},${underlying.toAmount(deployerUnderlyingBalance)}]
    `
    );
    if (sleepAfter) await sleep(sleepAfter);
  } catch (e) {
    console.log(`Error logging state ${step ?? ""}: ${e}`);
  }
}

export const getEnv = async (
  env: Partial<ITestEnv> = {},
  addressesOverride?: Addresses
): Promise<ITestEnv> => {
  const addr = (addressesOverride ?? addresses)[network.config.chainId!];
  const deployer = await getDeployer();
  const multicallProvider = new MulticallProvider();
  await multicallProvider.init(provider);
  const live = isLive(env);
  if (live) env.revertState = false;
  return merge(
    {
      network,
      blockNumber: await provider.getBlockNumber(),
      snapshotId: live ? 0 : await provider.send("evm_snapshot", []),
      revertState: false,
      wgas: await SafeContract.build(addr.tokens.WGAS, wethAbi, env.deployer!),
      addresses: addr,
      deployer: deployer as SignerWithAddress,
      provider: provider,
      multicallProvider,
      needsFunding: false,
      gasUsedForFunding: 0, // denominated in wgas decimal
    },
    env
  );
};

export class SafeContract extends Contract {

  public multi: MulticallContract = {} as MulticallContract;
  public sym: string = '';
  public scale: number = 0;
  public weiPerUnit: number = 0;

  constructor(address: string, abi: ReadonlyArray<any>|any[]=erc20Abi, signer: SignerWithAddress|ethers.providers.JsonRpcProvider) {
      super(address, abi, signer);
  }

  public static async build(address: string, abi: ReadonlyArray<any>|any[]=erc20Abi, signer?: SignerWithAddress): Promise<SafeContract> {
    signer ||= await getDeployer() as SignerWithAddress;
    const c = new SafeContract(address, abi, signer);
    c.multi = new MulticallContract(address, abi as any[]);
    if ("symbol" in c) {
      // c is a token
      c.sym = await c.symbol?.();
      c.scale = await c.decimals?.();
      c.weiPerUnit = 10 ** c.scale ?? 0;  
    }
    return c;
  }

  public safe = async (fn: string, params: any[], opts: any = {}): Promise<any> => {
    if (typeof this[fn] != 'function')
      throw new Error(`${fn} does not exist on the contract ${this.address}`);
    try {
      await this.callStatic[fn](...params, opts);
    } catch (error) {
      throw new Error(`${fn} static call failed, tx not sent: ${error}`);
    }
    console.log(`${fn} static call succeeded, sending tx...`);
    return this[fn](...params, opts);
  };

  public toWei = (n: number | bigint | string | BigNumber): BigNumber => {
      return ethers.utils.parseUnits(n.toString(), this.scale);
  };

  public toAmount = (n: number | bigint | string | BigNumber): number => {
      const weiString = ethers.utils.formatUnits(n, this.scale);
      return parseFloat(weiString);
  };
}

async function _swap(env: Partial<IStrategyDeploymentEnv>, o: ISwapperParams) {
  if (o.inputChainId != network.config.chainId) {
    if (network.name.includes("tenderly")) {
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

  console.log(swapperParamsToString(o));

  let inputBalance = await input.balanceOf(o.payer);

  if (inputBalance.lt(o.amountWei)) {
    console.log(
      `payer ${o.payer} has not enough balance of ${o.inputChainId}:\n${o.input}, swapping from gasToken to ${o.input}`
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

  await input.approve(env.deployment!.swapper.address, MaxUint256.toString());
  const trs: TransactionRequest[] | undefined =
    (await getAllTransactionRequests(o)) as TransactionRequest[];
  assert(trs?.length);
  let received = BigNumber.from(0);
  for (const tr of trs) {
    assert(!!tr?.data);
    console.log(`using request: ${JSON.stringify(tr, null, 2)}`);
    await ensureWhitelisted(env.deployment!.swapper, [
      tr.from as string,
      tr.to!,
      o.input,
      o.output,
    ], env as IStrategyDeploymentEnv);
    const ok = await env.deployment!.swapper.swap(
      input.target ?? input.address,
      output.target ?? output.address,
      o.amountWei.toString(),
      "1",
      tr.to,
      tr.data,
      { gasLimit: Math.max(Number(tr.gasLimit ?? 0), 50_000_000) }
    );
    console.log(`received response: ${JSON.stringify(ok, null, 2)}`);
    received = (await output.balanceOf(o.payer)).sub(outputBalanceBeforeSwap);
    console.log(`received ${received} ${o.output}`);
    if (received.gt(0)) break;
  }
  assert(received.gt(1));
}

export async function fundAccount(
  env: Partial<IStrategyDeploymentEnv>,
  amount: number | BigNumber,
  asset: string,
  receiver: string
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

async function ensureWhitelisted(
  contract: SafeContract | any,
  addresses: string[],
  env: IStrategyDeploymentEnv
) {
  // check if isWhitelisted and addToWhitelist exist on the contract
  for (const method of ["isWhitelisted", "addToWhitelist"]) {
    if (!(method in contract)) {
      console.error(
        `Skipping whitelisting as ${method} is not available on ${contract.address}`
      );
      return;
    }
  }
  const whitelisted = await env.multicallProvider!.all(
    addresses.map((addr) => contract.multi.isWhitelisted(addr))
  );
  whitelisted.map(async (isWhitelisted, i) => {
    if (!isWhitelisted) {
      console.log(`whitelisting ${addresses[i]}`);
      await contract.addToWhitelist(addresses[i]);
    }
  });
}

export async function ensureFunding(env: IStrategyDeploymentEnv) {
  if (isLive(env)) {
    console.log(
      `Funding is only applicable to test forks and testnets, not ${env.network.name}`
    );
    return;
  }

  const underlyingSymbol = env.deployment!.underlying.sym;
  const underlyingAddress = env.deployment!.underlying.address;
  const minLiquidity = underlyingSymbol.includes("USD") ? 1e8 : 5e16; // 100 USDC or 0.05 ETH
  const underlyingBalance = await env.deployment!.underlying.balanceOf(
    env.deployer.address
  );
  if (underlyingBalance.lt(minLiquidity)) {
    console.log(
      `${env.deployer.address} needs at least ${minLiquidity}${underlyingSymbol} => funding required`
    );
    env.needsFunding = true;
  }

  if (env.needsFunding) {
    console.log(
      `Funding ${env.deployer.address} from ${env.gasUsedForFunding}wei ${env.wgas.sym} (gas tokens) to ${minLiquidity}wei ${underlyingSymbol}`
    );
    let gas =
      env.gasUsedForFunding ||
      (await getSwapperOutputEstimate(
        "USDC",
        env.wgas.sym,
        50_005 * 1e6,
        network.config.chainId!,
        network.config.chainId!
      )) ||
      0;
    if (!gas) {
      throw new Error(
        `Failed to get gas estimate for ${env.wgas.sym} => ${underlyingSymbol}`
      );
    }
    console.log(
      `Balance before funding: ${underlyingBalance}wei ${underlyingSymbol}`
    );
    const nativeBalance = await provider.getBalance(env.deployer.address);
    if (nativeBalance.lt(gas)) {
      console.log(
        `Funding ${env.deployer.address} with ${gas}wei ${env.wgas.sym} (gas tokens)`
      );
      // if not enough gas tokens, add it
      // await setBalances(gas, env.deployer.address);
      await env.provider.send("tenderly_setBalance", [
        [env.deployer.address],
        ethers.utils.hexValue(gas),
      ])
    }
    const received = await fundAccount(
      env,
      gas,
      underlyingAddress,
      env.deployer.address
    );
    console.log(
      `Balance after funding: ${underlyingBalance.add(
        received
      )}wei ${underlyingSymbol} (+${received})`
    );
  }
}

export async function ensureOracleAccess(env: IStrategyDeploymentEnv) {
  if (isLive(env)) {
    console.log(
      `Oracle access is only applicable to test forks and testnets, not ${env.network.name}`
    );
    return;
  }
  const params = env.deployment!.initParams[1] as IChainlinkParams;
  for (const lib of Object.keys(env.deployment!.units!)) {
    if (isOracleLib(lib)) {
      console.log(`Whitelisting oracle access for ${lib}`);
      switch (lib) {
        case "ChainlinkUtils": {
          const oracles = new Set([params.underlyingPriceFeed, ...params.inputPriceFeeds]);
          for (const oracle of oracles) {
            const storageSlot = '0x0000000000000000000000000000000000000000000000000000000000000031';
            // set the storage slot for Chainlink's "checkEnabled" to false, in order to deactivate access control
            const newValue = '0x0000000000000000000000000000000000000000000000000000000000000000';
            // Sending the tenderly_setStorageAt command
            await provider.send("tenderly_setStorageAt", [
              oracle,
              storageSlot,
              newValue,
            ]);
          }
        }
      }
    }
  }
}

export function getTxLogData(
  tx: TransactionReceipt,
  types = ["uint256"],
  outputIndex = 0,
  logIndex: string | number = -1
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
      `Failed to parse log ${e}: tx ${tx.transactionHash} probably reverted`
    );
    return undefined;
  }
}

export async function getSwapperRateEstimate(
  from: string,
  to: string,
  inputWei: BigNumberish | bigint,
  chainId = 1
): Promise<number> {
  return (
    Number(
      (await getSwapperEstimate(from, to, inputWei, chainId))
        ?.estimatedExchangeRate
    ) ?? 0
  );
}

export async function getSwapperOutputEstimate(
  from: string,
  to: string,
  inputWei: BigNumberish | bigint,
  chainId = 1,
  outputChainId?: number
): Promise<BigNumber> {
  return BigNumber.from(
    (await getSwapperEstimate(from, to, inputWei, chainId, outputChainId))
      ?.estimatedOutputWei ?? 0
  );
}

export async function getSwapperEstimate(
  from: string, // "USDC"
  to: string, // "AVAX"
  inputWei: BigNumberish | bigint,
  inputChainId = 1,
  outputChainId?: number
): Promise<ITransactionRequestWithEstimate | undefined> {
  const [input, output] = [from, to].map((s) => getAddresses(s));
  if (!input || !output)
    throw new Error(
      `Token ${from} or ${to} not found in addresses.ts:ethereum`
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
