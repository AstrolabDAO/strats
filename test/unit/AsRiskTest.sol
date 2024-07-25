// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../../src/libs/AsRisk.sol";

contract AsRiskTest is Test {
  using AsRisk for *;
  using AsMaths for *;
  using AsArrays for *;

  uint16[] public scores1 = AsArrays.toArray16(80, 30, 90, 40);
  uint16[] public scores2 = AsArrays.toArray16(80, 30, 90, 40);

  function setUp() public {
    // Setup code if needed
  }

  function testCompositeScore() public {
    assertApproxEqAbs(AsRisk.cScore(scores1, AverageType.ARITHMETIC), 60, 1); // allow truncation/rounding
    assertApproxEqAbs(AsRisk.cScore(scores1, AverageType.GEOMETRIC), 54, 1);
    assertApproxEqAbs(AsRisk.cScore(scores1, AverageType.HARMONIC), 48, 1);
  }

  function testCompositeScoreFromStrategyScore() public {
    RiskParams.StrategyScore memory score = RiskParams.StrategyScore({
      performance: 80,
      safety: 30,
      scalability: 90,
      liquidity: 40,
      composite: 0
    });
    assertApproxEqAbs(AsRisk.cScore(score, AverageType.GEOMETRIC), 54, 1); // Allow for small rounding differences
  }

  function testTargetCompositeAllocation() public {
    uint16[] memory scores = new uint16[](3);
    (scores[0], scores[1], scores[2]) = (30, 60, 90);
    (uint256 amount, uint256 maxAllocRatio, uint256 scoreExponent) = (
      1000 ether,
      0.8e4,
      1.8614e18
    );

    uint256[] memory allocations = AsRisk.targetCompositeAllocation(
      scores,
      amount,
      maxAllocRatio,
      scoreExponent
    );

    assertApproxEqRel(allocations[0], 80.890268 ether, 1e15);
    assertApproxEqRel(allocations[1], 293.922959 ether, 1e15);
    assertApproxEqRel(allocations[2], 625.186772 ether, 1e15);

    (scores[0], scores[1], scores[2]) = (40, 50, 60);

    allocations = AsRisk.targetCompositeAllocation(
      scores,
      amount,
      maxAllocRatio,
      scoreExponent
    );

    assertApproxEqRel(allocations[0], 215.42633 ether, 1e15);
    assertApproxEqRel(allocations[1], 326.35260 ether, 1e15);
    assertApproxEqRel(allocations[2], 458.22107 ether, 1e15);

    scoreExponent = 2e18;

    allocations = AsRisk.targetCompositeAllocation(
      scores,
      amount,
      maxAllocRatio,
      scoreExponent
    );
    assertApproxEqRel(allocations[0], 207.79220779 ether, 1e15);
    assertApproxEqRel(allocations[1], 324.67532467 ether, 1e15);
    assertApproxEqRel(allocations[2], 467.53246753 ether, 1e15);

    maxAllocRatio = 0.4e4; // 40%
    allocations = AsRisk.targetCompositeAllocation(
      scores,
      amount,
      maxAllocRatio,
      scoreExponent
    );
    assertApproxEqRel(allocations[0], 234.12688111 ether, 1e15);
    assertApproxEqRel(allocations[1], 365.82325173 ether, 1e15);
    assertApproxEqRel(allocations[2], 400.04986715 ether, 1e15);
  }

  function testMaxAllocationRatio() public {
    uint64[4][5] memory cases = [
      // nstrats, minMax, exponent, expected result wad
      [2, 0.25e18, 0.3e18, 0.7988116e18],
      [5, 0.25e18, 0.3e18, 0.4731301e18],
      [10, 0.25e18, 0.3e18, 0.2997870e18],
      [20, 0.25e18, 0.3e18, 0.2524787e18],
      [50, 0.25e18, 0.3e18, 0.2500003e18]
    ];
    for (uint256 i = 0; i < cases.length; i++) {
      assertApproxEqRel(
        AsRisk.maxAllocationRatio(cases[i][0], cases[i][1], cases[i][2]),
        cases[i][3],
        1e15
      );
    }
  }

  function testMinHarvestToCostRatio() public {
    uint256[4][6] memory cases = [
      [uint256(1000e18), 0.55e18, 0.4e18, 8.7169125e18], // 8.7x harvest reward to cost for $1k tvl
      [uint256(10_000e18), 0.55e18, 0.4e18, 21.895894e18], // 21.9x harvest reward to cost for $10k tvl
      [uint256(100_000e18), 0.55e18, 0.4e18, 55.00e18], // 55x harvest reward to cost for $100k tvl
      [uint256(1_000_000e18), 0.55e18, 0.4e18, 138.1537537e18], // 138.15x harvest reward to cost for $1m tvl
      [uint256(10_000_000e18), 0.55e18, 0.4e18, 347.0265394e18], // 347.03x harvest reward to cost for $10m tvl
      [uint256(100_000_000e18), 0.55e18, 0.4e18, 871.6912558e18] // 871.69x harvest reward to cost for $100m tvl
    ];
    for (uint256 i = 0; i < cases.length; i++) {
      assertApproxEqRel(
        AsRisk.minHarvestToCostRatio(cases[i][0], cases[i][1], cases[i][2]),
        cases[i][3],
        1e15
      );
    }
  }

  function testLiquidityRatioRegressor() public {
    uint256[5][9] memory cases = [
      // tvl, minMax, exponent, expected result wad
      [uint256(1e18), 0.05e18, 0.05e18, 0.32e18, 0.99161298e18], // 99% cash for $1 tvl
      [uint256(10e18), 0.05e18, 0.05e18, 0.32e18, 0.92809317e18], // 92.8% cash for $10 tvl
      [uint256(100e18), 0.05e18, 0.05e18, 0.32e18, 0.676766257e18], // 67.67% cash for $100 tvl
      [uint256(1000e18), 0.05e18, 0.05e18, 0.32e18, 0.389090089e18], // 38.9% cash for $1k tvl
      [uint256(10_000e18), 0.05e18, 0.05e18, 0.32e18, 0.22145638e18], // 22.1% cash for $10k tvl
      [uint256(100_000e18), 0.05e18, 0.05e18, 0.32e18, 0.13600898e18], // 13.6% cash for $100k tvl
      [uint256(1_000_000e18), 0.05e18, 0.05e18, 0.32e18, 0.9311048e18], // 9.31% cash for $1m tvl
      [uint256(10_000_000e18), 0.05e18, 0.05e18, 0.32e18, 0.71606618e18], // 7.16% cash for $10m tvl
      [uint256(100_000_000e18), 0.05e18, 0.05e18, 0.32e18, 0.60828971e18] // 6.08% cash for $100m tvl
    ];
    for (uint256 i = 0; i < cases.length; i++) {
      assertApproxEqRel(
        AsRisk.liquidityRatioRegressor(
          cases[i][0],
          cases[i][1],
          cases[i][2],
          cases[i][3]
        ),
        cases[i][4],
        1e20
      );
    }
  }
}
