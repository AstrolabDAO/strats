// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

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
 * @title AaveV3 Optimizer - Dynamic liquidity providing on Aave
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Aave V3 (https://aave.com/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract AaveV3Optimizer is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  IPoolAddressesProvider internal _poolProvider;

  constructor(address _accessController) StrategyV5(_accessController) {}

  function _setParams(bytes memory _params) internal override {
    (address poolProvider) = abi.decode(_params, (address));
    _poolProvider = IPoolAddressesProvider(poolProvider);
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

  function _stake(uint256 _index, uint256 _amount) internal override {
    IAavePool pool = IAavePool(_poolProvider.getPool());
    pool.supply({
      asset: address(inputs[_index]),
      amount: _amount,
      onBehalfOf: address(this),
      referralCode: 0
    });
  }

  function _unstake(uint256 _index, uint256 _amount) internal override {
    IAavePool pool = IAavePool(_poolProvider.getPool());
    pool.withdraw({asset: address(inputs[_index]), amount: _amount, to: address(this)});
  }

  function _setLpTokenAllowances(uint256 _amount) internal override {
    IAavePool pool = IAavePool(_poolProvider.getPool());
    for (uint256 i = 0; i < _inputLength; i++) {
      inputs[i].forceApprove(address(pool), _amount);
      lpTokens[i].forceApprove(address(pool), _amount);
    }
  }

  function rewardsAvailable() public view override returns (uint256[] memory amounts) {}
}
