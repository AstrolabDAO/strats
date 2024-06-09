// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5.sol";
import "./interfaces/IDHedge.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title Toros Strategy - Liquidity providing on Toros
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Toros (https://toros.finance/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract Toros is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  // strategy specific params
  IDhedgeEasySwapper internal _dHedgeSwapper;

  constructor(address _accessController) StrategyV5(_accessController) {}

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function _setParams(bytes memory _params) internal override {
    address dHedgeSwapper = abi.decode(_params, (address));
    _dHedgeSwapper = IDhedgeEasySwapper(dHedgeSwapper);
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

  /**
   * @notice Stakes or provides `_amount` from `input[_index]` to `lpTokens[_index]`
   * @param _index Index of the input to stake
   * @param _amount Amount of underlying assets to allocate to `inputs[_index]`
   */
  function _stake(uint256 _index, uint256 _amount) internal override {
    _dHedgeSwapper.deposit({
      pool: address(lpTokens[_index]),
      depositAsset: address(inputs[_index]),
      amount: _amount,
      poolDepositAsset: address(inputs[_index]),
      expectedLiquidityMinted: 1 // _inputToStake(_amount, _index).subBp(_4626StorageExt().maxSlippageBps)
    });
  }

  /**
   * @notice Unstakes or liquidates `_amount` of `lpTokens[i]` back to `input[_index]`
   * @param _index Index of the input to liquidate
   * @param _amount Amount of underlying assets to recover from liquidating `inputs[_index]`
   */
  function _unstake(uint256 _index, uint256 _amount) internal override {
    _dHedgeSwapper.withdraw({
      pool: address(lpTokens[_index]),
      fundTokenAmount: _amount,
      withdrawalAsset: address(inputs[_index]),
      expectedAmountOut: 1
    });
  }

  /**
   * @notice Sets allowances for third party contracts (except rewardTokens)
   * @param _amount Allowance amount
   */
  function _setLpTokenAllowances(uint256 _amount) internal override {
    for (uint256 i = 0; i < _inputLength; i++) {
      inputs[i].forceApprove(address(_dHedgeSwapper), _amount);
    }
  }

  /**
   * @notice Converts LP/staked LP to input
   * @return Input value of the LP amount
   */
  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _usdToInput(
      _amount.mulDiv(IDHedgePool(address(lpTokens[_index])).tokenPrice(), 1e12), _index
    );
  }

  /**
   * @notice Converts input to LP/staked LP
   * @return LP value of the input amount
   */
  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _inputToUsd(_amount, _index).mulDiv(
      1e12 * 10 ** _lpTokenDecimals[_index],
      IDHedgePool(address(lpTokens[_index])).tokenPrice()
    ); // eg. 1e6*1e12*1e18/1e18 = 1e18
  }

  /**
   * @notice Returns the available rewards
   * @return amounts Array of rewards available for each reward token
   */
  function rewardsAvailable() public view override returns (uint256[] memory amounts) {}
}
