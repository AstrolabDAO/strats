// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {Fees} from "../../src/abstract/AsTypes.sol";
import {AsArrays} from "../../src/libs/AsArrays.sol";
import {AsMaths} from "../../src/libs/AsMaths.sol";
import {TestEnvArb} from "./TestEnvArb.sol";

contract Erc4626VaultTest is TestEnvArb {
  using AsMaths for uint256;
  using AsArrays for uint256[8];

  constructor() TestEnvArb(true, true) {}

  function deposit(uint256 _toDeposit) public {
    console.log("--- deposit test ---");
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    usdc.approve(address(strat), type(uint256).max);
    vm.prank(bob);
    strat.deposit(_toDeposit, bob);
    uint256 deposited = balanceBefore - usdc.balanceOf(bob);
    require(strat.assetsOf(bob) == deposited, "Deposited vs received mismatch");
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Deposit total assets accounting error"
    );
  }

  function safeDeposit(uint256 _toDeposit) public {
    console.log("--- safeDeposit test ---");
    uint256 minShares = strat.convertToShares(_toDeposit) - 1;
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    usdc.approve(address(strat), type(uint256).max);
    vm.prank(bob);
    strat.safeDeposit(_toDeposit, minShares, bob);
    uint256 deposited = balanceBefore - usdc.balanceOf(bob);
    require(strat.assetsOf(bob) == deposited, "Deposited vs received mismatch");
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Deposit total assets accounting error"
    );
  }

  function mint(uint256 _toDeposit) public {
    console.log("--- mint test ---");
    uint256 toMint = strat.convertToShares(_toDeposit);
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    usdc.approve(address(strat), type(uint256).max);
    vm.prank(bob);
    strat.mint(toMint, bob);
    uint256 deposited = balanceBefore - usdc.balanceOf(bob);
    require(strat.assetsOf(bob) == deposited, "Minted vs received mismatch");
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Mint total assets accounting error"
    );
  }

  function safeMint(uint256 _toDeposit) public {
    console.log("--- safeMint test ---");
    uint256 toMint = strat.convertToShares(_toDeposit);
    uint256 maxAmount = _toDeposit + 1;
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    usdc.approve(address(strat), type(uint256).max);
    vm.prank(bob);
    strat.safeMint(toMint, maxAmount, bob);
    uint256 deposited = balanceBefore - usdc.balanceOf(bob);
    require(strat.assetsOf(bob) == deposited, "Minted vs received mismatch");
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Mint total assets accounting error"
    );
  }

  function withdraw(uint256 _toWithdraw) public {
    console.log("--- withdraw test ---");
    uint256 sharesBefore = strat.balanceOf(bob);
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    strat.withdraw(_toWithdraw, bob, bob);
    uint256 withdrawn = usdc.balanceOf(bob) - balanceBefore;
    require(
      withdrawn >= (_toWithdraw - 1) && withdrawn <= (_toWithdraw + 1),
      "Withdrawn vs received mismatch"
    );
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Withdraw total assets accounting error"
    );
  }

  function safeWithdraw(uint256 _toWithdraw) public {
    console.log("--- safeWithdraw test ---");
    uint256 minAmount = _toWithdraw - 1;
    uint256 sharesBefore = strat.balanceOf(bob);
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    strat.safeWithdraw(_toWithdraw, minAmount, bob, bob);
    uint256 withdrawn = usdc.balanceOf(bob) - balanceBefore;
    require(withdrawn == _toWithdraw, "Withdrawn vs received mismatch");
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Withdraw total assets accounting error"
    );
  }

  function redeem(uint256 _toWithdraw) public {
    console.log("--- redeem test ---");
    uint256 toRedeem = strat.convertToShares(_toWithdraw);
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    strat.redeem(toRedeem, bob, bob);
    uint256 withdrawn = usdc.balanceOf(bob) - balanceBefore;
    require(withdrawn == _toWithdraw, "Redeemed vs received mismatch");
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Redeem total assets accounting error"
    );
  }

  function safeRedeem(uint256 _toWithdraw) public {
    console.log("--- safeRedeem test ---");
    uint256 toRedeem = strat.convertToShares(_toWithdraw);
    uint256 minAmountOut = _toWithdraw - 1;
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    strat.safeRedeem(toRedeem, minAmountOut, bob, bob);
    uint256 withdrawn = usdc.balanceOf(bob) - balanceBefore;
    require(withdrawn == _toWithdraw, "Redeemed vs received mismatch");
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Redeem total assets accounting error"
    );
  }

  function checkBalancesAfter(uint256 _assetsBefore, uint256 _bobBalanceBefore) public {
    require(strat.balanceOf(bob) == 0, "Bob still owns shares");
    require(strat.totalAssets() == _assetsBefore, "Total assets not reset");
    require(
      usdc.balanceOf(bob) == _bobBalanceBefore, "Bob lost or earned assets unexpectedly"
    );
  }

  function resetStrat(
    Fees memory _fees,
    uint256 _minLiquidity
  ) public returns (uint256, uint256) {
    deployStrat(_fees, _minLiquidity);
    return (strat.totalAssets(), usdc.balanceOf(bob));
  }

  function testAll() public {
    deployDependencies();
    Fees memory zeroFees = Fees({perf: 0, mgmt: 0, entry: 0, exit: 0, flash: 0});
    uint256 assetsBefore;
    uint256 bobBalanceBefore;

    // deposit+withdraw
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    deposit(1000e6);
    withdraw(1000e6);
    checkBalancesAfter(assetsBefore, bobBalanceBefore);

    // safeDeposit+safeWithdraw
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    safeDeposit(1000e6);
    safeWithdraw(1000e6);
    checkBalancesAfter(assetsBefore, bobBalanceBefore);

    // deposit+redeem
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    deposit(1000e6);
    redeem(1000e6);
    checkBalancesAfter(assetsBefore, bobBalanceBefore);

    // safeDeposit+safeRedeem
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    safeDeposit(1000e6);
    safeRedeem(1000e6);
    checkBalancesAfter(assetsBefore, bobBalanceBefore);

    // mint+withdraw
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    mint(1000e6);
    withdraw(1000e6);
    checkBalancesAfter(assetsBefore, bobBalanceBefore);

    // safeMint+safeWithdraw
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    safeMint(1000e6);
    safeWithdraw(1000e6);
    checkBalancesAfter(assetsBefore, bobBalanceBefore);

    // mint+redeem
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    mint(1000e6);
    redeem(1000e6);
    checkBalancesAfter(assetsBefore, bobBalanceBefore);

    // safeMint+safeRedeem
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    safeMint(1000e6);
    safeRedeem(1000e6);
    checkBalancesAfter(assetsBefore, bobBalanceBefore);
  }
}
