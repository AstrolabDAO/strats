// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {Fees} from "../../src/abstract/AsTypes.sol";
import {AsArrays} from "../../src/libs/AsArrays.sol";
import {AsMaths} from "../../src/libs/AsMaths.sol";
import {IStrategyV5} from "../../src/interfaces/IStrategyV5.sol";
import {ERC20} from "../../src/abstract/ERC20.sol";
import {TestEnvArb} from "./TestEnvArb.sol";
import {Borrower} from "./Erc3156FlashLenderTest.sol";

contract FeesTest is TestEnvArb {
  using AsMaths for uint256;
  using AsArrays for uint256[8];

  constructor() TestEnvArb(true, true) {}

  function entryFees(Fees memory _fees, uint256 _minLiquidity) public {
    console.log("--- entry fees test ---");
    uint256 toDeposit = 1000e6;

    // deposit
    deployStrat(_fees, _minLiquidity);
    vm.prank(bob);
    usdc.approve(address(strat), type(uint256).max);
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    strat.deposit(toDeposit, bob); // same as safeDeposit
    uint256 deposited = balanceBefore - usdc.balanceOf(bob);
    uint256 depositClaimableFee = strat.claimableTransactionFees();
    uint256 assetsBefore = strat.totalAssets();
    vm.prank(manager);
    uint256 depositCollectedFeeShares = strat.collectFees();
    uint256 depositCollectedFee = strat.convertToAssets(depositCollectedFeeShares);
    require(
      depositCollectedFee == depositClaimableFee,
      "Deposit entry fees collected does not match claimable"
    );
    require(
      depositCollectedFee + strat.assetsOf(bob) == deposited,
      "Deposit entry fee accounting error"
    );
    require(
      depositCollectedFee == strat.assetsOf(manager),
      "Collected fees vs feeCollector assets mismatch"
    );
    checkSumOfAssets(assetsBefore + depositCollectedFee);

    // mint
    deployStrat(_fees, _minLiquidity);
    vm.prank(bob);
    usdc.approve(address(strat), type(uint256).max);
    uint256 toMint = strat.convertToShares(toDeposit, true);
    balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    strat.mint(toMint, bob); // same as safeMint
    deposited = balanceBefore - usdc.balanceOf(bob);
    uint256 mintClaimableFee = strat.claimableTransactionFees();
    assetsBefore = strat.totalAssets();
    vm.prank(manager);
    uint256 mintCollectedFeeShares = strat.collectFees();
    uint256 mintCollectedFee = strat.convertToAssets(mintCollectedFeeShares);
    require(
      mintCollectedFee == mintClaimableFee,
      "Mint entry fee collected does not match claimable"
    );
    require(
      mintCollectedFee + strat.assetsOf(bob) == deposited,
      "Mint entry fee accounting error"
    );
    require(
      mintCollectedFee == strat.assetsOf(manager),
      "Collected fees vs feeCollector assets mismatch"
    );
    require(depositCollectedFee == mintCollectedFee, "Deposit and mint fees do not match");
    checkSumOfAssets(assetsBefore + depositCollectedFee);
  }

  function exitFees(Fees memory _fees, uint256 _minLiquidity) public returns (uint256) {
    console.log("--- exit fees test ---");
    uint256 toDeposit = 2000e6;
    uint256 toWithdraw = 1000e6;

    // withdraw
    deployStrat(_fees, _minLiquidity);
    vm.prank(bob);
    usdc.approve(address(strat), type(uint256).max);
    vm.prank(bob);
    strat.deposit(toDeposit, bob); // same as safeDeposit
    vm.prank(manager);
    strat.collectFees(); // clear any existing fees
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    strat.withdraw(toWithdraw, bob, bob); // same as safeWithdraw
    uint256 withdrawn = usdc.balanceOf(bob) - balanceBefore;
    uint256 withdrawClaimableFee = strat.claimableTransactionFees();

    uint256 assetsBefore = strat.totalAssets();
    vm.prank(manager);
    uint256 withdrawCollectedFeeShares = strat.collectFees();
    uint256 withdrawCollectedFee = strat.convertToAssets(withdrawCollectedFeeShares);
    require(
      withdrawCollectedFee == withdrawClaimableFee,
      "Withdrawal exit collected does not match claimable"
    );
    require(
      strat.assetsOf(bob) == toDeposit - withdrawn - withdrawCollectedFee,
      "Withdraw exit fee accounting error"
    );
    require(
      withdrawCollectedFee == strat.assetsOf(manager),
      "Collected fees vs feeCollector assets mismatch"
    );
    checkSumOfAssets(assetsBefore + withdrawCollectedFee); // tx fees are non inflationary, total assets increase along with the minted shares

    // redeem
    deployStrat(_fees, _minLiquidity);
    vm.prank(bob);
    usdc.approve(address(strat), type(uint256).max);
    vm.prank(bob);
    strat.deposit(toDeposit, bob); // same as safeDeposit
    vm.prank(manager);
    strat.collectFees(); // clear any existing fees
    balanceBefore = usdc.balanceOf(bob);
    uint256 toRedeem = strat.convertToShares(toWithdraw);
    vm.prank(bob);
    strat.redeem(toRedeem, bob, bob); // same as safeRedeem
    withdrawn = usdc.balanceOf(bob) - balanceBefore;
    uint256 redeemClaimableFee = strat.claimableTransactionFees();

    assetsBefore = strat.totalAssets();
    vm.prank(manager);
    uint256 redeemCollectedFeeShares = strat.collectFees();
    uint256 redeemCollectedFee = strat.convertToAssets(redeemCollectedFeeShares);
    require(
      redeemCollectedFee == redeemClaimableFee,
      "Redeem exit collected does not match claimable"
    );
    require(
      strat.assetsOf(bob) == toDeposit - withdrawn - withdrawCollectedFee,
      "Redeem exit fee accounting error"
    );
    require(
      redeemCollectedFee == strat.assetsOf(manager),
      "Collected fees vs feeCollector assets mismatch"
    );
    require(
      withdrawCollectedFee == redeemCollectedFee, "Withdraw and redeem fees do not match"
    );
    checkSumOfAssets(assetsBefore + redeemCollectedFee); // tx fees are non inflationary, total assets increase along with the minted shares
  }

  // Test management fee after fast-forwarding time
  function managementFees(Fees memory _fees, uint256 _minLiquidity) public {
    console.log("--- management fees test ---");
    uint256 toDeposit = 1000e6;

    deployStrat(_fees, _minLiquidity);
    vm.startPrank(bob);
    // deposit
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(toDeposit, bob);
    vm.stopPrank();

    uint256 assetsBefore = strat.totalAssets();
    vm.prank(manager);
    strat.collectFees(); // clear any existing fees
    // fast-forward time 1 year without changing the share price (no performance fees)
    uint256 lastFeeCollectionTime = strat.last().feeCollection;
    vm.warp(lastFeeCollectionTime + AsMaths.SEC_PER_YEAR);
    uint256 duration = block.timestamp - lastFeeCollectionTime;
    uint256 theoreticalMgmtFeeShares = strat.totalSupply().mulDiv(
      strat.fees().mgmt * duration, AsMaths.BP_BASIS * AsMaths.SEC_PER_YEAR
    );
    vm.prank(manager);
    uint256 mgmtFeeShares = strat.collectFees();
    require(
      mgmtFeeShares == theoreticalMgmtFeeShares, "Management fee does not match (shares)"
    );
    checkSumOfAssets(assetsBefore); // dynamic fees are inflationary, minted shared slightly dilute total assets
  }

  // Test performance fee by simulating strategy performance
  function performanceFees(Fees memory _fees, uint256 _minLiquidity) public {
    console.log("--- performance fees test ---");
    deployStrat(_fees, _minLiquidity);
    uint256 profitCooldown = 1 seconds;

    // set profit cooldown to 1 second
    vm.prank(admin);
    strat.setProfitCooldown(profitCooldown); // no share price linearization
    vm.prank(bob);
    usdc.approve(address(strat), type(uint256).max);
    vm.prank(bob);
    strat.deposit(1000e6, bob);
    vm.prank(manager);
    strat.collectFees(); // clear any existing fees
    uint256 sharePriceBefore = strat.sharePrice();
    uint256 assetsBefore = strat.totalAssets();
    // pump share price through total assets
    vm.prank(admin);
    usdc.transfer(address(strat), assetsBefore); // pump the share price 2x
    vm.warp(block.timestamp + profitCooldown); // fast-forward profit cooldown to realize 2x PnL
    uint256 sharePriceAfter = strat.sharePrice();
    uint256 profitBps =
      (sharePriceAfter - sharePriceBefore).mulDiv(AsMaths.BP_BASIS, sharePriceAfter); // eg. 50% of current share price
    uint256 theoreticalPerfFee =
      (profitBps * strat.totalAssets()).mulDiv(strat.fees().perf, AsMaths.BP_BASIS ** 2);
    uint256 theoreticalPerfFeeShares = strat.convertToShares(theoreticalPerfFee);

    assetsBefore = strat.totalAssets();
    vm.prank(manager);
    uint256 perfFeeShares = strat.collectFees();
    require(
      perfFeeShares == theoreticalPerfFeeShares, "Performance fee does not match (shares)"
    );
    checkSumOfAssets(assetsBefore); // dynamic fees are inflationary, minted shared slightly dilute total assets
  }

  function flashLoanFees(Fees memory _fees, uint256 _minLiquidity) public {
    console.log("--- flash loan fees test ---");
    uint256 toBorrow = 1000e6;
    deployStrat(_fees, _minLiquidity);

    uint256 theoreticalFlashFee = toBorrow.mulDiv(strat.fees().flash, AsMaths.BP_BASIS);
    uint256 theoreticalFlashFeeShares = strat.convertToShares(theoreticalFlashFee);

    console.log("theoretical flash fees", theoreticalFlashFee);

    vm.prank(manager);
    strat.collectFees(); // clear any existing fees
    vm.startPrank(admin);
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(toBorrow, admin); // make sure there's enough to borrow
    strat.setMaxLoan(toBorrow);
    Borrower borrower = new Borrower(address(strat), keeper);
    usdc.transfer(address(borrower), theoreticalFlashFee);
    vm.stopPrank();

    require(strat.isLendable(USDC), "USDC not lendable");
    uint256 maxLoan = strat.maxFlashLoan(USDC);
    require(maxLoan >= toBorrow, "USDC max flash loan too low");
    require(maxLoan <= strat.totalAssets(), "USDC max flash loan too high");

    uint256 assetsBefore = strat.totalAssets();
    uint256 borrowerBalanceBefore = usdc.balanceOf(address(borrower));

    vm.prank(address(borrower));
    borrower.flashBorrow(USDC, toBorrow);

    vm.prank(manager);
    uint256 effectiveFlashFeeShares = strat.collectFees();
    uint256 effectiveFlashFee = strat.convertToAssets(effectiveFlashFeeShares);
    uint256 borrowerLoss = borrowerBalanceBefore - usdc.balanceOf(address(borrower));

    require(
      effectiveFlashFee == strat.flashFee(USDC, address(borrower), toBorrow),
      "Flash fee mismatch"
    );
    require(effectiveFlashFee == theoreticalFlashFee, "Flash fee mismatch");
    require(borrowerLoss == effectiveFlashFee, "Borrower loss does not match flash fee");
    require(
      strat.balanceOf(manager) == theoreticalFlashFeeShares, "Flash fee accounting error"
    );
    checkSumOfAssets(assetsBefore + effectiveFlashFee); // tx fees are non inflationary, total assets increase along with the minted shares
  }

  function checkSumOfAssets(uint256 _expected) public {
    uint256 assets = strat.totalAssets();
    uint256 sumOfAssets =
      strat.assetsOf(bob) + strat.assetsOf(manager) + strat.assetsOf(admin);
    require(
      assets <= (_expected + 1) && assets >= (_expected - 1),
      "Total assets inflated or deflated"
    );
    require(
      strat.totalAssets() <= (sumOfAssets + 3) && strat.totalAssets() >= (sumOfAssets - 3),
      "Total assets do not add up"
    ); // 3 = 1wei max flooring error per user
  }

  function flow(Fees memory _fees, uint256 _minLiquidity) public {
    deployDependencies();
    entryFees(
      Fees({perf: 0, mgmt: 0, entry: _fees.entry, exit: 0, flash: 0}), _minLiquidity
    );
    exitFees(
      Fees({perf: 0, mgmt: 0, entry: 0, exit: _fees.exit, flash: 0}), _minLiquidity
    );
    managementFees(
      Fees({perf: 0, mgmt: _fees.mgmt, entry: 0, exit: 0, flash: 0}), _minLiquidity
    );
    performanceFees(
      Fees({perf: _fees.perf, mgmt: 0, entry: 0, exit: 0, flash: 0}), _minLiquidity
    );
    flashLoanFees(
      Fees({perf: 0, mgmt: 0, entry: 0, exit: 0, flash: _fees.flash}), _minLiquidity
    );
  }

  function testAll() public {
    flow(Fees({perf: 10_00, mgmt: 10_00, entry: 1_00, exit: 1_00, flash: 1_00}), 1000e6);
  }
}
