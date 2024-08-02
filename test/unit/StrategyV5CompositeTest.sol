// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {
  Fees,
  Erc20Metadata,
  CoreAddresses,
  StrategyParams
} from "../../src/abstract/AsTypes.sol";
import {AsArrays} from "../../src/libs/AsArrays.sol";
import {AsMaths} from "../../src/libs/AsMaths.sol";
import {StrategyV5} from "../../src/abstract/StrategyV5.sol";

import {StrategyV5Simulator} from "../../src/implementations/StrategyV5Simulator.sol";
import {TestEnvArb} from "./TestEnvArb.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract StrategyV5CompositeTest is TestEnvArb {
  using AsMaths for uint256;
  using AsArrays for uint256[8];
  using AsArrays for uint16;
  using AsArrays for address;
  using Strings for uint256;

  uint256 public constant N_PRIMITIVES = 2; // 2+

  constructor() TestEnvArb(true, true) {}

  function init(Fees memory _fees) public override {
    // strategy core addresses
    CoreAddresses memory coreAddresses = CoreAddresses({
      wgas: WETH,
      asset: USDC,
      feeCollector: manager,
      swapper: swapper,
      agent: agent,
      oracle: address(oracle)
    });

    StrategyV5[] memory primitives = new StrategyV5[](N_PRIMITIVES);
    for (uint256 i = 0; i < N_PRIMITIVES; i++) {
      Erc20Metadata memory erc20Meta = Erc20Metadata({
        // use i as unique strategy suffix identifier
        name: string(abi.encodePacked("Astrolab Primitive Dummy USD ", i.toString())),
        symbol: string(abi.encodePacked("apDUMMY-USD-", i.toString())),
        decimals: 12
      });
      StrategyParams memory primitiveParams = StrategyParams({
        erc20Metadata: erc20Meta,
        coreAddresses: coreAddresses,
        fees: _fees,
        inputs: USDC.toArray(), // [USDC]
        inputWeights: uint16(100_00).toArray16(), // 100% weight on USDC
        lpTokens: USDCe.toArray(),
        rewardTokens: USDCe.toArray(),
        extension: new bytes(0)
      });

      // deploy and initialize primitive strategy
      primitives[i] = new StrategyV5Simulator(address(accessController));
      vm.prank(admin);
      StrategyV5(primitives[i]).init(primitiveParams);
    }

    // initialize the strategy
    // ERC20 metadata
    Erc20Metadata memory compositeErc20Meta = Erc20Metadata({
      name: "Astrolab Composite Dummy USD",
      symbol: "acDUMMY-USD",
      decimals: 12
    });

    // aggregated strategy base parameters
    StrategyParams memory compositeParams = StrategyParams({
      erc20Metadata: compositeErc20Meta,
      coreAddresses: coreAddresses,
      fees: _fees,
      inputs: USDC.toArray(USDC), // [USDC, USDC]
      inputWeights: uint16(50_00).toArray16(50_00), // [50%, 50%]
      lpTokens: address(primitives[0]).toArray(address(primitives[1])), // [Primitive0, Primitive1]
      rewardTokens: USDC.toArray(),
      extension: new bytes(1) // empty bytes are required in order for StrategyV5Composite.setParams() to be called
    });

    // initialize (admin only)
    vm.prank(admin);
    strat.init(compositeParams);
  }

  function deposit(uint256 _toDeposit) public {
    console.log("--- deposit test ---");
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.startPrank(bob);
    usdc.approve(address(strat), type(uint256).max);
    // strat.requestDeposit(_toDeposit, bob, bob, ""); // useless but ERC-7540 polyfill
    strat.deposit(_toDeposit, bob);
    vm.stopPrank();
    uint256 deposited = balanceBefore - usdc.balanceOf(bob);
    require(strat.assetsOf(bob) == deposited, "Deposited vs received mismatch");
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Deposit total assets accounting error"
    );
  }

  function redeem(uint256 _toWithdraw) public {
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
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Redeem total assets accounting error"
    );
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
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Withdraw total assets accounting error"
    );
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
    require(
      strat.totalAssets() == strat.assetsOf(bob) + strat.assetsOf(admin),
      "Redeem total assets accounting error"
    );
  }

  function requestedSharesReservation(uint256 _toWithdraw) public {
    console.log("--- requestedSharesReservation test ---");
    uint256 toRedeem = strat.convertToShares(_toWithdraw);
    // uint256 balanceBefore = usdc.balanceOf(bob);
    vm.startPrank(bob);
    strat.requestRedeem(toRedeem, bob, bob, "");
    // TODO: replace with try/catch
    (bool success,) = address(strat).call(
      abi.encodeWithSignature("transfer(address,uint256)", alice, toRedeem)
    );
    if (success) {
      revert("Shares transfer should fail");
    } else {
      console.log("Transfer failed as expected");
    }
    strat.cancelRedeemRequest(bob, bob);
    strat.transfer(alice, toRedeem);
    vm.stopPrank();
    require(strat.balanceOf(bob) == 0, "Bob still owns shares");
    require(strat.balanceOf(alice) == toRedeem, "Alice does not own shares");
  }

  function resetStrat(
    Fees memory _fees,
    uint256 _minLiquidity
  ) public returns (uint256, uint256) {
    deployStrat(_fees, _minLiquidity, true);
    return (strat.totalAssets(), usdc.balanceOf(bob));
  }

  function testAll() public {
    deployDependencies();
    Fees memory zeroFees = Fees({perf: 0, mgmt: 0, entry: 0, exit: 0, flash: 0});
    Fees memory nonZeroFees = Fees({perf: 100, mgmt: 50, entry: 10, exit: 10, flash: 0});

    uint256 assetsBefore;
    uint256 bobBalanceBefore;

    // deposit+withdraw
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    deposit(1000e6);
    withdraw(1000e6);

    // withdrawing more than deposited should fail
    (assetsBefore, bobBalanceBefore) = resetStrat(zeroFees, 1000e6);
    deposit(1000e6);
    vm.startPrank(bob);
    vm.expectRevert();
    strat.withdraw(2000e6, bob, bob);
    vm.stopPrank();

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

    // deposit with fees
    resetStrat(nonZeroFees, 1000e6);
    vm.startPrank(bob);
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(1000e6, bob);
    vm.stopPrank();
    uint256 expectedAssetsAfterFees = 1000e6 - (1000e6 * nonZeroFees.entry / 10000);
    require(
      strat.assetsOf(bob) == expectedAssetsAfterFees, "Assets after deposit fee mismatch"
    );

    // withdraw with fees
    uint256 balanceBefore = usdc.balanceOf(bob);
    vm.prank(bob);
    strat.requestWithdraw(expectedAssetsAfterFees, bob, bob, ""); // non standard as no guarantee of price (uses requestRedeem)
    uint256[8] memory liquidateAmounts = strat.previewLiquidate(0);
    bytes[] memory swapData = new bytes[](1);
    vm.prank(keeper);
    strat.liquidate(liquidateAmounts, 0, false, swapData); // free the redemption requests
    vm.prank(bob);
    strat.withdraw(expectedAssetsAfterFees, bob, bob);
    uint256 expectedBalanceAfterWithdraw =
      expectedAssetsAfterFees - (expectedAssetsAfterFees * nonZeroFees.exit / 10000);
    console.log(usdc.balanceOf(bob), expectedBalanceAfterWithdraw);
    require(
      usdc.balanceOf(bob) - balanceBefore == expectedBalanceAfterWithdraw,
      "Balance after withdraw fee mismatch"
    );
  }
}
