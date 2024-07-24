// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "../libs/AsMaths.sol";
import "../libs/AsRisk.sol";
import "./AsPermissioned.sol";
import "../interfaces/IStrategyV5.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title RiskModel Abstract - Astrolab DAO risk framework
 * @author Astrolab DAO
 * @notice Dictates how strategies are evaluated, allocated to, and rebalanced
 */
contract RiskModel is AsPermissioned {
  using AsMaths for uint256;
  using AsMaths for uint32;
  using AsMaths for uint64;
  using AsRisk for uint64;

  /*═══════════════════════════════════════════════════════════════╗
  ║                             EVENTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  event StrategyScoreUpdated(IStrategyV5 indexed strategy, RiskParams.StrategyScore score);
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
  RiskParams.Strategy public strategyParams;
  RiskParams.StableMint public stableMintParams;
  RiskParams.Allocation public allocationParams;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) AsPermissioned(_accessController) {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  function depositCap(IStrategyV5 _strategy) public view returns (uint256) {
    return _strategy.maxTotalAssets();
  }

  function depositCapUsd(IStrategyV5 _strategy) public view returns (uint256) {
    return
      _strategy.oracle().toUsd(
        address(_strategy.asset()),
        _strategy.maxTotalAssets()
      );
  }

  function strategyTvl(IStrategyV5 _strategy) public view returns (uint256) {
    return _strategy.totalAssets();
  }

  function strategyTvlUsd(IStrategyV5 _strategy) public view returns (uint256) {
    return
      _strategy.oracle().toUsd(
        address(_strategy.asset()),
        _strategy.totalAssets()
      );
  }

  function targetCompositeAllocation(
    IStrategyV5[] memory _strategies,
    uint256 _amount
  ) external view returns (uint256[] memory) {
    uint16[] memory scores = new uint16[](_strategies.length);
    unchecked {
      for (uint256 i = 0; i < _strategies.length; i++) {
        scores[i] = scoreByStrategy[_strategies[i]].composite;
      }
    }
    return
      AsRisk.targetCompositeAllocation(
        scores,
        _amount,
        maxAllocationRatio(_strategies.length),
        allocationParams.scoring.exponent
      );
  }

  function compositeScores(
    IStrategyV5[] memory _strategies
  ) public view returns (uint16[] memory) {
    uint16[] memory scores = new uint16[](_strategies.length);
    unchecked {
      for (uint256 i = 0; i < _strategies.length; i++) {
        scores[i] = scoreByStrategy[_strategies[i]].composite;
      }
    }
    return scores;
  }

  function excessAllocation(
    IStrategyV5[] memory _strategies,
    uint256 _amount,
    address _owner
  ) public view returns (int256[] memory) {
    uint256[] memory targets = AsRisk.targetCompositeAllocation(
      compositeScores(_strategies),
      _amount,
      maxAllocationRatio(_strategies.length),
      allocationParams.scoring.exponent
    );
    int256[] memory excess = new int256[](_strategies.length);
    unchecked {
      for (uint256 i = 0; i < _strategies.length; i++) {
        excess[i] = int256(_strategies[i].assetsOf(_owner)) - int256(targets[i]);
      }
    }
    return excess;
  }

  function previewAllocate(
    IStrategyV5[] memory _strategies,
    uint256 _amount,
    address _owner
  ) external view returns (uint256[] memory) {
    int256[] memory excess = excessAllocation(
      _strategies,
      _amount,
      _owner
    );
    uint256[] memory allocation = new uint256[](_strategies.length);
    unchecked {
      for (uint256 i = 0; i < _strategies.length; i++) {
        allocation[i] = excess[i] > 0 ? uint256(excess[i]) : 0;
      }
    }
    return allocation;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             METHODS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  function _updateScore(
    IStrategyV5 _strategy,
    uint16 _performance,
    uint16 _scalability,
    uint16 _liquidity
  ) internal {
    RiskParams.StrategyScore memory _score = AsRisk.computeStrategyScore(
      [_performance, _scalability, _liquidity]);
    scoreByStrategy[_strategy] = _score;
    emit StrategyScoreUpdated(_strategy, _score);
  }

  function _updateScore(IStrategyV5 _strategy, bytes calldata _scoreData) internal {
    (uint16 _perf, uint16 _scalability, uint16 _liquidity) = abi.decode(
      _scoreData,
      (uint16, uint16, uint16)
    );
    _updateScore(_strategy, _perf, _scalability, _liquidity);
  }

  function updateScore(
    IStrategyV5 _strategy,
    bytes calldata _scoreData
  ) external onlyManager {
    _updateScore(_strategy, _scoreData);
  }

  function updateScores(
    IStrategyV5[] memory _strategies,
    bytes[] calldata _scoreData
  ) external onlyManager {
    unchecked {
      for (uint256 i = 0; i < _strategies.length; i++) {
        _updateScore(_strategies[i], _scoreData[i]);
      }
    }
  }

  function updateStrategyParams(
    RiskParams.Strategy memory _p
  ) external onlyAdmin {
    unchecked {
      if (
        // strategy defaults sanitization
        !_p.defaultSeedUsd.within(10e18, 100_000e18) || // liquidity seeding (>$10, <$100k)
        !_p.defaultDepositCapUsd.within(0, 1_000_000e18) || // deposit cap (>$100, <$1m)
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
   * @param _p The new allocation parameters
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
        !_p.scoring.exponent.within32(7000, 2_5000) || // score exponent (>0.7, <2.5)
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
        !_p.allocationTrigger.minRatio.within32(250, 10_000) || // allocation trigger tvl factor (>.25%, <10%)
        !_p.allocationTrigger.factor.within32(100, 1500) || // allocation trigger tvl factor (>.01, <.15)
        !_p.allocationTrigger.exponent.within32(500, 1_0000) || // allocation trigger tvl exponent (>.0005, <1)
        // liquidation lower band (soft-liquidation) sanitization
        !_p.liquidationTrigger.minRatio.within32(250, 1000) || // liquidation trigger tvl factor (>.25%, <10%)
        !_p.liquidationTrigger.factor.within32(100, 1500) || // liquidation trigger tvl factor (>.01, <.15)
        !_p.liquidationTrigger.exponent.within32(500, 1_0000) || // liquidation trigger tvl exponent (>.0005, <1)
        // liquidation 2nd lower band (hard-liquidation) sanitization
        !_p.panicTrigger.minRatio.within32(500, 2_000) || // panic trigger tvl factor (>.05%, <10%)
        !_p.panicTrigger.factor.within32(1200, 1700) || // panic trigger tvl factor (>.012, <.17)
        !_p.panicTrigger.exponent.within32(6000, 1_0000) || // panic trigger tvl exponent (>.0006, <1)
        // hard-liquidation vs soft-liquidation sanitization
        _p.liquidationTrigger.minRatio <= _p.panicTrigger.minRatio ||
        _p.liquidationTrigger.factor <= _p.panicTrigger.factor ||
        _p.liquidationTrigger.exponent <= _p.panicTrigger.exponent
      ) revert Errors.InvalidData();
      allocationParams = _p;
      emit AllocationParamsUpdated(_p);
    }
  }

  /**
   * @notice Updates the stable mint parameters for the risk model
   * @param _p The new stable mint parameters
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

  /**
   * @notice Calculates the maximum allocation ratio for a given number of strategies
   * @param _strategyCount The number of strategies
   * @return The maximum allocation ratio
   */
  function maxAllocationRatio(
    uint256 _strategyCount
  ) public view returns (uint256) {
    return
      AsRisk
        .maxAllocationRatio(
          _strategyCount,
          allocationParams.diversification.minMaxRatio.toWad32(),
          allocationParams.diversification.exponent.toWad32()
        )
        .toBps();
  }

  /**
   * @notice Calculates the minimum harvest to cost ratio for a given strategy
   * @param _strategy The strategy
   * @return The minimum harvest to cost ratio
   */
  function minHarvestToCostRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      AsRisk
        .minHarvestToCostRatio(
          strategyTvlUsd(_strategy),
          allocationParams.harvestTrigger.factor.toWad(),
          allocationParams.harvestTrigger.exponent.toWad()
        )
        .toBps();
  }

  /**
   * @notice Determines whether a strategy should harvest rewards
   * @param _strategy The strategy
   * @param _pendingRewards The pending rewards
   * @param _costEstimate The cost estimate
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
        strategyTvl(_strategy),
        allocationParams.harvestTrigger.factor.toWad32(),
        allocationParams.harvestTrigger.exponent.toWad32()
      );
  }

  /**
   * @notice Calculates the target liquidity ratio for a given strategy
   * @param _strategy The strategy
   * @return The target liquidity ratio
   */
  function targetLiquidityRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      AsRisk
        .targetLiquidityRatio(
          strategyTvlUsd(_strategy),
          allocationParams.targetLiquidity.minRatio.toWad32(),
          allocationParams.targetLiquidity.factor.toWad32(),
          allocationParams.targetLiquidity.exponent.toWad32()
        )
        .toBps();
  }

  /**
   * @notice Calculates the target allocation ratio for a given strategy
   * @param _strategy The strategy
   * @return The target allocation ratio
   */
  function targetAllocationRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      AsRisk
        .targetAllocationRatio(
          strategyTvlUsd(_strategy),
          allocationParams.targetLiquidity.minRatio.toWad32(),
          allocationParams.targetLiquidity.factor.toWad32(),
          allocationParams.targetLiquidity.exponent.toWad32()
        )
        .toBps();
  }

  function targetAllocation(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return targetAllocationRatio(_strategy) * strategyTvlUsd(_strategy);
  }

  /**
   * @notice Calculates the liquidation trigger ratio for a given strategy
   * @param _strategy The strategy
   * @return The liquidation trigger ratio
   */
  function liquidationTriggerRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      AsRisk
        .liquidationTriggerRatio(
          strategyTvlUsd(_strategy),
          allocationParams.liquidationTrigger.minRatio.toWad32(),
          allocationParams.liquidationTrigger.factor.toWad32(),
          allocationParams.liquidationTrigger.exponent.toWad32()
        )
        .toBps();
  }

  /**
   * @notice Calculates the liquidation trigger for a given strategy
   * @param _strategy The strategy
   * @return The liquidation trigger
   */
  function liquidationTrigger(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      AsRisk
        .liquidationTrigger(
          strategyTvlUsd(_strategy),
          allocationParams.liquidationTrigger.minRatio.toWad32(),
          allocationParams.liquidationTrigger.factor.toWad32(),
          allocationParams.liquidationTrigger.exponent.toWad32()
        )
        .toBps();
  }

  /**
   * @notice Calculates the panic trigger ratio for a given strategy
   * @param _strategy The strategy
   * @return The panic trigger ratio
   */
  function panicTriggerRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      AsRisk
        .panicTriggerRatio(
          strategyTvlUsd(_strategy),
          allocationParams.panicTrigger.minRatio.toWad32(),
          allocationParams.panicTrigger.factor.toWad32(),
          allocationParams.panicTrigger.exponent.toWad32()
        )
        .toBps();
  }

  /**
   * @notice Calculates the allocation trigger ratio for a given strategy
   * @param _strategy The strategy
   * @return The allocation trigger ratio in basis points (bps)
   */
  function allocationTriggerRatio(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      AsRisk
        .allocationTriggerRatio(
          strategyTvlUsd(_strategy),
          allocationParams.allocationTrigger.minRatio.toWad32(),
          allocationParams.allocationTrigger.factor.toWad32(),
          allocationParams.allocationTrigger.exponent.toWad32()
        )
        .toBps();
  }

  /**
   * @notice Calculates the allocation trigger for a given strategy
   * @param _strategy The strategy
   * @return The allocation trigger in basis points (bps)
   */
  function allocationTrigger(
    IStrategyV5 _strategy
  ) public view returns (uint256) {
    return
      AsRisk
        .allocationTrigger(
          strategyTvlUsd(_strategy),
          allocationParams.allocationTrigger.minRatio.toWad32(),
          allocationParams.allocationTrigger.factor.toWad32(),
          allocationParams.allocationTrigger.exponent.toWad32()
        )
        .toBps();
  }
}
