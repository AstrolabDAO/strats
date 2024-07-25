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
  IStrategyV5[] public strategies;
  bytes score1 = abi.encode(uint16(80), uint16(30), uint16(90), uint16(40));
  bytes score2 = abi.encode(uint16(80), uint16(30), uint16(90), uint16(40));

  constructor() TestEnvArb(true, true) {}

  function _setUp() internal override {
    riskModel = new RiskModel(address(accessController)); // Assuming the test contract is the access controller

    // create and set up strategies
    strategies.push(newStrat(100_000e6, 2_000e6)); // $100k TVL, $2k liquidity
    strategies.push(newStrat(100_000e6, 20_000e6)); // $100k TVL, $20k liquidity
    strategies.push(newStrat(500_000e6, 10_000e6)); // 500K TVL, $10k liquidity
    strategies.push(newStrat(500_000e6, 100_000e6)); // $500K TVL, $100k liquidity

    // assign scores to strategies
    vm.startPrank(manager);
    riskModel.updateScore(strategies[0], score1);
    riskModel.updateScore(strategies[1], score1);
    riskModel.updateScore(strategies[2], score1);
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
    riskModel.updateScore(strategies[0], abi.encode(80, 30, 90, 40));

    RiskParams.StrategyScore memory score;
    (score.performance, score.safety, score.scalability, score.liquidity, score.composite) =
      riskModel.scoreByStrategy(strategies[0]);
    assertEq(score.performance, 80);
    assertEq(score.safety, 30);
    assertEq(score.scalability, 90);
    assertEq(score.liquidity, 40);
    assertApproxEqAbs(score.composite, 54, 1); // geometric mean of 80, 30, 90, 40
  }

  function testTargetCompositeAllocation() public {
    uint256 totalAmount = 1000000e6; // $1M
    uint256[] memory allocations = riskModel.targetCompositeAllocation(
      strategies,
      strategies.length,
      totalAmount
    );

    assertEq(allocations.length, strategies.length);

    uint256 totalAllocation = 0;
    for (uint256 i = 0; i < allocations.length; i++) {
      totalAllocation += allocations[i];
    }

    assertApproxEqAbs(totalAllocation, totalAmount, 1e6); // Allow for small rounding differences
  }

  function testShouldHarvest() public {
    uint256 pendingRewards = 1000e6; // $1000
    uint256 costEstimate = 50e6; // $50

    bool shouldHarvest = riskModel.shouldHarvest(
      strategies[0],
      pendingRewards,
      costEstimate
    );
    assertTrue(shouldHarvest);

    // Test with smaller rewards
    pendingRewards = 10e6; // $10
    shouldHarvest = riskModel.shouldHarvest(
      strategies[0],
      pendingRewards,
      costEstimate
    );
    assertFalse(shouldHarvest);
  }

  function testLiquidityLimits() public {
    uint256 tvl = 1000000e6; // $1M
    uint256[4] memory limits = riskModel.liquidityLimits(tvl);

    assertGt(limits[0], limits[1]); // Upper band > Target
    assertGt(limits[1], limits[2]); // Target > Lower band
    assertGt(limits[2], limits[3]); // Lower band > Panic band
  }

  function testShouldLiquidate() public {
    bool shouldLiquidate = riskModel.shouldLiquidate(strategies[0]);
    assertFalse(shouldLiquidate);

    // Simulate low liquidity scenario
    IStrategyV5 lowLiquidityStrat = newStrat(1000000e6, 10000e6); // $1M TVL, only $10k liquidity
    vm.prank(manager);
    riskModel.updateScore(lowLiquidityStrat, abi.encode(80, 70, 60, 90));

    shouldLiquidate = riskModel.shouldLiquidate(lowLiquidityStrat);
    assertTrue(shouldLiquidate);
  }

  function testShouldPanic() public {
    bool shouldPanic = riskModel.shouldPanic(strategies[0]);
    assertFalse(shouldPanic);

    // Simulate extremely low liquidity scenario
    IStrategyV5 veryLowLiquidityStrat = newStrat(1000000e6, 1000e6); // $1M TVL, only $1k liquidity
    vm.prank(manager);
    riskModel.updateScore(veryLowLiquidityStrat, abi.encode(80, 70, 60, 90));

    shouldPanic = riskModel.shouldPanic(veryLowLiquidityStrat);
    assertTrue(shouldPanic);
  }

  function testShouldAllocate() public {
    bool shouldAllocate = riskModel.shouldAllocate(strategies[0]);
    assertFalse(shouldAllocate);

    // Simulate high liquidity scenario
    IStrategyV5 highLiquidityStrat = newStrat(1000000e6, 500000e6); // $1M TVL, $500k liquidity
    vm.prank(manager);
    riskModel.updateScore(highLiquidityStrat, abi.encode(80, 70, 60, 90));

    shouldAllocate = riskModel.shouldAllocate(highLiquidityStrat);
    assertTrue(shouldAllocate);
  }

  function testExcessAllocation() public {
    uint256 totalAmount = 1000000e6; // $1M
    address owner = address(this);

    int256[] memory excess = riskModel.excessAllocation(
      strategies,
      totalAmount,
      owner
    );

    assertEq(excess.length, strategies.length);

    // Check that the sum of positive excesses roughly equals the sum of negative excesses
    int256 positiveSum = 0;
    int256 negativeSum = 0;
    for (uint256 i = 0; i < excess.length; i++) {
      if (excess[i] > 0) {
        positiveSum += excess[i];
      } else {
        negativeSum += excess[i];
      }
    }

    assertApproxEqAbs(positiveSum, -negativeSum, 1e6); // Allow for small rounding differences
  }

  function testUpdateParams() public {
    RiskParams.Strategy memory _in = RiskParams.Strategy({
      defaultSeedUsd: 2000e18,
      defaultDepositCapUsd: 200000e18,
      defaultMaxLeverage: 4_00,
      defaultMaxSlippage: 2_00,
      minUpkeepInterval: 7200
    });
    vm.prank(address(admin));
    riskModel.updateStrategyParams(_in);
    RiskParams.Strategy memory _out;
    (
      _out.defaultSeedUsd,
      _out.defaultDepositCapUsd,
      _out.defaultMaxLeverage,
      _out.defaultMaxSlippage,
      _out.minUpkeepInterval
    ) = riskModel.strategyParams();
    assertEq(_out.defaultSeedUsd, 2000e18);
    assertEq(_out.defaultDepositCapUsd, 200000e18);
    assertEq(_out.defaultMaxLeverage, 4_00);
    assertEq(_out.defaultMaxSlippage, 2_00);
    assertEq(_out.minUpkeepInterval, 7200);
  }

  function testInvalidParamsUpdate() public {
    RiskParams.Strategy memory invalidParams = RiskParams.Strategy({
      defaultSeedUsd: 1e18, // Too low
      defaultDepositCapUsd: 2000000e18, // Too high
      defaultMaxLeverage: 1_00, // Too low
      defaultMaxSlippage: 10_00, // Too high
      minUpkeepInterval: 100 // Too low
    });

    vm.prank(address(this));
    vm.expectRevert(Errors.InvalidData.selector);
    riskModel.updateStrategyParams(invalidParams);
  }
}
