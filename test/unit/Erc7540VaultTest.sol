// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {Fees} from "../../src/abstract/AsTypes.sol";
import {AsArrays} from "../../src/libs/AsArrays.sol";
import {AsMaths} from "../../src/libs/AsMaths.sol";
import {TestEnvArb} from "./TestEnvArb.sol";

contract Erc7540VaultTest is TestEnvArb {
  using AsMaths for uint256;
  using AsArrays for uint256[8];

  constructor() TestEnvArb(true, true) {}

  function deposit(uint256 _toDeposit) public {
    console.log("--- deposit test ---");
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.startPrank(bob);
    usdc.approve(address(strat), type(uint256).max);
    strat.requestDeposit(_toDeposit, bob, bob, ""); // useless but ERC-7540 polyfill
    strat.deposit(_toDeposit, bob);
    vm.stopPrank();
    uint256 deposited = balanceBefore - usdc.balanceOf(bob);
    require(strat.assetsOf(bob) == deposited, "Deposited vs received mismatch");
    require(strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin), "Deposit total assets accounting error");
  }

  function redeem(uint256 _toWithdraw) public  {
    console.log("--- redeem test ---");
    uint256 toRedeem = strat.convertToShares(_toWithdraw);
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    strat.requestRedeem(toRedeem, bob, bob, "");
    uint256[8] memory liquidateAmounts = strat.previewLiquidate(0);
    bytes[] memory swapData = new bytes[](1);
    vm.prank(keeper);
    strat.liquidate(liquidateAmounts, 0, false, swapData); // free the redemption requests
    vm.prank(bob);
    strat.redeem(toRedeem, bob, bob);
    uint256 withdrawn = usdc.balanceOf(bob) - balanceBefore;
    require(withdrawn == _toWithdraw, "Redeemed vs received mismatch");
    require(strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin), "Redeem total assets accounting error");
  }

  function withdraw(uint256 _toWithdraw) public {
    console.log("--- withdraw test ---");
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    strat.requestWithdraw(_toWithdraw, bob, bob, ""); // non standard as no guarantee of price (uses requestRedeem)
    uint256[8] memory liquidateAmounts = strat.previewLiquidate(0);
    bytes[] memory swapData = new bytes[](1);
    vm.prank(keeper);
    strat.liquidate(liquidateAmounts, 0, false, swapData); // free the redemption requests
    vm.prank(bob);
    strat.withdraw(_toWithdraw, bob, bob);
    uint256 withdrawn = usdc.balanceOf(bob) - balanceBefore;
    require(withdrawn == _toWithdraw, "Withdrawn vs received mismatch");
    require(strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin), "Withdraw total assets accounting error");
  }

  function locktime(uint256 _toWithdraw) public {
    console.log("--- redeem after locktime test (no liquidate) ---");
    uint256 toRedeem = strat.convertToShares(_toWithdraw);
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    strat.requestRedeem(toRedeem, bob, bob, "");
    vm.prank(admin);
    strat.setRedemptionRequestLocktime(1 days);
    vm.warp(block.timestamp + 2 days);
    vm.prank(bob);
    strat.redeem(toRedeem, bob, bob);
    uint256 withdrawn = usdc.balanceOf(bob) - balanceBefore;
    require(withdrawn == _toWithdraw, "Redeemed vs received mismatch");
    require(strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin), "Redeem total assets accounting error");
  }

  function requestedSharesReservation(uint256 _toWithdraw) public {
    console.log("--- requestedSharesReservation test ---");
    uint256 toRedeem = strat.convertToShares(_toWithdraw);
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.startPrank(bob);
    strat.requestRedeem(toRedeem, bob, bob, "");
    // TODO: replace with try/catch
    (bool success, ) = address(strat).call(
        abi.encodeWithSignature("transfer(address,uint256)", alice, toRedeem)
    );
    if (success) {
        revert("Shares transfer should fail");
    } else {
        // console.log("Transfer failed as expected");
    }
    strat.cancelRedeemRequest(bob, bob);
    strat.transfer(alice, toRedeem);
    vm.stopPrank();
    require(strat.balanceOf(bob) == 0, "Bob still owns shares");
    require(strat.balanceOf(alice) == toRedeem, "Alice does not own shares");
  }

  function resetStrat(Fees memory _fees, uint256 _minLiquidity) public returns (uint256, uint256) {
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

    // deposit+redeem
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    deposit(1000e6);
    redeem(1000e6);

    // request locktime
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    deposit(1000e6);
    locktime(1000e6);

    // deposit+requested shares reservation
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    deposit(1000e6);
    requestedSharesReservation(1000e6);
  }
}
