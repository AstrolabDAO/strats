// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../libs/AsMaths.sol";
import "../libs/AsIterableSet.sol";	
import "./AsPermissioned.sol";
import "../interfaces/IStrategyV5.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title Registry - On-chain registry of strategies and tokens
 * @author Astrolab DAO
 * @notice Source of truth for all production deployments
 */
contract Registry is AsPermissioned {
  using AsIterableSet for AsIterableSet.Set;
  using AsCast for bytes32;
  using AsCast for address;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct Core {
    // static libs
    address AsAccounting;
    // infra
    address Registry;
    address Swapper;
    address Bridger;
    address StableMint;
    address PriceProvider;
    address StrategyV5Agent;
    // governance
    address DaoCouncil;
    address DaoTreasury;
    address RiskModel;
    address RewardDistributor;
  }

  struct Tokens {
    // local chain gas token
    address wgas;
    // stables
    address asUSD;
    address asETH;
    address asBTC;
    // governance
    address ASL;
    // staked
    address sASL;
    address sasUSD;
    address sasETH;
    address sasBTC;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             EVENTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  event CoreSet(Core core);
  event TokensSet(Tokens tokens);
  event CompositeAdded(AggregationLevel aggregationLevel, address composite);
  event CompositeRemoved(AggregationLevel aggregationLevel, address composite);
  event PrimitiveAdded(address primitive);
  event PrimitiveRemoved(address primitive);

  /*═══════════════════════════════════════════════════════════════╗
  ║                             STORAGE                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  AsIterableSet.Set[3] private _composites; // from 0x000...AAA1 (eg. asUSD) to 0x000...AAA3 (eg. asUSD-AAVE-O)
  AsIterableSet.Set private _primitives; // 0x000...AAA4
  mapping(address => address) public composite1ByUnderlying;
  Core public core;
  Tokens public tokens;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) AsPermissioned(_accessController) {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Gets the list of composite startegies (acXXX) for a given `_aggregationLevel` (0x000...AAA1, 0x000...AAA2, 0x000...AAA3)
   * @param _aggregationLevel Aggregation level
   * @return Array of composite strategies
   */
  function getComposites(uint256 _aggregationLevel) public view virtual returns (address[] memory) {
    return _composites[_aggregationLevel].valuesAsAddress();
  }

  /**
   * @notice Gets the list of cross-chain composite strategies (0x000...AAA1)
   * @return Array of cross-chain composite strategies
   */
  function getCrossChainComposites() public view virtual returns (address[] memory) {
    return _composites[uint256(AggregationLevel.CROSS_CHAIN)].valuesAsAddress();
  }

  /**
   * @notice Gets the list of chain composite strategies (0x000...AAA2)
   * @return Array of chain composite strategies
   */
  function getChainComposites() public view virtual returns (address[] memory) {
    return _composites[uint256(AggregationLevel.CHAIN)].valuesAsAddress();
  }

  /**
   * @notice Gets the list of class composite strategies (0x000...AAA3)
   * @return Array of class composite strategies
   */
  function getClassComposites() public view virtual returns (address[] memory) {
    return _composites[uint256(AggregationLevel.CLASS)].valuesAsAddress();
  }

  /**
   * @notice Gets the list of primitive strategies (0x000...AAA4)
   * @return Array of primitive strategies
   */
  function getPrimitives() public view virtual returns (address[] memory) {
    return _primitives.valuesAsAddress();
  }

  /**
   * @notice Checks if the given aggregation level is valid and if the caller has the required role
   * @param _aggregationLevel Aggregation level to check
   */
  function _checkAggregationLevel(AggregationLevel _aggregationLevel) internal view virtual {
    if (uint256(_aggregationLevel) > 2) revert Errors.InvalidData();
    if (_aggregationLevel == AggregationLevel.CROSS_CHAIN) {
      _checkRole(Roles.ADMIN, msg.sender);
    }
  }

  /**
   * @notice Checks if the given strategy is valid and initialized
   * @param _strategy Address of the strategy to check
   */
  function _checkStrategy(address _strategy) internal view virtual {
    (bool success,) = _strategy.staticcall(
      abi.encodeWithSelector(IAccessController.isAdmin.selector, msg.sender)
    );
    if (!success || address(IStrategyV5(_strategy).asset()) == address(0)) {
      revert Errors.ContractNonCompliant(); // not a strat or uninitialized
    }
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             METHODS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Adds a composite strategy to the specified aggregation level
   * @param _aggregationLevel Aggregation level to add the composite strategy to
   * @param _strategy Address of the composite strategy to add
   */
  function addComposite(AggregationLevel _aggregationLevel, address _strategy) external onlyManager {
    _checkAggregationLevel(_aggregationLevel);
    _checkStrategy(_strategy);
    if (_aggregationLevel == AggregationLevel.CROSS_CHAIN) {
      composite1ByUnderlying[address(IStrategyV5(_strategy).asset())] = _strategy;
    }
    _composites[uint256(_aggregationLevel)].push(_strategy);
    emit CompositeAdded(_aggregationLevel, _strategy);
  }

  /**
   * @notice Removes a composite strategy from the specified aggregation level
   * @param _aggregationLevel Aggregation level to remove the composite strategy from
   * @param _strategy Address of the composite strategy to remove
   */
  function removeComposite(AggregationLevel _aggregationLevel, address _strategy) external onlyManager {
    _checkAggregationLevel(_aggregationLevel);
    if (_aggregationLevel == AggregationLevel.CROSS_CHAIN) {
      delete composite1ByUnderlying[address(IStrategyV5(_strategy).asset())];
    }
    _composites[uint256(_aggregationLevel)].remove(_strategy);
    emit CompositeRemoved(_aggregationLevel, _strategy);
  }

  /**
   * @notice Adds a primitive strategy
   * @param _strategy Address of the primitive strategy to add
   */
  function addPrimitive(address _strategy) external onlyManager {
    _checkStrategy(_strategy);
    _primitives.push(_strategy);
    emit PrimitiveAdded(_strategy);
  }

  /**
   * @notice Removes a primitive strategy
   * @param _strategy Address of the primitive strategy to remove
   */
  function removePrimitive(address _strategy) external onlyManager {
    _primitives.remove(_strategy);
    emit PrimitiveRemoved(_strategy);
  }

  /**
   * @notice Sets the core configuration
   * @param _core Core configuration to set
   */
  function setCore(Core memory _core) external onlyAdmin {
    // NB: these being non-trivial to sanitize, we expect the multisig callers to triple check the payload
    core = _core;
    emit CoreSet(_core);
  }

  /**
   * @notice Sets the tokens configuration
   * @param _tokens Tokens configuration to set
   */
  function setTokens(Tokens memory _tokens) external onlyAdmin {
    // NB: same as above
    tokens = _tokens;
    emit TokensSet(_tokens);
  }
}
