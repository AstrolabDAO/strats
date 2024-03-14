import {
  IDeploymentUnit,
  TransactionResponse,
  deploy,
  deployAll,
  loadAbi,
  network,
} from "@astrolabs/hardhat";
import {
  ITransactionRequestWithEstimate,
  getTransactionRequest,
} from "@astrolabs/swapper";
import * as ethers from "ethers";
import { BigNumber, Contract } from "ethers";
import { merge, shuffle } from "lodash";
import chainlinkOracles from "../../src/chainlink-oracles.json";
import {
  IStrategyParams,
  IStrategyDeployment,
  IStrategyDeploymentEnv,
  SafeContract,
} from "../../src/types";
import {
  addressZero,
  arraysEqual,
  ensureFunding,
  ensureOracleAccess,
  getEnv,
  getInitSignature,
  getOverrides,
  getTxLogData,
  isAddress,
  isLive,
  isOracleLib,
  isStablePair,
  logState,
} from "../utils";
import { collectFees, setMinLiquidity } from "./As4626";
import { grantRoles } from "./AsManageable";
import { findSymbolByAddress } from "../../src/addresses";
import compoundAddresses from "../../src/implementations/Compound/addresses";

export const indexes = Array.from({ length: 8 }, (_, index) => index);

/**
 * Deploys a strategy with the given parameters
 * @param env - Strategy deployment environment
 * @param name - Name of the strategy
 * @param contract - Contract name
 * @param initParams - Initialization parameters for the strategy
 * @param libNames - Names of the libraries required by the strategy
 * @param forceVerify - A flag indicating whether to check if the contract is verified on etherscan/tenderly
 * @returns Strategy deployment environment
 */
export const deployStrat = async (
  env: Partial<IStrategyDeploymentEnv>,
  name: string,
  contract: string,
  initParams: [IStrategyParams, ...any],
  libNames = ["AsAccounting"],
  forceVerify = false, // check that the contract is verified on etherscan/tenderly
): Promise<IStrategyDeploymentEnv> => {

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
        libraries: {} // isOracleLib(n) ? { AsMaths: libraries.AsMaths } : {},
      } as IDeploymentUnit;
      if (libParams.deployed) {
        console.log(`Using existing ${n} at ${libParams.address}`);
        lib = await SafeContract.build(
          address,
          (loadAbi(n) as any[]) ?? [],
          env.deployer!,
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
  const agentLibs = Object.assign({}, stratLibs);
  delete agentLibs.AsMaths; // not used statically by Agent/Strat

  for (const lib of Object.keys(agentLibs)) {
    if (isOracleLib(lib)) delete agentLibs[lib];
  }

  // delete stratLibs.AsAccounting; // not used statically by Strat

  const units: { [name: string]: IDeploymentUnit } = {
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

  // if (!isLive(env)) {
  //   env.deployment!.export = false;
  //   for (const unit of Object.values(units))
  //     unit.export = false;
  // }

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

  const preDeploymentsContracts: string[] = ["AccessController", "ChainlinkProvider", "Swapper", "StrategyV5Agent"];
  const preDeployments: { [name: string]: Contract } = {};
  for (const c of preDeploymentsContracts) {
    units[c] = {
      contract: c,
      name: c,
      verify: true,
      deployed: env.addresses!.astrolab?.[c] ? true : false,
      address: env.addresses!.astrolab?.[c] ?? "",
      overrides: getOverrides(env),
    };
    if (c == "StrategyV5Agent") {
      units[c].args = [preDeployments.AccessController.address];
      units[c].libraries = agentLibs;
    } else if (c == "ChainlinkProvider") {
      units[c].args = [preDeployments.AccessController.address];
    }
    if (!env.addresses!.astrolab?.[c]) {
      console.log(`Deploying missing ${c}`);
      preDeployments[c] = (await deploy(units[c]));
      units[c].verify = false; // we just verified it
    } else {
      console.log(
        `Using existing ${c} at ${env.addresses!.astrolab?.[c]}`,
      );
      preDeployments[c] = (await SafeContract.build(
        env.addresses!.astrolab?.[c]!,
        loadAbi(c)! as any[],
        env.deployer!,
      ));
    }
  }

  // default erc20Metadata
  initParams[0].erc20Metadata = merge(
    {
      name,
      decimals: 12,
    },
    initParams[0].erc20Metadata,
  );

  // default coreAddresses
  initParams[0].coreAddresses = merge(
    {
      wgas: env.addresses!.tokens.WGAS,
      feeCollector: env.deployer!.address, // feeCollector
      swapper: preDeployments.Swapper.address, // Swapper
      agent: preDeployments.StrategyV5Agent.address, // StrategyV5Agent
      oracle: preDeployments.ChainlinkProvider.address, // ChainlinkProvider
    },
    initParams[0].coreAddresses,
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
    initParams[0].fees,
  );

  // inputs
  if (initParams[0].inputWeights.length == 1)
    // default input weight == 100%
    initParams[0].inputWeights = [100_00];

  // add the access controller as sole constructor parameter to the strategy and its agent
  units[contract].args = [preDeployments.AccessController.address];

  merge(env.deployment, {
    ...preDeployments,
    name: `${name} Stack`,
    contract: "",
    initParams,
    verify: true,
    libraries,
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
  } else {
    await deployAll(env.deployment!);
  }

  if (!env.deployment!.units![contract].address)
    throw new Error(`Could not deploy ${contract}`);

  for (const c of preDeploymentsContracts) {
    if (!env.deployment!.units![c].address)
      throw new Error(`Could not deploy ${c}`);
    (env.deployment as any)[c] = await SafeContract.build(
      env.deployment!.units![c].address!,
      loadAbi(c) as any[],
    );
  }
  env.deployment!.strat = await SafeContract.build(
    env.deployment!.units![contract].address!,
    loadAbi(contract) as any[],
  );
  return env as IStrategyDeploymentEnv;
};

/**
 * Sets up a strategy deployment environment
 * @param contract - Strategy contract name
 * @param name - Name of the strategy
 * @param initParams - Initialization parameters for the strategy
 * @param minLiquidityUsd - Minimum liquidity in USD
 * @param libNames - Names of the libraries used by the strategy
 * @param env - Strategy deployment environment
 * @param forceVerify - A flag indicating whether to force verification
 * @param addressesOverride - Overridden addresses
 * @returns Strategy deployment environment
 */
export async function setupStrat(
  contract: string,
  name: string,
  // below we use hop strategy signature as placeholder
  initParams: [IStrategyParams, ...any],
  minLiquidityUsd = 10,
  libNames = ["AsAccounting"],
  env: Partial<IStrategyDeploymentEnv> = {},
  forceVerify = false,
  addressesOverride?: any,
): Promise<IStrategyDeploymentEnv> {
  env = await getEnv(env, addressesOverride);

  // make sure to include PythUtils if pyth is used (not lib used with chainlink)
  if (initParams[1]?.pyth && !libNames.includes("PythUtils")) {
    libNames.push("PythUtils");
  }
  env.deployment = {
    asset: await SafeContract.build(initParams[0].coreAddresses!.asset!),
    inputs: await Promise.all(
      initParams[0].inputs!.map((input) => SafeContract.build(input)),
    ),
    rewardTokens: await Promise.all(
      initParams[0].rewardTokens!.map((rewardToken) =>
        SafeContract.build(rewardToken),
      ),
    ),
  } as any;

  env = await deployStrat(
    env,
    name,
    contract,
    initParams,
    libNames,
    forceVerify,
  );

  const { strat, inputs, rewardTokens } = env.deployment!;

  // manager role is not granted instantly, it has to be accepted after 48 hours (deployer de-facto gets it)
  // here, only KEEPER will be granted at block-time
  await grantRoles(env, ["MANAGER", "KEEPER"], env.deployer!.address);

  // load the implementation abi, containing the overriding init() (missing from d.strat)
  // init((uint64,uint64,uint64,uint64,uint64),address,address[3],address[],uint256[],address[],address,address,address,uint8)'
  const proxy = env.deployment!.strat;

  await setMinLiquidity(env, minLiquidityUsd);
  // NB: can use await proxy.initialized?.() instead
  if ((await proxy.agent()) != addressZero) {
    console.log(`Skipping init() as ${name} already initialized`);
  } else {
    const initSignature = getInitSignature(contract);
    console.log("InitParams : ", initParams);
    console.log("InitSignature : ", initSignature);
    await proxy[initSignature](...initParams, getOverrides(env)).then(
      (tx: TransactionResponse) => tx.wait(),
    );
  }

  // once the strategy is initialized, rebuild the SafeContract object as symbol and decimals are updated
  env.deployment!.strat = await SafeContract.build(
    env.deployment!.units![contract].address!,
    loadAbi(contract) as any[], // use "StrategyV5" for strat generic abi
  );

  if (!isAddress(env.deployment!.strat.address)) {
    throw new Error(
      `Strategy ${name} not deployed at ${env.deployment!.strat.address}`,
    );
  }

  const actualInputs: string[] = //inputs.map((input) => input.address);
    await env.multicallProvider!.all(
      inputs.map((input, index) => strat.multi.inputs(index)),
    );

  const actualRewardTokens: string[] = // rewardTokens.map((reward) => reward.address);
    await env.multicallProvider!.all(
      rewardTokens.map((input, index) => strat.multi.rewardTokens(index)),
    );

  // assert that the inputs and rewardTokens are set correctly
  for (const i in inputs) {
    if (inputs[i].address.toUpperCase() != actualInputs[i].toUpperCase())
      throw new Error(
        `Input ${i} address mismatch ${inputs[i].address} != ${actualInputs[i]}`,
      );
  }

  for (const i in rewardTokens) {
    if (
      rewardTokens[i].address.toUpperCase() !=
      actualRewardTokens[i].toUpperCase()
    )
      throw new Error(
        `RewardToken ${i} address mismatch ${rewardTokens[i].address} != ${actualRewardTokens[i]}`,
      );
  }

  await logState(env, "After init", 1_000);

  const fullEnv = env as IStrategyDeploymentEnv;

  if (!isLive(env)) {
    await ensureFunding(fullEnv);
    // await ensureOracleAccess(fullEnv);
  }

  return fullEnv;
}

/**
 * Pre-investment function that computes the amounts and swap data for an on-chain invest call
 * @param env - Strategy deployment environment
 * @param _amount - Amount to invest (default: 100)
 * @returns Array containing the calculated amounts and swap data
 */
export async function preInvest(
  env: Partial<IStrategyDeploymentEnv>,
  _amount = 100,
) {
  const { asset, inputs, strat } = env.deployment!;
  const stratLiquidity = await strat.available();
  const [minSwapOut, minIouOut] = [1, 1];
  let amount = asset.toWei(_amount);

  if (stratLiquidity.lt(amount)) {
    console.warn(
      `Using stratLiquidity as amount (${stratLiquidity} < ${amount})`,
    );
    amount = stratLiquidity;
  }

  const amounts = await strat.callStatic.previewInvest(amount); // parsed as uint256[8]
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
      // inputAmount = amount.mul(weight).div(100_00).toString()
      tr = (await getTransactionRequest({
        input: asset.address,
        output: inputs[i].address,
        amountWei: amounts[i], // using a 100_00 bp basis (100_00 = 100%)
        inputChainId: network.config.chainId!,
        payer: strat.address,
        testPayer: env.addresses!.accounts!.impersonate,
      })) as ITransactionRequestWithEstimate;
    }
    trs.push(tr);
    swapData.push(
      ethers.utils.defaultAbiCoder.encode(
        // router, minAmountOut, data // TODO: minSwapOut == pessimistic estimate - slippage
        ["address", "uint256", "bytes"],
        [tr.to, minSwapOut, tr.data],
      ),
    );
  }
  return [amounts, swapData];
}

/**
 * Executes the on-chain investment of a strategy (cash to protocol)
 * @param env - Strategy deployment environment
 * @param _amount - Amount to invest (default: 0 will invest all available liquidity)
 * @returns Invested amount as a BigNumber
 */
export async function invest(
  env: Partial<IStrategyDeploymentEnv>,
  _amount = 0,
): Promise<BigNumber> {
  const { strat } = env.deployment!;
  const params = await preInvest(env!, _amount);
  await logState(env, "Before Invest");
  // only exec if static call is successful
  const receipt = await strat
    .safe("invest(uint256[8],bytes[])", params, getOverrides(env))
    // .invest(...params, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Invest", 1_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0);
}

/**
 * Executes the on-chain liquidation of a strategy (protocol to cash)
 * @param env - Strategy deployment environment
 * @param _amount - Amount to liquidate (default: 0 will liquidate all required liquidity)
 * @returns Liquidity available after liquidation
 */
export async function liquidate(
  env: Partial<IStrategyDeploymentEnv>,
  _amount = 0,
): Promise<BigNumber> {
  const { asset, inputs, strat } = env.deployment!;

  let amount = asset.toWei(_amount);

  const pendingWithdrawalRequest = await strat.totalPendingAssetRequest();
  const invested = await strat["invested()"]();
  const max = invested.gt(pendingWithdrawalRequest)
    ? invested
    : pendingWithdrawalRequest;

  if (pendingWithdrawalRequest.gt(invested)) {
    console.warn(
      `pendingWithdrawalRequest > invested (${pendingWithdrawalRequest} > ${invested})`,
    );
  }

  if (max.lt(amount)) {
    console.warn(`Using total allocated assets (max) ${max} (< ${amount})`);
    amount = max;
  }

  const trs = [] as Partial<ITransactionRequestWithEstimate>[];
  const swapData = [] as string[];
  const amounts = Object.assign([], await strat.callStatic.previewLiquidate(amount));
  const swapAmounts = new Array<BigNumber>(amounts.length).fill(
    BigNumber.from(0),
  );

  for (const i in inputs) {
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

      amounts[i] = amounts[i].mul(100_00 + derivation).div(100_00);
      swapAmounts[i] = amounts[i].mul(100_00).div(100_00); // slippage

      if (swapAmounts[i].gt(10)) {
        // only generate swapData if the input is not the asset
        tr = (await getTransactionRequest({
          input: inputs[i].address,
          output: asset.address,
          amountWei: swapAmounts[i], // take slippage off so that liquidated LP value > swap input
          inputChainId: network.config.chainId!,
          payer: strat.address, // env.deployer.address
          testPayer: env.addresses!.accounts!.impersonate,
          maxSlippage: 5000, // TODO: increase for low liquidity chains (moonbeam/celo/metis/linea...)
        })) as ITransactionRequestWithEstimate;
        if (!tr.to)
          throw new Error(
            `No swapData generated for ${inputs[i].address} -> ${asset.address}`,
          );
      }
    }
    trs.push(tr);
    swapData.push(
      ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256", "bytes"],
        [tr.to, 1, tr.data],
      ),
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
              swapAmounts[i],
            )} (${swapAmounts[i].toString()}wei), est. output: ${trs[i]
              .estimatedOutput!} ${asset.sym} (${trs[
              i
            ].estimatedOutputWei?.toString()}wei - exchange rate: ${
              trs[i].estimatedExchangeRate
            })\n`,
        )
        .join(""),
  );

  await logState(env, "Before Liquidate");
  // only exec if static call is successful
  const receipt = await strat
    .safe("liquidate", [amounts, 1, false, swapData], getOverrides(env))
    // .liquidate(amounts, 1, false, swapData, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());

  await logState(env, "After Liquidate", 1_000);
  return getTxLogData(receipt, ["uint256", "uint256", "uint256"], 2); // liquidityAvailable
}

/**
 * Generates harvest swap data for the given strategy
 * @param env - Strategy deployment environment
 * @returns Array of swapData strings
 */
export async function preHarvest(
  env: Partial<IStrategyDeploymentEnv>,
): Promise<string[]> {
  const { asset, inputs, rewardTokens, strat } = env.deployment!;

  // const rewardTokens = (await strat.rewardTokens()).filter((rt: string) => rt != addressZero);
  let amounts: BigNumber[];
  try {
    amounts = await strat.callStatic.claimRewards?.();
  } catch (e) {
    // claimRewards not implemented in legacy contracts
    amounts = (await strat.rewardsAvailable?.()) ?? [];
  }

  console.log(
    `Generating harvest swapData for:\n${rewardTokens
      .map((rt, i) => "  - " + rt.sym + ": " + rt.toAmount(amounts[i]))
      .join("\n")}`,
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

    if (rewardTokens[i].address != asset.address && amounts[i].gt(1e6)) {
      tr = (await getTransactionRequest({
        input: rewardTokens[i].address,
        output: asset.address,
        amountWei: amounts[i].sub(amounts[i].div(1_000)), // .1% slippage
        inputChainId: network.config.chainId!,
        payer: strat.address,
        testPayer: env.addresses!.accounts!.impersonate,
      })) as ITransactionRequestWithEstimate;
    }
    trs.push(tr);
    swapData.push(
      ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256", "bytes"],
        [tr.to, 1, tr.data],
      ),
    );
  }
  return swapData;
}

/**
 * Executes the strategy on-chain harvest (claim pending rewards + swap to underlying asset)
 * @param env The strategy deployment environment
 * @returns Amount of rewards harvested
 */
export async function harvest(
  env: Partial<IStrategyDeploymentEnv>,
): Promise<BigNumber> {
  const { strat, rewardTokens } = env.deployment!;
  const harvestSwapData = await preHarvest(env);
  await logState(env, "Before Harvest");
  // only exec if static call is successful
  const receipt = await strat
    .safe("harvest", [harvestSwapData], getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Harvest", 1_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0);
}

/**
 * Executes the strategy on-chain compound (harvest + invest)
 * @param env - Strategy deployment environment
 * @returns Compound result as a BigNumber
 */
export async function compound(
  env: IStrategyDeploymentEnv,
): Promise<BigNumber> {
  const { asset, inputs, strat } = env.deployment!;
  const harvestSwapData = await preHarvest(env);
  // harvest static call
  let harvestEstimate = BigNumber.from(0);
  try {
    harvestEstimate = await strat.callStatic.harvest(
      harvestSwapData,
      getOverrides(env),
    );
  } catch (e) {
    console.error(`Harvest static call failed: probably reverted ${e}`);
  }

  const [investAmounts, investSwapData] = await preInvest(
    env,
    asset.toAmount(harvestEstimate.sub(harvestEstimate.div(50))),
  ); // 2% slippage
  await logState(env, "Before Compound");
  // only exec if static call is successful
  const receipt = await strat
    .safe(
      "compound",
      [investAmounts, harvestSwapData, investSwapData],
      getOverrides(env),
    )
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Compound", 1_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0);
}

/**
 * Empties/retires a strategy by performing the following steps:
 * 1. Sets the maximum total assets to 0 (withdraw-only, retired strategy)
 * 2. Sets the minimum liquidity to 0
 * 3. Harvests and liquidates all invested assets
 * 4. Collects fees
 * 5. Withdraws all assets
 * @param env - Strategy deployment environment
 * @returns Difference in asset balance before and after executing the empty strategy
 */
export async function emptyStrategy(
  env: Partial<IStrategyDeploymentEnv>,
): Promise<BigNumber> {
  const { strat, asset, initParams } = env.deployment!;

  await logState(env, "Before EmptyStrategy");
  const assetBalanceBefore = await asset.balanceOf(env.deployer!.address);
  const deployerAddress = env.deployer!.address;
  // step 0: set max deposit to 0 (withdraw-only, retired strategy)
  await strat
    // .setMaxTotalAssets(0, getOverrides(env))
    .safe("setMaxTotalAssets", [0], getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());

  // step 1: set minLiquidity to 0
  await strat
    // .setMinLiquidity(0, getOverrides(env))
    .safe("setMinLiquidity", [0], getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());

  // step 2: harvest+liquidate all invested assets
  await harvest(env);
  await liquidate(env, asset.toAmount(await strat["invested()"]()));
  await collectFees(env);

  // step 3: withdraw all assets
  await strat
    // .redeem(strat.balanceOf(env.deployer!.address), getOverrides(env))
    .safe(
      "redeem",
      [
        (await strat.balanceOf(deployerAddress)).sub(1e8),
        deployerAddress,
        deployerAddress,
      ],
      getOverrides(env),
    )
    .then((tx: TransactionResponse) => tx.wait());

  await logState(env, "After EmptyStrategy", 1_000);
  return await asset.balanceOf(deployerAddress).sub(assetBalanceBefore);
}

/**
 * Pre-update generates swap data for the strategy on-chain underlying asset update
 * @param env - Partial strategy deployment environment
 * @param from - Address of the previous underlying asset (to swap from)
 * @param to - Address of the new underlying asset (to swap to)
 * @param amount - Amount of the asset to swap from (usually the strategy balance)
 * @returns Encoded swap data
 */
export async function preUpdateAsset(
  env: Partial<IStrategyDeploymentEnv>,
  from: string,
  to: string,
  amount: BigNumber,
): Promise<string> {
  const minSwapOut = 1; // TODO: use callstatic to define accurate minAmountOut
  let tr = {
    to: addressZero,
    data: "0x00",
  } as ITransactionRequestWithEstimate;

  // only generate swapData if the input is not the asset
  if (from != to && amount.gt(10)) {
    console.log("Preparing invest() SwapData from inputs/inputWeights");
    // const weight = env.deployment!.initParams[0].inputWeights[i];
    // if (!weight) throw new Error(`No inputWeight found for input ${i} (${inputs[i].symbol})`);
    // inputAmount = amount.mul(weight).div(100_00).toString()
    tr = (await getTransactionRequest({
      input: from,
      output: to,
      amountWei: amount, // using a 100_00 bp basis (100_00 = 100%)
      inputChainId: network.config.chainId!,
      payer: env.deployment!.strat.address,
      testPayer: env.addresses!.accounts!.impersonate,
    })) as ITransactionRequestWithEstimate;
  }
  return ethers.utils.defaultAbiCoder.encode(
    // router, minAmountOut, data
    ["address", "uint256", "bytes"],
    [tr.to, minSwapOut, tr.data],
  );
}

/**
 * Updates the underlying asset of a strategy (critical)
 * @param env - Strategy deployment environment
 * @param to - Address of the new underlying asset
 * @returns Updated balance of the new asset
 */
export async function updateAsset(
  env: Partial<IStrategyDeploymentEnv>,
  to: string,
): Promise<BigNumber> {
  const strat = await env.deployment!.strat;
  const from = await strat.asset();
  const fromToken = await SafeContract.build(from);
  const toToken = await SafeContract.build(to);
  const balance = await fromToken.balanceOf(strat.address);
  if (to == from) {
    console.warn(`Strategy underlying asset is already ${to}`);
    return balance;
  }
  const oracles = (<any>chainlinkOracles)[network.config.chainId!];
  const toSymbol = findSymbolByAddress(to, network.config.chainId!);
  if (!toSymbol) {
    throw new Error(`No symbol found for address: ${to}`);
  }
  const feed = oracles[`Crypto.${toSymbol}/USD`];
  const swapData = await preUpdateAsset(env, from, to, balance);
  await logState(env, "Before UpdateAsset");
  const receipt = await strat
    .safe(
      "updateAsset(address,bytes,address,uint256)",
      [to, swapData, feed, 86400],
      getOverrides(env),
    )
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After UpdateAsset", 1_000);
  // no event is emitted for optimization purposes, manual check
  const updated = await strat.asset();
  console.log("Updated asset: ", updated);
  return updated == to
    ? await toToken.balanceOf(strat.address)
    : BigNumber.from(0);
}

/**
 * Updates the inputs and weights of a strategy (critical)
 * @param env - Strategy deployment environment
 * @param inputs - New inputs to be set
 * @param weights - Corresponding weights for the new inputs
 * @param reorder - whether to reorder the inputs on existing (for testing purposes)
 * @returns BigNumber representing the result of the update
 */
export async function updateInputs(
  env: Partial<IStrategyDeploymentEnv>,
  inputs: string[],
  weights: number[],
  reorder: boolean = true,
  lpTokens: string[],
): Promise<BigNumber> {
  // step 1: retrieve current inputs
  const strat = await env.deployment!.strat;
  const oracles = (<any>chainlinkOracles)[network.config.chainId!];
  const emptyAddress = "0x0000000000000000000000000000000000000000";
  const indexes = [...Array(8).keys()];

  const stratParams = await env.multicallProvider!.all([
    ...indexes.map((i) => strat.multi.inputs(i)),
    ...indexes.map((i) => strat.multi.inputWeights(i)),
    ...indexes.map((i) => strat.multi.lpTokens(i)),
  ]);

  let lastInputIndex = stratParams.findIndex((input) => input == emptyAddress);

  if (lastInputIndex < 0) lastInputIndex = indexes.length; // max 8 inputs (if no empty address found)

  const [currentInputs, currentWeights, currentLpTokens] = [
    stratParams.slice(0, lastInputIndex),
    stratParams.slice(8, lastInputIndex),
    stratParams.slice(16, lastInputIndex),
  ] as [string[], number[], string[]];

  // step 2: Initialize final inputs and weights arrays
  let orderedInputs: string[] = new Array<string>(inputs.length).fill("");
  let orderedWeights: number[] = new Array<number>(inputs.length).fill(0);
  let orederedLpTokens: string[] = new Array<string>(inputs.length).fill("");

  const leftovers: string[] = [];

  if (reorder) {
    // step 3: Keep existing inputs in their original position if still present
    for (let i = 0; i < inputs.length; i++) {
      const prevIndex = currentInputs.indexOf(inputs[i]);
      if (prevIndex >= inputs.length || prevIndex < 0) {
        leftovers.push(inputs[i]);
        continue;
      }
      if (inputs.length > prevIndex) {
        orderedInputs[prevIndex] = currentInputs[prevIndex];
        orderedWeights[prevIndex] = weights[i];
        orederedLpTokens[prevIndex] = lpTokens[i];
      }
    }
  } else {
    orderedInputs = inputs;
    orderedWeights = weights;
    orederedLpTokens = lpTokens;
  }
  // TODO: add support for Pyth (only supports Chainlink)
  const oldSymbol = currentInputs.map((i) =>
    findSymbolByAddress(i, network.config.chainId!),
  );
  const newSymbol = inputs.map((i) =>
    findSymbolByAddress(i, network.config.chainId!),
  );
  const currentFeeds = oldSymbol.map((i) => oracles[`Crypto.${i}/USD`]);
  const newFeeds = newSymbol.map((i) => oracles[`Crypto.${i}/USD`]);

  // step 4: Infill + backfill with leftovers
  for (let i = 0; i < leftovers.length; i++) {
    const fillIndex = orderedInputs.indexOf("");
    orderedInputs[fillIndex] = leftovers[i];
    orderedWeights[fillIndex] = weights[currentInputs.indexOf(leftovers[i])];
    orederedLpTokens[fillIndex] = lpTokens[currentInputs.indexOf(leftovers[i])];
  }

  console.log(`
    prev inputs: [${currentInputs.join(", ")}] weights: [${currentWeights.join(
      ", ",
    )}]
    raw inputs: [${inputs.join(", ")}] weights: [${weights.join(", ")}]
    ord inputs: [${orderedInputs.join(", ")}] weights: [${orderedWeights.join(
      ", ",
    )}], reorder flag at: [${reorder}]
    prev feeds: [${currentFeeds.join(", ")}]
    ordered feeds: [${newFeeds.join(", ")}]
  `);

  // step 5: Set new input weights with current inputs to liquidate it all
  console.log(currentInputs, "currentInputs");
  console.log(currentLpTokens, "currentLpTokens");
  console.log(currentWeights, "currentWeights");

  // TODO: make sure that the oracle has all new feeds already set up

  let receipt = await strat
    .safe(
      "setInputs(address[],address[],uint16[],address[],uint256[])",
      [
        currentInputs,
        currentLpTokens,
        [0, 4500],
        // currentWeights.map((_, i) => {
        //   const index = orderedInputs.indexOf(currentInputs[i]);
        //   // reduce exposure to 0 for removed inputs (liquidate)
        //   // update weights for existing inputs (start rebalancing)
        //   return index > -1 ? orderedWeights[index] : 0;
        // }),
        [86400, 86400],
      ],
      getOverrides(env),
    )
    .then((tx: TransactionResponse) => tx.wait());

  // step 6: Liquidate all weights that have been set to 0 step 5
  console.log(`Liquidating removed inputs...`);
  await liquidate(env, 0);

  // step 7: Set new inputs and input weight
  console.log(`Setting new inputs...`);
  receipt = await strat
    .safe(
      "setInputs(address[],address[],uint16[],address[],uint256[])",
      [orderedInputs, lpTokens, orderedWeights, newFeeds,[86400,86400]],
      getOverrides(env),
    )
    .then((tx: TransactionResponse) => tx.wait());

  // step 8: Invest all assets (effective rebalancing with available cash from step 6 liquidation)
  console.log(`Investing all inputs...`);
  return await invest(env, 0);
}

/**
 * Shuffles the inputs of a strategy and sets random weights to it
 * @param env - Strategy deployment environment
 * @param weights - New weights to be set (for testing purposes)
 * @param reorder - whether to reorder the inputs on existing (for testing purposes)
 * @returns Rebalanced amounts as a BigNumber
 * @dev Not entirely generic yet, tailored for Compoundv3 forks
 */
export async function shuffleInputs(
  env: Partial<IStrategyDeploymentEnv>,
  weights?: number[],
  reorder = true,
): Promise<BigNumber> {
  // step 1: retrieve current inputs
  const strat = await env.deployment!.strat;
  const emptyAddress = "0x0000000000000000000000000000000000000000";
  const inputIndexes = [...Array(8).keys()];

  const inputData = await env.multicallProvider!.all(
    indexes.map((i) => strat.multi.inputs(i)),
  );
  const weightData = await env.multicallProvider!.all(
    indexes.map((i) => strat.multi.inputWeights(i)),
  );
  // const [inputData, weightData] = (await env.multicallProvider!.all(
  //   indexes.map((i) =>
  //   strat.multi.inputs(i)
  //   strat.multi.inputWeights(i),
  // ))) as [string[], BigNumber[]];

  let lastInputIndex = inputData.findIndex((input) => input == emptyAddress);

  if (lastInputIndex < 0) lastInputIndex = inputIndexes.length; // max 8 inputs (if no empty address found)

  let [currentInputs, currentWeights] = [
    inputData.slice(0, lastInputIndex),
    weightData.slice(0, lastInputIndex),
  ] as [string[], number[]];

  if (weights) currentWeights = weights;

  console.log(currentInputs, currentWeights);

  // step 2: randomly reorder inputs and set random weights adding up to the same cumsum
  console.log(`Shuffling inputs...`);
  let [randomInputs, randomWeights] = [
    shuffle(currentInputs),
    shuffle(currentWeights),
  ];
  // shuffle again if the result is the same for one of the arrays
  while (arraysEqual(randomInputs, currentInputs)) {
    randomInputs = shuffle(currentInputs);
  }

  // if there are two inputs and the weights are the same, break
  if (!currentWeights.every((v) => v === currentWeights[0])) {
    while (arraysEqual(randomWeights, currentWeights)) {
      randomWeights = shuffle(currentWeights);
    }
  }
  console.log(randomInputs, randomWeights);

  // For Compound only
  const symbol = randomInputs.map((i) =>
    findSymbolByAddress(i, network.config.chainId!),
  );
  console.log("The symbol to search for: ", symbol);
  const cTokens = symbol.map(
    (i) => compoundAddresses[network.config.chainId!].Compound[i!].comet,
  );
  console.log("The cTokens we found after shuffle: ", cTokens);

  // step 3: return updateInputs with the above
  return await updateInputs(env, randomInputs, randomWeights, reorder, cTokens);
}

/**
 * Updates the input weights of a strategy
 * @param env - Strategy deployment environment
 * @param weights - New weights to be set
 * @returns Boolean indicating whether the input weights were successfully updated
 */
export async function updateInputWeights(
  env: Partial<IStrategyDeploymentEnv>,
  weights: number[],
): Promise<boolean> {
  // step 1: retrieve current inputs
  const strat = await env.deployment!.strat;
  const [currentInputs, currentWeights] = (await env.multicallProvider!.all([
    strat.multi.inputs(),
    strat.multi.inputWeights(),
  ])) as [string[], number[]];

  // step 2: return updateInputs with the above
  const receipt = await strat
    .safe(
      "setInputs(address[],uint16[])", // StrategyV5Agent overload
      [currentInputs, currentWeights],
      getOverrides(env),
    )
    .then((tx: TransactionResponse) => tx.wait());
  const updatedWeights = await strat.inputWeights();

  for (let i = 0; i < env!.deployment!.inputs.length; i++)
    if (weights[i] != updatedWeights[i].toNumber()) return false;
  return true;
}

/**
 * Shuffles the input weights of a strategy
 * @param env - Strategy deployment environment
 * @returns Boolean indicating whether the shuffling was successful
 */
export async function shuffleInputWeights(
  env: Partial<IStrategyDeploymentEnv>,
): Promise<boolean> {
  // step 1: retrieve current inputs
  const strat = await env.deployment!.strat;
  const currentWeights: number[] = await strat.inputWeights();

  // step 2: randomly reorder inputs and set random weights adding up to the same cumsum
  console.log(`Shuffling input weights...`);
  const randomWeights = shuffle(currentWeights);

  // step 3: return updateInputs with the above
  return await updateInputWeights(env, randomWeights);
}

/**
 * Shuffles the weights, rebalances the strategy, and returns Result
 * @param env - Strategy deployment environment
 * @returns Rebalanced amounts as a BigNumber
 */
export async function shuffleWeightsRebalance(
  env: Partial<IStrategyDeploymentEnv>,
): Promise<BigNumber> {
  // step 1: shuffle
  if (!(await shuffleInputWeights(env))) return BigNumber.from(0);

  // step 2: liquidate
  const strat = await env.deployment!.strat;
  const invested = await strat.invested();
  await liquidate(env, invested.mul(100).div(110)); // 90% turnover

  // step 3: invest
  return await invest(env, 0);
}
// function findSymbolByAddress(to: string, arg1: number) {
//   throw new Error("Function not implemented.");
// }

