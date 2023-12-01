import { IDeploymentUnit, TransactionResponse, deploy, deployAll, ethers, loadAbi, network } from "@astrolabs/hardhat";
import { ITransactionRequestWithEstimate, getTransactionRequest } from "@astrolabs/swapper";
import { erc20Abi } from "abitype/abis";
import { Contract, BigNumber, utils as ethersUtils } from "ethers";
import { get, merge } from "lodash";
import { Erc20Metadata, IStrategyDeployment, IStrategyDeploymentEnv, ITestEnv, IStrategyBaseParams, IToken } from "../../src/types";
import { addressZero, getEnv, getInitSignature, getOverrides, getTokenInfo, getTxLogData, isLive, logState, sleep } from "./utils";

const MaxUint256 = ethers.constants.MaxUint256;

export const deployStrat = async (
  env: Partial<IStrategyDeploymentEnv>,
  name: string,
  contract: string,
  constructorParams: [Erc20Metadata],
  initParams: [IStrategyBaseParams, ...any],
  libNames = ["AsAccounting"],
): Promise<IStrategyDeploymentEnv> => {

  let [swapper, agent] = [{}, {}] as Contract[];

  // strategy dependencies
  const libraries: { [name: string]: string } = {};
  const contractUniqueName = `${contract}.${env.deployment?.inputs?.map(i => i.symbol).join("-")}`; // StrategyV5.[inputAddresses.join("-")]

  for (const n of libNames) {
    let lib = {} as Contract;
    const path = `src/libs/${n}.sol:${n}`;
    if (!libraries[path]) {
      const libParams = {
        contract: n,
        name: n,
        verify: true,
        deployed: env.addresses?.libs?.[n] ? true : false,
        address: env.addresses?.libs?.[n] ?? "",
      } as IDeploymentUnit;
      // console.log(`Deploying missing library ${n}`);
      // deployment will be automatically skipped if address is already set
      lib = await deploy(libParams);
    } else {
      console.log(`Using existing ${n} at ${lib.address}`);
      lib = new Contract(libraries[path], loadAbi(n) ?? [], env.deployer);
    }
    libraries[path] = lib.address;
  }

  // exclude oracle libraries from agentLibs
  // as these are specific to the strategy implementation
  const agentLibs = Object.assign({}, libraries);
  for (const lib of Object.keys(agentLibs)) {
    if (["Pyth", "RedStone", "Chainlink", "Witnet"]
      .some((oracleName) => lib.includes(oracleName))) {
      delete agentLibs[lib];
    }
  }

  const units: { [name: string]: IDeploymentUnit } = {
    Swapper: {
      contract: "Swapper",
      name: "Swapper",
      verify: true,
      deployed: env.addresses!.astrolab?.Swapper ? true : false,
      address: env.addresses!.astrolab?.Swapper ?? "",
    },
    StrategyAgentV5: {
      contract: "StrategyAgentV5",
      name: "StrategyAgentV5",
      libraries: agentLibs,
      verify: true,
      deployed: env.addresses!.astrolab?.StrategyAgentV5 ? true : false,
      address: env.addresses!.astrolab?.StrategyAgentV5,
      overrides: getOverrides(env),
    },
    [contract]: {
      contract,
      name: contract,
      verify: true,
      deployed: env.addresses!.astrolab?.[contractUniqueName] ? true : false,
      address: env.addresses!.astrolab?.[contractUniqueName],
      proxied: ["StrategyAgentV5"],
      args: constructorParams,
      overrides: getOverrides(env),
      libraries, // External libraries are only used in StrategyAgentV5
    },
  };

  for (const libName of libNames) {
    units[libName] = {
      contract: libName,
      name: libName,
      verify: true,
      deployed: true,
      address: libraries[libName] ?? libraries[`src/libs/${libName}.sol:${libName}`],
    };
  }

  if (!env.addresses!.astrolab?.Swapper) {
    console.log(`Deploying missing Swapper`);
    swapper = await deploy(units.Swapper);
  } else {
    console.log(
      `Using existing Swapper at ${env.addresses!.astrolab?.Swapper}`
    );
    swapper = new Contract(
      env.addresses!.astrolab?.Swapper!,
      loadAbi("Swapper")!,
      env.deployer
    );
  }

  if (!env.addresses!.astrolab?.StrategyAgentV5) {
    console.log(`Deploying missing StrategyAgentV5`);
    agent = await deploy(units.StrategyAgentV5);
  } else {
    console.log(
      `Using existing StrategyAgentV5 at ${env.addresses!.astrolab?.StrategyAgentV5
      }`
    );
    agent = new Contract(
      env.addresses!.astrolab?.StrategyAgentV5,
      loadAbi("StrategyAgentV5")!,
      env.deployer
    );
  }

  // default fees
  initParams[0].fees = merge(
    {
      perf: 1_000, // 10%
      mgmt: 20, // .2%
      entry: 2, // .02%
      exit: 2, // .02%
    },
    initParams[0]
  );

  // coreAddresses
  initParams[0].coreAddresses = [
    env.deployer!.address, // feeCollector
    swapper.address, // Swapper
    agent.address, // StrategyAgentV5
  ];

  // inputs
  if (initParams[0].inputWeights.length == 1)
    // default input weight == 100%
    initParams[0].inputWeights = [10_000];

  merge(env.deployment, {
    name: `${name} Stack`,
    contract: "",
    constructorParams,
    initParams,
    verify: true,
    libraries,
    swapper,
    agent,
    // deployer/provider
    deployer: env.deployer,
    provider: env.provider,
    // deployment units
    units,
    inputs: [] as IToken[],
    rewardTokens: [] as IToken[],
    underlying: {} as IToken,
    strat: {} as IToken,
  } as IStrategyDeployment);

  await deployAll(env.deployment!);

  if (!env.deployment!.units![contract].address) {
    throw new Error(`Could not deploy ${contract}`);
  }

  const stratProxyAbi = loadAbi("StrategyV5") as any;
  env.deployment!.strat = await getTokenInfo(
    env.deployment!.units![contract].address!,
    stratProxyAbi);
  env.deployment = env.deployment;
  return env as IStrategyDeploymentEnv;
};

export async function grantManagerRole(env: Partial<IStrategyDeploymentEnv>, address: string) {
  const { strat } = env.deployment!;
  const [keeperRole, managerRole] = await Promise.all([
    strat.contract.KEEPER_ROLE(),
    strat.contract.MANAGER_ROLE()
  ]);
  // await env.multicallProvider!.all([
  //   strat.multicallContract.grantRole(keeperRole, address),
  //   strat.multicallContract.grantRole(managerRole, address),
  // ]);
  for (const role of [keeperRole, managerRole]) {
    if (!(await strat.contract.hasRole(role, address)))
      await strat.contract.grantRole(role, address, getOverrides(env)).then((tx: TransactionResponse) => tx.wait());
  }
}

export async function setupStrat(
  contract: string,
  name: string,
  // below we use hop strategy signature as placeholder
  constructorParams: [Erc20Metadata],
  initParams: [IStrategyBaseParams, ...any],
  libNames = ["AsAccounting"],
  env: Partial<IStrategyDeploymentEnv> = {},
  addressesOverride?: any
): Promise<IStrategyDeploymentEnv> {

  env = await getEnv(env, addressesOverride);
  env.deployment = {
    underlying: await getTokenInfo(initParams[0].underlying),
    inputs: await Promise.all(initParams[0].inputs!.map((input) => getTokenInfo(input))),
    rewardTokens: await Promise.all(initParams[0].rewardTokens!.map((rewardToken) => getTokenInfo(rewardToken))),
  } as any;

  env = await deployStrat(env, name, contract, constructorParams, initParams, libNames);

  const { strat } = env.deployment!;

  await grantManagerRole(env, env.deployer!.address);

  // load the implementation abi, containing the overriding init() (missing from d.strat)
  // init((uint64,uint64,uint64,uint64),address,address[3],address[],uint256[],address[],address,address,address,uint8)'
  const proxy = new Contract(strat.contract.address, loadAbi(contract)!, env.deployer);

  // TODO: use await proxy.initialized?.() in next deployments
  if ((await proxy.agent()) != addressZero) {
    console.log(`Skipping init() as ${name} already initialized`);
  } else {
    const initSignature = getInitSignature("HopStrategy");
    await proxy[initSignature](...initParams, getOverrides(env));
  }

  await logState(env, "After init", 5_000);
  return env as IStrategyDeploymentEnv;
}

export async function deposit(env: IStrategyDeploymentEnv, amount = 100) {
  const { strat, underlying } = env.deployment!;
  amount *= underlying.weiPerUnit; // 100$ or equivalent

  const balance = await underlying.contract.balanceOf(env.deployer.address);
  if (balance.lt(amount)) {
    console.log(`Using full balance ${balance} (< ${amount})`);
    amount = balance;
  }

  await underlying.contract.approve(strat.contract.address, MaxUint256, getOverrides(env));
  await logState(env, "Before Deposit");
  const receipt = await strat.contract.safeDeposit(
    amount, env.deployer.address, 1, getOverrides(env))
      .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Deposit", 5_000);
  return getTxLogData(receipt, ["uint256", "uint256"])[0];
}

export async function swapDeposit(
  env: IStrategyDeploymentEnv,
  inputAddress?: string,
  amount = 100
) {
  const { strat, underlying } = env.deployment!;
  amount *= underlying.weiPerUnit; // 100$ or equivalent

  const input = new Contract(inputAddress!, erc20Abi, env.deployer);

  await underlying.contract.approve(strat.contract.address, MaxUint256, getOverrides(env));
  await input.approve(strat.contract.address, MaxUint256);

  let swapData: any = [];
  if (underlying.contract.address != input.address) {
    const tr = (await getTransactionRequest({
      input: input.address,
      output: underlying.contract.address,
      amountWei: BigInt(amount).toString(),
      inputChainId: network.config.chainId!,
      payer: strat.contract.address,
      testPayer: env.addresses!.accounts!.impersonate,
    })) as ITransactionRequestWithEstimate;
    swapData = ethers.utils.defaultAbiCoder.encode(
      ["address", "uint256", "bytes"],
      [tr.to, 1, tr.data]
    );
  }
  await logState(env, "Before SwapDeposit");
  const receipt = await strat.contract.swapSafeDeposit(
    input.address, // input
    amount, // amount == 100$
    env.deployer.address, // receiver
    1, // minShareAmount in wei
    swapData, // swapData
    getOverrides(env)
  ).then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After SwapDeposit", 5_000);
  return getTxLogData(receipt, ["uint256", "uint256"])[0];
}

export async function seedLiquidity(
  env: IStrategyDeploymentEnv,
  amount = 50
) {
  const { strat, underlying } = env.deployment!;
  if (await strat.contract.totalAssets() > await strat.contract.minLiquidity()) {
    console.log(`Skipping seedLiquidity as totalAssets > minLiquidity`);
    return BigNumber.from(1);
  }
  amount *= underlying.weiPerUnit;
  await underlying.contract.approve(strat.contract.address, MaxUint256, getOverrides(env));
  await logState(env, "Before SeedLiquidity");
  const receipt = await strat.contract.seedLiquidity(amount, MaxUint256, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After SeedLiquidity", 5_000);
  return getTxLogData(receipt, ["uint256", "uint256"], -2)[0]; // seeded amount
}

// TODO: add support for multiple inputs
// input prices are required to weight out the swaps and create the SwapData array
export async function invest(env: IStrategyDeploymentEnv, amount = 100) {
  const { underlying, inputs, strat } = env.deployment!;
  amount *= inputs[0].weiPerUnit; // 100$ or equivalent

  const stratLiquidity = await strat.contract.available();
  if (stratLiquidity.lt(amount)) {
    console.log(`Using stratLiquidity as amount (${stratLiquidity} < ${amount})`);
    amount = stratLiquidity;
  }

  let tr = { to: addressZero, data: "0x00" } as Partial<ITransactionRequestWithEstimate>;
  const minAmountOut = 1;
  if (underlying.contract.address != inputs[0].contract.address) {
    console.log("SwapData required by invest() as underlying != input");
    tr = (await getTransactionRequest({
      input: underlying.contract.address,
      output: inputs[0].contract.address,
      amountWei: BigInt(amount).toString(),
      inputChainId: network.config.chainId!,
      payer: strat.contract.address,
      testPayer: env.addresses.accounts!.impersonate,
    })) as ITransactionRequestWithEstimate;
  }
  const swapData = ethers.utils.defaultAbiCoder.encode(
    ["address", "uint256", "bytes"],
    [tr.to, minAmountOut, tr.data]
  );
  await logState(env, "Before Invest");
  const receipt = await strat.contract.invest(amount, minAmountOut, [swapData], getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Invest", 5_000);
  return getTxLogData(receipt, ["uint256", "uint256"])[0];
}

// TODO: add support for multiple inputs
// input prices are required to weight out the swaps and create the SwapData array
export async function liquidate(env: IStrategyDeploymentEnv, amount = 50) {
  const { underlying, inputs, strat } = env.deployment!;
  amount *= inputs[0].weiPerUnit; // 10$ or equivalent

  const pendingWithdrawalRequest = await strat.contract.totalPendingUnderlyingRequest();
  const invested = await strat.contract.invested();
  const max = invested.gt(pendingWithdrawalRequest) ? invested : pendingWithdrawalRequest;

  if (pendingWithdrawalRequest.gt(invested)) {
    console.warn(`pendingWithdrawalRequest > invested (${pendingWithdrawalRequest} > ${invested})`);
  }

  if (pendingWithdrawalRequest.gt(amount)) {
    console.log(`Using pendingWithdrawalRequest ${pendingWithdrawalRequest} (> amount ${amount})`);
    amount = pendingWithdrawalRequest;
  }

  if (max.lt(amount)) {
    console.log(`Using total allocated assets (max) ${max} (< ${amount})`);
    amount = max;
  }

  let swapData: any = [];

  const input = inputs[0].contract.address;
  const output = underlying.contract.address;

  let tr = { to: addressZero, data: "0x00" } as ITransactionRequestWithEstimate;
  if (input != output) {
    tr = (await getTransactionRequest({
      input,
      output,
      amountWei: BigInt(amount).toString(),
      inputChainId: network.config.chainId!,
      payer: strat.contract.address, // env.deployer.address
      testPayer: env.addresses.accounts!.impersonate,
    })) as ITransactionRequestWithEstimate;
  }
  swapData = ethersUtils.defaultAbiCoder.encode(
    ["address", "uint256", "bytes"],
    [tr.to, 1, tr.data]
  );
  await logState(env, "Before Liquidate");
  // const [liquidity, totalAssets] = await strat.liquidate(amount, 1, false, [swapData], { 2e6 });
  const receipt = await strat.contract.liquidate(amount, 1, false, [swapData], getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Liquidate", 5_000);
  return getTxLogData(receipt, ["uint256", "uint256", "uint256"])[2]; // liquidityAvailable
}

export async function withdraw(env: IStrategyDeploymentEnv, amount = 50) {
  const { underlying, inputs, strat } = env.deployment!;
  amount *= underlying.weiPerUnit; // 10$ or equivalent
  const minAmount = 1; // TODO: change with staticCall

  const max = await strat.contract.maxWithdraw(env.deployer.address);

  if (max.lt(10)) {
    console.log(`Skipping withdraw as maxWithdraw < 10wei (no exit possible at this time)`);
    return BigNumber.from(1);
  }

  if (BigNumber.from(amount).gt(max)) {
    console.log(`Using maxWithdraw ${max} (< ${amount})`);
    amount = max;
  }

  await logState(env, "Before Withdraw");
  const receipt = await strat.contract.safeWithdraw(
    amount, minAmount, env.deployer.address, env.deployer.address,
    getOverrides(env)
  ).then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Withdraw", 5_000);
  return getTxLogData(receipt, ["uint256", "uint256"])[0]; // recovered
}

export async function requestWithdraw(env: IStrategyDeploymentEnv, amount = 50) {

  const { underlying, inputs, strat } = env.deployment!;
  amount *= underlying.weiPerUnit; // 10$ or equivalent

  const balance = await strat.contract.balanceOf(env.deployer.address);
  if (balance.lt(10)) {
    console.log(`Skipping requestWithdraw as balance < 10wei (user owns no shares)`);
    return BigNumber.from(1);
  }

  if (BigNumber.from(amount).gt(balance)) {
    console.log(`Using full balance ${balance} (< ${amount})`);
    amount = balance;
  }

  // TODO: use await strat.contract.pendingUnderlyingRequest (not available atm but next deployments)
  const request = (await strat.contract.pendingRedeemRequest(env.deployer.address)).mul(
    await strat.contract.sharePrice()).div(strat.weiPerUnit);
  if (request.gte(BigNumber.from(amount).mul(underlying.weiPerUnit))) {
    console.log(`Skipping requestWithdraw as pendingRedeemRequest > amount`);
    return BigNumber.from(1);
  }
  await logState(env, "Before RequestWithdraw");
  const receipt = await strat.contract.requestWithdraw(
    amount,
    env.deployer.address, env.deployer.address, getOverrides(env)
  ).then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After RequestWithdraw", 5_000);
  return getTxLogData(receipt, ["uint256", "uint256"])[0]; // recovered
}
