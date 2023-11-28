import { provider, network, weiToString, TransactionRequest, IDeploymentUnit, deploy, deployAll, loadAbi, ethers, TransactionResponse } from "@astrolabs/hardhat";
import { ISwapperParams, swapperParamsToString, getAllTransactionRequests, getTransactionRequest, ITransactionRequestWithEstimate } from "@astrolabs/swapper";
import { wethAbi, erc20Abi } from "abitype/abis";
import { Contract, BigNumber, utils as ethersUtils } from "ethers";
import { assert } from "chai";
import { merge } from "lodash";
import { IStrategyDeployment, IStrategyDeploymentEnv, StrategyV5InitParams, IToken, Erc20Metadata } from "../../src/types";
import { addressZero, getEnv, getTokenInfo, getTxLogData, logState } from "./utils";

const MaxUint256 = ethers.constants.MaxUint256;


export const deployStrat = async (
  env: Partial<IStrategyDeploymentEnv>,
  name: string,
  contract: string,
  constructorParams: [Erc20Metadata],
  initParams: StrategyV5InitParams,
): Promise<IStrategyDeploymentEnv> => {
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
      libraries,
      verify: true,
      deployed: env.addresses!.astrolab?.StrategyAgentV5 ? true : false,
      address: env.addresses!.astrolab?.StrategyAgentV5,
    },
    [contract]: {
      contract,
      name: contract,
      verify: true,
      proxied: ["StrategyAgentV5"],
      args: constructorParams,
      libraries,
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
  initParams[0] = merge(
    {
      perf: 1_000, // 10%
      mgmt: 20, // .2%
      entry: 2, // .02%
      exit: 2, // .02%
    },
    initParams[0]
  );

  // coreAddresses
  initParams[2] = [
    env.deployer!.address, // feeCollector
    swapper.address, // Swapper
    addressZero, // Allocator
    agent.address, // StrategyAgentV5
  ];

  // inputs
  if (initParams[3].length == 1)
    // default input weight == 100%
    initParams[4] = [100_000];

  const deployment = {
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
  env.deployment = deployment;
  return env as IStrategyDeploymentEnv;
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
  constructorParams: [Erc20Metadata],
  initParams: StrategyV5InitParams,
  initSignature = "init",
  env: Partial<IStrategyDeploymentEnv> = {},
  addressesOverride?: any
): Promise<IStrategyDeploymentEnv> {

  env = await getEnv(env, addressesOverride);
  env = await deployStrat(env, name, contract, constructorParams, initParams);

  const { strat } = env.deployment!;

  await grantAdminRole(strat, env.deployer!.address);

  // load the implementation abi, containing the overriding init() (missing from d.strat)
  // init((uint64,uint64,uint64,uint64),address,address[4],address[],uint256[],address[],address,address,address,uint8)'
  const proxy = new Contract(strat.address, loadAbi(contract)!, env.deployer);
  const ok = await proxy[initSignature](...initParams, {
    gasLimit: 5e7,
  });

  const underlying = new Contract(initParams[1], erc20Abi, env.deployer);
  const inputs = initParams[3]!.map(
    (input) => new Contract(input, erc20Abi, env.deployer)
  );
  const rewardTokens = initParams[5]!.map(
    (rewardToken) => new Contract(rewardToken, erc20Abi, env.deployer)
  );

  env.deployment!.underlying = await getTokenInfo(underlying);
  env.deployment!.inputs = await Promise.all(inputs.map(getTokenInfo));
  env.deployment!.rewardTokens = await Promise.all(rewardTokens.map(getTokenInfo));

  await logState(env, "After init");
  return env as IStrategyDeploymentEnv;
}

export async function deposit(env: IStrategyDeploymentEnv, amount = 100) {
  const { strat, underlying } = env.deployment!;
  amount *= underlying.weiPerUnit; // 100$ or equivalent
  await underlying.contract.approve(strat.address, MaxUint256);
  await logState(env, "Before Deposit");
  const receipt = await strat.safeDeposit(amount, env.deployer.address, 1, {
    gasLimit: 5e7,
  }).then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Deposit");
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
  const receipt = await strat.swapSafeDeposit(
    input.address, // input
    amount, // amount == 100$
    env.deployer.address, // receiver
    1, // minShareAmount in wei
    swapData, // swapData
    { gasLimit: 5e7 }
  ).then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After SwapDeposit");
  return getTxLogData(receipt, ["uint256", "uint256"])[0];
}

export async function seedLiquidity(
  env: IStrategyDeploymentEnv,
  amount = 50
) {
  const { strat, underlying } = env.deployment!;
  amount *= underlying.weiPerUnit;
  await underlying.contract.approve(strat.address, MaxUint256);
  await logState(env, "Before SeedLiquidity");
  const receipt = await strat.seedLiquidity(amount, MaxUint256, { gasLimit: 5e7 })
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After SeedLiquidity");
  return getTxLogData(receipt, ["uint256", "uint256"], -2)[0]; // seeded amount
}

// TODO: add support for multiple inputs
// input prices are required to weight out the swaps and create the SwapData array
export async function invest(env: IStrategyDeploymentEnv, amount = 100) {
  const { underlying, inputs, strat } = env.deployment!;
  amount *= inputs[0].weiPerUnit; // 100$ or equivalent
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
  const receipt = await strat.invest(amount, 1, [swapData], { gasLimit: 5e7 })
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Invest");
  return getTxLogData(receipt, ["uint256", "uint256"])[0];
}

// TODO: add support for multiple inputs
// input prices are required to weight out the swaps and create the SwapData array
export async function liquidate(env: IStrategyDeploymentEnv, amount = 50) {
  const { underlying, inputs, strat } = env.deployment!;
  amount *= inputs[0].weiPerUnit; // 10$ or equivalent
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
      payer: env.deployer.address,
      testPayer: env.addresses.accounts!.impersonate,
    })) as ITransactionRequestWithEstimate;
  }
  swapData = ethersUtils.defaultAbiCoder.encode(
    ["address", "uint256", "bytes"],
    [tr.to, 1, tr.data]
  );
  await logState(env, "Before Liquidate");
  // const [liquidity, totalAssets] = await strat.liquidate(amount, 1, false, [swapData], { gasLimit: 5e7 });
  const receipt = await strat.liquidate(amount, 1, false, [swapData], { gasLimit: 5e7 })
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Liquidate");
  return getTxLogData(receipt, ["uint256", "uint256", "uint256"])[2]; // liquidityAvailable
}

export async function withdraw(env: IStrategyDeploymentEnv, amount = 50) {
  const { underlying, inputs, strat } = env.deployment!;
  amount *= underlying.weiPerUnit; // 10$ or equivalent
  const minAmount = 1; // TODO: change with staticCall
  await logState(env, "Before Withdraw");
  const receipt = await strat.safeWithdraw(
    amount, minAmount,
    env.deployer.address, env.deployer.address,
    { gasLimit: 5e7 }
  ).then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Withdraw");
  return getTxLogData(receipt, ["uint256", "uint256"])[0]; // recovered
}

export async function requestWithdraw(env: IStrategyDeploymentEnv, amount = 50) {
  const { underlying, inputs, strat } = env.deployment!;
  amount *= underlying.weiPerUnit; // 10$ or equivalent
  const minAmount = 1; // TODO: change with staticCall
  await logState(env, "Before RequestWithdraw");
  const receipt = await strat.requestWithdraw(
    amount,
    env.deployer.address, env.deployer.address,
    { gasLimit: 5e7 }
  ).then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After RequestWithdraw");
  return getTxLogData(receipt, ["uint256", "uint256"])[0]; // recovered
}