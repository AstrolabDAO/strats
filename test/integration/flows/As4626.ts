import * as ethers from "ethers";
import { BigNumber, Contract } from "ethers";
import {
  TransactionResponse,
  network,
  weiToString,
  MaxUint256,
  getTxLogData,
  ERC20_ABI,
} from "@astrolabs/hardhat";
import { ITransactionRequestWithEstimate, getTransactionRequest } from "@astrolabs/swapper";
import { IStrategyDeploymentEnv } from "../../../src/types";
import { getOverrides, getSwapperRateEstimate, logState } from "../../utils";

/**
 * Sets the minimum liquidity for a strategy deployment
 * @param env - Strategy deployment environment
 * @param usdAmount - Amount in USD to set as the minimum liquidity (default: 10)
 * @returns Seed amount in BigNumber
 */
export async function setMinLiquidity(
  env: Partial<IStrategyDeploymentEnv>,
  usdAmount = 10,
): Promise<BigNumber> {
  const { strat, asset } = env.deployment!;
  const [from, to] = ["USDC", env.deployment!.asset.sym];
  const exchangeRate = await getSwapperRateEstimate(from, to, 1e12, 1, <any>env);
  const seedAmount = asset.toWei(usdAmount * exchangeRate);
  const minLiquidity = await strat.minLiquidity();
  if (minLiquidity.gte(seedAmount)) {
    console.log(`Skipping setMinLiquidity as minLiquidity >= ${seedAmount}`);
  } else {
    console.log(
      `Setting minLiquidity to ${seedAmount} ${to} wei (${usdAmount} USDC)`,
    );
    // await strat.safe("setMinLiquidity", [seedAmount], getOverrides(env))
    await strat.setMinLiquidity(seedAmount, getOverrides(env))
      .then((tx: TransactionResponse) => tx.wait());
    console.log(
      `Liquidity can now be seeded with ${minLiquidity}wei ${to}`,
    );
  }
  return seedAmount;
}

/**
 * Seeds a strategy liquidity and activates deposits
 * @param env - Strategy deployment environment
 * @param _amount - Amount of liquidity to seed (default: 10)
 * @returns Amount of liquidity seeded
 */
export async function seedLiquidity(
  env: IStrategyDeploymentEnv,
  _amount = 10,
): Promise<BigNumber> {
  const { strat, asset } = env.deployment!;
  let amount = asset.toWei(_amount);
  const [totalAssets, minLiquidity, allowance] = await env.multicallProvider!.all([
    strat.multi.totalAssets(),
    strat.multi.minLiquidity(),
    asset.multi.allowance(env.deployer.address, strat.address),
  ]) as BigNumber[];
  if (totalAssets.gte(minLiquidity)) {
    console.log(`Skipping seedLiquidity as totalAssets > minLiquidity`);
    return BigNumber.from(1);
  }
  if (await allowance.lt(amount))
    await asset
      .approve(strat.address, MaxUint256, getOverrides(env))
      .then((tx: TransactionResponse) => tx.wait());

  await logState(env, "Before SeedLiquidity");
  // only exec if static call is successful
  const receipt = await strat
    // .safe("seedLiquidity", [amount, MaxUint256], getOverrides(env))
    .seedLiquidity(amount, MaxUint256, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After SeedLiquidity", 1_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0); // NB: on some chains, a last (aggregate) event is emitted
}

/**
 * Deposits a specified amount of assets into a strategy
 * @param env - Strategy deployment environment
 * @param _amount - Amount to deposit (default: 10)
 * @returns Amount deposited as a BigNumber
 */
export async function deposit(
  env: IStrategyDeploymentEnv,
  _amount = 10,
): Promise<BigNumber> {
  const { strat, asset } = env.deployment!;
  const [balance, allowance] = await env.multicallProvider!.all([
    asset.multi.balanceOf(env.deployer.address),
    asset.multi.allowance(env.deployer.address, strat.address),
  ]) as BigNumber[];
  let amount = asset.toWei(_amount);

  if (balance.lt(amount)) {
    console.warn(`Using full balance ${balance} (< ${amount})`);
    amount = balance;
  }
  if (allowance.lt(amount))
    await asset
      .approve(strat.address, MaxUint256, getOverrides(env))
      .then((tx: TransactionResponse) => tx.wait());
  await logState(env, `Before Deposit ${_amount}`);
  // only exec if static call is successful
  const receipt = await strat
    .safe("safeDeposit", [amount, 1, env.deployer.address], { gasLimit: 1e7 })
    // .safeDeposit(amount, 1, env.deployer.address, { gasLimit: 1e7 })
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, `After Deposit ${_amount}`, 1_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0);
}

/**
 * Swaps from asset to inputAddress and safe deposit for a given strategy deployment environment
 * @param env - Strategy deployment environment
 * @param inputAddress - Input address for the deposit asset
 * @param _amount - Amount to deposit (default is 10)
 * @returns Amount of shares received
 */
export async function swapSafeDeposit(
  env: IStrategyDeploymentEnv,
  inputAddress?: string,
  _amount = 10,
): Promise<BigNumber> {
  const { strat, asset } = env.deployment!;
  const depositAsset = new Contract(inputAddress!, ERC20_ABI, env.deployer);
  const [minSwapOut, minSharesOut] = [1, 1];
  let amount = depositAsset.toWei(_amount);

  if (
    (await depositAsset.allowance(env.deployer.address, strat.address)).lt(
      amount,
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
      [tr.to, minSwapOut, tr.data],
    );
  }
  await logState(env, "Before SwapSafeDeposit");
  const receipt = await strat.safe(
    "swapSafeDeposit",
    [
      depositAsset.address, // input
      amount, // amount == 100$
      env.deployer.address, // receiver
      minSharesOut, // minShareAmount in wei
      swapData,
    ], // swapData
    getOverrides(env),
  )
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After SwapSafeDeposit", 1_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0);
}

/**
 * Withdraws a specified amount from the strategy deployment environment
 * @param env - Strategy deployment environment
 * @param _amount - Amount to withdraw (default: 50)
 * @returns Amount withdrawn as a BigNumber
 */
export async function withdraw(
  env: Partial<IStrategyDeploymentEnv>,
  _amount = 50,
): Promise<BigNumber> {
  const { asset, inputs, strat } = env.deployment!;
  const minAmountOut = 1; // TODO: use callstatic to define accurate minAmountOut
  const [max, balance] = await env.multicallProvider!.all([
    strat.multi.maxWithdraw(env.deployer!.address),
    strat.multi.balanceOf(env.deployer!.address),
  ]) as BigNumber[];
  let amount = asset.toWei(_amount);

  if (max.lt(10)) {
    console.warn(
      `Skipping withdraw as maxWithdraw < 10wei (no exit possible at this time)`,
    );
    return BigNumber.from(1);
  }

  if (amount.gt(max)) {
    console.warn(`Using maxWithdraw ${max} (< ${amount}), balance: ${balance}`);
    amount = max;
  }

  await logState(env, "Before Withdraw");
  const receipt = await strat
    .safe("safeWithdraw", [
      amount,
      minAmountOut,
      env.deployer!.address,
      env.deployer!.address
    ], { gasLimit: 2e7 })
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Withdraw", 1_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0); // recovered
}

/**
 * Requests a withdrawal of a specified amount from the strategy contract
 * @param env - Strategy deployment environment
 * @param _amount - Amount to withdraw (default: 50)
 * @returns Amount withdrawn as a BigNumber
 */
export async function requestWithdraw(
  env: IStrategyDeploymentEnv,
  _amount = 50,
): Promise<BigNumber> {
  const { asset, inputs, strat } = env.deployment!;
  let amount = strat.toWei(_amount); // in shares
  const [balance, pendingRequest, assetAmount] = await env.multicallProvider!.all([
    strat.multi.balanceOf(env.deployer.address),
    strat.multi.pendingWithdrawRequest(env.deployer.address, env.deployer.address),
    strat.multi.convertToAssets(amount),
  ]) as BigNumber[];

  if (balance.lt(10)) {
    console.warn(
      `Skipping requestWithdraw as balance < 10wei (user owns no shares)`,
    );
    return BigNumber.from(1);
  }

  if (amount.gt(balance)) { // shares vs shares
    console.warn(`Using full balance ${balance} (< ${amount})`);
    amount = balance;
  }

  if (pendingRequest.gte(assetAmount)) {
    console.warn(`Skipping requestWithdraw as pendingRedeemRequest > amount already`);
    return BigNumber.from(1);
  }
  await logState(env, "Before RequestWithdraw");
  const receipt = await strat
    .safe("requestWithdraw", [
      assetAmount,
      env.deployer.address,
      env.deployer.address,
      "0x"
    ], { gasLimit: 2e7 })
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After RequestWithdraw", 1_000);
  return (
    getTxLogData(receipt, ["address, address, address, uint256"], 3) ??
    BigNumber.from(0)
  ); // recovered
}

/**
 * Redeems a specified amount of tokens using the given strategy deployment environment
 * @param env - Strategy deployment environment
 * @param _amount - Amount of tokens to redeem (default: 50)
 * @returns Amount of tokens redeemed
 */
export async function redeem(
  env: Partial<IStrategyDeploymentEnv>,
  _amount = 50,
): Promise<BigNumber> {
  const { inputs, strat } = env.deployment!;
  const minAmountOut = 1; // TODO: use callstatic to define accurate minAmountOut
  const max = await strat.maxRedeem(env.deployer!.address);
  let amount = strat.toWei(_amount);

  if (max.lt(10)) {
    console.warn(
      `Skipping redeem as maxRedeem < 10wei (no exit possible at this time)`,
    );
    return BigNumber.from(1);
  }

  if (amount.gt(max)) {
    console.warn(`Using maxRedeem ${max} (< ${amount})`);
    amount = max;
  }

  await logState(env, "Before Redeem");
  // only exec if static call is successful
  const receipt = await strat
    .safe("safeRedeem", [
      amount,
      minAmountOut,
      env.deployer!.address,
      env.deployer!.address
    ], { gasLimit: 2e7 })
    // .safeRedeem(amount, minAmountOut, env.deployer.address, env.deployer.address, getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After Redeem", 1_000);
  return getTxLogData(receipt, ["uint256", "uint256"], 0); // recovered
}

/**
 * Requests redemption of a specified amount of assets from the strategy
 * @param env - Strategy deployment environment
 * @param _amount - Amount of assets to redeem (default: 50)
 * @returns Amount of redeemed assets as a BigNumber
 */
export async function requestRedeem(
  env: IStrategyDeploymentEnv,
  _amount = 50,
): Promise<BigNumber> {
  const { strat } = env.deployment!;
  let amount = strat.toWei(_amount);
  const [balance, pendingRequest] = await env.multicallProvider!.all([
    strat.multi.balanceOf(env.deployer.address),
    strat.multi.pendingWithdrawRequest(env.deployer.address, env.deployer.address),
  ]) as BigNumber[];

  if (balance.lt(10)) {
    console.warn(
      `Skipping requestRedeem as balance < 10wei (user owns no shares)`,
    );
    return BigNumber.from(1);
  }

  if (amount.gt(balance)) {
    console.warn(`Using full balance ${balance} (< ${amount})`);
    amount = balance;
  }

  const assetAmount = await strat["convertToAssets(uint256)"](amount);

  if (pendingRequest.gte(assetAmount)) {
    console.warn(`Skipping requestRedeem as pendingRedeemRequest > amount already`);
    return BigNumber.from(1);
  }
  await logState(env, "Before RequestRedeem");
  const receipt = await strat
    .safe("requestRedeem", [
      amount,
      env.deployer.address,
      env.deployer.address,
      "0x",
    ], { gasLimit: 2e7 })
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After RequestRedeem", 1_000);
  return (
    getTxLogData(receipt, ["address, address, address, uint256"], 3) ??
    BigNumber.from(0)
  ); // recovered
}

/**
 * Requests liquidations from the Composite to the primitives
 * @param env - Strategy deployment environment
 * @param _amounts - Amounts to withdraw (default: 50)
 */
export async function requestLiquidate(
  env: IStrategyDeploymentEnv,
  _amounts = [50],
  caller = env.deployer.address,
): Promise<BigNumber> {
  const { asset, inputs, strat } = env.deployment!;
  const balance = await strat.balanceOf(env.deployer.address);

  if (balance.lt(10)) {
    console.log(
      `Skipping requestLiquidate as balance < 10wei (user owns no shares)`,
    );
    return BigNumber.from(1);
  }

  const amounts: BigNumber[] = _amounts.map((amount) => asset.toWei(amount));

  const totalAmount = amounts.reduce((acc, amount) => acc.add(amount), BigNumber.from(0));

  if (totalAmount.gt(balance)) {
    console.warn(`Trying to requestLiquidate more than balance ${balance}wei`);
    return BigNumber.from(0);
  }

  await logState(env, "Before RequestLiquidate");
  const result = await strat
    .safe("requestLiquidate", [
      amounts,
      caller, // operator
      caller // owner
    ], { gasLimit: 2e7 })
    .then((tx: TransactionResponse) => tx.wait());
  await logState(env, "After RequestLiquidate", 2_000);
  return BigNumber.from(1);
}

/**
 * Collects fees for a strategy
 * @param env - Strategy deployment environment
 * @returns Total fees collected as a BigNumber
 */
export async function collectFees(
  env: IStrategyDeploymentEnv,
): Promise<BigNumber> {
  const { strat, asset, initParams } = env.deployment!;
  const feeCollector = await strat.feeCollector(); // initParams[0].coreAddresses.feeCollector;
  const balancesBefore: BigNumber[] = await env.multicallProvider!.all([
    asset.multi.balanceOf(feeCollector),
    strat.multi.balanceOf(feeCollector),
  ]);
  await logState(env, "Before CollectFees");
  console.log(
    `FeeCollector balances before: ${asset.toAmount(balancesBefore[0])} ${asset.sym
    }, ${strat.toAmount(balancesBefore[1])} ${strat.sym}`,
  );
  const receipt = await strat
    // .collectFees(getOverrides(env))
    .safe("collectFees", [], getOverrides(env))
    .then((tx: TransactionResponse) => tx.wait());
  const balancesAfter: BigNumber[] = await env.multicallProvider!.all([
    asset.multi.balanceOf(feeCollector),
    strat.multi.balanceOf(feeCollector),
  ]);
  await logState(env, "After CollectFees", 1_000);
  console.log(
    `FeeCollector balances after: ${asset.toAmount(balancesAfter[0])} ${asset.sym
    }, ${strat.toAmount(balancesAfter[1])} ${strat.sym}`,
  );
  return getTxLogData(
    receipt,
    ["uint256", "uint256", "uint256", "uint256", "uint256"], // event FeeCollection
    3,
    -2,
  );
}
