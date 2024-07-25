// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/abstract/AsTypes.sol";
import "../../src/interfaces/IStrategyV5.sol";
import "./TestEnvArb.sol";
import {AsArrays} from "../../src/libs/AsArrays.sol";
import {AsMaths} from "../../src/libs/AsMaths.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StrategyV5Simulator, StrategyV5CompositeSimulator} from "./StrategyV5Simulator.sol";

contract IStrategyV5CompositeTest is TestEnvArb {
  using AsMaths for uint256;
  using AsArrays for uint256[8];
  using AsArrays for uint16;
  using AsArrays for address;
  using Strings for uint256;

  uint256 public constant N_PRIMITIVES = 2; // 2+

  constructor() TestEnvArb(true, true) {}

  function init(IStrategyV5 _strat, Fees memory _fees) public override {

    // strategy core addresses
    CoreAddresses memory coreAddresses = CoreAddresses({
      wgas: WETH,
      asset: USDC,
      feeCollector: manager,
      swapper: swapper,
      agent: agent,
      oracle: address(oracle)
    });

    IStrategyV5[] memory primitives = new IStrategyV5[](N_PRIMITIVES);
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
        inputWeights: uint16(90_00).toArray16(), // 90% weight on USDC, 10% cash
        lpTokens: USDCe.toArray(),
        rewardTokens: USDCe.toArray(),
        extension: new bytes(0)
      });

      // deploy and initialize primitive strategy
      primitives[i] = IStrategyV5(
        address(new StrategyV5Simulator(address(accessController), vm))
      );
      vm.prank(admin);
      IStrategyV5(primitives[i]).init(primitiveParams);
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
      extension: new bytes(1) // empty bytes are required in order for IStrategyV5Composite.setParams() to be called
    });

    // initialize (admin only)
    vm.prank(admin);
    _strat.init(compositeParams);
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
    vm.prank(keeper);
    uint256[8] memory liquidateAmounts = strat.preview(0, false);
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
    vm.prank(keeper);
    uint256[8] memory liquidateAmounts = strat.preview(0, false);
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
      // console.log("Transfer failed as expected");
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
    strat = deployStrat(_fees, _minLiquidity, true);
    return (strat.totalAssets(), usdc.balanceOf(bob));
  }

  function testAll() public {
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
