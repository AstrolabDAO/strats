// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../libs/AsArrays.sol";
import "../core/StrategyV5.sol";
import "../external/DHedge/IDHedge.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title Toros Optimizer - Dynamic liquidity providing on Toros
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Toros (https://toros.finance/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract TorosOptimizer is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  IDhedgeEasySwapper internal _dHedgeSwapper;

  constructor(address _accessController) StrategyV5(_accessController) {}

  function _setParams(bytes memory _params) internal override {
    address dHedgeSwapper = abi.decode(_params, (address));
    _dHedgeSwapper = IDhedgeEasySwapper(dHedgeSwapper);
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

  function _stake(uint256 _amount, uint256 _index) internal override {
    _dHedgeSwapper.deposit({
      pool: address(lpTokens[_index]),
      depositAsset: address(inputs[_index]),
      amount: _amount,
      poolDepositAsset: address(inputs[_index]),
      expectedLiquidityMinted: 1 // _inputToStake(_amount, _index).subBp(_4626StorageExt().maxSlippageBps)
    });
  }

  function _unstake(uint256 _amount, uint256 _index) internal override {
    _dHedgeSwapper.withdraw({
      pool: address(lpTokens[_index]),
      fundTokenAmount: _amount,
      withdrawalAsset: address(inputs[_index]),
      expectedAmountOut: 1
    });
  }

  function _setLpTokenAllowances(uint256 _amount) internal override {
    for (uint256 i = 0; i < _inputLength; i++) {
      inputs[i].forceApprove(address(_dHedgeSwapper), _amount);
    }
  }

  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _usdToInput(
      _amount.mulDiv(IDHedgePool(address(lpTokens[_index])).tokenPrice(), 1e12), _index
    );
  }

  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _inputToUsd(_amount, _index).mulDiv(
      1e12 * 10 ** _lpTokenDecimals[_index],
      IDHedgePool(address(lpTokens[_index])).tokenPrice()
    ); // eg. 1e6*1e12*1e18/1e18 = 1e18
  }

  function rewardsAvailable() public view override returns (uint256[] memory amounts) {}
}
