import { assert } from "chai";
import {
  Log,
  TransactionReceipt,
  TransactionRequest,
  TransactionResponse,
  ethers,
  getDeployer,
  loadAbi,
  network,
  provider,
  weiToString
} from "@astrolabs/hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { erc20Abi, wethAbi } from "abitype/abis";
import { Contract, constants, BigNumber, utils as ethersUtils, Overrides } from "ethers";
import { merge } from "lodash";
import {
  IStrategyDeploymentEnv,
  ITestEnv,
  IToken
} from "../../src/types";
import addresses, { Addresses } from "../../src/addresses";
import { ISwapperParams, swapperParamsToString, getAllTransactionRequests } from "@astrolabs/swapper";
import { Provider as MulticallProvider, Contract as MulticallContract, Call } from "ethcall";


export const addressZero = constants.AddressZero;
const MaxUint256 = ethers.constants.MaxUint256;
const maxTopup = BigNumber.from(weiToString(5 * 1e18));

export async function logState(
  env: Partial<IStrategyDeploymentEnv>,
  step?: string,
  sleepBefore = 0,
  sleepAfter = 0
) {
  const { strat, underlying } = env.deployment!;
  if (sleepBefore) {
    console.log(`Sleeping ${sleepBefore}ms before logging state...`)
    await sleep(sleepBefore);
  }
  try {
    const [
      inputsAddresses,
      rewardTokensAddresses,
      sharePrice,
      totalSupply,
      totalAssets,
      invested,
      available,
      totalDepositRequest,
      totalRedemptionRequest,
      totalClaimableRedemption,
      stratUnderlyingBalance,
      deployerUnderlyingBalance,
      deployerSharesBalance
    ]: any[] = await env.multicallProvider!.all([
      strat.multicallContract.inputs(0),
      strat.multicallContract.rewardTokens(0),
      strat.multicallContract.sharePrice(),
      strat.multicallContract.totalSupply(),
      strat.multicallContract.totalAssets(),
      strat.multicallContract.invested(),
      strat.multicallContract.available(),
      strat.multicallContract.totalDepositRequest(),
      strat.multicallContract.totalRedemptionRequest(),
      strat.multicallContract.totalClaimableRedemption(),
      underlying.multicallContract.balanceOf(strat.contract.address),
      underlying.multicallContract.balanceOf(env.deployer!.address),
      strat.multicallContract.balanceOf(env.deployer!.address),
      // await underlyingTokenContract.balanceOf(strategy.address),
    ]);

    console.log(
      `State ${step ?? ""}:
      underlying: ${underlying.contract.address}
      inputs[0]: ${inputsAddresses}
      rewardTokens[0]: ${rewardTokensAddresses}
      sharePrice(): ${sharePrice/underlying.weiPerUnit} (${sharePrice}wei)
      totalSuply(): ${totalSupply/underlying.weiPerUnit} (${totalSupply}wei)
      totalAssets(): ${totalAssets/underlying.weiPerUnit} (${totalAssets}wei)
      invested(): ${invested/underlying.weiPerUnit} (${invested}wei)
      available(): ${available/underlying.weiPerUnit} (${available}wei) (${Math.round(available*100/totalAssets)/100}%)
      stratUnderlyingBalance(): ${stratUnderlyingBalance/underlying.weiPerUnit} (${stratUnderlyingBalance}wei)
      deployerBalances(shares, underlying): [${deployerSharesBalance/underlying.weiPerUnit},${deployerUnderlyingBalance/underlying.weiPerUnit}]
      totalRedemptionRequest(): ${totalRedemptionRequest/underlying.weiPerUnit} (${totalRedemptionRequest}wei)
      totalClaimableRedemption(): ${totalClaimableRedemption/underlying.weiPerUnit} (${totalClaimableRedemption}wei) (${Math.round(totalClaimableRedemption*100/totalRedemptionRequest)/100}%)
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
  const wgas = new Contract(addr.tokens.WGAS, erc20Abi, await getDeployer());
  const deployer = await getDeployer();
  const multicallProvider = new MulticallProvider();
  await multicallProvider.init(provider);

  return merge(
    {
      network,
      blockNumber: await provider.getBlockNumber(),
      snapshotId: isLive(env) ? 0 : await provider.send("evm_snapshot", []),
      revertState: false,
      wgas: {
        contract: wgas,
        symbol: await wgas.symbol(),
        decimals: await wgas.decimals(),
        weiPerUnit: 10 ** (await wgas.decimals()),
      },
      addresses: addr,
      deployer: deployer as SignerWithAddress,
      provider: ethers.provider,
      multicallProvider,
      needsFunding: false,
      gasUsedForFunding: 1e21,
    },
    env
  );
};

export const getTokenInfo = async (address: string, abi=erc20Abi, deployer?: SignerWithAddress): Promise<IToken> => {
  if (!Array.isArray(abi) || !abi.filter)
    throw new Error(`ABI must be an array`);
  const contract = new Contract(address, abi, await getDeployer());
  return {
    contract,
    multicallContract: new MulticallContract(contract.address, abi as any),
    symbol: await contract.symbol(),
    decimals: await contract.decimals(),
    weiPerUnit: 10 ** (await contract.decimals()),
  }
};


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
      `payer ${o.payer} has not enough balance of ${o.inputChainId}:${o.input}, swapping from gasToken to ${o.input}`
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
    ]);
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
  amount: number,
  asset: string,
  receiver: string
): Promise<void> {
  const output = new Contract(asset, erc20Abi, env.deployer!);
  const balanceBefore = await output.balanceOf(receiver);
  let balanceAfter = balanceBefore;
  let retries = 3;
  while (balanceAfter <= balanceBefore && retries--) {
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

async function ensureWhitelisted(contract: Contract|any, addresses: string[]) {
  // check if isWhitelisted and addToWhitelist exist on the contract
  for (const method of ["isWhitelisted", "addToWhitelist"]) {
    if (!(method in contract)) {
      console.error(`Skipping whitelisting as ${method} is not available on ${contract.address}`);
      return;
    }
  }
  const whitelistPromises = addresses.map(async (addr) => {
    const isWhitelisted = await contract.isWhitelisted(addr);
    if (!isWhitelisted) {
      console.log(`whitelisting ${addr}`);
      await contract.addToWhitelist(addr);
      assert(
        await contract.isWhitelisted(addr),
        `Address ${addr} could not be whitelisted`
      );
    }
  });

  await Promise.all(whitelistPromises);
}

export async function ensureFunding(env: IStrategyDeploymentEnv) {

  if (isLive(env)) {
    console.log(
      `Funding is only applicable to test forks and testnets, not ${env.network.name}`
    );
    return;
  }

  const underlyingSymbol = env.deployment!.underlying.symbol;
  const underlyingAddress = env.deployment!.underlying.contract.address;
  const minLiquidity = underlyingSymbol.includes("USD") ? 1e8 : 5e16; // 100 USDC or 0.05 ETH
  const underlyingBalance = await env.deployment!.underlying.contract.balanceOf(
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
      `Funding ${env.deployer.address} from ${env.gasUsedForFunding}wei ${env.wgas.symbol} (gas tokens) to ${minLiquidity}wei ${underlyingSymbol}`
    );
    let gas = env.gasUsedForFunding;
    if (["BTC", "ETH"].some((s) => s.includes(env.wgas.symbol.toUpperCase())))
      gas /= 1000; // less gas tokens or swaps will fail
    console.log(`Balance before funding: ${underlyingBalance}wei ${underlyingSymbol}`);
    const received = await fundAccount(
      env,
      gas,
      underlyingAddress,
      env.deployer.address
    );
    console.log(`Balance after funding: ${underlyingBalance.add(received)}wei ${underlyingSymbol} (+${received})`);
  }
}

export function getTxLogData(tx: TransactionReceipt, types=["uint256"], logIndex: string|number=-1): any {
  const logs = (tx as any).events || tx.logs;
  let log: Log;
  if (typeof logIndex === "string") {
    log = logs.find((l: any) => l?.event === logIndex) as Log;
  } else {
    if (logIndex < 0)
      logIndex = logs.length + logIndex;
    log = logs[logIndex];
  }
  if (!log) throw new Error(`No log ${logIndex} found on tx ${tx.transactionHash}`);
  return ethersUtils.defaultAbiCoder.decode(types, log.data);
}

export function isLive(env: any) {
  const n = env.network ?? network;
  return !["tenderly", "localhost", "hardhat"].some((s) => n?.name.includes(s));
}

const networkOverrides: { [name: string]: Overrides } = {
  "gnosis-mainnet": {
    gasLimit: 1e7,
    maxPriorityFeePerGas: 2e9,
    maxFeePerGas: 4e9,
    // gasPrice: 4e9,
  },
  "tenderly": {
    gasLimit: 1e7,
  }
}

type AbiFragment = { name: string, inputs: [{ type: string }] };

export const getInitSignature = (contract: string) => {
  const fragments = (loadAbi(contract) as AbiFragment[])
    .filter((a) => a.name === "init");
  const dummy = new Contract(addressZero, fragments, provider);
  return Object.keys(dummy).sort(s => s.length)[0];
}
export const getOverrides = (env: Partial<ITestEnv>) => isLive(env) ? {} : networkOverrides[network.name] ?? {};
export const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
