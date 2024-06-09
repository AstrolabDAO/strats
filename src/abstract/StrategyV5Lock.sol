// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.22;

import "./StrategyV5.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title StrategyV5Lock - Async StrategyV5 compatible with lock/unlock stakes
 * @author Astrolab DAO
 * @notice Base strategy for async (non-atomic) staking and unstaking
 * @dev Asset->inputs->LPs->inputs->asset
 */
abstract contract StrategyV5Lock is StrategyV5 {
  using AsMaths for uint256;
  using AsMaths for int256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) StrategyV5(_accessController) {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Request inputs liquidation (non-atomic)
   * @param _amount Amounts of `inputs` to liquidate from related `lpTokens`
   * @param _index Index of the input to liquidate
   */
  function _requestLiquidate(uint256 _amount, uint256 _index) internal virtual;

  /**
   * @notice Request inputs liquidation (non-atomic)
   * @param _amounts Amounts of `inputs` to liquidate from related `lpTokens`
   * @return amountRequested Amount of `asset` requested to liquidate
   */
  function requestLiquidate(uint256[] calldata _amounts) external onlyKeeper returns (uint256 amountRequested) {
    uint256 totalRequest;
    for (uint256 i = 0; i < _inputLength; i++) {
      _requestLiquidate(_amounts[i], i);
      _req.liquidate[i] += _amounts[i];
      uint256 assetAmount = _inputToAsset(_amounts[i], i);
      // _req.totalLiquidate += assetAmount;
      totalRequest += assetAmount;
    }
    return totalRequest;
  }

  /**
   * @notice Called before liquidating strategy inputs
   * @param _amounts Amount of each input to liquidate
   */
  function _beforeLiquidate(uint256[8] calldata _amounts) internal override {
    for (uint256 i = 0; i < _inputLength; i++) {
      if (_req.liquidate[i] < _amounts[i]) {
        revert Errors.AmountTooHigh(_amounts[i]);
      } else {
        _req.liquidate[i] = _req.liquidate[i].subMax0(_amounts[i]);
        // _req.totalLiquidate = _req.totalLiquidate.subMax0(_inputToAsset(_amounts[i], i));
      }
    }
  }

  function _afterLiquidate(uint256 _totalRecovered) internal override {}
}
