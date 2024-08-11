// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../libs/AsMaths.sol";
import "../libs/AsRisk.sol";
import "../access-control/AsManageable.sol";
import "../interfaces/IStrategyV5.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title RiskModel - Astrolab DAO risk framework
 * @author Astrolab DAO
 * @notice Dictates how strategies are evaluated, allocated to, and rebalanced
 */
contract RiskModel is AsManageable {
  using AsMaths for uint256;
  using AsMaths for uint32;
  using AsMaths for uint64;
  using AsRisk for uint64;

  /*═══════════════════════════════════════════════════════════════╗
  ║                             EVENTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  event StrategyScoreUpdated(
    IStrategyV5 indexed strategy,
    RiskParams.StrategyScore score
  );
  event CollateralizationUpdated(
    IStrategyV5 indexed strategy,
    RiskParams.Collateralization collateralization
  );
  event StrategyParamsUpdated(RiskParams.Strategy params);
  event AllocationParamsUpdated(RiskParams.Allocation params);
  event StableMintParamsUpdated(RiskParams.StableMint params);

  /*═══════════════════════════════════════════════════════════════╗
  ║                            CONSTANTS                           ║
  ╚═══════════════════════════════════════════════════════════════*/

  /*═══════════════════════════════════════════════════════════════╗
  ║                             STORAGE                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  mapping(IStrategyV5 => RiskParams.StrategyScore) public scoreByStrategy;
  mapping(IStrategyV5 => RiskParams.Collateralization) public collateralizationByStrategy;
  RiskParams.Strategy public strategyParams;
  RiskParams.StableMint public stableMintParams;
  RiskParams.Allocation public allocationParams;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) AsManageable(_accessController) {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Retrieves a composite strategy's primitives
   * @param _strategy Composite strategy
   * @return _primitives Array of primitive strategies
   * @return _boundary Maximum number of primitives to use
   */
  function primitives(
    IStrategyV5 _strategy
  ) public view returns (IStrategyV5[] memory _primitives, uint256 _boundary) {
    _primitives = new IStrategyV5[](8);
    unchecked {
      for (uint256 i = 0; i < 8; i++) {
        if (address(_strategy.inputs(i)) == address(0)) {
          _boundary = i;
          break;
        }
        _primitives[i] = IStrategyV5(address(_strategy.inputs(i)));
      }
    }
  }

  /**
   * @notice Returns the composite scores (C-Score) for a set of strategies
   * @param _primitives Array of strategies
   * @param _boundary Maximum number of primitives to use
   * @return cScores Composite scores for each strategy
   */
  function primitiveCScores(
    IStrategyV5[] memory _primitives,
    uint256 _boundary
  ) public view returns (uint16[] memory cScores) {
    cScores = new uint16[](_boundary);
    unchecked {
      for (uint256 i = 0; i < _boundary; i++) {
        cScores[i] = scoreByStrategy[_primitives[i]].composite;
      }
    }
  }

  /**
   * @notice Returns the composite scores (C-Score) for a composite strategy's primitives
   * @param _composite Composite strategy
   * @return Array of composite scores for each primitive strategy
   */
  function primitiveCScores(
    IStrategyV5 _composite
  ) public view returns (uint16[] memory) {
    (IStrategyV5[] memory _primitives, uint256 _boundary) = primitives(
      _composite
    );
    return primitiveCScores(_primitives, _boundary);
  }

  /**
   * @notice Returns the composite score (C-Score) for a composite strategy
   * Underlying primitives C-Scores are averaged using the composite strategy's allocation params
   * @param _composite Composite strategy
   * @return Composite score for the composite strategy
   */
  function compositeCScore(
    IStrategyV5 _composite
  ) public view returns (uint16) {
    (IStrategyV5[] memory _primitives, uint256 _boundary) = primitives(
      _composite
    );
    return
      AsRisk.cScore(
        primitiveCScores(_primitives, _boundary),
        _boundary,
        allocationParams.scoring.mean
      );
  }

  /**
   * @notice Returns the deposit cap of a strategy
   * @param _strategy Strategy
   * @return Deposit cap in the strategy's asset
   */
  function depositCap(IStrategyV5 _strategy) public view returns (uint256) {
    return _strategy.maxTotalAssets();
  }

  /**
   * @notice Returns the deposit cap of a strategy in USD
   * @param _strategy Strategy
   * @return Deposit cap in USD
   */
  function depositCapUsd(IStrategyV5 _strategy) public view returns (uint256) {
    return
      _strategy.oracle().toUsd(
        address(_strategy.asset()),
        _strategy.maxTotalAssets()
      );
  }

  /**
   * @notice Returns the total value locked (TVL) of a strategy
   * @param _strategy Strategy
   * @return TVL in the strategy's asset
   */
  function strategyTvl(IStrategyV5 _strategy) public view returns (uint256) {
    return _strategy.totalAssets();
  }

  /**
   * @notice Returns the total value locked (TVL) of a strategy in USD e18
   * @param _strategy Strategy
   * @return TVL in USD
   */
  function tvlUsd(IStrategyV5 _strategy) public view returns (uint256) {
    return
      _strategy.oracle().toUsd(
        address(_strategy.asset()),
        _strategy.totalAssets()
      );
  }

  /**
   * @notice Returns the position value of an owner in a strategy in USD e18
   * @param _strategy Strategy
   * @param _owner Owner of the assets
   * @return Position value in USD
   */
  function positionUsd(
    IStrategyV5 _strategy,
    address _owner
  ) public view returns (uint256) {
    return
      _strategy.oracle().toUsd(
        address(_strategy.asset()),
        _strategy.assetsOf(_owner)
      );
  }

  /**
   * @notice Returns the liquidity of a strategy in USD e18
   * @param _strategy Strategy
   * @return Liquidity in USD
   */
  function liquidityUsd(IStrategyV5 _strategy) public view returns (uint256) {
    return
      _strategy.oracle().toUsd(
        address(_strategy.asset()),
        _strategy.available()
      );
  }

  /**
   * @notice Returns the liquidity ratio of a strategy
   * @param _strategy Strategy
   * @return Liquidity ratio
   */
  function liquidityRatio(IStrategyV5 _strategy) public view returns (uint256) {
    return (_strategy.available() * 1e18) / _strategy.totalAssets(); // cash e18
  }

  /**
   * @notice Returns the liquidation request in USD e18 for a strategy
   * @param _strategy Strategy
   * @return Liquidation request in USD
   */
  function liquidationRequestUsd(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      _strategy.oracle().toUsd(
        address(_strategy.asset()),
        _strategy.totalPendingWithdrawRequest()
      );
  }

  /**
   * @notice Calculates the target composition ratios for a set of scores
   * @param _scores Array of scores
   * @return Calculated target composition ratios
   */
  function targetCompositionRatios(
    uint16[] memory _scores
  ) public view returns (uint256[] memory) {
    return
      AsRisk.targetCompositionRatios(
        _scores,
        maxAllocationRatio(_scores.length),
        allocationParams.scoring.exponent.toWad32()
      );
  }

  /**
   * @notice Calculates the target composition ratios for a set of strategies
   * @param _strategies Array of strategies
   * @return Calculated target composition ratios
   */
  function targetCompositionRatios(
    IStrategyV5[] memory _strategies,
    uint256 _boundary
  ) public view returns (uint256[] memory) {
    return
      AsRisk.targetCompositionRatios(
        primitiveCScores(_strategies, _boundary),
        maxAllocationRatio(_boundary),
        allocationParams.scoring.exponent.toWad32()
      );
  }

  /**
   * @notice Calculates the target composition ratios for a composite strategy
   * @param _strategy Composite strategy
   * @return Calculated target composition ratios
   */
  function targetCompositionRatios(
    IStrategyV5 _strategy
  ) public view returns (uint256[] memory) {
    (IStrategyV5[] memory _primitives, uint256 _boundary) = primitives(
      _strategy
    );
    return targetCompositionRatios(_primitives, _boundary);
  }

  /**
   * @notice Calculates the target composition for a set of scores
   * @param _scores Array of scores
   * @param _amount Total amount to be allocated
   * @return Calculated target composition
   */
  function targetComposition(
    uint16[] memory _scores,
    uint256 _amount
  ) public view returns (uint256[] memory) {
    return
      AsRisk.targetComposition(
        _scores,
        _amount,
        maxAllocationRatio(_scores.length),
        allocationParams.scoring.exponent.toWad32()
      );
  }

  /**
   * @notice Calculates the target composite allocation for a set of strategies
   * @param _strategies Array of strategies
   * @param _boundary Maximum number of strategies to use
   * @param _amount Total amount to be allocated
   * @return Target composite allocation for each strategy
   */
  function targetComposition(
    IStrategyV5[] memory _strategies,
    uint256 _boundary,
    uint256 _amount
  ) public view returns (uint256[] memory) {
    return
      AsRisk.targetComposition(
        primitiveCScores(_strategies, _boundary),
        _amount,
        maxAllocationRatio(_boundary),
        allocationParams.scoring.exponent.toWad32()
      );
  }

  /**
   * @notice Calculates the target composite allocation for a composite strategy
   * @param _strategy Composite strategy
   * @param _amount Total amount to be allocated
   * @return Target composite allocation for each strategy
   */
  function targetComposition(
    IStrategyV5 _strategy,
    uint256 _amount
  ) external view returns (uint256[] memory) {
    (IStrategyV5[] memory _primitives, uint256 _boundary) = primitives(
      _strategy
    );
    return targetComposition(_primitives, _boundary, _amount);
  }

  /**
   * @notice Calculates the excess allocation for a set of strategies
   * @param _strategies Array of strategies
   * @param _amount Total amount to be allocated
   * @param _owner Owner of the assets
   * @return Excess allocation for each strategy
   */
  function excessAllocation(
    IStrategyV5[] memory _strategies,
    uint256 _amount,
    address _owner
  ) public view returns (int256[] memory) {
    uint256 boundary = _strategies.length;
    uint256[] memory targets = AsRisk.targetComposition(
      primitiveCScores(_strategies, boundary),
      _amount,
      maxAllocationRatio(boundary),
      allocationParams.scoring.exponent.toWad32()
    ); // USD e18 denominated
    int256[] memory excess = new int256[](boundary);
    unchecked {
      for (uint256 i = 0; i < boundary; i++) {
        excess[i] =
          int256(positionUsd(_strategies[i], _owner)) -
          int256(targets[i]);
      }
    }
    return excess;
  }

  /**
   * @notice Previews the allocation for a set of strategies
   * @param _strategies Array of strategies
   * @param _amount Total amount to be allocated
   * @param _owner Owner of the assets
   * @return Allocation for each strategy
   */
  function previewAllocate(
    IStrategyV5[] memory _strategies,
    uint256 _amount,
    address _owner
  ) external view returns (uint256[] memory) {
    int256[] memory excess = excessAllocation(_strategies, _amount, _owner);
    uint256[] memory allocation = new uint256[](_strategies.length);
    unchecked {
      for (uint256 i = 0; i < _strategies.length; i++) {
        allocation[i] = excess[i] > 0 ? uint256(excess[i]) : 0;
      }
    }
    return allocation;
  }

  /**
   * @notice Calculates the maximum allocation ratio for a given number of strategies
   * @param _strategyCount Number of strategies
   * @return Maximum allocation ratio in `WAD`
   */
  function maxAllocationRatio(
    uint256 _strategyCount
  ) public view returns (uint256) {
    return
      AsRisk.maxAllocationRatio(
        _strategyCount,
        allocationParams.diversification.minMaxRatio.toWad32(),
        allocationParams.diversification.exponent.toWad32()
      );
  }

  /**
   * @notice Calculates the minimum harvest to cost ratio for a given strategy
   * @param _strategy Strategy
   * @return Minimum harvest to cost ratio
   */
  function minHarvestToCostRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      AsRisk.minHarvestToCostRatio(
        tvlUsd(_strategy),
        allocationParams.harvestTrigger.factor.toWad(),
        allocationParams.harvestTrigger.exponent.toWad()
      );
  }

  /**
   * @notice Determines whether a strategy should harvest rewards
   * @param _strategy Strategy
   * @param _pendingRewards Pending rewards in USD
   * @param _costEstimate Cost estimate in USD
   * @return Whether the strategy should harvest rewards
   */
  function shouldHarvest(
    IStrategyV5 _strategy,
    uint256 _pendingRewards,
    uint256 _costEstimate
  ) public view returns (bool) {
    return
      AsRisk.shouldHarvest(
        _pendingRewards,
        _costEstimate,
        tvlUsd(_strategy),
        allocationParams.harvestTrigger.factor.toWad32(),
        allocationParams.harvestTrigger.exponent.toWad32()
      );
  }

  /**
   * @notice Calculates the liquidity ratio regressor for a given TVL and parameters
   * @param _tvl Total value locked in USD e18
   * @param _params Liquidity parameters
   * @return Liquidity ratio regressor in `WAD`
   */
  function _liquidityRatioRegressor(
    uint256 _tvl,
    RiskParams.Liquidity memory _params
  ) internal pure returns (uint256) {
    return
      AsRisk.liquidityRatioRegressor(
        _tvl,
        _params.minRatio.toWad32(),
        _params.factor.toWad32(),
        _params.exponent.toWad32()
      );
  }

  /**
   * @notice Calculates the liquidity value regressor for a given TVL and parameters
   * @param _tvl Total value locked in USD e18
   * @param _params Liquidity parameters
   * @return Liquidity value regressor in USD e18
   */
  function _liquidityValueRegressor(
    uint256 _tvl,
    RiskParams.Liquidity memory _params
  ) internal pure returns (uint256) {
    return (_liquidityRatioRegressor(_tvl, _params) * _tvl) / 1e18;
  }

  /**
   * @notice Calculates the liquidity limit ratio in `WAD`
   * @param _target Target liquidity ratio in `WAD`
   * @param _offset Offset ratio in `WAD`
   * @param _upper Whether it is the upper limit
   * @return Liquidity limit ratio in `WAD`
   */
  function _liquidityLimitRatio(
    uint256 _target,
    uint256 _offset,
    bool _upper
  ) internal pure returns (uint256) {
    unchecked {
      if (_upper) {
        return AsMaths.min(_offset + _target, 1e18); // upper band (allocation threshold) should never exceed 100%
      } else {
        _offset = AsMaths.min(_target.bp(9000), _offset); // lower band (liquidation threshold) should never be less than 20% of liquidity target
        return _target - _offset;
      }
    }
  }

  /**
   * @notice Checks if the liquidity limit is breached
   * @param _current Current liquidity ratio in `WAD`
   * @param _target Target liquidity ratio in `WAD`
   * @param _offset Offset ratio in `WAD`
   * @param _upper Whether it is the upper limit
   * @return Whether the liquidity limit is breached
   */
  function _liquidityLimitBreached(
    uint256 _current,
    uint256 _target,
    uint256 _offset,
    bool _upper
  ) internal pure returns (bool) {
    uint256 band = _liquidityLimitRatio(_target, _offset, _upper);
    return _upper ? _current >= band : _current <= band;
  }

  /**
   * @notice Checks if the liquidity limit is breached for a strategy
   * @param _strategy Strategy
   * @param _offset Offset parameters
   * @param _upperBand Whether it is the upper limit
   * @return Whether the liquidity limit is breached
   */
  function _liquidityLimitBreached(
    IStrategyV5 _strategy,
    RiskParams.Liquidity memory _offset,
    bool _upperBand
  ) internal view returns (bool) {
    uint256 tvl = tvlUsd(_strategy);
    uint256 current = liquidityRatio(_strategy); // e18
    uint256 targetRatio = _liquidityRatioRegressor(
      tvl,
      allocationParams.targetLiquidity
    ); // e18
    uint256 offsetRatio = _liquidityRatioRegressor(tvl, _offset); // e18
    return
      _liquidityLimitBreached(current, targetRatio, offsetRatio, _upperBand);
  }

  /**
   * @notice Returns the liquidity limit ratios for a given TVL
   * @param _tvl Total value locked in USD e18
   * @return Liquidity limit ratios in `WAD`
   */
  function liquidityLimitRatios(
    uint256 _tvl
  ) public view returns (uint256[4] memory) {
    uint256 targetRatio = _liquidityRatioRegressor(
      _tvl,
      allocationParams.targetLiquidity
    ); // e18
    (uint256 aOffset, uint256 lOffset, uint256 pOffset) = (
      _liquidityRatioRegressor(_tvl, allocationParams.allocationTrigger), // e18
      _liquidityRatioRegressor(_tvl, allocationParams.liquidationTrigger), // e18
      _liquidityRatioRegressor(_tvl, allocationParams.panicTrigger) // e18
    );
    return [
      _liquidityLimitRatio(targetRatio, aOffset, true), // upper band (allocation)
      targetRatio, // target liquidity ratio
      _liquidityLimitRatio(targetRatio, lOffset, false), // lower band (liquidation)
      _liquidityLimitRatio(targetRatio, pOffset, false) // 2nd lower band (panic)
    ];
  }

  /**
   * @notice Returns the liquidity limits for a given TVL
   * @param _tvl Total value locked in USD e18
   * @return limits Liquidity limits in USD e18
   */
  function liquidityLimits(
    uint256 _tvl
  ) public view returns (uint256[4] memory limits) {
    uint256[4] memory ratios = liquidityLimitRatios(_tvl);
    unchecked {
      limits[0] = (ratios[0] * _tvl) / 1e18;
      limits[1] = (ratios[1] * _tvl) / 1e18;
      limits[2] = (ratios[2] * _tvl) / 1e18;
      limits[3] = (ratios[3] * _tvl) / 1e18;
    }
    return limits; // in USD e18
  }

  /**
   * @notice Calculates the target liquidity ratio for a given strategy
   * @param _strategy Strategy
   * @return Target liquidity ratio in `WAD`
   */
  function targetLiquidityRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      _liquidityRatioRegressor(
        tvlUsd(_strategy),
        allocationParams.targetLiquidity
      );
  }

  /**
   * @notice Calculates the target liquidity for a given strategy
   * @param _strategy Strategy
   * @return Target liquidity in USD e18
   */
  function targetLiquidity(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      _liquidityValueRegressor(
        tvlUsd(_strategy),
        allocationParams.targetLiquidity
      );
  }

  /**
   * @notice Calculates the target allocation ratio for a given strategy
   * @param _strategy Strategy
   * @return Target allocation ratio in `WAD`
   */
  function targetAllocationRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return 1e18 - targetLiquidityRatio(_strategy);
  }

  /**
   * @notice Calculates the target allocation for a given strategy
   * @param _strategy Strategy
   * @return Target allocation in USD e18
   */
  function targetAllocation(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return (targetAllocationRatio(_strategy) * tvlUsd(_strategy)) / 1e18;
  }

  /**
   * @notice Calculates the liquidation trigger ratio for a given strategy
   * @param _strategy Strategy
   * @return Liquidation trigger ratio in `WAD`
   */
  function liquidationTriggerRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      _liquidityRatioRegressor(
        tvlUsd(_strategy),
        allocationParams.liquidationTrigger
      );
  }

  /**
   * @notice Calculates the liquidation trigger for a given strategy
   * @param _strategy Strategy
   * @return Liquidation trigger in USD e18
   */
  function liquidationTrigger(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      _liquidityValueRegressor(
        tvlUsd(_strategy),
        allocationParams.liquidationTrigger
      );
  }

  /**
   * @notice Determines whether a strategy should be liquidated
   * @param _strategy Strategy
   * @return Whether the strategy should be liquidated
   */
  function shouldLiquidate(IStrategyV5 _strategy) public view returns (bool) {
    return
      _liquidityLimitBreached(
        _strategy,
        allocationParams.liquidationTrigger,
        false
      );
  }

  /**
   * @notice Calculates the panic trigger ratio for a given strategy
   * @param _strategy Strategy
   * @return Panic trigger ratio in `WAD`
   */
  function panicTriggerRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      _liquidityRatioRegressor(
        tvlUsd(_strategy),
        allocationParams.panicTrigger
      );
  }

  /**
   * @notice Calculates the panic trigger for a given strategy
   * @param _strategy Strategy
   * @return Panic trigger in USD e18
   */
  function panicTrigger(IStrategyV5 _strategy) public view returns (uint256) {
    return
      _liquidityValueRegressor(
        tvlUsd(_strategy),
        allocationParams.panicTrigger
      );
  }

  /**
   * @notice Determines whether a strategy should enter panic mode
   * @param _strategy Strategy
   * @return Whether the strategy should enter panic mode
   */
  function shouldPanic(IStrategyV5 _strategy) public view returns (bool) {
    return
      _liquidityLimitBreached(_strategy, allocationParams.panicTrigger, false);
  }

  /**
   * @notice Calculates the allocation trigger ratio for a given strategy
   * @param _strategy Strategy
   * @return Allocation trigger ratio in `WAD`
   */
  function allocationTriggerRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      _liquidityRatioRegressor(
        tvlUsd(_strategy),
        allocationParams.allocationTrigger
      );
  }

  /**
   * @notice Calculates the allocation trigger for a given strategy
   * @param _strategy Strategy
   * @return Allocation trigger in USD e18
   */
  function allocationTrigger(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      _liquidityValueRegressor(
        tvlUsd(_strategy),
        allocationParams.allocationTrigger
      );
  }

  /**
   * @notice Determines whether a strategy should allocate more funds
   * @param _strategy Strategy
   * @return Whether the strategy should allocate more funds
   */
  function shouldAllocate(IStrategyV5 _strategy) public view returns (bool) {
    return
      _liquidityLimitBreached(
        _strategy,
        allocationParams.allocationTrigger,
        true
      );
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             METHODS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Internal function to update the score of a strategy
   * @param _strategy Strategy
   * @param _performance Performance score
   * @param _safety Safety score
   * @param _scalability Scalability score
   * @param _liquidity Liquidity score
   */
  function _updateScore(
    IStrategyV5 _strategy,
    uint16 _performance,
    uint16 _safety,
    uint16 _scalability,
    uint16 _liquidity
  ) internal {
    RiskParams.StrategyScore memory _score = AsRisk.computeStrategyScore(
      AsArrays.toArray16(_performance, _safety, _scalability, _liquidity),
      allocationParams.scoring.mean
    );
    scoreByStrategy[_strategy] = _score;
    emit StrategyScoreUpdated(_strategy, _score);
  }

  /**
   * @notice Internal function to update the score of a strategy using score data
   * @param _strategy Strategy
   * @param _scoreData Score data
   */
  function _updateScore(
    IStrategyV5 _strategy,
    bytes calldata _scoreData
  ) internal {
    (
      uint16 _perf,
      uint16 _safety,
      uint16 _scalability,
      uint16 _liquidity
    ) = AsRisk.decodePackedScores(_scoreData);
    _updateScore(_strategy, _perf, _safety, _scalability, _liquidity);
  }

  /**
   * @notice Updates the score of a strategy
   * @param _strategy Strategy
   * @param _scoreData Score data
   */
  function updateScore(
    IStrategyV5 _strategy,
    bytes calldata _scoreData
  ) external onlyManager whenNotPaused {
    _updateScore(_strategy, _scoreData);
  }

  /**
   * @notice Updates the scores of multiple strategies
   * @param _strategies Array of strategies
   * @param _scoreData Array of score data
   */
  function updateScores(
    IStrategyV5[] memory _strategies,
    bytes[] calldata _scoreData
  ) external onlyManager whenNotPaused {
    unchecked {
      for (uint256 i = 0; i < _strategies.length; i++) {
        _updateScore(_strategies[i], _scoreData[i]);
      }
    }
  }

  /**
   * @notice Updates the collateralization of a strategy
   * @param _strategy Strategy
   * @param _p New collateralization
   */
  function updateCollateralization(
    IStrategyV5 _strategy,
    RiskParams.Collateralization memory _p
  ) external onlyAdmin {
    if (
      _p.maxLtv < _p.defaultLtv ||
      _p.maxLtv > stableMintParams.compositeCollateral.maxLtv
    ) revert Errors.InvalidData();
    collateralizationByStrategy[_strategy] = _p;
    emit CollateralizationUpdated(_strategy, _p);
  }

  /**
   * @notice Updates the strategy parameters
   * @param _p New strategy parameters
   */
  function updateStrategyParams(
    RiskParams.Strategy memory _p
  ) external onlyAdmin {
    unchecked {
      if (
        // strategy defaults sanitization
        !_p.defaultSeedUsd.within(10e18, 100_000e18) || // liquidity seeding (>$10, <$100k)
        !_p.defaultDepositCapUsd.within(0, 10_000_000e18) || // deposit cap (>$100, <$10m)
        !_p.defaultMaxLeverage.within32(2_00, 200_00) || // max leverage to not brick any strats (>2:1, <200:1)
        !_p.defaultMaxSlippage.within32(6, 5_00) || // slippage range (>0.06%, <5%)
        !_p.minUpkeepInterval.within64(1800, 604_800) // forced upkeep interval (>30min, <7days)
      ) revert Errors.InvalidData();
      strategyParams = _p;
      emit StrategyParamsUpdated(_p);
    }
  }

  /**
   * @notice Updates the allocation parameters for the risk model
   * @param _p New allocation parameters
   */
  function updateAllocationParams(
    RiskParams.Allocation memory _p
  ) external onlyAdmin {
    unchecked {
      if (
        // scoring methodology sanitization
        (_p.scoring.mean != AverageType.ARITHMETIC &&
          _p.scoring.mean != AverageType.GEOMETRIC &&
          _p.scoring.mean != AverageType.HARMONIC) ||
        !_p.scoring.exponent.within32(0.7e4, 2.5e4) || // score exponent (>0.7, <2.5)
        // diversification bias sanitization
        !_p.diversification.minRatio.within32(0, 2_000) || // min allocation (<20%)
        !_p.diversification.minMaxRatio.within32(10_00, 60_00) || // min max allocation (>10%,<60%)
        !_p.diversification.exponent.within32(2000, 2_0000) || // max allocation exponent (.2>, <2)
        // trailing profits/rewards harvesting sanitization
        !_p.harvestTrigger.factor.within32(1000, 100_0000) || // harvest tvl factor (>.1, <100)
        !_p.harvestTrigger.exponent.within32(3000, 8500) || // harvest tvl exponent (>.3, <.85)
        // target liquidity (netting gravity center) sanitization
        !_p.targetLiquidity.minRatio.within32(300, 2_500) || // target liquidity ratio (>3%, <25%)
        !_p.targetLiquidity.factor.within32(100, 100_000) || // target liquidity tvl factor (>.01, <1000)
        !_p.targetLiquidity.exponent.within32(500, 7000) || // target liquidity tvl exponent (>.05, <.7)
        // liquidity upper band (allocation) sanitization
        !_p.allocationTrigger.minRatio.within32(25, 1000) || // allocation trigger tvl factor (>.25%, <10%)
        !_p.allocationTrigger.factor.within32(100, 1500) || // allocation trigger tvl factor (>.01, <.15)
        !_p.allocationTrigger.exponent.within32(500, 1_0000) || // allocation trigger tvl exponent (>.0005, <1)
        // liquidation lower band (soft-liquidation) sanitization
        !_p.liquidationTrigger.minRatio.within32(25, 1000) || // liquidation trigger tvl factor (>.25%, <10%)
        !_p.liquidationTrigger.factor.within32(100, 1500) || // liquidation trigger tvl factor (>.01, <.15)
        !_p.liquidationTrigger.exponent.within32(500, 1_0000) || // liquidation trigger tvl exponent (>.0005, <1)
        // liquidation 2nd lower band (hard-liquidation) sanitization
        !_p.panicTrigger.minRatio.within32(30, 2_000) || // panic trigger tvl factor (>.05%, <20%)
        !_p.panicTrigger.factor.within32(120, 1700) || // panic trigger tvl factor (>.012, <.17)
        !_p.panicTrigger.exponent.within32(6, 1_0000) || // panic trigger tvl exponent (>.0006, <1)
        // hard-liquidation vs soft-liquidation sanitization (hard trigger should converge slower than soft to never cross)
        _p.liquidationTrigger.minRatio > _p.panicTrigger.minRatio ||
        _p.liquidationTrigger.factor < _p.panicTrigger.factor ||
        _p.liquidationTrigger.exponent < _p.panicTrigger.exponent
      ) revert Errors.InvalidData();
      allocationParams = _p;
      emit AllocationParamsUpdated(_p);
    }
  }

  /**
   * @notice Updates the stable mint parameters for the risk model
   * @param _p New stable mint parameters
   */
  function updateStableMintParams(
    RiskParams.StableMint memory _p
  ) external onlyAdmin {
    unchecked {
      if (
        !_p.compositeCollateral.defaultLtv.within32(0, 9800) || // collateralization factor (<98%)
        !_p.primitiveCollateral.defaultLtv.within32(0, 9800) || // collateralization factor (<98%)
        !_p.compositeCollateral.maxLtv.within32(0, 9800) || // max collateralization factor (<98%)
        !_p.primitiveCollateral.maxLtv.within32(0, 9800) // max collateralization factor (<98%)
      ) revert Errors.InvalidData();
      stableMintParams = _p;
      emit StableMintParamsUpdated(_p);
    }
  }
}
