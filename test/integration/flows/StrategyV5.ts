import {
  IDeploymentUnit,
  TransactionResponse,
  deploy,
  deployAll,
  getSalts,
  loadAbi,
  network,
  findSymbolByAddress,
  SafeContract,
  abiEncode,
  addressToBytes32,
  addressZero,
  arraysEqual,
  duplicatesOnly,
  getEnv,
  getInitSignature,
  getTxLogData,
  isAddress,
  isLive,
  isOracleLib,
  isStablePair,
  isDeployed,
} from "@astrolabs/hardhat";
import {
  ITransactionRequestWithEstimate,
  getTransactionRequest,
} from "@astrolabs/swapper";
import * as ethers from "ethers";
import { BigNumber, Contract } from "ethers";
import { merge, shuffle } from "lodash";
import {
  IStrategyParams,
  IStrategyDeployment,
  IStrategyDeploymentEnv,
  IAddons,
} from "../../../src/types";
import {
  randomRedistribute,
  ensureFunding,
  ensureOracleAccess,
  getOverrides,
  logState,
  getStratParams,
} from "../../utils";
import { collectFees, setMinLiquidity } from "./As4626";
import { grantRoles } from "./AsManageable";
import compoundAddresses from "../../../src/external/Compound/addresses";

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
  initParams: IStrategyParams,
  libNames = ["AsAccounting"],
  forceVerify = false, // check that the contract is verified on etherscan/tenderly
): Promise<IStrategyDeploymentEnv> => {

  // strategy dependencies
  const libraries: { [name: string]: string } = {};
  const contractUniqueName = name; // `${contract}.${env.deployment?.inputs?.map(i => i.symbol).join("-")}`;
  const salts = getSalts();
  for (const n of libNames) {
    let lib = {} as Contract;
    const path = `src/libs/${n}.sol:${n}`;
    const address = env.addresses!.astrolab?.[n] ?? "";
    if (!libraries[n]) {
      const deployed = !!address && await isDeployed(address, env);
      const libParams: IDeploymentUnit = {
        contract: n,
        name: n,
        verify: !deployed,
        deployed,
        address,
        libraries: {}, // isOracleLib(n) ? { AsMaths: libraries.AsMaths } : {},
      };
      if (libParams.deployed) {
        console.log(`Using existing ${n} at ${libParams.address}`);
        lib = await SafeContract.build(
          address,
          await loadAbi(n) as any[],
          env.deployer!,
        );
      } else {
        if (salts[n]) {
          libParams.useCreate3 = true;
          libParams.create3Salt = salts[n];
        }
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

  const deployed = await isDeployed(contractUniqueName, env);
  const units: { [name: string]: IDeploymentUnit } = {
    [contract]: {
      contract,
      name: contract,
      verify: !deployed,
      deployed,
      address: deployed ? env.addresses!.astrolab?.[contractUniqueName] : "",
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

  const preDeploymentsContracts: string[] = [
    "AccessController",
    "PriceProvider",
    "Swapper",
    "StrategyV5Agent",
  ];
  const preDeployments: { [name: string]: Contract } = {};
  for (const c of preDeploymentsContracts) {
    const deployed = await isDeployed(c, env);
    const dep = {
      contract: c,
      name: c,
      verify: !deployed,
      deployed,
      address: deployed ? env.addresses!.astrolab?.[c] : "",
      overrides: getOverrides(env),
    } as any;
    if (c == "AccessController") {
      dep.args = [env.deployer!.address];
    } else if (c == "StrategyV5Agent") {
      dep.args = [preDeployments.AccessController.address];
      dep.libraries = agentLibs;
    } else if (c == "PriceProvider") {
      dep.args = [preDeployments.AccessController.address];
      // NB: Chainlink only for now, not Pyth/API3/RedStone
      dep.contract = "ChainlinkProvider";
    }
    units[c] = dep;
    if (!env.addresses!.astrolab?.[c]) {
      console.log(`Deploying missing ${c}`);
      const create3Id = dep.contract == contract ? contractUniqueName : dep.contract;
      if (salts[create3Id]) {
        units[c].useCreate3 = true;
        units[c].create3Salt = salts[create3Id];
      }
      const d = await deploy(units[c]);
      // construct deployed contract
      preDeployments[c] = await SafeContract.build(
        d.address!,
        await loadAbi(dep.contract) as any[],
        env.deployer!,
      );
      dep.verify = false; // we just verified it (theoretically)
    } else {
      console.log(`Using existing ${c} at ${env.addresses!.astrolab?.[c]}`);
      preDeployments[c] = await SafeContract.build(
        env.addresses!.astrolab?.[c]!,
        await loadAbi(dep.contract) as any[],
        env.deployer!,
      );
    }
  }

  // NB: PriceProvider deployments + feeds initialization (eg. ChainlinkProvider.update())
  // eliminates the need for in-testing price feed setup
  // this remains here for custom dev setup
  let baseSymbols = Array.from(
    new Set([
      ...env.deployment!.inputs.map(i => i.sym),  // initParams.inputs!,
      ...["WETH", "WBTC", "USDC", "USDT", "FRAX", "DAI"]
    ].filter((t) => !!t)),
  );
  let baseAddresses = baseSymbols.map((sym) => env.addresses!.tokens[sym]);
  const checkFeeds = async () =>
    env.multicallProvider!.all(
      baseAddresses!.map(addr => preDeployments.PriceProvider.multi.hasFeed(addr)),
    );

  // NB: the signer has to be the admin of `PriceProvider.accessController`, otherwise this will fail
  if ((await checkFeeds()).some((has) => !has)) {
    let feeds = baseSymbols.map((sym) => {
      const feed = env.oracles![`Crypto.${sym}/USD`];
      return feed ? addressToBytes32(feed) : null;
    });
    const indexes = feeds.map((feed, i) => (feed ? i : null));
    [baseAddresses, baseSymbols, feeds] = [baseAddresses, baseSymbols, feeds].map(
      (a) => a.filter((_, i) => indexes.includes(i)),
    ) as string[][];
    if (feeds.length != baseSymbols.length) {
      console.warn(`{baseSymbols.length - feeds.length} feeds missing`);
    }
    // NB: this is Chainlink's initializer, not Pyth (Pyth takes bytes32[] feeds and not addresses)
    await preDeployments.PriceProvider.update(
      abiEncode(
        ["(address[],bytes32[],uint256[])"],
        [
          [
            baseAddresses,
            feeds,
            baseSymbols.map((feed) => 3600 * 48), // chainlink default validity (1 day) * 2
          ],
        ],
      ),
    ).then((tx: TransactionResponse) => tx.wait());
  }

  if ((await checkFeeds()).some((has) => !has)) {
    throw new Error(`Some price feeds are still missing`);
  }

  // default erc20Metadata
  initParams.erc20Metadata = merge(
    {
      name,
      decimals: 12, // default strategy decimals
    },
    initParams.erc20Metadata,
  );

  // default coreAddresses
  initParams.coreAddresses = merge(
    {
      wgas: env.addresses!.tokens.WGAS,
      feeCollector: env.deployer!.address, // feeCollector
      swapper: preDeployments.Swapper.address, // Swapper
      agent: preDeployments.StrategyV5Agent.address, // StrategyV5Agent
      oracle: preDeployments.PriceProvider.address, // PriceProvider
    },
    initParams.coreAddresses,
  );

  // default fees
  initParams.fees = merge(
    {
      perf: 1_000, // 10%
      mgmt: 20, // .2%
      entry: 2, // .02%
      exit: 2, // .02%
      flash: 2, // .02% << 2.5x cheaper than aave
    },
    initParams.fees,
  );

  // inputs
  if (initParams.inputWeights.length == 1)
    // default input weight == 90%, 10% cash
    initParams.inputWeights = [90_00];

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
    if (salts[contractUniqueName]) {
      env.deployment!.units![contract].useCreate3 = true;
      env.deployment!.units![contract].create3Salt = salts[contractUniqueName];
    }
    await deployAll(env.deployment!);
  }

  if (!env.deployment!.units![contract].address)
    throw new Error(`Could not deploy ${contract}`);

  for (const c of preDeploymentsContracts) {
    if (!env.deployment!.units![c].address)
      throw new Error(`Could not deploy ${c}`);
    const dep = (env.deployment as any);
    if (dep[c]?.symbol) {
      dep[c] = await SafeContract.build(
        env.deployment!.units![c].address!, // dep[c].address
        await loadAbi(c) as any[],
      );
    }
  }
  env.deployment!.strat = await SafeContract.build(
    env.deployment!.units![contract].address!,
    await loadAbi(contract) as any[],
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
  initParams: IStrategyParams,
  minLiquidityUsd = 10,
  libNames = ["AsAccounting"],
  env: Partial<IStrategyDeploymentEnv> = {},
  forceVerify = false,
  addressesOverride?: any,
): Promise<IStrategyDeploymentEnv> {
  env = await getEnv(env, addressesOverride);

  // make sure to include PythUtils if pyth is used (not lib used with chainlink)
  env.deployment = {
    asset: await SafeContract.build(initParams.coreAddresses!.asset!),
    inputs: await Promise.all(
      initParams.inputs!.map((input) => SafeContract.build(input)),
    ),
    rewardTokens: await Promise.all(
      initParams.rewardTokens!.map((rewardToken) =>
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
  const proxy = env.deployment!.strat;

  await setMinLiquidity(env, minLiquidityUsd);
  // NB: can use await proxy.initialized?.() instead
  if ((await proxy.agent()) != addressZero) {
    console.log(`Skipping init() as ${name} already initialized`);
  } else {
    const initSignature = await getInitSignature(contract);
    console.log("InitParams:", initParams);
    console.log("InitSignature:", initSignature);
    await proxy[initSignature](initParams, getOverrides(env)).then(
      (tx: TransactionResponse) => tx.wait(),
    );
  }

  // once the strategy is initialized, rebuild the SafeContract object as symbol and decimals are updated
  env.deployment!.strat = await SafeContract.build(
    env.deployment!.units![contract].address!,
    await loadAbi(contract) as any[], // use "StrategyV5" for strat generic abi
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
  _amount = 0,
) {
  const { asset, inputs, strat } = env.deployment!;
  const [minSwapOut, minIouOut] = [1, 1];
  let amount = asset.toWei(_amount);
  const stratLiquidity = await strat.available();

  if (stratLiquidity.lt(amount)) {
    console.warn(
      `Using stratLiquidity as amount (${stratLiquidity} < ${amount})`,
    );
    amount = stratLiquidity;
  }

  const amounts = await strat.callStatic.preview(amount, true); // parsed as uint256[8]
  const trs = [] as Partial<ITransactionRequestWithEstimate>[];
  const swapData = [] as string[];

  for (const i in inputs) {
    let tr = <ITransactionRequestWithEstimate>({
      to: addressZero,
      data: "0x00",
      estimatedExchangeRate: 1, // no swap 1:1
      estimatedOutputWei: amounts[i],
    });

    // only generate swapData if the input is not the asset
    if (asset.address != inputs[i].address && amounts[i].gt(10)) {
      // const weight = env.deployment!.initParams.inputWeights[i];
      // if (!weight) throw new Error(`No inputWeight found for input ${i} (${inputs[i].symbol})`);
      // inputAmount = amount.mul(weight).div(100_00).toString()
      tr = <ITransactionRequestWithEstimate>(await getTransactionRequest({
        input: asset.address,
        output: inputs[i].address,
        amountWei: amounts[i], // using a 100_00 bp basis (100_00 = 100%)
        inputChainId: network.config.chainId!,
        payer: strat.address,
        testPayer: env.addresses!.accounts!.impersonate,
      }));
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

  // generate investAddons swapdata if any
  const addons = await strat.callStatic.previewSwapAddons(amounts, true) as IAddons;
  for (const i in addons.amounts) {
    if (addons.from[i] == addons.to[i]) continue;
    if (addons.to[i] == addressZero || addons.from[i] == addressZero) break;
    if (addons.amounts[i].gt(10)) {
      const tr = <ITransactionRequestWithEstimate>(await getTransactionRequest({
        input: addons.from[i],
        output: addons.to[i],
        amountWei: addons.amounts[i],
        inputChainId: network.config.chainId!,
        payer: strat.address,
        testPayer: env.addresses!.accounts!.impersonate,
      }));
      trs.push(tr);
      swapData.push(
        ethers.utils.defaultAbiCoder.encode(
          ["address", "uint256", "bytes"],
          [tr.to, 1, tr.data],
        ),
      );
    }
  }
  console.log(`InvestAddons:\n\t${addons.from.filter((f) => !!f).map((f, i) => `${findSymbolByAddress(addons.from[i])} -> ${findSymbolByAddress(addons.to[i])}: ${addons.amounts[i].toString()}`).join("\n\t")}`);
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
  const [amounts, swapData] = await preInvest(env!, _amount);
  await logState(env, "Before Invest");
  const receipt = await strat
    .invest(amounts, swapData, getOverrides(env))
    // .safe("invest(uint256[8],bytes[])", [amounts, swapData], getOverrides(env))
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
export async function liquidatePrimitives(
  env: Partial<IStrategyDeploymentEnv>,
  _amounts = [[BigNumber.from(0)]],
  _minLiquidity = [BigNumber.from(0)],
): Promise<BigNumber> {
  const { asset, inputs, strat } = env.deployment!;

  let amounts: BigNumber[][] = _amounts.map(innerArray =>
    innerArray.map(amount =>
      BigNumber.from(amount)
    )
  );

  // if (max.lt(amount)) {
  //   console.warn(`Using total allocated assets (max) ${max} (< ${amount})`);
  //   amount = max;
  // }

  const trs = [] as Partial<ITransactionRequestWithEstimate>[];
  const swapData = [] as string[];
  // const amounts = Object.assign([], await strat.preview(amount, false));
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
      estimatedOutput: inputs[i].toAmount(amounts[i][0]),
    } as ITransactionRequestWithEstimate;

    if (asset.address != inputs[i].address) {
      // add 1% slippage to the input amount, .1% if stable (2x as switching from ask estimate->bid)
      // NB: in case of a volatility event (eg. news/depeg), the liquidity would be one sided
      // and these estimates would be off. Liquidation would require manual parametrization
      // using more pessimistic amounts (eg. more slippage) in the swapData generation
      const stablePair = isStablePair(asset.sym, inputs[i].sym);
      // oracle derivation tolerance (can be found at https://data.chain.link/ for chainlink)
      const derivation = stablePair ? 100 : 1_000; // .1% or 1%
      amounts[i] = [amounts[i][0].mul(10_000 + derivation).div(10_000)];
      swapAmounts[i] = amounts[i][0].mul(10_000).div(10_000); // slippage

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
    `Liquidating ${asset.sym}\n` +
    inputs
      .map(
        (input, i) =>
          `  - ${input.sym}: ${input.toAmount(amounts[i][0])} (${amounts[
            i
          ].toString()}wei), swap amount: ${input.toAmount(
            swapAmounts[i],
          )} (${swapAmounts[i].toString()}wei), est. output: ${trs[i]
            .estimatedOutput!} ${asset.sym} (${trs[
              i
            ].estimatedOutputWei?.toString()}wei - exchange rate: ${trs[i].estimatedExchangeRate
          })\n`,
      )
      .join(""),
  );

  await logState(env, "Before Liquidate primitives");
  // only exec if static call is successful
  const receipt = await strat
    .safe("liquidatePrimitives", [amounts, 1, false, []], getOverrides(env))
    // .liquidatePrimitives(amounts, 1, false, swapData, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());

  await logState(env, "After Liquidate", 2_000);
  return getTxLogData(receipt, ["uint256", "uint256", "uint256"], 2); // liquidityAvailable
}

/**
 * Pre-divestment function that computes the amounts and swap data for an on-chain invest call
 * @param env - Strategy deployment environment
 * @param _amount - Amount to invest (default: 100)
 * @returns Array containing the calculated amounts and swap data
 */
export async function preLiquidate(
  env: Partial<IStrategyDeploymentEnv>,
  _amount = 0,
) {
  const { asset, inputs, strat, PriceProvider } = env.deployment!;
  const [minSwapOut, minIouOut] = [1, 1];
  let amount = asset.toWei(_amount);

  const pendingWithdrawalRequest = await strat.totalPendingWithdrawRequest();
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
  let amounts = (await strat.callStatic.preview(amount, false) as BigNumber[]);

  // NB: no need to convert to input amounts anymore as amounts are already in input units
  // const inputSwapAmounts = await env.multicallProvider?.all(
  //   inputs.map((input, i) => PriceProvider.multi.convert(asset.address, amounts[i], inputs[i].address))) as BigNumber[];

  const investedInputs = await env.multicallProvider?.all(
    inputs.map((input, i) => strat.multi.investedInput(i)),
  ) as BigNumber[];

  for (const i in inputs) {

    // by default input == asset, no swapData is required
    let tr = <ITransactionRequestWithEstimate>({
      to: addressZero,
      data: "0x00",
      estimatedExchangeRate: 1, // no swap 1:1
      estimatedOutputWei: amounts[i],
    });

    if (investedInputs[i] && amounts[i].gt(investedInputs[i])) {
      console.log(
        `Swap amount ${inputs[i].toAmount(amount)} > invested ${inputs[i].toAmount(
          investedInputs[i],
        )} reducing...`,
      );
      amounts[i] = investedInputs[i];
    }

    // only generate swapData if the input is not the asset
    if (inputs[i] && asset.address != inputs[i].address && amounts[i].gt(10)) {
      // add 1% slippage to the input amount, .1% if stable (2x as switching from ask estimate->bid)
      // NB: in case of a volatility event (eg. news/depeg), the liquidity would be one sided
      // and these estimates would be off. Liquidation would require manual parametrization
      // using more pessimistic amounts (eg. more slippage) in the swapData generation
      // const stablePair = isStablePair(asset.sym, inputs[i].sym);
      // oracle derivation tolerance (can be found at https://data.chain.link/ for chainlink)
      // const derivation = stablePair ? 100 : 1_000; // .1% or 1%
      // const slippage = stablePair ? 25 : 250; // .025% or .25%
      // amounts[i] = amounts[i].mul(100_00 + derivation).div(100_00);

      tr = <ITransactionRequestWithEstimate>(await getTransactionRequest({
        input: inputs[i].address,
        output: asset.address,
        amountWei: amounts[i], // take slippage off so that liquidated LP value > swap input
        inputChainId: network.config.chainId!,
        payer: strat.address, // env.deployer.address
        testPayer: env.addresses!.accounts!.impersonate,
        maxSlippage: 5_000, // TODO: use a smarter slippage estimation cf. above
      }));
    }
    trs.push(tr);
    swapData.push(
      ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256", "bytes"],
        [tr.to, minSwapOut, tr.data],
      ),
    );
  }

  // generate liquidateAddons swapdata if any
  const addons = await strat.callStatic.previewSwapAddons(amounts, false) as IAddons;
  for (const i in addons.amounts) {
    if (addons.from[i] == addons.to[i]) continue;
    if (addons.to[i] == addressZero || addons.from[i] == addressZero) break;
    if (addons.amounts[i].gt(10)) {
      const tr = <ITransactionRequestWithEstimate>(await getTransactionRequest({
        input: addons.from[i],
        output: addons.to[i],
        amountWei: addons.amounts[i],
        inputChainId: network.config.chainId!,
        payer: strat.address,
        testPayer: env.addresses!.accounts!.impersonate,
      }));
      trs.push(tr);
      swapData.push(
        ethers.utils.defaultAbiCoder.encode(
          ["address", "uint256", "bytes"],
          [tr.to, 1, tr.data],
        ),
      );
    }
  }
  console.log(
    `Liquidating ${asset.toAmount(amount)}${asset.sym
    } (default: 0 will liquidate all required liquidity)\n` +
    inputs
      .map(
        (input, i) =>
          `  - ${input.sym}: ${input.toAmount(amounts[i])} (${amounts[
            i
          ].toString()}wei), swap amount: ${input.toAmount(
            amounts[i],
          )} (${amounts[i].toString()}wei), est. output: ${trs[i]
            .estimatedOutput!} ${asset.sym} (${trs[
              i
            ].estimatedOutputWei?.toString()}wei - exchange rate: ${trs[i].estimatedExchangeRate
          })\n`,
      )
      .join(""),
  );
  console.log(`LiquidateAddons:\n\t${addons.from.filter((f) => !!f).map((f, i) => `${findSymbolByAddress(addons.from[i])} -> ${findSymbolByAddress(addons.to[i])}: ${addons.amounts[i].toString()}`).join("\n\t")}`);
  return [amounts, swapData];
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
  const { strat } = env.deployment!;
  const [amounts, swapData] = await preLiquidate(env, _amount);
  await logState(env, "Before Liquidate");
  const receipt = await strat
    // .safe("liquidate", [amounts, 1, false, swapData], getOverrides(env))
    .liquidate(amounts, 1, false, swapData, getOverrides(env))
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
    // .safe("harvest", [harvestSwapData], getOverrides(env))
    .harvest(harvestSwapData, getOverrides(env))
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
    // .safe("compound", [investAmounts, harvestSwapData, investSwapData], getOverrides(env))
    .compound(investAmounts, harvestSwapData, investSwapData, getOverrides(env))
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
  await collectFees(<IStrategyDeploymentEnv>env);

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
 * Updates the underlying asset of a strategy (critical)
 * @param env - Strategy deployment environment
 * @param to - Address of the new underlying asset
 * @returns Updated balance of the new asset
 */
export async function updateAsset(
  env: Partial<IStrategyDeploymentEnv>,
  to: string,
): Promise<BigNumber> {
  let { strat, asset, PriceProvider } = env.deployment!;
  const newAsset = await SafeContract.build(to);
  const actualAsset = await strat.asset();

  if (actualAsset != asset.address) {
    const prevAsset = asset;
    asset = await SafeContract.build(actualAsset);
    console.warn(
      `Strategy asset was changed since deployment: ${prevAsset.sym} (${prevAsset.address}) -> ${asset.sym} (${asset.address})`,
    );
    env.deployment!.asset = asset;
  }

  const assetBalance = await asset.balanceOf(strat.address);
  if (to == asset.address) {
    console.warn(`Strategy underlying asset is already ${to}`);
    return assetBalance;
  }

  if (!(await PriceProvider.hasFeed(to))) {
    console.log(`Adding ${newAsset.sym} (${to}) price feed to PriceProvider`);
    await PriceProvider.setFeed(
      to,
      addressToBytes32(env.oracles![`Crypto.${newAsset.sym}/USD`]),
      3600 * 48, // 2 days
    ).then((tx: TransactionResponse) => tx.wait());
    if (!(await PriceProvider.hasFeed(to))) {
      throw new Error(`Price feed could not be set for ${newAsset.sym}`);
    }
  }

  const minSwapOut = 1; // TODO: use callstatic to define accurate minAmountOut
  let tr = {
    to: addressZero,
    data: "0x00",
  } as ITransactionRequestWithEstimate;

  // only generate swapData if the input is not the asset
  if (assetBalance.gt(10)) {
    console.log("Preparing invest() SwapData from inputs/inputWeights");
    // const weight = env.deployment!.initParams.inputWeights[i];
    // if (!weight) throw new Error(`No inputWeight found for input ${i} (${inputs[i].symbol})`);
    // inputAmount = amount.mul(weight).div(100_00).toString()
    tr = (await getTransactionRequest({
      input: asset.address,
      output: to,
      amountWei: assetBalance, // using a 100_00 bp basis (100_00 = 100%)
      inputChainId: network.config.chainId!,
      payer: env.deployment!.strat.address,
      testPayer: env.addresses!.accounts!.impersonate,
    })) as ITransactionRequestWithEstimate;
  }

  const swapData = ethers.utils.defaultAbiCoder.encode(
    // router, minAmountOut, data
    ["address", "uint256", "bytes"],
    [tr.to, minSwapOut, tr.data],
  );
  await logState(env, `Before UpdateAsset ${asset.sym}->${newAsset.sym}`);
  const receipt = await strat
    .safe("updateAsset(address,bytes)", [to, swapData], getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());

  await logState(env, `After UpdateAsset ${asset.sym}->${newAsset.sym}`, 1_000);

  if (!((await strat.asset()) == to)) {
    throw new Error(`Strategy asset not updated to ${to}`);
  }

  env.deployment!.asset = newAsset;
  env.deployment!.initParams.coreAddresses!.asset = to;

  // unpause the strategy that was paused preemptively during the update
  await strat.unpause();

  // no event is emitted for optimization purposes, manual check
  return await newAsset.balanceOf(strat.address);
}

/**
 * Updates the inputs and weights of a strategy (critical)
 * @param env - Strategy deployment environment
 * @param inputs - New inputs to be set
 * @param weights - Corresponding weights for the new inputs
 * @param lpTokens - Corresponding LP tokens for the new inputs
 * @param reorder - whether to reorder the inputs on existing (for testing purposes)
 * @returns BigNumber representing the result of the update
 */
export async function updateInputs(
  env: Partial<IStrategyDeploymentEnv>,
  inputs: string[],
  weights: number[],
  lpTokens: string[],
  reorder: boolean = true,
  prev?: [string[], number[], string[]],
): Promise<BigNumber> {
  // step 1: retrieve current inputs
  const strat = await env.deployment!.strat;
  const [currentInputs, currentWeights, currentLpTokens] =
    prev ?? (await getStratParams(env));

  // step 2: Initialize final inputs and weights arrays
  let orderedInputs: string[] = new Array<string>(inputs.length).fill("");
  let orderedWeights: number[] = new Array<number>(inputs.length).fill(0);
  let orderedLpTokens: string[] = new Array<string>(inputs.length).fill("");

  const leftovers: string[] = [];

  // if (reorder) {
  //   console.log("Reordering inputs...");
  //   // step 3: Keep existing inputs in their original position if still present
  //   for (let i = 0; i < inputs.length; i++) {
  //     const prevIndex = currentInputs.indexOf(inputs[i]);
  //     if (prevIndex >= inputs.length || prevIndex < 0) {
  //       leftovers.push(inputs[i]);
  //       continue;
  //     }
  //     if (inputs.length > prevIndex) {
  //       orderedInputs[prevIndex] = currentInputs[prevIndex];
  //       orderedWeights[prevIndex] = weights[i];
  //       orderedLpTokens[prevIndex] = lpTokens[i];
  //     }
  //   }
  // } else {
  //   orderedInputs = inputs;
  //   orderedWeights = weights;
  //   orderedLpTokens = lpTokens;
  // }

  // Correction in the reordering logic and handling of leftovers
  if (reorder) {
    console.log("Reordering inputs...");
    // Correctly identify and manage existing inputs and leftovers
    currentInputs.forEach((input, index) => {
      const newIndex = inputs.indexOf(input);
      if (newIndex !== -1) {
        // Input exists in the new inputs, so we place it correctly
        orderedInputs[newIndex] = input;
        orderedWeights[newIndex] = weights[newIndex]; // Assign corresponding weight
        orderedLpTokens[newIndex] = lpTokens[newIndex]; // Assign corresponding LP token
      }
    });

    // Handle leftovers: new inputs that weren't in currentInputs
    inputs.forEach((input, index) => {
      if (!orderedInputs.includes(input)) {
        // Find the first empty slot in ordered arrays
        const emptyIndex = orderedInputs.indexOf("");
        orderedInputs[emptyIndex] = input;
        orderedWeights[emptyIndex] = weights[index];
        orderedLpTokens[emptyIndex] = lpTokens[index];
      }
    });
  } else {
    // If not reordering, directly assign inputs, weights, and LP tokens
    orderedInputs = inputs;
    orderedWeights = weights;
    orderedLpTokens = lpTokens;
  }

  // NB: make sure that env.deployment.PriceProvider has all the new feeds already set up
  // step 4: Infill + backfill with leftovers
  for (let i = 0; i < leftovers.length; i++) {
    const fillIndex = orderedInputs.indexOf("");
    orderedInputs[fillIndex] = leftovers[i];
    orderedWeights[fillIndex] = weights[currentInputs.indexOf(leftovers[i])];
    orderedLpTokens[fillIndex] = lpTokens[currentInputs.indexOf(leftovers[i])];
  }

  console.log(`Reordering (reordered: ${reorder}):\n
    prev inputs: [${currentInputs.join(",")}] weights: [${currentWeights.join(
    ",",
  )}] lpTokens: [${currentLpTokens.join(",")}]
    raw inputs: [${inputs.join(",")}] weights: [${weights.join(
    ",",
  )}] lpTokens: [${lpTokens.join(", ")}]
    ord inputs: [${orderedInputs.join(",")}] weights: [${orderedWeights.join(
    ",",
  )}] lpTokens: [${orderedLpTokens.join(",")}]
  `);

  // step 5: Set new input weights with current inputs to liquidate it all
  // TODO: make sure that the oracle has all new feeds already set up
  let receipt = await strat
    .safe(
      "setInputs(address[],uint16[],address[])",
      [
        currentInputs,
        currentWeights.map((_, i) => {
          const index = orderedInputs.indexOf(currentInputs[i]);
          // reduce exposure to 0 for removed inputs (liquidate)
          // update weights for existing inputs (start rebalancing)
          return (index > -1 ? currentWeights[index] : 0) ?? 0;
        }),
        currentLpTokens,
      ],
      getOverrides(env),
    )
    .then((tx: TransactionResponse) => tx.wait());

  // step 6: Liquidate all weights that have been set to 0 step 5
  console.log(`Liquidating removed inputs...`);
  await liquidate(env, 0);

  // step 7: Set new inputs and input weight
  console.log(`Setting new inputs... `, orderedInputs);
  receipt = await strat
    .safe(
      "setInputs(address[],uint16[],address[])",
      [orderedInputs, orderedWeights, orderedLpTokens],
      getOverrides(env),
    )
    .then((tx: TransactionResponse) => tx.wait());

  // step 8: Update the test environment to reflect the new inputs
  env.deployment!.inputs = await Promise.all(orderedInputs.map((input) =>
    SafeContract.build(input),
  ));
  env.deployment!.initParams.inputs = orderedInputs;
  env.deployment!.initParams.inputWeights = orderedWeights;

  // step 9: Invest all assets (effective rebalancing with available cash from step 6 liquidation)
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
  newWeights?: number[] | BigNumber[],
  reorder = true,
): Promise<BigNumber> {
  // step 1: retrieve current inputs
  const strat = await env.deployment!.strat;
  const [inputs, weights, lpTokens] = await getStratParams(env);
  const symbols = inputs.map((i) =>
    findSymbolByAddress(i, network.config.chainId!),
  );
  console.log(
    `Before shuffling:\n  inputs [${symbols.join(
      ", ",
    )}]\n  weights [${weights.join(", ")}]\n  lpTokens [${lpTokens.join(
      ", ",
    )}]`,
  );

  if (!newWeights) newWeights = weights;

  // step 2: randomly reorder inputs and set random weights adding up to the same cumsum
  let [randomInputs, randomWeights] = [shuffle(inputs), shuffle(weights)];
  // shuffle again if the result is the same for one of the arrays
  while (arraysEqual(randomInputs, inputs)) {
    randomInputs = shuffle(inputs);
  }

  // if there are two inputs and the weights are the same, break
  if (!duplicatesOnly(randomWeights)) {
    while (arraysEqual(randomWeights, weights)) {
      randomWeights = shuffle(weights);
    }
  } else {
    randomWeights = randomRedistribute(randomWeights);
  }

  console.log(randomInputs, randomWeights);

  const newInputSymbols = randomInputs.map((i) =>
    findSymbolByAddress(i, network.config.chainId!),
  );
  const newLpTokens = newInputSymbols.map(
    (i) => compoundAddresses[network.config.chainId!].Compound[i!].comet,
  );
  console.log(
    `Shuffled:\n  inputs [${newInputSymbols.join(
      ", ",
    )}]\n  weights [${randomWeights.join(
      ", ",
    )}]\n  lpTokens [${newLpTokens.join(", ")}]`,
  );

  // step 3: return updateInputs with the above
  return await updateInputs(
    env,
    randomInputs,
    randomWeights,
    lpTokens,
    reorder,
    [inputs, weights, lpTokens],
  );
}

/**
 * Updates the input weights of a strategy
 * @param env - Strategy deployment environment
 * @param weights - New weights to be set
 * @returns Boolean indicating whether the input weights were successfully updated
 */
export async function setInputWeights(
  env: Partial<IStrategyDeploymentEnv>,
  weights: number[],
  resetInputs = false,
): Promise<boolean> {
  // step 1: retrieve current inputs
  const strat = await env.deployment!.strat;
  let tx;
  const [prevInputs, prevWeights, prevLpTokens] = await getStratParams(env);
  if (resetInputs) {
    tx = await strat
      .safe(
        "setInputs(address[],uint16[],address[])", // StrategyV5Agent overload
        [prevInputs, prevWeights, prevLpTokens],
        getOverrides(env)
      );
  } else {
    tx = await strat
      .safe("setInputWeights", [weights], getOverrides(env));
  }
  const receipt = await tx.wait();
  const updatedWeights = (await getStratParams(env))[1];
  console.log(`Updated weights: ${prevWeights}->${updatedWeights}`);
  return weights.every((weight, i) => weight == updatedWeights[i]);
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
  return await setInputWeights(env, randomWeights);
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
