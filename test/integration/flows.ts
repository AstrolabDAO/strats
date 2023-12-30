import { erc20Abi } from "abitype/abis";
import { add, get, merge } from "lodash";
import { Contract, BigNumber } from "ethers";
import * as ethers from "ethers";
import {
  IDeploymentUnit,
  TransactionResponse,
  deploy,
  deployAll,
  loadAbi,
  network,
  weiToString,
} from "@astrolabs/hardhat";
import {
  ITransactionRequestWithEstimate,
  getTransactionRequest,
} from "@astrolabs/swapper";
import {
  Erc20Metadata,
  IStrategyDeployment,
  IStrategyDeploymentEnv,
  ITestEnv,
  IStrategyBaseParams,
  SafeContract,
  MaybeAwaitable,
} from "../../src/types";
import {
  addressZero,
  getEnv,
  getInitSignature,
  getOverrides,
  getSwapperEstimate,
  getSwapperOutputEstimate,
  getSwapperRateEstimate,
  getTxLogData,
  isLive,
  isStablePair,
  logState,
  sleep,
  isOracleLib,
  addressOne,
  logRescue,
  resolveMaybe,
} from "./utils";
import addresses from "../../src/addresses";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const MaxUint256 = ethers.constants.MaxUint256;

// TODO: move the already existing libs/contracts logic to @astrolabs/hardhat
export const deployStrat = async (
  env: Partial<IStrategyDeploymentEnv>,
  name: string,
  contract: string,
  initParams: [IStrategyBaseParams, ...any],
  libNames = ["AsAccounting"],
  forceVerify = false // check that the contract is verified on etherscan/tenderly
): Promise<IStrategyDeploymentEnv> => {
  let [swapper, agent] = [{}, {}] as Contract[];

  // strategy dependencies
  const libraries: { [name: string]: string } = {};
  const contractUniqueName = name; // `${contract}.${env.deployment?.inputs?.map(i => i.symbol).join("-")}`;

  for (const n of libNames) {
    let lib = {} as Contract;
    const path = `src/libs/${n}.sol:${n}`;
    const address = env.addresses?.libs?.[n] ?? "";
    if (!libraries[n]) {
      const libParams = {
        contract: n,
        name: n,
        verify: true,
        deployed: address ? true : false,
        address,
        libraries: isOracleLib(n) ? { AsMaths: libraries.AsMaths } : {},
      } as IDeploymentUnit;
      if (libParams.deployed) {
        console.log(`Using existing ${n} at ${libParams.address}`);
        lib = await SafeContract.build(
          address,
          (loadAbi(n) as any[]) ?? [],
          env.deployer!
        );
      } else {
        lib = await deploy(libParams);
      }
    }
    libraries[n] = lib.address;
  }

  // exclude implementation specific libraries from agentLibs (eg. oracle libs)
  // as these are specific to the strategy implementation
  const stratLibs = Object.assign({}, libraries);

  delete stratLibs.AsMaths; // not used statically by Agent/Strat

  const agentLibs = Object.assign({}, stratLibs);
  for (const lib of Object.keys(agentLibs)) {
    if (isOracleLib(lib)) delete agentLibs[lib];
  }

  delete stratLibs.AsAccounting; // not used statically by Strat

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
      overrides: getOverrides(env),
      libraries: stratLibs, // External libraries are only used in StrategyV5Agent
    },
  };

  for (const libName of libNames) {
    units[libName] = {
      contract: libName,
      name: libName,
      verify: false,
      deployed: true,
      address:
        libraries[libName] ?? libraries[`src/libs/${libName}.sol:${libName}`],
    };
  }

  if (!env.addresses!.astrolab?.Swapper) {
    console.log(`Deploying missing Swapper`);
    swapper = await deploy(units.Swapper);
  } else {
    console.log(
      `Using existing Swapper at ${env.addresses!.astrolab?.Swapper}`
    );
    swapper = await SafeContract.build(
      env.addresses!.astrolab?.Swapper!,
      loadAbi("Swapper")! as any[],
      env.deployer!
    );
  }

  if (!env.addresses!.astrolab?.StrategyV5Agent) {
    console.log(`Deploying missing StrategyV5Agent`);
    agent = await deploy(units.StrategyV5Agent);
    units.StrategyV5Agent.verify = false; // already verified
  } else {
    console.log(
      `Using existing StrategyV5Agent at ${env.addresses!.astrolab
        ?.StrategyV5Agent}`
    );
    agent = await SafeContract.build(
      env.addresses!.astrolab?.StrategyV5Agent,
      loadAbi("StrategyV5Agent") as any[],
      env.deployer!
    );
  }

  // default erc20Metadata
  initParams[0].erc20Metadata = merge(
    {
      name,
      decimals: 8,
    },
    initParams[0].erc20Metadata
  );

  // default coreAddresses
  initParams[0].coreAddresses = merge(
    {
      feeCollector: env.deployer!.address, // feeCollector
      swapper: swapper.address, // Swapper
      agent: agent.address, // StrategyV5Agent
    },
    initParams[0].coreAddresses
  );

  // default fees
  initParams[0].fees = merge(
    {
      perf: 1_000, // 10%
      mgmt: 20, // .2%
      entry: 2, // .02%
      exit: 2, // .02%
      flash: 2, // .02% << 2.5x cheaper than aave
    },
    initParams[0].fees
  );

  // inputs
  if (initParams[0].inputWeights.length == 1)
    // default input weight == 100%
    initParams[0].inputWeights = [10_000];

  merge(env.deployment, {
    name: `${name} Stack`,
    contract: "",
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
    inputs: [] as SafeContract[],
    rewardTokens: [] as SafeContract[],
    asset: {} as SafeContract,
    strat: {} as SafeContract,
  } as IStrategyDeployment);

  if (
    Object.values(env.deployment!.units!).every((u) => u.deployed) &&
    !forceVerify
  ) {
    console.log(`Using existing deployment [${name} Stack]`);
    env.deployment!.strat = await SafeContract.build(
      env.deployment!.units![contract].address!,
      loadAbi(contract)! as any[],
      env.deployer
    );
  } else {
    await deployAll(env.deployment!);
  }

  if (!env.deployment!.units![contract].address) {
    throw new Error(`Could not deploy ${contract}`);
  }

  const stratProxyAbi = loadAbi(contract)!; // use "StrategyV5" for generic abi
  env.deployment!.strat = await SafeContract.build(
    env.deployment!.units![contract].address!,
    stratProxyAbi as any[]
  );
  env.deployment = env.deployment;
  return env as IStrategyDeploymentEnv;
};

export async function setMinLiquidity(
  env: Partial<IStrategyDeploymentEnv>,
  usdAmount = 10
) {
  const { strat, asset } = env.deployment!;
  const [from, to] = ["USDC", env.deployment!.asset.sym];
  const exchangeRate = await getSwapperRateEstimate(from, to, 1e12);
  const seedAmount = asset.toWei(usdAmount * exchangeRate);
  if ((await strat.minLiquidity()).gte(seedAmount)) {
    console.log(`Skipping setMinLiquidity as minLiquidity == ${seedAmount}`);
  } else {
    console.log(
      `Setting minLiquidity to ${seedAmount} ${to} wei (${usdAmount} USDC)`
    );
    await strat
      .setMinLiquidity(seedAmount)
      .then((tx: TransactionResponse) => tx.wait());
    console.log(
      `Liquidity can now be seeded with ${await strat.minLiquidity()}wei ${to}`
    );
  }
  return seedAmount;
}

export async function seedLiquidity(env: IStrategyDeploymentEnv, _amount = 10) {
  const { strat, asset } = env.deployment!;
  let amount = asset.toWei(_amount);
  if ((await strat.totalAssets()).gte(await strat.minLiquidity())) {
    console.log(`Skipping seedLiquidity as totalAssets > minLiquidity`);
    return BigNumber.from(1);
  }
  if ((await asset.allowance(env.deployer.address, strat.address)).lt(amount))
    await asset
      .approve(strat.address, MaxUint256, getOverrides(env))
      .then((tx: TransactionResponse) => tx.wait());

  await logState(env, "Before SeedLiquidity");
  // only exec if static call is successful
  const receipt = await strat
    // .safe("seedLiquidity", [amount, MaxUint256], getOverrides(env))
    .seedLiquidity(amount, MaxUint256, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After SeedLiquidity", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0); // NB: on some chains, a last (aggregate) event is emitted
}

export async function setupStrat(
  contract: string,
  name: string,
  // below we use hop strategy signature as placeholder
  initParams: [IStrategyBaseParams, ...any],
  minLiquidityUsd = 10,
  libNames = ["AsAccounting"],
  env: Partial<IStrategyDeploymentEnv> = {},
  forceVerify = false,
  addressesOverride?: any
): Promise<IStrategyDeploymentEnv> {
  env = await getEnv(env, addressesOverride);

  // make sure to include PythUtils if pyth is used (not lib used with chainlink)
  if (initParams[1]?.pyth && !libNames.includes("PythUtils")) {
    libNames.push("PythUtils");
  }
  env.deployment = {
    asset: await SafeContract.build(initParams[0].coreAddresses.asset),
    inputs: await Promise.all(
      initParams[0].inputs!.map((input) => SafeContract.build(input))
    ),
    rewardTokens: await Promise.all(
      initParams[0].rewardTokens!.map((rewardToken) =>
        SafeContract.build(rewardToken)
      )
    ),
  } as any;

  env = await deployStrat(
    env,
    name,
    contract,
    initParams,
    libNames,
    forceVerify
  );

  const { strat, inputs, rewardTokens } = env.deployment!;

  // manager role is not granted instantly, it has to be accepted after 48 hours (deployer de-facto gets it)
  // here, only KEEPER will be granted at block-time
  await grantRoles(env, ["MANAGER", "KEEPER"], env.deployer!.address);

  // load the implementation abi, containing the overriding init() (missing from d.strat)
  // init((uint64,uint64,uint64,uint64,uint64),address,address[3],address[],uint256[],address[],address,address,address,uint8)'
  const proxy = new Contract(strat.address, loadAbi(contract)!, env.deployer);

  await setMinLiquidity(env, minLiquidityUsd);
  // NB: can use await proxy.initialized?.() instead
  if ((await proxy.agent()) != addressZero) {
    console.log(`Skipping init() as ${name} already initialized`);
  } else {
    const initSignature = getInitSignature(contract);
    console.log("InitParams : ", initParams);
    await proxy[initSignature](...initParams, getOverrides(env)).then(
      (tx: TransactionResponse) => tx.wait()
    );
  }

  const actualInputs: string[] = //inputs.map((input) => input.address);
    await env.multicallProvider!.all(
      inputs.map((input, index) => strat.multi.inputs(index))
    );

  const actualRewardTokens: string[] = // rewardTokens.map((reward) => reward.address);
    await env.multicallProvider!.all(
      rewardTokens.map((input, index) => strat.multi.rewardTokens(index))
    );

  // assert that the inputs and rewardTokens are set correctly
  for (const i in inputs) {
    if (inputs[i].address.toUpperCase() != actualInputs[i].toUpperCase())
      throw new Error(
        `Input ${i} address mismatch ${inputs[i].address} != ${actualInputs[i]}`
      );
  }

  for (const i in rewardTokens) {
    if (
      rewardTokens[i].address.toUpperCase() !=
      actualRewardTokens[i].toUpperCase()
    )
      throw new Error(
        `RewardToken ${i} address mismatch ${rewardTokens[i].address} != ${actualRewardTokens[i]}`
      );
  }

  await logState(env, "After init", 2_000);
  return env as IStrategyDeploymentEnv;
}

export async function deposit(env: IStrategyDeploymentEnv, _amount = 10) {
  const { strat, asset } = env.deployment!;
  const balance = await asset.balanceOf(env.deployer.address);
  let amount = asset.toWei(_amount);

  if (balance.lt(amount)) {
    console.log(`Using full balance ${balance} (< ${amount})`);
    amount = balance;
  }
  if ((await asset.allowance(env.deployer.address, strat.address)).lt(amount))
    await asset
      .approve(strat.address, MaxUint256, getOverrides(env))
      .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "Before Deposit");
  // only exec if static call is successful
  const receipt = await strat
    // .safe("safeDeposit", [amount, 1, env.deployer.address], getOverrides(env))
    .safeDeposit(amount, 1, env.deployer.address, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Deposit", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0);
}

export async function swapSafeDeposit(
  env: IStrategyDeploymentEnv,
  inputAddress?: string,
  _amount = 10
) {
  const { strat, asset } = env.deployment!;
  const depositAsset = new Contract(inputAddress!, erc20Abi, env.deployer);
  const [minSwapOut, minSharesOut] = [1, 1];
  let amount = depositAsset.toWei(_amount);

  if (
    (await depositAsset.allowance(env.deployer.address, strat.address)).lt(
      amount
    )
  )
    await depositAsset
      .approve(strat.address, MaxUint256, getOverrides(env))
      .then((tx: TransactionResponse) => tx.wait());

  let swapData: any = [];
  if (asset.address != depositAsset.address) {
    const tr = (await getTransactionRequest({
      input: depositAsset.address,
      output: asset.address,
      amountWei: amount.toString(),
      inputChainId: network.config.chainId!,
      payer: strat.address,
      testPayer: env.addresses!.accounts!.impersonate,
    })) as ITransactionRequestWithEstimate;
    swapData = ethers.utils.defaultAbiCoder.encode(
      ["address", "uint256", "bytes"],
      [tr.to, minSwapOut, tr.data]
    );
  }
  await logState(env, "Before SwapSafeDeposit");
  const receipt = await strat
    .safe(
      "swapSafeDeposit",
      [
        depositAsset.address, // input
        amount, // amount == 100$
        env.deployer.address, // receiver
        minSharesOut, // minShareAmount in wei
        swapData,
      ], // swapData
      getOverrides(env)
    )
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After SwapSafeDeposit", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0);
}

export async function preInvest(env: IStrategyDeploymentEnv, _amount = 100) {
  const { asset, inputs, strat } = env.deployment!;
  const stratLiquidity = await strat.available();
  const [minSwapOut, minIouOut] = [1, 1];
  let amount = asset.toWei(_amount);

  if (stratLiquidity.lt(amount)) {
    console.log(
      `Using stratLiquidity as amount (${stratLiquidity} < ${amount})`
    );
    amount = stratLiquidity;
  }

  const amounts = await strat.previewInvest(amount); // parsed as uint256[8]
  const trs = [] as Partial<ITransactionRequestWithEstimate>[];
  const swapData = [] as string[];

  for (const i in inputs) {
    let tr = {
      to: addressZero,
      data: "0x00",
    } as ITransactionRequestWithEstimate;

    // only generate swapData if the input is not the asset
    if (asset.address != inputs[i].address && amounts[i].gt(10)) {
      console.log("Preparing invest() SwapData from inputs/inputWeights");
      // const weight = env.deployment!.initParams[0].inputWeights[i];
      // if (!weight) throw new Error(`No inputWeight found for input ${i} (${inputs[i].symbol})`);
      // inputAmount = amount.mul(weight).div(10_000).toString()
      tr = (await getTransactionRequest({
        input: asset.address,
        output: inputs[i].address,
        amountWei: amounts[i], // using a 10_000 bp basis (10_000 = 100%)
        inputChainId: network.config.chainId!,
        payer: strat.address,
        testPayer: env.addresses.accounts!.impersonate,
      })) as ITransactionRequestWithEstimate;
    }
    trs.push(tr);
    swapData.push(
      ethers.utils.defaultAbiCoder.encode(
        // router, minAmountOut, data // TODO: minSwapOut == pessimistic estimate - slippage
        ["address", "uint256", "bytes"],
        [tr.to, minSwapOut, tr.data]
      )
    );
  }
  return [amounts, swapData];
}

// input prices are required to weight out the swaps and create the SwapData array
export async function invest(env: IStrategyDeploymentEnv, _amount = 0) {
  const { strat } = env.deployment!;
  const params = await preInvest(env, _amount);
  await logState(env, "Before Invest");
  // only exec if static call is successful
  const receipt = await strat
    // .safe("invest(uint256[8],bytes[])", params, getOverrides(env)) // Pass the invest only if the static call passed to avoid losing gas
    .invest(...params, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Invest", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0);
}

// input prices are required to weight out the swaps and create the SwapData array
export async function liquidate(env: IStrategyDeploymentEnv, _amount = 50) {
  const { asset, inputs, strat } = env.deployment!;

  let amount = asset.toWei(_amount);

  const pendingWithdrawalRequest = await strat.totalPendingAssetRequest();
  const invested = await strat["invested()"]();
  const max = invested.gt(pendingWithdrawalRequest)
    ? invested
    : pendingWithdrawalRequest;

  if (pendingWithdrawalRequest.gt(invested)) {
    console.warn(
      `pendingWithdrawalRequest > invested (${pendingWithdrawalRequest} > ${invested})`
    );
  }

  if (max.lt(amount)) {
    console.log(`Using total allocated assets (max) ${max} (< ${amount})`);
    amount = max;
  }

  if (amount.lt(10)) {
    console.log(
      `Skipping liquidate as amount < 10wei (no liquidation required)`
    );
    return BigNumber.from(1);
  }

  const trs = [] as Partial<ITransactionRequestWithEstimate>[];
  const swapData = [] as string[];
  const amounts = Object.assign([], await strat.previewLiquidate(amount));
  const swapAmounts = new Array<BigNumber>(amounts.length).fill(
    BigNumber.from(0)
  );

  // const balances = await env.multicallProvider!.all(
  //   inputs.map((input) => input.multi.balanceOf(strat.address))
  // );

  for (const i in inputs) {
    // const weight = env.deployment!.initParams[0].inputWeights[i];
    // const amountOut = amount.mul(weight).div(10_000); // using a 10_000 bp basis (10_000 = 100%)

    // by default input == asset, no swapData is required
    let tr = {
      to: addressZero,
      data: "0x00",
      estimatedExchangeRate: 1, // no swap 1:1
      estimatedOutputWei: amounts[i],
      estimatedOutput: inputs[i].toAmount(amounts[i]),
    } as ITransactionRequestWithEstimate;

    if (asset.address != inputs[i].address) {
      // add 1% slippage to the input amount, .1% if stable (2x as switching from ask estimate->bid)
      // NB: in case of a volatility event (eg. news/depeg), the liquidity would be one sided
      // and these estimates would be off. Liquidation would require manual parametrization
      // using more pessimistic amounts (eg. more slippage) in the swapData generation
      const stablePair = isStablePair(asset.sym, inputs[i].sym);
      // oracle derivation tolerance (can be found at https://data.chain.link/ for chainlink)
      const derivation = stablePair ? 100 : 1_000; // .1% or 1%
      const slippage = stablePair ? 25 : 250; // .025% or .25%

      amounts[i] = amounts[i].mul(10_000 + derivation).div(10_000);
      swapAmounts[i] = amounts[i].mul(10_000).div(10_000); // slippage

      if (swapAmounts[i].gt(10)) {
        // only generate swapData if the input is not the asset
        tr = (await getTransactionRequest({
          input: inputs[i].address,
          output: asset.address,
          amountWei: swapAmounts[i], // take slippage off so that liquidated LP value > swap input
          inputChainId: network.config.chainId!,
          payer: strat.address, // env.deployer.address
          testPayer: env.addresses.accounts!.impersonate,
          maxSlippage: 5000, // TODO: increase for low liquidity chains (moonbeam/celo/metis/linea...)
        })) as ITransactionRequestWithEstimate;
        if (!tr.to)
          throw new Error(
            `No swapData generated for ${inputs[i].address} -> ${asset.address}`
          );
      }
    }
    trs.push(tr);
    swapData.push(
      ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256", "bytes"],
        [tr.to, 1, tr.data]
      )
    );
  }
  console.log(
    `Liquidating ${asset.toAmount(amount)}${asset.sym}\n` +
      inputs
        .map(
          (input, i) =>
            `  - ${input.sym}: ${input.toAmount(amounts[i])} (${amounts[
              i
            ].toString()}wei), swap amount: ${input.toAmount(
              swapAmounts[i]
            )} (${swapAmounts[i].toString()}wei), est. output: ${trs[i]
              .estimatedOutput!} ${asset.sym} (${trs[
              i
            ].estimatedOutputWei?.toString()}wei - exchange rate: ${
              trs[i].estimatedExchangeRate
            })\n`
        )
        .join("")
  );

  await logState(env, "Before Liquidate");
  // only exec if static call is successful
  const receipt = await strat
    .safe("liquidate", [amounts, 1, false, swapData], getOverrides(env))
    // .liquidate(amounts, 1, false, swapData, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());

  await logState(env, "After Liquidate", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256", "uint256"], 2); // liquidityAvailable
}

export async function withdraw(env: IStrategyDeploymentEnv, _amount = 50) {
  const { asset, inputs, strat } = env.deployment!;
  const minAmountOut = 1; // TODO: change with staticCall
  const max = await strat.maxWithdraw(env.deployer.address);
  let amount = asset.toWei(_amount);

  if (max.lt(10)) {
    console.log(
      `Skipping withdraw as maxWithdraw < 10wei (no exit possible at this time)`
    );
    return BigNumber.from(1);
  }

  if (BigNumber.from(amount).gt(max)) {
    console.log(`Using maxWithdraw ${max} (< ${amount})`);
    amount = max;
  }

  await logState(env, "Before Withdraw");
  // only exec if static call is successful
  const receipt = await strat
    // .safe("safeWithdraw", [amount, minAmountOut, env.deployer.address, env.deployer.address], getOverrides(env))
    .safeWithdraw(
      amount,
      minAmountOut,
      env.deployer.address,
      env.deployer.address,
      getOverrides(env)
    )
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Withdraw", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0); // recovered
}

export async function requestWithdraw(
  env: IStrategyDeploymentEnv,
  _amount = 50
) {
  const { asset, inputs, strat } = env.deployment!;
  const balance = await strat.balanceOf(env.deployer.address);
  const pendingRequest = await strat.pendingAssetRequest(env.deployer.address);
  let amount = asset.toWei(_amount);

  if (balance.lt(10)) {
    console.log(
      `Skipping requestWithdraw as balance < 10wei (user owns no shares)`
    );
    return BigNumber.from(1);
  }

  if (BigNumber.from(amount).gt(balance)) {
    console.log(`Using full balance ${balance} (< ${amount})`);
    amount = balance;
  }

  if (pendingRequest.gte(amount.mul(weiToString(asset.weiPerUnit)))) {
    console.log(`Skipping requestWithdraw as pendingRedeemRequest > amount`);
    return BigNumber.from(1);
  }
  await logState(env, "Before RequestWithdraw");
  const receipt = await strat
    .requestWithdraw(
      amount,
      env.deployer.address,
      env.deployer.address,
      getOverrides(env)
    )
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After RequestWithdraw", 2_000);
  return (
    getTxLogData(receipt, ["address, address, address, uint256"], 3) ??
    BigNumber.from(0)
  ); // recovered
}

export async function preHarvest(env: IStrategyDeploymentEnv) {
  const { asset, inputs, rewardTokens, strat } = env.deployment!;

  // const rewardTokens = (await strat.rewardTokens()).filter((rt: string) => rt != addressZero);
  const amounts = await strat.rewardsAvailable();

  console.log(
    `Generating harvest swapData for:\n${rewardTokens
      .map((rt, i) => "  - " + rt.sym + ": " + rt.toAmount(amounts[i]))
      .join("\n")}`
  );

  const trs: Partial<ITransactionRequestWithEstimate>[] = [];
  const swapData: string[] = [];

  for (const i in rewardTokens) {
    let tr = {
      to: addressZero,
      data: "0x00",
      estimatedOutputWei: amounts[i],
      estimatedExchangeRate: 1,
    } as ITransactionRequestWithEstimate;

    if (rewardTokens[i].address != asset.address && amounts[i].gt(10)) {
      tr = (await getTransactionRequest({
        input: rewardTokens[i].address,
        output: asset.address,
        amountWei: amounts[i].sub(amounts[i].div(1_000)), // .1% slippage
        inputChainId: network.config.chainId!,
        payer: strat.address,
        testPayer: env.addresses.accounts!.impersonate,
      })) as ITransactionRequestWithEstimate;
    }
    trs.push(tr);
    swapData.push(
      ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256", "bytes"],
        [tr.to, 1, tr.data]
      )
    );
  }
  return [swapData];
}

export async function harvest(env: IStrategyDeploymentEnv) {
  const { strat, rewardTokens } = env.deployment!;
  const [harvestSwapData] = await preHarvest(env);
  await logState(env, "Before Harvest");
  // only exec if static call is successful
  const receipt = await strat
    // .safe("harvest", params, getOverrides(env))
    .harvest(harvestSwapData, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Harvest", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0);
}

export async function compound(env: IStrategyDeploymentEnv) {
  const { asset, inputs, strat } = env.deployment!;
  const [harvestSwapData] = await preHarvest(env);

  // harvest static call
  let harvestEstimate = BigNumber.from(0);
  try {
    harvestEstimate = await strat.callStatic.harvest(
      harvestSwapData,
      getOverrides(env)
    );
  } catch (e) {
    console.error(`Harvest static call failed: probably reverted ${e}`);
  }

  const [investAmounts, investSwapData] = await preInvest(
    env,
    asset.toAmount(harvestEstimate.sub(harvestEstimate.div(50)))
  ); // 2% slippage
  await logState(env, "Before Compound");
  // only exec if static call is successful
  const receipt = await strat
    .safe(
      "compound",
      [investAmounts, [...harvestSwapData, ...investSwapData]],
      getOverrides(env)
    )
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Compound", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0);
}

export async function grantRoles(
  env: Partial<IStrategyDeploymentEnv>,
  roles: string[],
  grantee: MaybeAwaitable<string>=env.deployer!.address,
  signer: MaybeAwaitable<SignerWithAddress>=env.deployer!
) {
  [signer, grantee] = await Promise.all([resolveMaybe(signer), resolveMaybe(grantee)]);
  const strat = await env.deployment!.strat.copy(signer);
  // const roleSignatures = roles.map((role) => ethers.utils.id(role));
  const roleSignatures = await env.multicallProvider!.all(
    roles.map((role) => strat.multi[`${role}_ROLE`]())
  );
  const hasRoles = async () =>
    env.multicallProvider!.all(
      roleSignatures.map((role) => strat.multi.hasRole(role, grantee))
    );
  const has = await hasRoles();
  console.log(`${signer.address} roles (before acceptRoles): ${has}`);
  for (const i in roleSignatures)
    if (!has[i])
      await strat
        .grantRole(roleSignatures[i], grantee, getOverrides(env))
        .then((tx: TransactionResponse) => tx.wait());
  console.log(`${signer.address} roles (after acceptRoles): ${await hasRoles()}`);
  return true;
}

export async function acceptRoles(
  env: Partial<IStrategyDeploymentEnv>,
  roles: string[],
  signer: MaybeAwaitable<SignerWithAddress>=env.deployer! // == grantee
) {
  signer = await resolveMaybe(signer);
  const strat = await env.deployment!.strat.copy(signer);
  // const roleSignatures = roles.map((role) => ethers.utils.id(role));
  const roleSignatures = await env.multicallProvider!.all(
    roles.map((role) => strat.multi[`${role}_ROLE`]())
  );

  const hasRoles = async () =>
    env.multicallProvider!.all(
      roleSignatures.map((role) => strat.multi.hasRole(role, (signer as SignerWithAddress).address))
    );
  const has = await hasRoles();
  console.log(`${signer.address} roles (before acceptRoles): ${has}`);
  for (const i in roleSignatures)
    if (!has[i])
      await strat
        .acceptRole(roleSignatures[i], getOverrides(env))
        .then((tx: TransactionResponse) => tx.wait());
  console.log(`${signer.address} roles (after acceptRoles): ${await hasRoles()}`);
  return true;
}

export async function revokeRoles(
  env: Partial<IStrategyDeploymentEnv>,
  roles: string[],
  deprived: MaybeAwaitable<string>, // == ex-grantee
  signer: MaybeAwaitable<SignerWithAddress>=env.deployer!
) {
  [signer, deprived] = await Promise.all([resolveMaybe(signer), resolveMaybe(deprived)]);
  const strat = await env.deployment!.strat.copy(signer);
  // const roleSignatures = roles.map((role) => ethers.utils.id(role));
  const roleSignatures = await env.multicallProvider!.all(
    roles.map((role) => strat.multi[`${role}_ROLE`]())
  );
  const hasRoles = async () =>
    env.multicallProvider!.all(
      roleSignatures.map((role) => strat.multi.hasRole(role, deprived))
    );
  const has = await hasRoles();
  console.log(`${signer.address} roles (before revokeRoles): ${has}`);
  for (const i in roleSignatures)
    if (has[i])
      await strat
        .revokeRole(roleSignatures[i], deprived, getOverrides(env))
        .then((tx: TransactionResponse) => tx.wait());
  console.log(`${signer.address} roles (after revokeRoles): ${await hasRoles()}`);
  return true;
}

export async function requestRescue(
  env: Partial<IStrategyDeploymentEnv>,
  token: SafeContract,
  signer: MaybeAwaitable<SignerWithAddress>=env.deployer! // == rescuer
) {
  signer = await resolveMaybe(signer);
  const strat = await env.deployment!.strat.copy(signer);
  await logRescue(env, token, signer.address, "Before RequestRescue");
  const receipt = await strat
    .requestRescue(token, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  return true;
}

export async function rescue(
  env: Partial<IStrategyDeploymentEnv>,
  token: SafeContract,
  signer: MaybeAwaitable<SignerWithAddress>=env.deployer! // == rescuer
) {
  signer = await resolveMaybe(signer);
  const strat = await env.deployment!.strat.copy(signer);
  await logRescue(env, token, signer.address, "Before Rescue");
  const receipt = await strat
    .rescue(token, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logRescue(env, token, signer.address, "After Rescue");
  return getTxLogData(receipt, ["uint256"], 0);
}

export const Flows: { [name: string]: Function } = {
  seedLiquidity,
  deposit,
  // requestDeposit: requestDeposit,
  withdraw,
  requestWithdraw,
  invest,
  liquidate,
  harvest,
  compound,
};

export interface IFlow {
  elapsedSec: number; // seconds since last block
  revertState: boolean; // revert state after flow
  env: IStrategyDeploymentEnv;
  fn: (typeof Flows)[keyof typeof Flows]; // only allow flow functions
  params: any[];
  assert: Function;
}

export async function testFlow(flow: IFlow) {
  let { env, elapsedSec, revertState, fn, params, assert } = flow;
  const live = isLive(env);

  console.log(
    `Running flow ${fn.name}(${params.join(", ")}, elapsedSec (before): ${
      elapsedSec ?? 0
    }, revertState (after): ${revertState ?? 0})`
  );
  let snapshotId = 0;

  if (!live) {
    if (revertState) snapshotId = await env.provider.send("evm_snapshot", []);
    if (elapsedSec) {
      const timeBefore = new Date(
        (await env.provider.getBlock("latest"))?.timestamp * 1000
      );
      await env.provider.send("evm_increaseTime", [
        ethers.utils.hexValue(elapsedSec),
      ]);
      await env.provider.send("evm_increaseBlocks", ["0x20"]); // evm_mine
      const timeAfter = new Date(
        (await env.provider.getBlock("latest"))?.timestamp * 1000
      );
      console.log(
        `⏰🔜 Advanced blocktime by ${elapsedSec}s: ${timeBefore} -> ${timeAfter}`
      );
    }
  }
  let result;
  try {
    result = await fn(env, ...params);
  } catch (e) {
    assert = () => false;
    console.error(e);
  }

  // revert the state of the chain to the beginning of this test, not to env.snapshotId
  if (!live && revertState) {
    const timeBefore = new Date(
      (await env.provider.getBlock("latest"))?.timestamp * 1000
    );
    await env.provider.send("evm_revert", [snapshotId]);
    const timeAfter = new Date(
      (await env.provider.getBlock("latest"))?.timestamp * 1000
    );
    console.log(`⏰🔙 Reverted blocktime: ${timeBefore} -> ${timeAfter}`);
  }

  if (assert) assert(result);

  return result;
}
