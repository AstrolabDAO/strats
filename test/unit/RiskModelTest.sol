// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./TestEnvArb.sol";
import "../../src/interfaces/IStrategyV5.sol";
import "../../src/abstract/RiskModel.sol";
import "../../src/abstract/AsTypes.sol";

contract RiskModelTest is TestEnvArb {
  using AsMaths for uint256;
  using AsArrays for *;

  RiskModel public riskModel;
  IStrategyV5 public lowTvlVeryLowLiq;
  IStrategyV5 public lowTvlLowLiq;
  IStrategyV5 public lowTvlHighLiq;
  IStrategyV5 public highTvlVeryLowLiq;
  IStrategyV5 public highTvlLowLiq;
  IStrategyV5 public highTvlHighLiq;
  bytes score1 = abi.encodePacked(uint16(80), uint16(30), uint16(90), uint16(40));
  bytes score2 = abi.encodePacked(uint16(50), uint16(50), uint16(50), uint16(50));

  constructor() TestEnvArb(true, true) {}

  function _setUp() internal override {

    // create and set up strategies
    lowTvlVeryLowLiq = newStrat(100_000e6, 2_000e6); // $100k TVL, $2k liquidity
    lowTvlLowLiq = newStrat(100_000e6, 9_000e6); // $100k TVL, $9k liquidity
    lowTvlHighLiq = newStrat(100_000e6, 20_000e6); // $100k TVL, $20k liquidity
    highTvlVeryLowLiq = newStrat(500_000e6, 10e6); // $500k TVL, $10k liquidity
    highTvlLowLiq = newStrat(500_000e6, 30_000e6); // $500k TVL, $30k liquidity
    highTvlHighLiq = newStrat(500_000e6, 100_000e6); // $500k TVL, $100k liquidity

    // accessController only exists after the first newStrat is called
    riskModel = new RiskModel(address(accessController)); // Assuming the test contract is the access controller

    // assign default scores to strategies
    vm.startPrank(manager);
    riskModel.updateScore(lowTvlVeryLowLiq, score1);
    riskModel.updateScore(lowTvlLowLiq, score1);
    riskModel.updateScore(lowTvlHighLiq, score2);
    riskModel.updateScore(highTvlLowLiq, score1);
    riskModel.updateScore(highTvlHighLiq, score2);
    vm.stopPrank();

    // set up default protocol risk parameters
    vm.startPrank(admin);
    riskModel.updateStrategyParams(RiskParams.defaultStrategy());
    riskModel.updateAllocationParams(RiskParams.defaultAllocation());
    riskModel.updateStableMintParams(RiskParams.defaultStableMint());
    vm.stopPrank();
  }

  function newStrat(
    uint256 _tvl,
    uint256 _liquidity
  ) public returns (IStrategyV5) {
    IStrategyV5 s = deployStrat(zeroFees, 100e6);
    vm.prank(bob);
    usdc.approve(address(s), type(uint256).max);
    vm.prank(bob);
    // deposit -> increases tvl (idle available liquidity)
    s.deposit(_tvl, bob);
    vm.prank(keeper);
    // invest -> invest excess liquidity (tvl does not change, available liquidity decreases)
    s.invest([_tvl - _liquidity, 0, 0, 0, 0, 0, 0, 0], emptyBytesArray); // bytes[8] of test swapdata
    return s;
  }

  function testStrategyScoreUpdate() public {
    vm.prank(manager);
    riskModel.updateScore(lowTvlLowLiq, score2);

    RiskParams.StrategyScore memory score;
    (score.performance, score.safety, score.scalability, score.liquidity, score.composite) =
      riskModel.scoreByStrategy(lowTvlLowLiq);
    assertEq(score.performance, 50);
    assertEq(score.safety, 50);
    assertEq(score.scalability, 50);
    assertEq(score.liquidity, 50);
    assertApproxEqAbs(score.composite, 50, 1); // geometric mean of 50, 50, 50, 50
  
    vm.prank(manager);
    riskModel.updateScore(lowTvlLowLiq, score1);
    (score.performance, score.safety, score.scalability, score.liquidity, score.composite) =
      riskModel.scoreByStrategy(lowTvlLowLiq);
    assertEq(score.performance, 80);
    assertEq(score.safety, 30);
    assertEq(score.scalability, 90);
    assertEq(score.liquidity, 40);
    assertApproxEqAbs(score.composite, 54, 1); // geometric mean of 80, 30, 90, 40
  }

  function testShouldHarvest() public {
    // default pending rewards (10% from Strateg)
    assertTrue(riskModel.shouldHarvest(
      lowTvlLowLiq,
      lowTvlLowLiq.rewardsAvailable()[0], // USDC <> USD conversion accepted
      1e6 // $2 total harvest cost (eg. gas+slippage)
    ));
    vm.prank(keeper);
    lowTvlVeryLowLiq.harvest(bytes("").toArray()); // to accomodate _swapRewards()
    // no reward should remain on the strategy
    assertFalse(riskModel.shouldHarvest(
      lowTvlVeryLowLiq,
      lowTvlVeryLowLiq.rewardsAvailable()[0],
      1e6 // $2 total harvest cost (eg. gas+slippage)
    ));
  }

  function testShouldPanic() public {
    assertTrue(riskModel.shouldPanic(lowTvlVeryLowLiq));
    assertFalse(riskModel.shouldPanic(lowTvlLowLiq));
    assertFalse(riskModel.shouldPanic(lowTvlHighLiq));
    assertTrue(riskModel.shouldPanic(highTvlVeryLowLiq));
    assertFalse(riskModel.shouldPanic(highTvlLowLiq));
    assertFalse(riskModel.shouldPanic(highTvlHighLiq));
  }

  function testShouldAllocate() public {
    assertFalse(riskModel.shouldAllocate(lowTvlVeryLowLiq));
    assertFalse(riskModel.shouldAllocate(lowTvlLowLiq));
    assertTrue(riskModel.shouldAllocate(lowTvlHighLiq));
    assertFalse(riskModel.shouldAllocate(highTvlVeryLowLiq));
    assertFalse(riskModel.shouldAllocate(highTvlLowLiq));
    assertTrue(riskModel.shouldAllocate(highTvlHighLiq));
  }

  function testShouldLiquidate() public {
    assertTrue(riskModel.shouldLiquidate(lowTvlVeryLowLiq));
    assertTrue(riskModel.shouldLiquidate(lowTvlLowLiq));
    assertFalse(riskModel.shouldLiquidate(lowTvlHighLiq));
    assertTrue(riskModel.shouldLiquidate(highTvlVeryLowLiq));
    assertTrue(riskModel.shouldLiquidate(highTvlLowLiq));
    assertFalse(riskModel.shouldLiquidate(highTvlHighLiq));
  }

  function testTargetCompositeAllocation() public {
    // consider a basket of 2 strategies
    IStrategyV5[] memory strategies = new IStrategyV5[](2);
    strategies[0] = lowTvlHighLiq;
    strategies[1] = highTvlHighLiq;
    uint256 amount = 10_000e6; // $10k more allocated to the basket

    uint256[] memory allocations = riskModel.targetCompositeAllocation(
      strategies,
      strategies.length,
      amount
    );

    assertEq(allocations.length, strategies.length);

    console.log("allocations:", allocations[0], allocations[1]);

    uint256 totalAllocation = 0;
    for (uint256 i = 0; i < allocations.length; i++) {
      totalAllocation += allocations[i];
    }

    assertApproxEqAbs(totalAllocation, amount, 1e6); // Allow for small rounding differences
  }

  function testExcessAllocation() public {
    // consider a basket of 2 strategies
    IStrategyV5[] memory strategies = new IStrategyV5[](2);
    strategies[0] = lowTvlHighLiq;
    strategies[1] = highTvlHighLiq;
    uint256 addon = 10_000e6; // $10k more allocated to the basket

    int256[] memory excess = riskModel.excessAllocation(
      strategies,
      addon,
      bob // bob owns the basket (usually a composite strategy would be used)
    );

    assertEq(excess.length, strategies.length);

    // Check that the sum of positive excesses roughly equals the sum of negative excesses
    int256 positiveSum = 0;
    int256 negativeSum = 0;
    for (uint256 i = 0; i < excess.length; i++) {
      if (excess[i] > 0) {
        console.log("excess[", i, "]:", uint256(excess[i]));
        positiveSum += excess[i];
      } else {
        console.log("excess[", i, "]: -", uint256(-excess[i]));
        negativeSum += excess[i];
      }
    }

    assertApproxEqAbs(positiveSum, -negativeSum + int256(addon), 1e6); // $1 rounding error
  }

  function testLiquidityLimits() public {
    uint256[8] memory tvls = [uint256(100e6), uint256(1000e6), uint256(10_000e6), uint256(100_000e6), uint256(1_000_000e6), uint256(10_000_000e6), uint256(100_000_000e6), uint256(1_000_000_000e6)];
    uint256[4] memory limits;
    for (uint256 i = 0; i < tvls.length; i++) {
      limits = riskModel.liquidityLimits(tvls[i]);
      for (uint256 j = 0; j < limits.length; j++) {
        console.log("limit[", j, "]:", limits[j]);
      }
      assertGt(limits[0], limits[1]); // allocation trigger (upper band) > liquidity target
      assertGt(limits[1], limits[2]); // liquidity target (gravity center) > liquidation level (lower band)
      assertGt(limits[2], limits[3]); // liquidation level (lower band) > panic level (2nd lower band)
    }
  }

  function testUpdateParams() public {
    RiskParams.Strategy memory _in = RiskParams.Strategy({
      defaultSeedUsd: 2000e18,
      defaultDepositCapUsd: 200000e18,
      defaultMaxSlippage: 2_00,
      defaultMaxLeverage: 4_00,
      minUpkeepInterval: 7200
    });
    vm.prank(address(admin));
    riskModel.updateStrategyParams(_in);
    RiskParams.Strategy memory _out;
    (
      _out.defaultSeedUsd,
      _out.defaultDepositCapUsd,
      _out.defaultMaxSlippage,
      _out.defaultMaxLeverage,
      _out.minUpkeepInterval
    ) = riskModel.strategyParams();
    assertEq(_out.defaultSeedUsd, _in.defaultSeedUsd);
    assertEq(_out.defaultDepositCapUsd, _in.defaultDepositCapUsd);
    assertEq(_out.defaultMaxSlippage, _in.defaultMaxSlippage);
    assertEq(_out.defaultMaxLeverage, _in.defaultMaxLeverage);
    assertEq(_out.minUpkeepInterval, _in.minUpkeepInterval);
  }

  function testInvalidParamsUpdate() public {
    RiskParams.Strategy memory invalidParams = RiskParams.Strategy({
      defaultSeedUsd: 1e18, // Too low
      defaultDepositCapUsd: 2000000e18, // Too high
      defaultMaxSlippage: 10_00, // Too high
      defaultMaxLeverage: 1_00, // Too low
      minUpkeepInterval: 100 // Too low
    });

    vm.prank(address(this));
    vm.expectRevert(Errors.InvalidData.selector);
    riskModel.updateStrategyParams(invalidParams);
  }
}
