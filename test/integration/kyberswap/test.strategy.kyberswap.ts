import { assert } from "chai";
import { network, ethers } from "hardhat";
import { BigNumber, Contract, Signer } from "ethers";
import { erc20Abi } from "abitype/abis";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import swapperAbi from "@astrolabs/registry/abis/Swapper.json";
import {
  ITransactionRequestWithEstimate,
  getTransactionRequest,
} from "@astrolabs/swapper";
import {
  changeNetwork,
  revertNetwork,
  getDeployer,
  deploy,
  deployAll,
} from "@astrolabs/hardhat";
import addresses from "../../../src/implementations/Kyberswap/addresses";
import { deploySwapper, setupStrat, addressZero, fundAccount, logState } from "../utils";
import { ChainAddresses } from "src/addresses";
import { IKyberswapStrategyV5 } from "src/implementations/Kyberswap/types";

const fee = 180;
const inputSymbols = ["USDT", "DAI", "USDC"];
const gasUsedForFunding = 1e21; // 1k gas tokens
const fees = {
  perf: 2000,
  mgmt: 0,
  entry: 2,
  exit: 2,
};
// NOTE: For testing purposes only, set as false when accounts are well funded to avoid swap
const needsFunding = false;
const revertState = false;
const swapperAddress = "";

const MaxUint256 = ethers.constants.MaxUint256;
let networkSlug;
let networkId;
let deployer: SignerWithAddress;
let provider = ethers.provider;
let strategy: Contract;
let swapper: Contract;
let input: Contract;
let inputDecimals: number;
let inputWeiPerUnit: number;
let wgasSymbol: string;
let wgas: Contract;
let underlying: Contract;
let underlyingSymbol: string;
let underlyingDecimals: number;
let underlyingWeiPerUnit: number;
let decimals: number;
let assetBalance: BigNumber;
let a: any;
let snapshotId: string;

describe("test.strategy.kyberswapProtocol", function () {
  this.beforeAll(async function () {
    // load environment
    deployer = (await getDeployer()) as SignerWithAddress;
    provider = ethers.provider;
    networkId = network.config.chainId!;
    networkSlug = network.name;
    a = addresses[networkId];
    snapshotId = await provider.send("evm_snapshot", []);
    wgas = new Contract(a.tokens.WGAS, erc20Abi, deployer);
    wgasSymbol = await wgas.symbol();

    // deploy pre-requisites
    swapper = swapperAddress
      ? new Contract(swapperAddress, swapperAbi.abi, deployer)
      : await deploySwapper();

    underlying = new Contract(a.tokens.USDC, erc20Abi, deployer);
    underlyingDecimals = await underlying.decimals();
    underlyingWeiPerUnit = 10 ** underlyingDecimals;
    underlyingSymbol = await underlying.symbol();

    if (needsFunding) {
      console.log("Funding account");
      for (const inputSymbol of inputSymbols) {
        console.log("Funding account with", inputSymbol);
        let gas = gasUsedForFunding;
        if (["BTC", "ETH"].some((s) => s.includes(wgasSymbol.toUpperCase())))
          gas /= 1000; // less gas tokens or swaps will fail
        await fundAccount(gas, a.tokens[inputSymbol], deployer.address, a);
      }
    }
    console.log("End of 1st BeforeAll");
  });

  this.afterAll(async function () {
    // This reverts the state of the blockchain to the state it was in before the tests were run
    if (revertState) await revertNetwork(snapshotId);
  });

  beforeEach(async function () {});

  let i = 0;
  for (const inputSymbol of inputSymbols) {
    describe(`Test ${++i}: Kyberswap ${inputSymbol}`, function () {
      this.beforeAll("Deploy and setup strat", async function () {
        // instantiate contracts used in the test
        input = new Contract(a.tokens[inputSymbol], erc20Abi, deployer);
        inputDecimals = await input.decimals();
        inputWeiPerUnit = 10 ** inputDecimals;

        const name = `Astrolab Kyberswap ${inputSymbol}`;
        // Deploy strategy, grant roles to deployer and set maxTotalAsset
        strategy = await setupStrat(
          "KyberswapStrategy",
          name,
          {
            fees,
            underlying: underlying.address,
            coreAddresses: [deployer.address, swapper.address, addressZero],
            erc20Metadata: [name, `as.sp${inputSymbol}`, "1"],
            router: a.kyberswap[inputSymbol].router,
            elasticLM: a.kyberswap[inputSymbol].elasticLM,
            tickfeesreader: a.kyberswap[inputSymbol].tickfeesreader,
            antisnip: a.kyberswap[inputSymbol].antisnip,
            pool: a.kyberswap[inputSymbol].pool,
          } as IKyberswapStrategyV5,
          underlying,
          [underlying.address],
          [100],
          MaxUint256
        );
        assert(strategy.address && strategy.address !== addressZero);
        console.log("End of 2nd BeforeAll");
      });
      it("Deposit", async function () {
        await underlying.approve(strategy.address, MaxUint256);
        await strategy.safeDeposit(
          inputWeiPerUnit * 100,
          deployer.address,
          inputWeiPerUnit * 90,
          {
            gasLimit: 5e7,
          }
        ); // 100$
        assert((await strategy.balanceOf(deployer.address)).gt(0));
        console.log(
          await strategy.balanceOf(deployer.address),
          "Balance of shares after deposit"
        );
        await logState(strategy, "After Deposit");
      });
      it("Swap+Deposit", async function () {
        await underlying.approve(strategy.address, MaxUint256);
        await input.approve(strategy.address, MaxUint256);

        let swapData: any = [];
        if (underlying.address != input.address) {
          const tr = (await getTransactionRequest({
            input: input.address,
            output: underlying.address,
            amountWei: BigInt(inputWeiPerUnit * 100).toString(),
            inputChainId: networkId!,
            payer: strategy.address,
            testPayer: a.accounts!.impersonate,
          })) as ITransactionRequestWithEstimate;
          swapData = ethers.utils.defaultAbiCoder.encode(
            ["address", "uint256", "bytes"],
            [tr.to, 1, tr.data]
          );
        }

        await strategy.swapSafeDeposit(
          input.address,
          inputWeiPerUnit * 100,
          deployer.address,
          inputWeiPerUnit * 90,
          swapData,
          { gasLimit: 5e7 }
        ); // 100$
        assert((await strategy.balanceOf(deployer.address)).gt(0));
        console.log(
          await strategy.balanceOf(deployer.address),
          "Balance of shares after swapSafeDeposit"
        );
        await logState(strategy, "After SwapDeposit");
      });
      it("Invest", async function () {
        let swapData: any = [];
        if (underlying.address != input.address) {
          console.log("We make a calldata");
          const tr = (await getTransactionRequest({
            input: underlying.address,
            output: input.address,
            amountWei: BigInt(inputWeiPerUnit * 100).toString(),
            inputChainId: networkId!,
            payer: strategy.address,
            testPayer: a.accounts!.impersonate,
          })) as ITransactionRequestWithEstimate;
          swapData = ethers.utils.defaultAbiCoder.encode(
            ["address", "uint256", "bytes"],
            [tr.to, 1, tr.data]
          );
        }
        await strategy.invest(inputWeiPerUnit * 100, 1, [swapData], {
          gasLimit: 5e7,
        });
        assert((await strategy.balanceOf(deployer.address)).gt(0));
        await logState(strategy, "After Invest");
      });
      // it("Withdraw", async function () {
      //   let balanceBefore = await underlying.balanceOf(deployer.address);
      //   await strategy.safeWithdraw(
      //     inputWeiPerUnit * 50,
      //     1, // TODO: change with staticCall
      //     deployer.address,
      //     deployer.address
      //   );
      //   assert((await underlying.balanceOf(deployer.address)) > balanceBefore);
      // });
      // it("Liquidate", async function () {
      //   let balanceBefore = await underlying.balanceOf(deployer.address);
      //   let swapData: any = [];
      //   const tr = (await getTransactionRequest({
      //     input: input.address,
      //     output: underlying.address,
      //     amountWei: BigInt(inputWeiPerUnit * 50).toString(),
      //     inputChainId: networkId!,
      //     payer: deployer.address,
      //     testPayer: a.accounts!.impersonate,
      //   })) as ITransactionRequestWithEstimate;
      //   swapData = ethers.utils.defaultAbiCoder.encode(
      //     ["address", "uint256", "bytes"],
      //     [tr.to, 1, tr.data]
      //   );

      //   await strategy.liquidate(inputWeiPerUnit * 50, 1, false,  [swapData]);
      //   assert((await underlying.balanceOf(deployer.address)) > balanceBefore);
      // });
    });
  }
});