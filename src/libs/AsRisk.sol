// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./AsMaths.sol";
import "./AsArrays.sol";
import "../abstract/AsTypes.sol";
import {console} from "forge-std/console.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title RiskParams+AsRisk Libraries - Astrolab's Risk management library
 * @author Astrolab DAO
 * @notice RiskParams defined all risk parameters used internally by RiskModel
 * @notice AsRisk provides the core risk-related logic used by RiskModel and by the Botnet
 */
library RiskParams {
  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  // liquidity (requirements & triggers)
  struct Liquidity {
    uint32 minRatio; // minimum liquidity ratio (eg. 9_00 == 9%)
    uint32 factor; // geometrically decreases towards ratio (usually increases risk), in bps
    uint32 exponent; // exponentially decreases towards ratio (usually increases risk), in bps
  }

  // scoring (methodology)
  struct Scoring {
    AverageType mean; // geometric/arithmetic/harmonic/quadratic/exponential
    uint32 exponent; // used to convert scores into weights (diversification bias), in bps eg. 20_000 == 2.0
  }

  // diversification (minima & bias)
  struct Diversification {
    uint32 minRatio; // minimum allocation ratio per strategy in bps eg. 2_00 == 2%
    uint32 minMaxRatio; // minimum maximum allocation ratio (floor, eg. 25_00 == 25% max minimum on the basket MVP, lowers the diversification bias)
    uint32 exponent; // exponentially reduces max allocation ratio (from 100% when _strategyCount = 1) down to minMaxAllocationRatio, in bps
  }

  // collateralization (levels & isolation)
  struct Collateralization {
    uint32 defaultLtv; // default asset collat factor in bps. eg. 90_00 == 90%
    uint32 maxLtv; // max asset collat factor in bps. eg. 98_00 == 98%
    bool isolated; // if false, cross-collateralization is enabled (eg. acETH can be used to mint asUSD, acUSD to mint asETH, at increased risk of liquidation)
  }

  // strategy risk parameters
  // NB: updating these is critical and requires a cScore() update
  struct StrategyScore {
    uint16 performance; // profit * sse
    uint16 safety; // ops risk (audits/track record/governance/team/off-chain risks) + market risk (underlyings volatility/liquidity)
    uint16 scalability;
    uint16 liquidity;
    uint16 composite;
  }

  // strategy initialization defaults
  struct Strategy {
    uint256 defaultSeedUsd; // default seed for new strategy deployments in USD `WAD`
    uint256 defaultDepositCapUsd; // default deposit cap in denomincated in USD `WAD`
    uint32 defaultMaxSlippage; // used for loans, swaps, stakes... in bps
    uint32 defaultMaxLeverage; // 1x every 100 eg. 5_00 = 5:1 leverage
    uint64 minUpkeepInterval; // in sec, eg. 86_400 = 1 day
  }

  // allocation model (refer to the risk model docs or directly to AsRisk.sol)
  struct Allocation {
    Scoring scoring; // scoring methodology
    Diversification diversification; // diversification (minima & bias)
    Liquidity harvestTrigger; // trailing profits/rewards harvesting
    Liquidity targetLiquidity; // liquidity target: gravity center/netting zone
    Liquidity allocationTrigger; // liquidity upper band (soft ceil): allocation
    Liquidity liquidationTrigger; // liquidity lower band: liquidation
    Liquidity panicTrigger; // liquidity 2nd lower band (hard floor): hard-liquidation
  }

  // stable minting
  struct StableMint {
    // collateralization
    Collateralization compositeCollateral;
    Collateralization primitiveCollateral;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            CONSTANTS                           ║
  ╚═══════════════════════════════════════════════════════════════*/

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Returns the default strategy parameters
   * @return A Strategy structure with default values
   */
  function defaultStrategy() internal pure returns (Strategy memory) {
    return
      Strategy({
        defaultSeedUsd: 10e18,
        defaultDepositCapUsd: 2_000_000e18,
        defaultMaxSlippage: 200, // 2% (bps)
        defaultMaxLeverage: 500, // 5:1 (base 100)
        minUpkeepInterval: 604_800 // 7 days (sec)
      });
  }

  /**
   * @notice Returns the default allocation parameters
   * @return An Allocation structure with default values
   */
  function defaultAllocation() internal pure returns (Allocation memory) {
    return
      Allocation({
        scoring: Scoring({mean: AverageType.GEOMETRIC, exponent: 1.8614e4}),
        diversification: Diversification({
          minRatio: 0, // 0% (bps) min to LVP
          minMaxRatio: 25_00, // 25% (bps) min to MVP
          exponent: 3000 // 30% (bps)
        }),
        harvestTrigger: Liquidity({
          minRatio: 0, // unused by harvest liquidity regressor
          factor: 5500, // .55
          exponent: 4000 // .4
        }),
        targetLiquidity: Liquidity({
          minRatio: 700, // 7%
          factor: 500, // .05
          exponent: 3500 // .35
        }),
        allocationTrigger: Liquidity({
          minRatio: 50, // .5%
          factor: 1000, // .1
          exponent: 4000 // .4
        }),
        liquidationTrigger: Liquidity({
          minRatio: 50, // .5%
          factor: 1000, // .1
          exponent: 4500 // .45
        }),
        panicTrigger: Liquidity({
          minRatio: 120, // .012
          factor: 1000, // .1
          exponent: 4000 // .4
        })
      });
  }

  /**
   * @notice Returns the default collateralization parameters
   * @return A Collateralization structure with default values
   */
  function defaultCollateralization()
    internal
    pure
    returns (Collateralization memory)
  {
    return
      Collateralization({defaultLtv: 90_00, maxLtv: 98_00, isolated: true});
  }

  /**
   * @notice Returns the default stable mint parameters
   * @return A StableMint structure with default values
   */
  function defaultStableMint() internal pure returns (StableMint memory) {
    return
      StableMint({
        compositeCollateral: defaultCollateralization(),
        primitiveCollateral: defaultCollateralization()
      });
  }
}

// actual risk library
library AsRisk {
  using AsMaths for uint256;
  using AsMaths for int256;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /*═══════════════════════════════════════════════════════════════╗
  ║                            CONSTANTS                           ║
  ╚═══════════════════════════════════════════════════════════════*/

  uint256 internal constant SCORE_BASIS = AsMaths.BP_BASIS;
  uint16 internal constant MAX_SCORE = 100;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Computes the composite score (C-Score) from an array of scores
   * @dev Uses the specified average type to compute the composite score
   * @param _scores An array of 3 scores: [performance, scalability, liquidity]
   * @param _averageType AverageType
   * @return Composite score as a uint16 value
   */
  function cScore(
    uint16[] memory _scores,
    uint256 _boundary,
    AverageType _averageType
  ) internal pure returns (uint16) {
    // geometrically merge performance and risk scores (risk-adjusted performance)
    unchecked {
      uint256 n = AsMaths.min(_scores.length, _boundary);
      if (_averageType == AverageType.GEOMETRIC) {
        uint256 product = 1;
        for (uint256 i = 0; i < n; i++) {
          product *= _scores[i]; // max == 10_000 ** 3, safe
        }
        return uint16((uint256(product) * 1e18).nrtWad(n) / 1e18); // nth root of the product
      } else if (_averageType == AverageType.ARITHMETIC) {
        uint16 sum = 0;
        for (uint256 i = 0; i < n; i++) {
          sum += _scores[i];
        }
        return uint16(sum / n);
      } else if (_averageType == AverageType.HARMONIC) {
        uint256 sum = 0;
        for (uint256 i = 0; i < n; i++) {
          sum += 1e18 / uint256(_scores[i]);
        }
        return uint16((n * 1e18) / sum);
      } else {
        revert Errors.NonImplemented();
      }
    }
  }

  /**
   * @notice Computes the composite score (C-Score) from an array of scores using the default average type (GEOMETRIC)
   * @param _scores An array of scores
   * @param _boundary Maximum number of scores to use
   * @return Composite score as a uint16 value
   */
  function cScore(
    uint16[] memory _scores,
    uint256 _boundary
  ) internal pure returns (uint16) {
    return cScore(_scores, _boundary, AverageType.GEOMETRIC);
  }

  function cScore(
    RiskParams.StrategyScore memory _score,
    AverageType _averageType
  ) internal pure returns (uint16) {
    return
      cScore(
        AsArrays.toArray16(
          _score.performance,
          _score.safety,
          _score.scalability,
          _score.liquidity
        ),
        4,
        _averageType
      );
  }

  function cScore(
    RiskParams.StrategyScore memory _score
  ) internal pure returns (uint16) {
    return cScore(_score, AverageType.GEOMETRIC);
  }

  function cScore(
    uint16[] memory _scores
  ) internal pure returns (uint16) {
    return cScore(_scores, _scores.length, AverageType.GEOMETRIC);
  }

  function cScore(
    uint16[] memory _scores,
    AverageType _averageType
  ) internal pure returns (uint16) {
    return cScore(_scores, _scores.length, _averageType);
  }

  /**
   * @notice Computes a StrategyScore structure from an array of scores
   * @param _scores An array of 4 scores: [performance, safety, scalability, liquidity]
   * @return A StrategyScore structure with calculated value score
   */
  function computeStrategyScore(
    uint16[] memory _scores,
    AverageType _averageType
  ) internal pure returns (RiskParams.StrategyScore memory) {
    uint256 n = _scores.length;
    if (n < 4) {
      revert Errors.InvalidData();
    }
    unchecked {
      for (uint256 i = 0; i < n; i++) {
        if (_scores[i] > MAX_SCORE) {
          revert Errors.InvalidData(); // scores should be within [0, 100]
        }
      }
    }
    RiskParams.StrategyScore memory score = RiskParams.StrategyScore({
      performance: _scores[0],
      safety: _scores[1],
      scalability: _scores[2],
      liquidity: _scores[3],
      composite: cScore(_scores, 4, _averageType)
    });
    return score;
  }

  /**
   * @notice Calculates the target allocation for a strategy based on strategy scores
   * @param _scores Scores for each strategy
   * @param _amount Total amount to be allocated
   * @param _maxAllocRatio Maximum allocation ratio per strategy in `WAD` eg. 5e17 == 50%
   * @param _scoreExponent Exponent used to adjust allocation based on scores
   * @return weightedScores Calculated allocation for each strategy
   */
  function targetCompositeAllocation(
    uint16[] memory _scores,
    uint256 _amount,
    uint256 _maxAllocRatio,
    uint256 _scoreExponent // used to convert scores into weights (diversification bias), in `WAD` e.g., 1.8614 * 1e18
  ) internal pure returns (uint256[] memory) {
    if (_maxAllocRatio > AsMaths.BP_BASIS) {
      revert Errors.InvalidData();
    }
    (uint256 totalWeightedScore, uint256 i, uint256 j) = (0, 0, 0);
    uint256[] memory weightedScores = new uint256[](_scores.length);

    unchecked {
      // alculate initial weighted scores
      for (j = 0; j < _scores.length; j++) {
        weightedScores[j] = uint256(
          int256(uint256(_scores[j]) * 1e18).powWad(int256(_scoreExponent))
        );
        totalWeightedScore += weightedScores[j];
      }

      bool needsRebalancing = true;

      while (needsRebalancing && i < 10) {
        needsRebalancing = false;
        uint256 excessWeight = 0;
        uint256 remainingWeight = 0;

        // Check for weights exceeding maxAllocRatio and calculate excess
        for (j = 0; j < weightedScores.length; j++) {
          uint256 ratio = (weightedScores[j] * AsMaths.BP_BASIS) /
            totalWeightedScore;
          if (ratio > _maxAllocRatio) {
            uint256 cappedWeight = (_maxAllocRatio * totalWeightedScore) /
              AsMaths.BP_BASIS;
            excessWeight += weightedScores[j] - cappedWeight;
            totalWeightedScore -= weightedScores[j] - cappedWeight;
            weightedScores[j] = cappedWeight;
            needsRebalancing = true;
          } else {
            remainingWeight += weightedScores[j];
          }
        }

        // redistribute excess weight
        if (excessWeight > 0 && remainingWeight > 0) {
          for (j = 0; j < weightedScores.length; j++) {
            uint256 ratio = (weightedScores[i] * AsMaths.BP_BASIS) /
              totalWeightedScore;
            if (ratio <= _maxAllocRatio) {
              uint256 additionalWeight = (excessWeight * weightedScores[j]) /
                remainingWeight;
              weightedScores[j] += additionalWeight;
              totalWeightedScore += additionalWeight;
            }
          }
        }

        i++;
      }

      // calculate allocations from weighted scores
      uint256[] memory allocations = new uint256[](_scores.length);
      for (i = 0; i < _scores.length; i++) {
        allocations[i] = (_amount * weightedScores[i]) / totalWeightedScore;
      }

      return allocations;
    }
  }

  /**
   * @notice Calculates the maximum allocation ratio for a single strategy in a composite/basket/index
   * @param _strategyCount Number of strategies in the composite/basket/index
   * @param _minMaxAlloc Minimum maximum allocation ratio (floor, eg. .25 * 1e18 == 25% max minimum on the basket MVP, lowers the diversification bias)
   * @param _exponent Exponent applied to the number of strategies (diversification bias)
   * @return Calculated maximum allocation ratio in `WAD` (1e18 == 100%)
   */
  function maxAllocationRatio(
    uint256 _strategyCount,
    uint256 _minMaxAlloc,
    uint256 _exponent
  ) internal pure returns (uint256) {
    return
      _minMaxAlloc +
      uint256(int256(int256(_strategyCount) * -int256(_exponent)).expWad());
  }

  /**
   * @notice Calculates the harvest to cost ratio for a strategy (slippage + gas price * gas units of harvesting == total fee)
   * @param _tvl Total value locked in the strategy
   * @param _tvlFactor Factor applied to TVL in `WAD` eg. .55 * 1e18
   * @param _tvlExponent Exponent applied to TVL in `WAD` eg. .4 * 1e18
   * @return Calculated ratio in `WAD` (1e18 == 100%)
   */
  function minHarvestToCostRatio(
    uint256 _tvl,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (uint256) {
    return
      (_tvlFactor * uint256(int256(_tvl).powWad(int256(_tvlExponent)))) /
      1e18;
  }

  /**
   * @notice Determines whether a strategy should be harvested based on reward and cost
   * @param _reward Pending strategy rewards to be harvested
   * @param _cost Cost of harvesting the strategy
   * @param _tvl Total value locked in the strategy
   * @param _tvlFactor Factor applied to TVL in `WAD` eg. .55 * 1e18
   * @param _tvlExponent Exponent applied to TVL in `WAD` eg. .4 * 1e18
   * @return True if the strategy should be harvested, false otherwise
   */
  function shouldHarvest(
    uint256 _reward,
    uint256 _cost,
    uint256 _tvl,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (bool) {
    return
      _reward >=
      ((_cost * minHarvestToCostRatio(_tvl, _tvlFactor, _tvlExponent)) / 1e18);
  }

  /**
   * @notice This function is the basis for our allocation and liquidation triggers
   * This regressor exhibits a non-linear relationship between TVL and the calculated trigger ratio
   * with behavior reminiscent of exponential decay
   *
   * Properties:
   * - Monotonic+Asymptotic: As TVL increases, the ratio decreases towards _minRatio (given positive _tvlFactor and _tvlExponent)
   * - Bounded: The ratio will always be between _minRatio and 1 (1e18)
   *
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum ratio in `WAD`
   * @param _tvlFactor Factor applied to TVL in `WAD`
   * @param _tvlExponent Exponent applied to TVL in `WAD`
   * @return Calculated regressor value in `WAD`
   */
  function liquidityRatioRegressor(
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (uint256) {
    unchecked {
      uint256 base = 1e18 + (_tvl * _tvlFactor) / 1e18; // (1 + tvl * tvlFactor) in WAD
      uint256 power = uint256(int256(base).powWad(-int256(_tvlExponent)));
      return _minRatio + ((1e18 - _minRatio) * power) / 1e18;
    }
  }

  /**
   * @notice Calculates the liquidity regressor value based on the given parameters
   * @dev This function uses the liquidity regressor ratio to compute the value
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum ratio in `WAD`
   * @param _tvlFactor Factor applied to TVL in `WAD`
   * @param _tvlExponent Exponent applied to TVL in `WAD`
   * @return Calculated liquidity regressor value in `WAD`
   */
  function liquidityValueRegressor(
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (uint256) {
    return
      (_tvl *
        liquidityRatioRegressor(_tvl, _minRatio, _tvlFactor, _tvlExponent)) /
      1e18;
  }

  /**
   * @notice Determines whether the liquidity is above the regressor
   * @param _excessLiquidity Current excess liquidity vs target
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum ratio in `WAD` (eg. .005 * 1e18 == 0.5%)
   * @param _tvlFactor Factor applied to TVL in `WAD` (eg. .1 * 1e18 == 10%)
   * @param _tvlExponent Exponent applied to TVL in `WAD` (eg. .45 * 1e18 == 45%)
   * @return True if the liquidity is above the regressor, false otherwise
   */
  function aboveLiquidityRegressor(
    uint256 _excessLiquidity,
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (bool) {
    return
      _excessLiquidity >=
      liquidityValueRegressor(_tvl, _minRatio, _tvlFactor, _tvlExponent);
  }

  /**
   * @notice Determines whether the liquidity is below the regressor
   * @param _excessLiquidity Current liquidity in the vault
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum ratio in `WAD` (eg. .005 * 1e18 == 0.5%)
   * @param _tvlFactor Factor applied to TVL in `WAD` (eg. .1 * 1e18 == 10%)
   * @param _tvlExponent Exponent applied to TVL in `WAD` (eg. .45 * 1e18 == 45%)
   * @return True if the liquidity is below the regressor, false otherwise
   */
  function belowLiquidityRegressor(
    uint256 _excessLiquidity,
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (bool) {
    return
      _excessLiquidity <=
      liquidityValueRegressor(_tvl, _minRatio, _tvlFactor, _tvlExponent);
  }
}
