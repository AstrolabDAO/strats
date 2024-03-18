// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5.sol";
import "./interfaces/v3/IAave.sol";
import "./interfaces/v3/IOracle.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AaveV3MultiStake Strategy - Liquidity providing on Aave
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Aave V3 (https://aave.com/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract AaveV3MultiStake is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  // strategy specific variables
  IPoolAddressesProvider internal _poolProvider;

  constructor(address _accessController) StrategyV5(_accessController) {}

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function _setParams(bytes memory _params) internal override {
    (address poolProvider) = abi.decode(_params, (address));
    _poolProvider = IPoolAddressesProvider(poolProvider);
    _setAllowances(AsMaths.MAX_UINT256);
  }

  /**
   * @notice Stakes or provides `_amount` from `input[_index]` to `lpTokens[_index]`
   * @param _index Index of the input to stake
   * @param _amount Amount of underlying assets to allocate to `inputs[_index]`
   */
  function _stake(uint8 _index, uint256 _amount) internal override {
    IAavePool pool = IAavePool(_poolProvider.getPool());
    pool.supply({
      asset: address(inputs[_index]),
      amount: _amount,
      onBehalfOf: address(this),
      referralCode: 0
    });
  }

  /**
   * @notice Unstakes or liquidates `_amount` of `lpTokens[i]` back to `input[_index]`
   * @param _index Index of the input to liquidate
   * @param _amount Amount of underlying assets to recover from liquidating `inputs[_index]`
   */
  function _unstake(uint8 _index, uint256 _amount) internal override {
    IAavePool pool = IAavePool(_poolProvider.getPool());
    pool.withdraw({asset: address(inputs[_index]), amount: _amount, to: address(this)});
  }

  /**
   * @notice Sets allowances for third party contracts (except rewardTokens)
   * @param _amount Allowance amount
   */
  function _setAllowances(uint256 _amount) internal override {
    IAavePool pool = IAavePool(_poolProvider.getPool());
    for (uint8 i = 0; i < _inputLength; i++) {
      inputs[i].forceApprove(address(pool), _amount);
      lpTokens[i].forceApprove(address(pool), _amount);
    }
  }

  /**
   * @notice Returns the invested input converted from the staked LP token
   * @return Input value of the LP/staked balance
   */
  function _investedInput(uint256 _index) internal view override returns (uint256) {
    return lpTokens[_index].balanceOf(address(this));
  }

  /**
   * @notice Returns the available rewards
   * @return amounts Array of rewards available for each reward token
   */
  function rewardsAvailable() public view override returns (uint256[] memory amounts) {}
}
