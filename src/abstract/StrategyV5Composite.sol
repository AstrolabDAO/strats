// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.25;

import "./StrategyV5Lock.sol";
import "../interfaces/IStrategyV5.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title StrategyV5Composite - Primitives base aggregator strategy
 * @author Astrolab DAO
 * @notice Aggregating network specific primitive strategies positions (acXXX -> apXXX)
 * Can be extended by domain-specific aggregator strategies (eg. acLEND, acDEX, acBRIDGE...)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract StrategyV5Composite is StrategyV5Lock {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  IStrategyV5[] internal _primitives;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) StrategyV5Lock(_accessController) {}

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function _setParams(bytes memory _params) internal override {
    // no use of specific params, only inputs (primitives) and weights
    _loadPrimitives();
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Convert LP/staked LP to input
   * @param _amount Amount of LP/staked LP
   * @return Input value of the LP amount
   */
  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _primitives[_index].convertToAssets(_amount);
  }

  /**
   * @notice Convert input to LP/staked LP
   * @return LP value of the input amount
   */
  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _primitives[_index].convertToShares(_amount);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            SETTERS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  function _loadPrimitives() internal {
    for (uint256 i = 0; i < _inputLength;) {
      (bool success,) =
        address(lpTokens[i]).staticcall(abi.encodeWithSelector(IStrategyV5.agent.selector));
      if (!success) {
        revert Errors.ContractNonCompliant();
      }
      unchecked {
        _primitives.push(IStrategyV5(address(lpTokens[i])));
        i++;
      }
    }
  }

  /**
   * @notice Changes the strategy input tokens
   * @param _inputs Array of input addresses
   * @param _weights Array of input weights
   * @param _lpTokens Array of LP tokens
   */
  function setInputs(
    address[] calldata _inputs,
    uint16[] calldata _weights,
    address[] calldata _lpTokens
  ) external onlyAdmin {
    // update inputs and lpTokens
    _setInputs(_inputs, _weights, _lpTokens);
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
    _loadPrimitives();
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Request inputs liquidation (non-atomic)
   * @param _amount Amounts of `inputs` to liquidate from related `lpTokens`
   * @param _index Index of the input to liquidate
   */
  function _requestLiquidate(uint256 _amount, uint256 _index) internal override {
    _primitives[_index].requestWithdraw(_amount, address(this), address(this), "0x");
  }

  /**
   * @notice Stakes or provides `_amount` from `input[_index]` to `lpTokens[_index]`
   * @param _amount Amount of underlying assets to allocate to `inputs[_index]`
   * @param _index Index of the input to stake
   */
  function _stake(uint256 _amount, uint256 _index) internal override {
    _primitives[_index].deposit(_amount, address(this));
  }

  /**
   * @notice Unstakes or liquidates `_amount` of `lpTokens[i]` back to `input[_index]`
   * @param _amount Amount of underlying assets to recover from liquidating `inputs[_index]`
   * @param _index Index of the input to liquidate
   */
  function _unstake(uint256 _amount, uint256 _index) internal override {
    _primitives[_index].withdraw(_amount, address(this), address(this));
  }
}
