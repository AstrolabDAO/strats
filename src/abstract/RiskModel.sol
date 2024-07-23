// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "../libs/AsMaths.sol";
import "../libs/AsRisk.sol";
import "./AsPermissioned.sol";

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
abstract contract RiskModel is AsPermissioned {
  using AsMaths for uint256;
  using AsMaths for uint32;
  using AsScoring for uint64;

  /*═══════════════════════════════════════════════════════════════╗
  ║                             EVENTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  event StrategyScoreUpdated(address indexed strategy, uint64 score);
  event StrategyParamsUpdated(RiskParams.Strategy params);
  event AllocationParamsUpdated(RiskParams.Allocation params);
  event StableMintParamsUpdated(RiskParams.StableMint params);

  /*═══════════════════════════════════════════════════════════════╗
  ║                            CONSTANTS                           ║
  ╚═══════════════════════════════════════════════════════════════*/

  /*═══════════════════════════════════════════════════════════════╗
  ║                             STORAGE                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  mapping(IStrategyV5 => StrategyScore) public scoreByStrategy;
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
    return _strategy.oracle().toUsdBp(_strategy.maxTotalAssets());
  }

  function strategyTvl(IStrategyV5 _strategy) public view returns (uint256) {
    return _strategy.totalAssets();
  }

  function strategyTvlUsd(IStrategyV5 _strategy) public view returns (uint256) {
    return _strategy.oracle().toUsdBp(_strategy.totalAssets());
  }

  function targetAllocation(IStrategyV5[] memory _strategies, uint256 _amount) external view returns (uint64[] memory) {
    uint64[] memory scores = new uint64[](_strategies.length);
    unchecked {
      for (uint256 i = 0; i < _strategies.length; i++) {
        scores[i] = scoreByStrategy[_strategies[i]];
      }
    }
    return AsRisk.targetAllocation(
      scores,
      _amount,
      AsRisk.maxAllocationRatio(
        _strategies.length,
        allocationParams.minMaxAllocationRatio,
        allocationParams.maxAllocationExponent
      ),
      allocationParams.scoreExponent
    );
  }

  function excessAllocation(IStrategyV5[] memory _strategies, uint256 _amount, address _owner) external view returns (int256[] memory) {
    uint256[] memory targets = targetAllocation(_strategies, _amount);
    int256[] memory excess = new int256[](_strategies.length);
    unchecked {
      for (uint256 i = 0; i < _strategies.length; i++) {
        excess[i] = _strategies[i].assetsOf(_owner) - int256(targets[i]);
      }
    }
    return excess;
  }

  function previewAllocate(IStrategyV5[] memory _strategies, uint256 _amount, address _owner) external view returns (uint256[] memory) {
    uint256[] memory excess = excessAllocation(_strategies, _amount, _owner);
    uint256[] memory allocation = new uint256[](_strategies.length);
    unchecked {
      for (uint256 i = 0; i < _strategies.length; i++) {
        allocation[i] = excess[i] > 0 ? excess[i] : 0;
      }
    }
    return allocation;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             METHODS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  function _updateScore(
    address _strategy,
    uint64 _performance,
    uint64 _scalability,
    uint64 _liquidity
  ) internal {
    scoreByStrategy[_strategy] = AsScoring.computeStrategyScore(
      _performance,
      _scalability,
      _liquidity
    );
    emit StrategyScoreUpdated(_strategy, scoreByStrategy[_strategy]);
  }

  function _updateScore(
    address _strategy,
    bytes calldata _scoreData
  ) internal {
    (uint64 _perf, uint64 _scalability, uint64 _liquidity) =
      abi.decode(_scoreData, (uint64, uint64, uint64));
    _updateScore(_strategy, _perf, _scalability, _liquidity);
  }

  function updateScore(
    address _strategy,
    bytes calldata _scoreData
  ) external onlyManager {
    _updateScore(_strategy, _scoreData);
  }

  function updateScores(address[] memory _strategies, bytes[] memory _scoreData) external onlyManager {
    unchecked {
      for (uint256 i = 0; i < _strategies.length; i++) {
        _updateScore(_strategies[i], _scoreData[i]);
      }
    }
  }

  function updateStrategyParams(RiskParams.Strategy memory _p) external onlyAdmin {
    unchecked {
      if (
        // strategy defaults sanitization
        !_p.defaultMaxLeverage.within(2_00, 200_00) || // max leverage to not brick any strats (>2:1, <200:1)
        !_p.defaultMaxSlippage.within(6, 5_00) || // slippage range (>0.06%, <5%)
        !_p.defaultSeedUsd.within(10e18, 100_000e18) || // liquidity seeding (>$10, <$100k)
        !_p.defaultDepositCapUsd.within(0, 1_000_000e18) || // deposit cap (>$100, <$1m)
        !_p.minUpkeepInterval.within(1800, 604_800) // forced upkeep interval (>30min, <7days)
      ) revert Errors.InvalidData();
      strategyParams = _p;
      emit StrategyParamsUpdated(_p);
    }
  }

  /**
   * @notice Updates the allocation parameters for the risk model
   * @param _params The new allocation parameters
   */
  function updateAllocationParams(RiskParams.Allocation memory _params) external onlyAdmin {
    unchecked {
      if (
        // scoring methodology sanitization
        (_params.scoringMean !== AverageType.ARITHMETIC && _params.scoringMean !== AverageType.GEOMETRIC),
        !_params.scoreExponent.within(7000, 2_5000) || // score exponent (>0.7, <2.5)
        // diversification bias sanitization
        !_params.minAllocationRatio.within(0, 2_000) || // min allocation (<20%)
        !_params.minMaxAllocationRatio.within(10_00, 60_00) || // min max allocation (>10%,<60%)
        !_params.maxAllocationExponent.within(2000, 2_0000) || // max allocation exponent (.2>, <2)
        // trailing profits/rewards harvesting sanitization
        !_params.harvestTvlFactor.within(1000, 100_0000) || // harvest tvl factor (>.1, <100)
        !_params.harvestTvlExponent.within(3000, 8500) || // harvest tvl exponent (>.3, <.85)
        // target liquidity (netting gravity center) sanitization
        !_params.targetLiquidityRatio.within(300, 2_500) || // target liquidity ratio (>3%, <25%)
        !_params.targetLiquidityTvlFactor.within(100, 100_000) || // target liquidity tvl factor (>.01, <100)
        !_params.targetLiquidityTvlExponent.within(500, 7000) || // target liquidity tvl exponent (>.05, <.7)
        // liquidity upper band (allocation) sanitization
        !_params.allocationTriggerTvlRatio.within(250, 10_000) || // allocation trigger tvl factor (>.25%, <10%)
        !_params.allocationTriggerTvlFactor.within(100, 1500) || // allocation trigger tvl factor (>.01, <.15)
        !_params.allocationTriggerTvlExponent.within(500, 1_0000) || // allocation trigger tvl exponent (>.0005, <1)
        // liquidation lower band (soft-liquidation) sanitization
        !_params.liquidationTriggerTvlRatio.within(250, 1000) || // liquidation trigger tvl factor (>.25%, <10%)
        !_params.liquidationTriggerTvlFactor.within(100, 1500) || // liquidation trigger tvl factor (>.01, <.15)
        !_params.liquidationTriggerTvlExponent.within(500, 1_0000) || // liquidation trigger tvl exponent (>.0005, <1)
        // liquidation 2nd lower band (hard-liquidation) sanitization
        !_params.panicTriggerTvlRatio.within(500, 2_000) || // panic trigger tvl factor (>.05%, <10%)
        !_params.panicTriggerTvlFactor.within(1200, 1700) || // panic trigger tvl factor (>.012, <.17)
        !_params.panicTriggerTvlExponent.within(6000, 1_0000) || // panic trigger tvl exponent (>.0006, <1)
        // hard-liquidation vs soft-liquidation sanitization
        _params.liquidationTriggerTvlRatio <= _params.panicTriggerTvlRatio ||
        _params.liquidationTriggerTvlFactor <= _params.panicTriggerTvlFactor ||
        _params.liquidationTriggerTvlExponent <= _params.panicTriggerTvlExponent
      ) revert Errors.InvalidData();
      allocationParams = _params;
      emit AllocationParamsUpdated(_params);
    }
  }

  /**
   * @notice Updates the stable mint parameters for the risk model
   * @param _stableMintParams The new stable mint parameters
   */
  function updateStableMintParams(RiskParams.StableMint memory _stableMintParams) external onlyAdmin {
    unchecked {
      if (
        !_stableMintParams.defaultCompositeLtv.within(0, 9800) || // collateralization factor (<98%)
        !_stableMintParams.defaultPrimitiveLtv.within(0, 9800) || // collateralization factor (<98%)
        !_stableMintParams.maxCompositeLtv.within(0, 9800) || // max collateralization factor (<98%)
        !_stableMintParams.maxPrimitiveLtv.within(0, 9800) || // max collateralization factor (<98%)
      ) revert Errors.InvalidData();
      stableMintParams = _stableMintParams;
      emit StableMintParamsUpdated(_stableMintParams);
    }
  }

  /**
   * @notice Calculates the maximum allocation ratio for a given number of strategies
   * @param _strategyCount The number of strategies
   * @return The maximum allocation ratio
   */
  function maxAllocationRatio(uint256 _strategyCount) public view returns (uint32) {
    return AsRisk.maxAllocationRatio(
      _strategyCount,
      allocationParams.minMaxAllocationRatio.toWad(),
      allocationParams.maxAllocationExponent.toWad()
    ).toBps();
  }

  /**
   * @notice Calculates the minimum harvest to cost ratio for a given strategy
   * @param _strategy The strategy
   * @return The minimum harvest to cost ratio
   */
  function minHarvestToCostRatio(IStrategyV5 _strategy) public view returns (uint32) {
    return AsRisk.minHarvestToCostRatio(
      strategyTvlUsd(_strategy),
      allocationParams.harvestTvlFactor.toWad(),
      allocationParams.harvestTvlExponent.toWad()
    ).toBps();
  }

  /**
   * @notice Determines whether a strategy should harvest rewards
   * @param _strategy The strategy
   * @param _pendingRewards The pending rewards
   * @param _costEstimate The cost estimate
   * @return Whether the strategy should harvest rewards
   */
  function shouldHarvest(IStrategyV5 _strategy, uint256 _pendingRewards, uint256 _costEstimate) public view returns (bool) {
    return AsRisk.shouldHarvest(
      _pendingRewards,
      _costEstimate,
      strategyTvl(_strategy),
      allocationParams.harvestTvlFactor.toWad(),
      allocationParams.harvestTvlExponent.toWad()
    );
  }

  /**
   * @notice Calculates the target liquidity ratio for a given strategy
   * @param _strategy The strategy
   * @return The target liquidity ratio
   */
  function targetLiquidityRatio(IStrategyV5 _strategy) public view returns (uint32) {
    return AsRisk.targetLiquidityRatio(
      strategyTvlUsd(_strategy),
      allocationParams.targetLiquidityTvlRatio.toWad(),
      allocationParams.targetLiquidityTvlFactor.toWad(),
      allocationParams.targetLiquidityTvlExponent.toWad()
    ).toBps();
  }

  /**
   * @notice Calculates the target allocation ratio for a given strategy
   * @param _strategy The strategy
   * @return The target allocation ratio
   */
  function targetAllocationRatio(IStrategyV5 _strategy) public view returns (uint32) {
    return AsRisk.targetAllocationRatio(
      strategyTvlUsd(_strategy),
      allocationParams.targetLiquidityTvlRatio.toWad(),
      allocationParams.targetLiquidityTvlFactor.toWad(),
      allocationParams.targetLiquidityTvlExponent.toWad()
    ).toBps();
  }

  /**
   * @notice Calculates the liquidation trigger ratio for a given strategy
   * @param _strategy The strategy
   * @return The liquidation trigger ratio
   */
  function liquidationTriggerRatio(IStrategyV5 _strategy) public view returns (uint32) {
    return AsRisk.liquidationTriggerRatio(
      strategyTvlUsd(_strategy),
      allocationParams.liquidationTriggerTvlRatio.toWad(),
      allocationParams.liquidationTriggerTvlFactor.toWad(),
      allocationParams.liquidationTriggerTvlExponent.toWad()
    ).toBps();
  }

  /**
   * @notice Calculates the liquidation trigger for a given strategy
   * @param _strategy The strategy
   * @return The liquidation trigger
   */
  function liquidationTrigger(IStrategyV5 _strategy) public view returns (uint32) {
    return AsRisk.liquidationTrigger(
      strategyTvlUsd(_strategy),
      allocationParams.liquidationTriggerTvlRatio.toWad(),
      allocationParams.liquidationTriggerTvlFactor.toWad(),
      allocationParams.liquidationTriggerTvlExponent.toWad()
    ).toBps();
  }

  /**
   * @notice Calculates the panic trigger ratio for a given strategy
   * @param _strategy The strategy
   * @return The panic trigger ratio
   */
  function panicTriggerRatio(IStrategyV5 _strategy) public view returns (uint32) {
    return AsRisk.panicTriggerRatio(
      strategyTvlUsd(_strategy),
      allocationParams.panicTriggerTvlRatio.toWad(),
      allocationParams.panicTriggerTvlFactor.toWad(),
      allocationParams.panicTriggerTvlExponent.toWad()
    ).toBps();
  }

  /**
   * @notice Calculates the allocation trigger ratio for a given strategy
   * @param _strategy The strategy
   * @return The allocation trigger ratio in basis points (bps)
   */
  function allocationTriggerRatio(IStrategyV5 _strategy) public view returns (uint32) {
    return AsRisk.allocationTriggerRatio(
      strategyTvlUsd(_strategy),
      allocationParams.allocationTriggerTvlRatio.toWad(),
      allocationParams.allocationTriggerTvlFactor.toWad(),
      allocationParams.allocationTriggerTvlExponent.toWad()
    ).toBps();
  }

  /**
   * @notice Calculates the allocation trigger for a given strategy
   * @param _strategy The strategy
   * @return The allocation trigger in basis points (bps)
   */
  function allocationTrigger(IStrategyV5 _strategy) public view returns (uint32) {
    return AsRisk.allocationTrigger(
      strategyTvlUsd(_strategy),
      allocationParams.allocationTriggerTvlRatio.toWad(),
      allocationParams.allocationTriggerTvlFactor.toWad(),
      allocationParams.allocationTriggerTvlExponent.toWad()
    ).toBps();
  }
}
