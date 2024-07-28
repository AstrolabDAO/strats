// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./TestEnvArb.sol";
import "../../src/interfaces/IStrategyV5.sol";
import "../../src/abstract/RiskModel.sol";
import "../../src/abstract/AsTypes.sol";

contract RiskModelTest is TestEnvArb {
  using AsMaths for *;
  using AsArrays for *;

  RiskModel public riskModel;
  IStrategyV5 public lowTvlVeryLowLiq;
  IStrategyV5 public lowTvlLowLiq;
  IStrategyV5 public lowTvlHighLiq;
  IStrategyV5 public highTvlVeryLowLiq;
  IStrategyV5 public highTvlLowLiq;
  IStrategyV5 public highTvlHighLiq;
  bytes score1 = abi.encodePacked(uint16(80), uint16(30), uint16(90), uint16(40));
  bytes score2 = abi.encodePacked(uint16(40), uint16(40), uint16(40), uint16(40));

  constructor() TestEnvArb(true, true) {}

  function _setUp() internal override {

    // create and set up strategies
    lowTvlVeryLowLiq = newStrat(100_000e6, 2_000e6); // $100k TVL, $2k liquidity
    lowTvlLowLiq = newStrat(100_000e6, 9_000e6); // $100k TVL, $9k liquidity
    lowTvlHighLiq = newStrat(100_000e6, 40_000e6); // $100k TVL, $40k liquidity
    highTvlVeryLowLiq = newStrat(500_000e6, 10e6); // $500k TVL, $10k liquidity
    highTvlLowLiq = newStrat(500_000e6, 40_000e6); // $500k TVL, $30k liquidity
    highTvlHighLiq = newStrat(500_000e6, 200_000e6); // $500k TVL, $200k liquidity

    // accessController only exists after the first newStrat is called
    riskModel = new RiskModel(address(accessController)); // Assuming the test contract is the access controller

    // assign default scores to strategies
    vm.startPrank(manager);
    riskModel.updateScore(lowTvlVeryLowLiq, score1);
    riskModel.updateScore(lowTvlLowLiq, score1);
    riskModel.updateScore(lowTvlHighLiq, score2);
    riskModel.updateScore(highTvlVeryLowLiq, score1);
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
    assertEq(score.performance, 40);
    assertEq(score.safety, 40);
    assertEq(score.scalability, 40);
    assertEq(score.liquidity, 40);
    assertApproxEqAbs(score.composite, 40, 1); // geometric mean of 40, 40, 40, 40
  
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
    IStrategyV5 strat = lowTvlVeryLowLiq;
    // default pending rewards (10% from Strategy)
    (uint256 cost, bool shouldHarvest, uint256 rewards) = (1e6, false, strat.rewardsAvailable()[0]);
    console.log("before harvest");
    shouldHarvest = riskModel.shouldHarvest(
      strat,
      rewards, // USDC <> USD conversion accepted
      cost // $1 total harvest cost (eg. gas+slippage)
    );
    console.log("rewards available: %e, harvest cost: %e", rewards, cost);
    console.log("-> shouldHarvest: %s", shouldHarvest);
    assertEq(shouldHarvest, true);
    vm.prank(keeper);
    strat.harvest(bytes("").toArray()); // to accomodate _swapRewards()
    // no reward should remain on the strategy
    console.log("after harvest");
    rewards = strat.rewardsAvailable()[0];
    console.log("rewards available: %e, harvest cost: %e", rewards, cost);
    shouldHarvest = riskModel.shouldHarvest(strat, rewards, cost);
    console.log("-> shouldHarvest: %s", shouldHarvest);
    assertEq(shouldHarvest, false);
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

  function testTargetComposition() public {

    IStrategyV5[] memory strategies = new IStrategyV5[](4);
    strategies[0] = lowTvlHighLiq; // score 1
    strategies[1] = highTvlHighLiq; // new score++
    strategies[2] = lowTvlLowLiq; // score 1
    strategies[3] = highTvlLowLiq; // score 2

    // inflate score of highTvlHighLiq to test the non-linear allocation increase
    vm.prank(admin);
    riskModel.updateScore(highTvlHighLiq, abi.encodePacked(uint16(95), uint16(90), uint16(80), uint16(90)));

    uint256 amount = 10_000e18; // $10k allocated to the basket

    uint256[] memory allocations = riskModel.targetComposition(
      strategies,
      strategies.length,
      amount
    );

    for (uint256 i = 0; i < allocations.length; i++) {
      console.log("allocation[%s]: %e", i, allocations[i]);
    }

    assertEq(allocations.length, strategies.length);

    uint256 totalAllocation = 0;
    for (uint256 i = 0; i < allocations.length; i++) {
      totalAllocation += allocations[i];
    }

    assertApproxEqAbs(totalAllocation, amount, 1e6); // Allow for small rounding differences
  }

  function testExcessAllocation() public {

    // consider a basket of 2 strategies
    IStrategyV5[] memory strategies = new IStrategyV5[](4);
    strategies[0] = lowTvlHighLiq; // score 1
    strategies[1] = highTvlHighLiq; // new score++
    strategies[2] = lowTvlLowLiq; // score 1
    strategies[3] = highTvlLowLiq; // score 2

    // inflate score of highTvlHighLiq to test the non-linear allocation increase
    vm.prank(admin);
    riskModel.updateScore(highTvlHighLiq, abi.encodePacked(uint16(95), uint16(90), uint16(80), uint16(90)));

    uint256 amount = 10_000e18; // $10k deposited on the basket

    int256[] memory excess = riskModel.excessAllocation(
      strategies,
      amount,
      alice // alice owns the basket (eg. composite strategy)
    );

    assertEq(excess.length, strategies.length);

    // check that the sum of positive excesses roughly equals the sum of negative excesses
    int256 positiveSum = 0;
    int256 negativeSum = 0;
    uint256 totalPriorPositionUsd = 0;

    // calculate the total prior position value in USD and log the excesses
    for (uint256 i = 0; i < excess.length; i++) {
      uint256 priorPositionUsd = uint256(riskModel.positionUsd(strategies[i], alice));
      console.log("positionUsd[%s]: %e", i, priorPositionUsd);
      totalPriorPositionUsd += priorPositionUsd;
      if (excess[i] > 0) {
        console.log("excess[%s]: %e", i, uint256(excess[i]));
        positiveSum += excess[i];
      } else {
        console.log("excess[%s]: -%e", i, uint256(-excess[i]));
        negativeSum += excess[i];
      }
    }

    console.log("totalPriorPositionUsd: %e", totalPriorPositionUsd);
    console.log("positiveSum: %e", uint256(positiveSum));
    console.log("negativeSum: %e", uint256(-negativeSum));
    assertApproxEqAbs(uint256(positiveSum) + uint256(-negativeSum) - totalPriorPositionUsd, amount, 1e6); // $1 rounding error

    // deposit/withdraw from the strategies in order to match the excesses
    for (uint256 i = 0; i < excess.length; i++) {
      vm.startPrank(alice);
      if (excess[i] > 0) {
        // positive excess == withdraw required (reduce exposure/position size)
        console.log("withdrawing %e from %s", uint256(excess[i]), strategies[i].symbol());
        strategies[i].withdraw(
          oracle.fromUsd(address(strategies[i].asset()), uint256(excess[i])),
          alice, // receiver
          alice // owner
        );
      } else {
        uint256 amountUsdc = oracle.fromUsd(address(strategies[i].asset()), uint256(-excess[i]));
        // negative excess == deposit required (increase exposure/position size)
        console.log("depositing %e usd -> %e USDC to %s", uint256(-excess[i]), amountUsdc, strategies[i].symbol());
        IERC20Metadata(strategies[i].asset()).approve(address(strategies[i]), amountUsdc);
        strategies[i].deposit(
          amountUsdc,
          alice // receiver
        );
      }
    }
    excess = riskModel.excessAllocation(
      strategies,
      amount,
      alice // alice owns the basket (eg. composite strategy)
    );

    for (uint256 i = 0; i < excess.length; i++) {
      console.log("new excess[%s]: %e", i, uint256(excess[i]));
      console.log("new positionUsd[%s]: %e", i, uint256(riskModel.positionUsd(strategies[i], alice)));
    }
    // all excesses should now be zero
    assertEq(excess.length, strategies.length);
    for (uint256 i = 0; i < excess.length; i++) {
      uint256 absExcess = uint256(excess[i].abs());
      assertApproxEqAbs(absExcess, 0, 50e18); // $50 tolerance
    }
    vm.stopPrank();
  }

  function testLiquidityLimitRatios() public {
    // tvls in USD e18
    uint256[8] memory tvls = [uint256(100e18), uint256(1000e18), uint256(10_000e18), uint256(100_000e18), uint256(1_000_000e18), uint256(10_000_000e18), uint256(100_000_000e18), uint256(1_000_000_000e18)];
    uint256[4] memory limits;
    for (uint256 i = 0; i < tvls.length; i++) {
      console.log("limit ratios for tvl: %e", tvls[i]);
      limits = riskModel.liquidityLimitRatios(tvls[i]);
      for (uint256 j = 0; j < limits.length; j++) {
        console.log("-> limit[%s]: %e", j, limits[j]);
      }
      assertLt(limits[0], 1e18); // allocation trigger (upper band) < 100%
      assertGt(limits[0], limits[1]); // allocation trigger (upper band) > liquidity target
      assertGt(limits[1], limits[2]); // liquidity target (gravity center) > liquidation level (lower band)
      assertGt(limits[2], limits[3]); // liquidation level (lower band) > panic level (2nd lower band)
    }
  }

  function testLiquidityLimits() public {
    // tvls in USD e18
    uint256[8] memory tvls = [uint256(100e18), uint256(1000e18), uint256(10_000e18), uint256(100_000e18), uint256(1_000_000e18), uint256(10_000_000e18), uint256(100_000_000e18), uint256(1_000_000_000e18)];
    uint256[4] memory limits;
    for (uint256 i = 0; i < tvls.length; i++) {
      console.log("limits for tvl: %e", tvls[i]);
      limits = riskModel.liquidityLimits(tvls[i]);
      for (uint256 j = 0; j < limits.length; j++) {
        console.log("-> limit[%s]: %e", j, limits[j]);
      }
      assertLt(limits[0], tvls[i]); // allocation trigger (upper band) < tvl
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
    vm.prank(admin);
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

  function testParamsUpdateInvalid() public {
    RiskParams.Strategy memory invalidParams = RiskParams.Strategy({
      defaultSeedUsd: 1e18, // Too low
      defaultDepositCapUsd: 2000000e18, // Too high
      defaultMaxSlippage: 10_00, // Too high
      defaultMaxLeverage: 1_00, // Too low
      minUpkeepInterval: 100 // Too low
    });

    vm.expectRevert(Errors.InvalidData.selector);
    vm.prank(admin);
    riskModel.updateStrategyParams(invalidParams);
  }
}
