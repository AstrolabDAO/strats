import { provider, network, ethers, weiToString, TransactionRequest, IDeploymentUnit, deploy, deployAll, loadAbi } from "@astrolabs/hardhat";
import { ISwapperParams, swapperParamsToString, getAllTransactionRequests, getTransactionRequest, ITransactionRequestWithEstimate } from "@astrolabs/swapper";
import { wethAbi, erc20Abi } from "abitype/abis";
import { BigNumber, Contract } from "ethers";
import { assert } from "chai";
import { merge } from "lodash";
import { IStrategyDeployment, IStrategyDeploymentEnv, IStrategyV5Params, IToken } from "../../src/types";
import { addressZero, getEnv, logState } from "./utils";

const MaxUint256 = ethers.constants.MaxUint256;
const maxTopup = BigNumber.from(weiToString(5 * 1e18));


export const deployStrat = async (
  name: string,
  contract: string,
  params: Partial<IStrategyV5Params>,
  env: Partial<IStrategyDeploymentEnv> = {}
): Promise<IStrategyDeployment> => {
  let [swapper, agent] = [{}, {}] as Contract[];

  // strategy dependencies
  const libNames = new Set([
    // no need to add AsMaths as imported and use by AsAccounting
    "AsAccounting",
  ]);
  const libraries: { [name: string]: string } = {};

  for (const n of libNames) {
    let lib = {} as Contract;
    const path = `src/libs/${n}.sol:${n}`;
    if (!libraries[path]) {
      const params = {
        contract: n,
        name: n,
        verify: true,
        deployed: env.addresses?.libs?.[n] ? true : false,
        address: env.addresses?.libs?.[n] ?? "",
      } as IDeploymentUnit;
      console.log(`Deploying missing library ${n}`);
      // deployment will be automatically skipped if address is already set
      lib = await deploy(params);
    } else {
      console.log(`Using existing ${n} at ${lib.address}`);
      lib = new Contract(libraries[path], loadAbi(n) ?? [], env.deployer);
    }
    libraries[path] = lib.address;
  }

  const units: { [name: string]: IDeploymentUnit } = {
    Swapper: {
      contract: "Swapper",
      name: "Swapper",
      verify: true,
      deployed: env.addresses!.astrolab!.Swapper ? true : false,
      address: env.addresses!.astrolab!.Swapper ?? "",
    },
    StrategyAgentV5: {
      contract: "StrategyAgentV5",
      name: "StrategyAgentV5",
      libraries,
      verify: true,
      deployed: env.addresses!.astrolab!.StrategyAgentV5 ? true : false,
      address: env.addresses!.astrolab!.StrategyAgentV5,
    },
    [contract]: {
      contract,
      name: contract,
      verify: true,
      proxied: ["StrategyAgentV5"],
      args: [params.erc20Metadata],
      libraries,
    },
  };

  for (const [libName, libAddress] of Object.entries(libraries)) {
    units[libName] = {
      contract: libName,
      name: libName,
      verify: true,
      deployed: true,
      address: libAddress,
    };
  }

  if (!env.addresses!.astrolab!.Swapper) {
    console.log(`Deploying missing Swapper`);
    swapper = await deploy(units.Swapper);
  } else {
    console.log(
      `Using existing Swapper at ${env.addresses!.astrolab!.Swapper}`
    );
    swapper = new Contract(
      env.addresses!.astrolab!.Swapper!,
      loadAbi("Swapper")!,
      env.deployer
    );
  }

  if (!env.addresses!.astrolab!.StrategyAgentV5) {
    console.log(`Deploying missing StrategyAgentV5`);
    agent = await deploy(units.StrategyAgentV5);
  } else {
    console.log(
      `Using existing StrategyAgentV5 at ${
        env.addresses!.astrolab!.StrategyAgentV5
      }`
    );
    agent = new Contract(
      env.addresses!.astrolab!.StrategyAgentV5,
      loadAbi("StrategyAgentV5")!,
      env.deployer
    );
  }

  params.fees = merge(
    {
      perf: 1_000, // 10%
      mgmt: 20, // .2%
      entry: 2, // .02%
      exit: 2, // .02%
    },
    params.fees
  );

  params.coreAddresses = [
    env.deployer!.address, // feeCollector
    swapper.address, // Swapper
    addressZero, // Allocator
    agent.address, // StrategyAgentV5
  ];

  if (params.inputs?.length == 1) params.inputWeights = [100_000]; // 100%

  const deployment = {
    name: "",
    contract: "",
    params,
    verify: true,
    libraries,
    swapper,
    agent,
    // deployer/provider
    deployer: env.deployer,
    provider: env.provider,
    // deployment units
    units,
  } as IStrategyDeployment;

  await deployAll(deployment);
  if (!deployment.units![contract].address) {
    throw new Error(`Could not deploy ${contract}`);
  }
  deployment.strat = new Contract(
    deployment.units![contract].address!,
    loadAbi("StrategyV5")!,
    deployment.deployer
  );
  return deployment;
};

export async function grantAdminRole(strat: Contract, address: string) {
  const keeperRole = await strat.KEEPER_ROLE();
  const managerRole = await strat.MANAGER_ROLE();

  await strat.grantRole(keeperRole, address);
  await strat.grantRole(managerRole, address);
}

export async function setupStrat(
  contract: string,
  name: string,
  // below we use hop strategy signature as placeholder
  initSignature = "init",
  params: Partial<IStrategyV5Params>,
  env: Partial<IStrategyDeploymentEnv> = {},
  addressesOverride?: any
): Promise<IStrategyDeploymentEnv> {
  env = await getEnv(env, addressesOverride);
  const d = await deployStrat(name, contract, params, env);

  await grantAdminRole(d.strat, d.deployer!.address);

  // exclude erc20Metadata from init args as already passed to constructor
  const initArgs = params as any;
  delete initArgs.erc20Metadata;

  // load the implementation abi, containing the overriding init() (missing from d.strat)
  const proxy = new Contract(contract, loadAbi(contract)!, d.deployer);
  const ok = await proxy[initSignature](...Object.values(initArgs), {
    gasLimit: 5e7,
  });

  await logState(env, "After init");

  const underlying = new Contract(params.underlying!, erc20Abi, d.deployer);
  const inputs = params.inputs!.map(
    (input) => new Contract(input, erc20Abi, d.deployer)
  );
  const rewardTokens = params.rewardTokens!.map(
    (rewardToken) => new Contract(rewardToken, erc20Abi, d.deployer)
  );

  env.deployment!.underlying = {
    contract: underlying,
    symbol: await underlying.symbol(),
    decimals: await underlying.decimals(),
    weiPerUnit: 10 ** (await underlying.decimals()),
  } as IToken;

  env.deployment!.inputs = await Promise.all(
    inputs.map(
      async (input) =>
        ({
          contract: input,
          symbol: await input.symbol(),
          decimals: await input.decimals(),
          weiPerUnit: 10 ** (await input.decimals()),
        }) as IToken
    )
  );

  env.deployment!.rewardTokens = await Promise.all(
    rewardTokens.map(
      async (rewardToken) =>
        ({
          contract: rewardToken,
          symbol: await rewardToken.symbol(),
          decimals: await rewardToken.decimals(),
          weiPerUnit: 10 ** (await rewardToken.decimals()),
        }) as IToken
    )
  );

  return env as IStrategyDeploymentEnv;
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
    input = await ethers.getContractAt("IERC20Metadata", o.input);
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

  const output = await ethers.getContractAt("IERC20Metadata", o.output);
  const outputBalanceBeforeSwap = await output.balanceOf(o.payer);

  await input.approve(env.deployment!.swapper.target, MaxUint256.toString());
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

export async function ensureFunding(env: IStrategyDeploymentEnv) {
  if (
    !["tenderly", "localhost", "hardhat"].some((s) =>
      env.network.name.includes(s)
    )
  ) {
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

export async function seedLiquidity(
  env: IStrategyDeploymentEnv,
  amount?: number
) {
  const { strat, underlying } = env.deployment!;
  amount ||= underlying.weiPerUnit * 100;
  await underlying.contract.approve(strat.address, MaxUint256);
  await logState(env, "Before SeedLiquidity");
  await strat.seedLiquidity(amount, MaxUint256, { gasLimit: 5e7 });
  await logState(env, "After SeedLiquidity");
  // assert((await strat.balanceOf(env.deployer.address)).gt(0));
  return await strat.available();
}

export async function deposit(env: IStrategyDeploymentEnv, amount?: number) {
  const { strat, underlying } = env.deployment!;
  amount ||= underlying.weiPerUnit * 100; // 100$ or equivalent
  await underlying.contract.approve(strat.address, MaxUint256);
  await logState(env, "Before Deposit");
  const received = await strat.safeDeposit(amount, env.deployer.address, 1, {
    gasLimit: 5e7,
  });
  await logState(env, "After Deposit");
  // assert(received.gt(0));
  return received;
}


export async function swapDeposit(
  env: IStrategyDeploymentEnv,
  inputAddress?: string,
  amount?: number
) {
  const { strat, underlying } = env.deployment!;
  amount ||= underlying.weiPerUnit * 100; // 100$ or equivalent

  const input = new Contract(inputAddress!, erc20Abi, env.deployer);
  await underlying.contract.approve(strat.address, MaxUint256);
  await input.approve(strat.address, MaxUint256);

  let swapData: any = [];
  if (underlying.contract.address != input.address) {
    const tr = (await getTransactionRequest({
      input: input.address,
      output: underlying.contract.address,
      amountWei: weiToString(amount),
      inputChainId: network.config.chainId!,
      payer: strat.address,
      testPayer: env.addresses!.accounts!.impersonate,
    })) as ITransactionRequestWithEstimate;
    swapData = ethers.utils.defaultAbiCoder.encode(
      ["address", "uint256", "bytes"],
      [tr.to, 1, tr.data]
    );
  }
  await logState(env, "Before SwapDeposit");
  const received = await strat.swapSafeDeposit(
    input.address, // input
    amount, // amount == 100$
    env.deployer.address, // receiver
    1, // minShareAmount in wei
    swapData, // swapData
    { gasLimit: 5e7 }
  );
  await logState(env, "After SwapDeposit");
  return received;
}

// TODO: add support for multiple inputs
// input prices are required to weight out the swaps and create the SwapData array
export async function invest(env: IStrategyDeploymentEnv, amount?: number) {
  const { underlying, inputs, strat } = env.deployment!;
  amount ||= inputs[0].weiPerUnit * 100; // 100$ or equivalent
  let swapData: any = [];
  if (underlying.contract.address != inputs[0].contract.address) {
    console.log("SwapData required by invest() as underlying != input");
    const tr = (await getTransactionRequest({
      input: underlying.contract.address,
      output: inputs[0].contract.address,
      amountWei: BigInt(amount).toString(),
      inputChainId: network.config.chainId!,
      payer: strat.address,
      testPayer: env.addresses.accounts!.impersonate,
    })) as ITransactionRequestWithEstimate;
    swapData = ethers.utils.defaultAbiCoder.encode(
      ["address", "uint256", "bytes"],
      [tr.to, 1, tr.data]
    );
  }
  await logState(env, "Before Invest");
  const received = await strat.invest(amount, 1, [swapData], { gasLimit: 5e7 });
  await logState(env, "After Invest");
  // assert((await strat.balanceOf(env.deployer.address)).gt(0));
  return received;
}

export async function withdraw(env: IStrategyDeploymentEnv, amount?: number) {
  const { underlying, inputs, strat } = env.deployment!;
  amount ||= underlying.weiPerUnit * 10; // 10$ or equivalent
  const minAmount = 1; // TODO: change with staticCall
  await logState(env, "Before Withdraw");
  const received = await strat.safeWithdraw(
    amount, minAmount,
    env.deployer.address, env.deployer.address,
    { gasLimit: 5e7 }
  );
  await logState(env, "After Withdraw");
  return received;
}

// TODO: add support for multiple inputs
// input prices are required to weight out the swaps and create the SwapData array
export async function liquidate(env: IStrategyDeploymentEnv, amount?: number) {
  const { underlying, inputs, strat } = env.deployment!;
  amount ||= inputs[0].weiPerUnit * 10; // 10$ or equivalent
  let balanceBefore = await underlying.contract.balanceOf(env.deployer.address);
  let swapData: any = [];
  const tr = (await getTransactionRequest({
    input: inputs[0].contract.address,
    output: underlying.contract.address,
    amountWei: BigInt(amount).toString(),
    inputChainId: network.config.chainId!,
    payer: env.deployer.address,
    testPayer: env.addresses.accounts!.impersonate,
  })) as ITransactionRequestWithEstimate;
  swapData = ethers.utils.defaultAbiCoder.encode(
    ["address", "uint256", "bytes"],
    [tr.to, 1, tr.data]
  );
  const [liquidity, totalAssets] = await strat.liquidate(amount, 1, false,  [swapData]);
  const liquidated = balanceBefore.sub(await underlying.contract.balanceOf(env.deployer.address));
  // assert(liquidated.gt(0));
  return liquidated;
}
