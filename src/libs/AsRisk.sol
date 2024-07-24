// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./AsMaths.sol";
import "./AsArrays.sol";
import "../abstract/AsTypes.sol";

// Risk params used by RiskModel
library RiskParams {

  // strategy risk parameters
  struct StrategyScore {
    uint16 performance; // similar to a sharpe but factors-in ops risk ((profit + sse)/(ops risk + market risk))
    uint16 scalability;
    uint16 liquidity;
    uint16 composite;
  }

  struct Strategy {
    // strategy defaults
    uint256 defaultSeedUsd; // default seed for new strategy deployments in USD `WAD`
    uint256 defaultDepositCapUsd; // default deposit cap in denomincated in USD `WAD`
    uint32 defaultMaxSlippage; // used for loans, swaps, stakes... in bps
    uint32 defaultMaxLeverage; // 1x every 100 eg. 5_00 = 5:1 leverage
    uint64 minUpkeepInterval; // in sec, eg. 86_400 = 1 day
  }

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

  // NB: to understand all the below risk params, refer to the risk model docs or directly to AsRisk.sol
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
}

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
   * @notice Computes the composite score from an array of scores
   * @dev Uses the specified average type to compute the composite score
   * @param _scores An array of 3 scores: [performance, scalability, liquidity]
   * @param _averageType AverageType
   * @return Composite score as a uint16 value
   */
  function compositeScore(
    uint16[3] memory _scores,
    AverageType _averageType
  ) internal pure returns (uint16) {
    unchecked {
      if (_averageType == AverageType.GEOMETRIC) {
        uint256 product = 1;
        uint256 length = _scores.length;
        for (uint256 i = 0; i < length; i++) {
          product *= _scores[i]; // max == 10_000 ** 3, safe
        }
        return uint16(AsMaths.cbrt(uint256(product))); // nth root of the product
      } else if (_averageType == AverageType.ARITHMETIC) {
        return
          uint16(
            (uint256(_scores[0]) + uint256(_scores[1]) + uint256(_scores[2])) /
              _scores.length
          );
      } else if (_averageType == AverageType.HARMONIC) {
        uint256 sum = 0;
        uint256 length = _scores.length;
        for (uint256 i = 0; i < length; i++) {
          sum += 1e18 / uint256(_scores[i]);
        }
        return uint16(length / sum);
      } else {
        revert Errors.NonImplemented();
      }
    }
  }

  function compositeScore(
    RiskParams.StrategyScore memory _score,
    AverageType _averageType
  ) internal pure returns (uint16) {
    return
      compositeScore(
        [_score.performance, _score.scalability, _score.liquidity],
        _averageType
      );
  }

  function compositeScore(
    uint16[3] memory _scores
  ) internal pure returns (uint16) {
    return compositeScore(_scores, AverageType.GEOMETRIC);
  }

  function compositeScore(
    RiskParams.StrategyScore memory _score
  ) internal pure returns (uint16) {
    return compositeScore(_score, AverageType.GEOMETRIC);
  }

  /**
   * @notice Computes a StrategyScore structure from an array of scores
   * @param _scores An array of 3 scores: [performance, scalability, liquidity]
   * @return A StrategyScore structure with calculated value score
   */
  function computeStrategyScore(
    uint16[3] memory _scores
  ) internal pure returns (RiskParams.StrategyScore memory) {
    unchecked {
      for (uint256 i = 0; i < _scores.length; i++) {
        if (_scores[i] > MAX_SCORE) {
          revert Errors.InvalidData();
        }
      }
    }
    RiskParams.StrategyScore memory score = RiskParams.StrategyScore({
      performance: _scores[0],
      scalability: _scores[1],
      liquidity: _scores[2],
      composite: compositeScore(_scores)
    });
    return score;
  }

  /**
   * @notice Calculates the target allocation for a strategy based on strategy scores
   * @param _scores Scores for each strategy
   * @param _amount Total amount to be allocated
   * @param _maxAllocRatio Maximum allocation ratio per strategy in `WAD` eg. 5e17 == 50%
   * @param _scoreExponent Exponent used to adjust allocation based on scores
   * @return Calculated allocation for each strategy
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

    uint256[] memory weightedScores;
    uint256 totalWeightedScore = 0;

    for (uint256 i = 0; i < _scores.length; i++) {
      // inflate/deflate the allocation of high scores based on scoreExponent
      weightedScores[i] = uint256(
        int256(uint256(_scores[i]) * 1e18).powWad(int256(_scoreExponent))
      );
      totalWeightedScore += weightedScores[i];
    }

    return
      distributeCompositeAllocation(
        weightedScores,
        _amount,
        (_maxAllocRatio * _amount) / AsMaths.BP_BASIS,
        totalWeightedScore,
        new uint256[](_scores.length)
      );
  }

  /**
   * @notice Distributes the allocation based on weighted scores
   * @param _weightedScores Weighted scores for each strategy
   * @param _amount Total amount to be allocated
   * @param _maxAlloc Maximum allocation per strategy
   * @param _totalWeightedScore Total of all weighted scores
   * @param _allocations Current allocations
   * @return Updated allocations for each strategy
   */
  function distributeCompositeAllocation(
    uint256[] memory _weightedScores,
    uint256 _amount,
    uint256 _maxAlloc,
    uint256 _totalWeightedScore,
    uint256[] memory _allocations
  ) internal pure returns (uint256[] memory) {
    unchecked {
      if (_totalWeightedScore == 0) {
        for (uint256 i = 0; i < _weightedScores.length; i++) {
          _totalWeightedScore += _weightedScores[i]; // we don't use AsArrays.sum() to cast and not overflow
        }
      }

      for (uint256 i = 0; i < _weightedScores.length; i++) {
        _allocations[i] += (_weightedScores[i] * _amount) / _totalWeightedScore;
      }

      uint256 excess = 0;
      for (uint256 i = 0; i < _allocations.length; i++) {
        if (_allocations[i] > _maxAlloc) {
          excess += _allocations[i] - _maxAlloc;
          _allocations[i] = _maxAlloc;
        }
      }

      if (excess <= 0) {
        return _allocations;
      }

      // Reallocate excess liquidity
      uint256 totalWeightBelowMax = 0;
      for (uint256 i = 0; i < _allocations.length; i++) {
        if (_allocations[i] < _maxAlloc) {
          totalWeightBelowMax += _weightedScores[i];
        }
      }

      if (totalWeightBelowMax == 0) {
        return _allocations;
      }
      return
        distributeCompositeAllocation(
          _weightedScores,
          excess,
          _maxAlloc,
          totalWeightBelowMax,
          _allocations
        );
    }
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
    return _tvlFactor * uint256(int256(_tvl).powWad(int256(_tvlExponent)));
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
   * @notice Calculates the target liquidity ratio for a vault
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum liquidity (cash) ratio eg. .075 * 1e18
   * @param _tvlFactor Factor applied to TVL in `WAD` eg. .03 * 1e18
   * @param _tvlExponent Exponent applied to TVL in `WAD` eg. .3 * 1e18
   * @return Calculated target liquidity ratio in `WAD` (1e18 == 100%)
   */
  function targetLiquidityRatio(
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (uint256) {
    return
      _minRatio +
      ((1e18 - _minRatio) *
        uint256(
          int256(1e18 + _tvl * _tvlFactor).powWad(-int256(_tvlExponent))
        )) /
      1e18;
  }

  /**
   * @notice Calculates the target allocation ratio for a vault
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum ratio
   * @param _tvlFactor Factor applied to TVL in `WAD`
   * @param _tvlExponent Exponent applied to TVL in `WAD`
   * @return Calculated target allocation ratio in `WAD` (1e18 == 100%)
   */
  function targetAllocationRatio(
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (uint256) {
    return
      1e18 - targetLiquidityRatio(_tvl, _minRatio, _tvlFactor, _tvlExponent);
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
   * @notice Calculates the liquidation trigger ratio for a vault
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum ratio in `WAD` (eg. .005 * 1e18 == 0.5%)
   * @param _tvlFactor Factor applied to TVL in `WAD` (eg. .1 * 1e18 == 10%)
   * @param _tvlExponent Exponent applied to TVL in `WAD` (eg. .45 * 1e18 == 45%)
   * @return Calculated liquidation trigger ratio in `WAD`
   */
  function liquidationTriggerRatio(
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (uint256) {
    return
      _minRatio +
      ((1e18 - _minRatio) *
        uint256(
          int256(1e18 + _tvl * _tvlFactor).powWad(-int256(_tvlExponent))
        )) /
      1e18;
  }

  /**
   * @notice Calculates the liquidation trigger for a vault
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum ratio in `WAD` (eg. .005 * 1e18 == 0.5%)
   * @param _tvlFactor Factor applied to TVL in `WAD` (eg. .1 * 1e18 == 10%)
   * @param _tvlExponent Exponent applied to TVL in `WAD` (eg. .45 * 1e18 == 45%)
   * @return Calculated liquidation trigger in `WAD`
   */
  function liquidationTrigger(
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (uint256) {
    return
      (_tvl *
        liquidationTriggerRatio(_tvl, _minRatio, _tvlFactor, _tvlExponent)) /
      1e18;
  }

  /**
   * @notice Calculates the panic liquidation trigger ratio for a vault
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum ratio in `WAD` (eg. .006 * 1e18 == 0.6%)
   * @param _tvlFactor Factor applied to TVL in `WAD` (eg. .1 * 1e18 == 10%)
   * @param _tvlExponent Exponent applied to TVL in `WAD` (eg. .4 * 1e18 == 40%)
   * @return Calculated panic liquidation trigger ratio in `WAD`
   */
  function panicTriggerRatio(
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (uint256) {
    return
      2 * liquidationTriggerRatio(_tvl, _minRatio, _tvlFactor, _tvlExponent);
  }

  /**
   * @notice Calculates the panic liquidation trigger for a vault
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum ratio in `WAD` (eg. .006 * 1e18 == 0.6%)
   * @param _tvlFactor Factor applied to TVL in `WAD` (eg. .1 * 1e18 == 10%)
   * @param _tvlExponent Exponent applied to TVL in `WAD` (eg. .4 * 1e18 == 40%)
   * @return Calculated panic liquidation trigger in `WAD`
   */
  function panicTrigger(
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (uint256) {
    return
      (_tvl * panicTriggerRatio(_tvl, _minRatio, _tvlFactor, _tvlExponent)) /
      1e18;
  }

  /**
   * @notice Calculates the allocation trigger ratio for a vault
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum ratio in `WAD` (eg. .005 * 1e18 == 0.5%)
   * @param _tvlFactor Factor applied to TVL in `WAD` (eg. .1 * 1e18 == 10%)
   * @param _tvlExponent Exponent applied to TVL in `WAD` (eg. .47 * 1e18 == 47%)
   * @return Calculated allocation trigger ratio in `WAD` (1e18 == 100%)
   */
  function allocationTriggerRatio(
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (uint256) {
    return liquidationTriggerRatio(_tvl, _minRatio, _tvlFactor, _tvlExponent);
  }

  /**
   * @notice Calculates the allocation trigger for a vault
   * @param _tvl Total value locked in the vault
   * @param _minRatio Minimum ratio in `WAD` (eg. .005 * 1e18 == 0.5%)
   * @param _tvlFactor Factor applied to TVL in `WAD` (eg. .1 * 1e18 == 10%)
   * @param _tvlExponent Exponent applied to TVL in `WAD` (eg. .47 * 1e18 == 47%)
   * @return Calculated allocation trigger in `WAD`
   */
  function allocationTrigger(
    uint256 _tvl,
    uint256 _minRatio,
    uint256 _tvlFactor,
    uint256 _tvlExponent
  ) internal pure returns (uint256) {
    return
      (_tvl *
        allocationTriggerRatio(_tvl, _minRatio, _tvlFactor, _tvlExponent)) /
      1e18;
  }
}
