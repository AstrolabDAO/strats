import {
  TransactionRequest,
  deploy,
  ethers,
  getDeployer,
  network,
  provider,
  weiToString,
} from "@astrolabs/hardhat";
import { BigNumber, Contract, constants } from "ethers";
import {
  ISwapperParams,
  getAllTransactionRequests,
  getTransactionRequest,
  swapperParamsToString,
} from "@astrolabs/swapper";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import addresses, { ChainAddresses } from "../../src/addresses";
import { erc20Abi, wethAbi } from "abitype/abis";
import { assert } from "console";
import { MaxUint256 } from "@ethersproject/constants";
import { IStrategyV5 } from "src/types";

export const addressZero = constants.AddressZero;
let maxTopup = BigNumber.from(weiToString(5 * 1e18));
let deployer: SignerWithAddress;
let swapper: Contract;

export async function deploySwapper(): Promise<Contract> {
  deployer ??= (await getDeployer()) as SignerWithAddress;
  const blockNumber = await provider.getBlockNumber();
  swapper = await deploy({ contract: "Swapper", verify: true });
  console.log(
    `Connected to ${network.name} (id ${network.config.chainId}), block ${blockNumber}`
  );
  return swapper;
}

export async function deployStrat(
  contract: string,
  name: string,
  args: IStrategyV5,
  allocator?: Contract
): Promise<Contract> {
  deployer ??= (await getDeployer()) as SignerWithAddress;
  const strat = await deploy({
    contract,
    name,
    args: Object.values(args), // vectorize [,,,,] [[,,,]]
    verify: true,
  });
  return strat;
}

export async function grantRoleStrat(strategy: Contract) {
  const keeperRole = await strategy.KEEPER_ROLE();
  const managerRole = await strategy.MANAGER_ROLE();

  await strategy.grantRole(keeperRole, deployer.address);
  await strategy.grantRole(managerRole, deployer.address);
}

export async function setupStrat(
  contract: string,
  name: string,
  args: IStrategyV5,
  underlying: Contract,
  inputs: string[],
  inputWeights: Number[],
  maxTotalAsset: BigNumber,
  allocator?: Contract,
): Promise<Contract> {
  console.log("In setup strat");
  const strategy = await deployStrat(contract, name, args, allocator);
  console.log("Strat deployed");
  await grantRoleStrat(strategy);
  if (allocator) {
    // Add new strategy to allocator
    await allocator.addNewStrategy(strategy.address, MaxUint256, name, {
      from: deployer.address,
    });
  }
  await strategy.setInputs(inputs, inputWeights);
  await underlying.approve(strategy.address, MaxUint256);
  await underlying.approve(strategy.address, MaxUint256);
  assert((await strategy.totalAssets()).gt(0));
  await logState(strategy, "Before initialize");
  await strategy.initialize(1e7, maxTotalAsset, { gasLimit: 50e6 });
  await logState(strategy, "After initialize");
  return strategy;
}

async function logState(strategy: Contract, step?: string) {
  try {
    const [
      underlyingAddress,
      inputsAddresses,
      rewardTokensAddresses,
      sharePriceAfter,
      totalAssetsAfter,
      invested
    ] = await Promise.all([
      strategy.underlying(),
      strategy.inputs(0),
      strategy.rewardTokens(0),
      strategy.sharePrice(),
      strategy.totalAssets(),
      strategy.invested(),
    ]);
    console.log(
      `State ${step ? `after ${step}` : ""}:
      underlying: ${underlyingAddress}
      inputs: ${inputsAddresses}
      rewardTokens: ${rewardTokensAddresses}
      sharePrice: ${sharePriceAfter}
      totalAssets(): ${totalAssetsAfter}
      invested(): ${invested}`);
  } catch(e) {
    console.log(`Error logging state: ${e}`);
  }
}

async function ensureWhitelisted(contract: Contract, addresses: string[]) {
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

async function _swap(o: ISwapperParams, a: ChainAddresses) {
  if (!swapper) swapper = await deploySwapper();
  if (o.inputChainId != network.config.chainId) {
    if (network.name.includes("tenderly")) {
      console.warn(`Skipping case as not on current network: ${network.name}`);
      return;
    } else {
      console.warn(`Case requires hardhat network change to ${network.name}`);
    }
  }

  o.payer ||= deployer!.address;
  const amountWei = BigNumber.from(o.amountWei as any);
  o.amountWei = amountWei;
  o.inputChainId ??= network.config.chainId!;

  let input: Contract;
  const nativeBalance = await provider.getBalance(o.payer);

  if (!o.input) {
    o.input = a.tokens.WGAS;
    input = new Contract(a.tokens.WGAS, wethAbi, deployer);

    const symbol = await input.symbol();
    if (["ETH", "BTC"].some((s) => symbol.includes(s))) {
      // limit the size of a swap to 10 ETH/BTC
      if (amountWei.gt(maxTopup)) o.amountWei = BigNumber.from(maxTopup);
    }
    assert(nativeBalance.gt(amountWei));
    const wrappedBalanceBefore = await input.balanceOf(o.payer);
    await input.deposit({ value: o.amountWei });
    const wrapped = (await input.balanceOf(o.payer)).sub(wrappedBalanceBefore);
    console.log(`wrapped ${wrapped} ${o.input}`);
    assert(wrapped.eq(o.amountWei));
  } else {
    input = await ethers.getContractAt("IERC20Metadata", o.input);
  }

  console.log(swapperParamsToString(o));

  let inputBalance = await input.balanceOf(o.payer);

  if (inputBalance.lt(o.amountWei)) {
    console.log(
      `payer ${o.payer} has not enough balance of ${o.inputChainId}:${o.input}, swapping from gasToken to ${o.input}`
    );
    await _swap(
      {
        payer: o.payer,
        inputChainId: o.inputChainId,
        output: o.input,
        amountWei: weiToString(nativeBalance.sub(BigInt(1e20).toString())),
      } as ISwapperParams,
      a
    );
    inputBalance = await input.balanceOf(o.payer);
  }

  const output = await ethers.getContractAt("IERC20Metadata", o.output);
  const outputBalanceBeforeSwap = await output.balanceOf(o.payer);
  await input.approve(swapper.target, MaxUint256.toString());
  const trs: TransactionRequest[]|undefined = (await getAllTransactionRequests(
    o
  )) as TransactionRequest[];
  assert(trs?.length);
  let received = BigNumber.from(0);
  for (const tr of trs) {
    assert(!!tr?.data);
    console.log(`using request: ${JSON.stringify(tr, null, 2)}`);
    await ensureWhitelisted(swapper, [
      tr.from as string,
      tr.to!,
      o.input,
      o.output,
    ]);
    const ok = await swapper.swap(
      input.target ?? input.address,
      output.target ?? output.address,
      o.amountWei.toString(),
      "1",
      tr.to,
      tr.data,
      { gasLimit: Math.max(Number(tr.gasLimit ?? 0), 50_000_000) }
    );
    console.log(`received response: ${JSON.stringify(ok, null, 2)}`);
    const received = (await output.balanceOf(o.payer)).sub(
      outputBalanceBeforeSwap
    );
    console.log(`received ${received} ${o.output}`);
    if (received.gt(0))
      break;
  }
  assert(received.gt(1));
}

export async function fundAccount(
  amount: number,
  asset: string,
  receiver: string,
  a: ChainAddresses
): Promise<void> {
  const deployer = (await getDeployer()) as SignerWithAddress;
  const output = new Contract(asset, erc20Abi, deployer);
  const balanceBefore = await output.balanceOf(receiver);
  let balanceAfter = balanceBefore;
  let retries = 3;
  while (balanceAfter <= balanceBefore && retries--) {
    await _swap(
      {
        inputChainId: network.config.chainId!,
        output: asset,
        amountWei: weiToString(amount),
        receiver,
        payer: deployer.address,
        testPayer: a.accounts!.impersonate,
      } as ISwapperParams,
      a
    );
    balanceAfter = await output.balanceOf(receiver);
  }
}
