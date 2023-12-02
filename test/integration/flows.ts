import { erc20Abi } from "abitype/abis";
import { add, get, merge } from "lodash";
import { Contract, BigNumber, utils as ethersUtils } from "ethers";
import { IDeploymentUnit, TransactionResponse, deploy, deployAll, ethers, loadAbi, network, weiToString } from "@astrolabs/hardhat";
import { ITransactionRequestWithEstimate, getTransactionRequest } from "@astrolabs/swapper";
import { Erc20Metadata, IStrategyDeployment, IStrategyDeploymentEnv, ITestEnv, IStrategyBaseParams, IToken } from "../../src/types";
import { addressZero, getEnv, getInitSignature, getOverrides, getSwapperOutputEstimate, getSwapperRateEstimate, getTokenInfo, getTxLogData, isLive, isStablePair, logState, sleep } from "./utils";
import addresses from "../../src/addresses";

const MaxUint256 = ethers.constants.MaxUint256;

// TODO: move the already existing libs/contracts logic to @astrolabs/hardhat
export const deployStrat = async (
  env: Partial<IStrategyDeploymentEnv>,
  name: string,
  contract: string,
  constructorParams: [Erc20Metadata],
  initParams: [IStrategyBaseParams, ...any],
  libNames = ["AsAccounting"],
  forceVerify = false // check that the contract is verified on etherscan/tenderly
): Promise<IStrategyDeploymentEnv> => {

  let [swapper, agent] = [{}, {}] as Contract[];

  // strategy dependencies
  const libraries: { [name: string]: string } = {};
  const contractUniqueName = `${contract}.${env.deployment?.inputs?.map(i => i.symbol).join("-")}`; // StrategyV5.[inputAddresses.join("-")]

  for (const n of libNames) {
    let lib = {} as Contract;
    const path = `src/libs/${n}.sol:${n}`;
    const address = env.addresses?.libs?.[n] ?? "";
    if (!libraries[path]) {
      const libParams = {
        contract: n,
        name: n,
        verify: true,
        deployed: address ? true : false,
        address,
      } as IDeploymentUnit;
      if (libParams.deployed) {
        console.log(`Using existing ${n} at ${libParams.address}`);
        lib = new Contract(address, loadAbi(n) ?? [], env.deployer);
      } else {
        lib = await deploy(libParams);
      }
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
    StrategyV5Agent: {
      contract: "StrategyV5Agent",
      name: "StrategyV5Agent",
      libraries: agentLibs,
      verify: true,
      deployed: env.addresses!.astrolab?.StrategyV5Agent ? true : false,
      address: env.addresses!.astrolab?.StrategyV5Agent,
      overrides: getOverrides(env),
    },
    [contract]: {
      contract,
      name: contract,
      verify: true,
      deployed: env.addresses!.astrolab?.[contractUniqueName] ? true : false,
      address: env.addresses!.astrolab?.[contractUniqueName],
      proxied: ["StrategyV5Agent"],
      args: constructorParams,
      overrides: getOverrides(env),
      libraries, // External libraries are only used in StrategyV5Agent
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

  if (!env.addresses!.astrolab?.StrategyV5Agent) {
    console.log(`Deploying missing StrategyV5Agent`);
    agent = await deploy(units.StrategyV5Agent);
  } else {
    console.log(
      `Using existing StrategyV5Agent at ${env.addresses!.astrolab?.StrategyV5Agent
      }`
    );
    agent = new Contract(
      env.addresses!.astrolab?.StrategyV5Agent,
      loadAbi("StrategyV5Agent")!,
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
    initParams[0].fees
  );

  // coreAddresses
  initParams[0].coreAddresses = [
    env.deployer!.address, // feeCollector
    swapper.address, // Swapper
    agent.address, // StrategyV5Agent
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

  if (Object.values(env.deployment!.units!).every((u) => u.deployed) && !forceVerify) {
    console.log(`Using existing deployment [${name} Stack]`);
    env.deployment!.strat = await getTokenInfo(
      env.deployment!.units![contract].address!,
      loadAbi(contract)!,
      env.deployer
    );
  } else {
    await deployAll(env.deployment!);
  }

  if (!env.deployment!.units![contract].address) {
    throw new Error(`Could not deploy ${contract}`);
  }

  const stratProxyAbi = loadAbi("StrategyV5")!;
  env.deployment!.strat = await getTokenInfo(
    env.deployment!.units![contract].address!,
    stratProxyAbi);
  env.deployment = env.deployment;
  return env as IStrategyDeploymentEnv;
};

export async function setMinLiquidity(env: Partial<IStrategyDeploymentEnv>, usdAmount=10) {
  const { strat } = env.deployment!;
  const [from, to] = ["USDC", env.deployment!.underlying.symbol];
  const exchangeRate = await getSwapperRateEstimate(from, to, 1e12);
  const seedAmount = BigNumber.from(usdAmount)
    .mul(weiToString(Math.round(exchangeRate * env.deployment!.underlying.weiPerUnit)));
  console.log(`Setting minLiquidity to ${seedAmount} ${to} wei (${usdAmount} USDC)`);
  await strat.contract.setMinLiquidity(seedAmount).then((tx: TransactionResponse) => tx.wait());
  console.log(`Liquidity can now be seeded with ${await strat.contract.minLiquidity()}wei ${to}`);
  return seedAmount;
}

export async function seedLiquidity(env: IStrategyDeploymentEnv, _amount = 10) {
  const { strat, underlying } = env.deployment!;
  let amount = BigNumber.from(_amount).mul(weiToString(underlying.weiPerUnit));

  if (await strat.contract.totalAssets() > await strat.contract.minLiquidity()) {
    console.log(`Skipping seedLiquidity as totalAssets > minLiquidity`);
    return BigNumber.from(1);
  }
  if ((await underlying.contract.allowance(env.deployer.address, strat.contract.address)).lt(amount))
    await underlying.contract.approve(strat.contract.address, MaxUint256, getOverrides(env))
      .then((tx: TransactionResponse) => tx.wait());

  await logState(env, "Before SeedLiquidity");
  const receipt = await strat.contract.seedLiquidity(amount, MaxUint256, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After SeedLiquidity", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"], -2)[0]; // seeded amount
}

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
  minLiquidityUsd = 10,
  libNames = ["AsAccounting"],
  env: Partial<IStrategyDeploymentEnv> = {},
  addressesOverride?: any
): Promise<IStrategyDeploymentEnv> {

  env = await getEnv(env, addressesOverride);

  // make sure to include PythUtils if pyth is used (not lib used with chainlink)
  if (initParams[1]?.pyth && !libNames.includes("PythUtils")) {
    libNames.push("PythUtils");
  }
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

  await setMinLiquidity(env, minLiquidityUsd);

  // NB: can use await proxy.initialized?.() instead
  if ((await proxy.agent()) != addressZero) {
    console.log(`Skipping init() as ${name} already initialized`);
  } else {
    const initSignature = getInitSignature("HopSingleStake");
    await proxy[initSignature](...initParams, getOverrides(env));
  }

  await logState(env, "After init", 2_000);
  return env as IStrategyDeploymentEnv;
}

export async function deposit(env: IStrategyDeploymentEnv, _amount = 10) {
  const { strat, underlying } = env.deployment!;
  const balance = await underlying.contract.balanceOf(env.deployer.address);
  let amount = BigNumber.from(_amount).mul(weiToString(underlying.weiPerUnit)); // 100$ or equivalent

  if (balance.lt(amount)) {
    console.log(`Using full balance ${balance} (< ${amount})`);
    amount = balance;
  }
  if ((await underlying.contract.allowance(env.deployer.address, strat.contract.address)).lt(amount))
    await underlying.contract.approve(strat.contract.address, MaxUint256, getOverrides(env))
      .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "Before Deposit");
  const receipt = await strat.contract.safeDeposit(
    amount, env.deployer.address, 1, getOverrides(env))
      .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Deposit", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"])[0];
}

export async function swapDeposit(
  env: IStrategyDeploymentEnv,
  inputAddress?: string,
  _amount = 10
) {
  const { strat, underlying } = env.deployment!;
  const depositAsset = new Contract(inputAddress!, erc20Abi, env.deployer);
  const [minSwapOut, minSharesOut] = [1, 1];
  let amount = BigNumber.from(_amount).mul(weiToString(underlying.weiPerUnit)); // 100$ or equivalent

  if ((await underlying.contract.allowance(env.deployer.address, strat.contract.address)).lt(amount))
    await underlying.contract.approve(strat.contract.address, MaxUint256, getOverrides(env))
      .then((tx: TransactionResponse) => tx.wait());

  let swapData: any = [];
  if (underlying.contract.address != depositAsset.address) {
    const tr = (await getTransactionRequest({
      input: depositAsset.address,
      output: underlying.contract.address,
      amountWei: amount.toString(),
      inputChainId: network.config.chainId!,
      payer: strat.contract.address,
      testPayer: env.addresses!.accounts!.impersonate,
    })) as ITransactionRequestWithEstimate;
    swapData = ethers.utils.defaultAbiCoder.encode(
      ["address", "uint256", "bytes"],
      [tr.to, minSwapOut, tr.data]
    );
  }
  await logState(env, "Before SwapDeposit");
  const receipt = await strat.contract.swapSafeDeposit(
    depositAsset.address, // input
    amount, // amount == 100$
    env.deployer.address, // receiver
    minSharesOut, // minShareAmount in wei
    swapData, // swapData
    getOverrides(env)
  ).then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After SwapDeposit", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"])[0];
}

// input prices are required to weight out the swaps and create the SwapData array
export async function invest(env: IStrategyDeploymentEnv, _amount = 100) {

  const { underlying, inputs, strat } = env.deployment!;
  const stratLiquidity = await strat.contract.available();
  const [minSwapOut, minIouOut] = [1, 1];
  let amount = BigNumber.from(_amount).mul(weiToString(underlying.weiPerUnit)); // 100$ or equivalent

  if (stratLiquidity.lt(amount)) {
    console.log(`Using stratLiquidity as amount (${stratLiquidity} < ${amount})`);
    amount = stratLiquidity;
  }

  const trs = [] as Partial<ITransactionRequestWithEstimate>[];
  const swapData = [] as string[];

  for (const i in inputs) {
    let tr = { to: addressZero, data: "0x00" } as ITransactionRequestWithEstimate;

    // only generate swapData if the input is not the underlying
    if (underlying.contract.address != inputs[i].contract.address) {
      console.log("Preparing invest() SwapData from inputs/inputWeights");
      const weight = env.deployment!.initParams[0].inputWeights[i];
      if (!weight) throw new Error(`No inputWeight found for input ${i} (${inputs[i].symbol})`);
      tr = (await getTransactionRequest({
        input: underlying.contract.address,
        output: inputs[i].contract.address,
        amountWei: amount.mul(weight).div(10_000).toString(), // using a 10_000 bp basis (10_000 = 100%)
        inputChainId: network.config.chainId!,
        payer: strat.contract.address,
        testPayer: env.addresses.accounts!.impersonate,
      })) as ITransactionRequestWithEstimate;
    }
    trs.push(tr);
    swapData.push(ethersUtils.defaultAbiCoder.encode(
      // router, minAmountOut, data // TODO: minSwapOut == pessimistic estimate - slippage
      ["address", "uint256", "bytes"],
      [tr.to, minSwapOut, tr.data]
    ));
  }
  await logState(env, "Before Invest");
  const receipt = await strat.contract.invest(amount, minIouOut, swapData, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Invest", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"])[0];
}

// input prices are required to weight out the swaps and create the SwapData array
export async function liquidate(env: IStrategyDeploymentEnv, _amount = 50) {
  const { underlying, inputs, strat } = env.deployment!;

  let amount = BigNumber.from(_amount).mul(weiToString(underlying.weiPerUnit)); // 10$ or equivalent

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

  if (amount.lt(10)) {
    console.log(`Skipping liquidate as amount < 10wei (no liquidation required)`);
    return BigNumber.from(1);
  }

  const trs = [] as Partial<ITransactionRequestWithEstimate>[];
  const swapData = [] as string[];

  for (const i in inputs) {

    const weight = env.deployment!.initParams[0].inputWeights[i];

    // convert underlying liquidation requirement to inputs[i] wei amount
    let amountInput = await getSwapperOutputEstimate(
      underlying.symbol,
      inputs[i].symbol,
      amount.mul(weight).div(10_000), // using a 10_000 bp basis (10_000 = 100%)
      env.network.config.chainId!);

    const stablePair = isStablePair(underlying.symbol, inputs[i].symbol);

    // add .1% slippage to the input amount, .015% if stable (2x as switching from ask estimate->bid)
    // NB: in case of a volatility event (eg. news/depeg), the liquidity would be one sided
    // and these estimates would be off. Liquidation would require manual parametrization
    // using more pessimistic amounts (eg. more slippage) in the swapData generation
    amountInput = amountInput.add(amountInput.div((stablePair ? 6666 : 1000)*2));

    let swapData: any = [];

    let tr = { to: addressZero, data: "0x00" } as ITransactionRequestWithEstimate;
    // only generate swapData if the input is not the underlying
    if (underlying.contract.address != inputs[i].contract.address) {
      tr = (await getTransactionRequest({
        input: inputs[i].contract.address,
        output: underlying.contract.address,
        amountWei: amountInput.mul(weight).div(10_000).toString(), // using a 10_000 bp basis (10_000 = 100%)
        inputChainId: network.config.chainId!,
        payer: strat.contract.address, // env.deployer.address
        testPayer: env.addresses.accounts!.impersonate,
      })) as ITransactionRequestWithEstimate;
      if (!tr.to)
        throw new Error(`No swapData generated for ${inputs[i].contract.address} -> ${underlying.contract.address}`);
    }
    trs.push(tr);
    swapData.push(ethersUtils.defaultAbiCoder.encode(
      ["address", "uint256", "bytes"],
      [tr.to, 1, tr.data]
    ));
  }
  await logState(env, "Before Liquidate");
  // const [liquidity, totalAssets] = await strat.liquidate(amount, 1, false, [swapData], { 2e6 });
  const receipt = await strat.contract.liquidate(amount, 1, false, swapData, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Liquidate", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256", "uint256"])[2]; // liquidityAvailable
}

export async function withdraw(env: IStrategyDeploymentEnv, _amount = 50) {

  const { underlying, inputs, strat } = env.deployment!;
  const minAmountOut = 1; // TODO: change with staticCall
  const max = await strat.contract.maxWithdraw(env.deployer.address);
  let amount = BigNumber.from(_amount).mul(weiToString(underlying.weiPerUnit)); // 10$ or equivalent

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
    amount, minAmountOut, env.deployer.address, env.deployer.address,
    getOverrides(env)
  ).then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Withdraw", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"])[0]; // recovered
}

export async function requestWithdraw(env: IStrategyDeploymentEnv, _amount = 50) {

  const { underlying, inputs, strat } = env.deployment!;
  const balance = await strat.contract.balanceOf(env.deployer.address);
  const pendingRequest = await strat.contract.pendingUnderlyingRequest(env.deployer.address);
  let amount = BigNumber.from(_amount).mul(weiToString(underlying.weiPerUnit)); // 10$ or equivalent

  if (balance.lt(10)) {
    console.log(`Skipping requestWithdraw as balance < 10wei (user owns no shares)`);
    return BigNumber.from(1);
  }

  if (BigNumber.from(amount).gt(balance)) {
    console.log(`Using full balance ${balance} (< ${amount})`);
    amount = balance;
  }

  if (pendingRequest.gte(amount.mul(weiToString(underlying.weiPerUnit)))) {
    console.log(`Skipping requestWithdraw as pendingRedeemRequest > amount`);
    return BigNumber.from(1);
  }
  await logState(env, "Before RequestWithdraw");
  const receipt = await strat.contract.requestWithdraw(
    amount,
    env.deployer.address, env.deployer.address,
    getOverrides(env)
  ).then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After RequestWithdraw", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"])[0]; // recovered
}
