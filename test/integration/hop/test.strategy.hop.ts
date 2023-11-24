import { assert } from "chai";
import { network, ethers } from "hardhat";
import { BigNumber, Contract, Signer } from "ethers";
import { erc20Abi } from "abitype/abis";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import swapperBuild from "@astrolabs/registry/abis/Swapper.json";

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
import addresses from "../../../src/implementations/Hop/addresses";
import { deploySwapper, setupStrat, addressZero, fundAccount, logState } from "../utils";
import { ChainAddresses } from "src/addresses";
import { IHopStrategyV5 } from "src/implementations/Hop/types";

const fee = 180;
const inputSymbols = ["USDC"]; // , "WETH", "DAI"];
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
// TODO: move to addresses.ts
const swapperAddress = "0xdfe11c1beb360820a6aa9ada899243de459b3894";
const libAddresses = {
  "src/libs/AsAccounting.sol:AsAccounting": "0x503301eb7cfc64162b5ce95cc67b84fbf6df5255",
};
const agentAddress = "0x8e8da0a2f93997c90373d4f61843355244cb378e";

const MaxUint256 = ethers.constants.MaxUint256;
let networkSlug;
let networkId;
let deployer: SignerWithAddress;
let provider = ethers.provider;
let swapper: Contract;
let strat: Contract;
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

describe("test.strategy.hopProtocol", function () {
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
      ? new Contract(swapperAddress, swapperBuild.abi, deployer)
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
    describe(`Test ${++i}: Hop ${inputSymbol}`, function () {
      this.beforeAll("Deploy and setup strat", async function () {
        // instantiate contracts used in the test
        input = new Contract(a.tokens[inputSymbol], erc20Abi, deployer);
        inputDecimals = await input.decimals();
        inputWeiPerUnit = 10 ** inputDecimals;

        const name = `Astrolab Hop h${inputSymbol}`;
        // Deploy strategy, grant roles to deployer and set maxTotalAsset
        strat = await setupStrat(
          "HopStrategy",
          name,
          {
            fees,
            underlying: underlying.address,
            coreAddresses: [deployer.address, swapper.address, addressZero],
            erc20Metadata: [name, `as.h${inputSymbol}`, "1"],
            inputs: [input.address],
            inputWeights: [100_000],
            rewardTokens: [a.tokens.HOP],
            lpToken: a.hop[inputSymbol].lp,
            rewardPool: a.hop[inputSymbol].rewardPools[0],
            stableRouter: a.hop[inputSymbol].swap,
            tokenIndex: 0,
          } as IHopStrategyV5,
          undefined,
          agentAddress,
          libAddresses
        );
        assert(strat.address && strat.address !== addressZero);
        console.log("End of 2nd BeforeAll");
      });
      it("Seed Liquidity", async function () {
        await logState(strat, "Before SeedLiquidity");
        await underlying.approve(strat.address, MaxUint256);
        await strat.seedLiquidity(MaxUint256);
        assert((await strat.balanceOf(deployer.address)).gt(0));
        console.log(
          await strat.balanceOf(deployer.address),
          "Balance of shares after seedLiquidity"
        );
        await logState(strat, "After SeedLiquidity");
      });
      it("Deposit", async function () {
        await underlying.approve(strat.address, MaxUint256);
        await strat.safeDeposit(
          inputWeiPerUnit * 100,
          deployer.address,
          inputWeiPerUnit * 90,
          {
            gasLimit: 5e7,
          }
        ); // 100$
        assert((await strat.balanceOf(deployer.address)).gt(0));
        console.log(
          await strat.balanceOf(deployer.address),
          "Balance of shares after deposit"
        );
        await logState(strat, "After Deposit");
      });
      it("Swap+Deposit", async function () {
        await underlying.approve(strat.address, MaxUint256);
        await input.approve(strat.address, MaxUint256);

        let swapData: any = [];
        if (underlying.address != input.address) {
          const tr = (await getTransactionRequest({
            input: input.address,
            output: underlying.address,
            amountWei: BigInt(inputWeiPerUnit * 100).toString(),
            inputChainId: networkId!,
            payer: strat.address,
            testPayer: a.accounts!.impersonate,
          })) as ITransactionRequestWithEstimate;
          swapData = ethers.utils.defaultAbiCoder.encode(
            ["address", "uint256", "bytes"],
            [tr.to, 1, tr.data]
          );
        }

        await strat.swapSafeDeposit(
          input.address,
          inputWeiPerUnit * 100,
          deployer.address,
          inputWeiPerUnit * 90,
          swapData,
          { gasLimit: 5e7 }
        ); // 100$
        assert((await strat.balanceOf(deployer.address)).gt(0));
        console.log(
          await strat.balanceOf(deployer.address),
          "Balance of shares after swapSafeDeposit"
        );
        await logState(strat, "After SwapDeposit");
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
            payer: strat.address,
            testPayer: a.accounts!.impersonate,
          })) as ITransactionRequestWithEstimate;
          swapData = ethers.utils.defaultAbiCoder.encode(
            ["address", "uint256", "bytes"],
            [tr.to, 1, tr.data]
          );
        }
        await strat.invest(inputWeiPerUnit * 100, 1, [swapData], {
          gasLimit: 5e7,
        });
        assert((await strat.balanceOf(deployer.address)).gt(0));
        await logState(strat, "After Invest");
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