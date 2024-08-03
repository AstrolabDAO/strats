// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5.sol";
import "./interfaces/ISonne.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title Sonne Optimizer - Dynamic liquidity providing on Sonne
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Sonne (https://sonne.finance/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract SonneOptimizer is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  IUnitroller internal _unitroller;

  constructor(address _accessController) StrategyV5(_accessController) {}

  function _setParams(bytes memory _params) internal override {
    address unitroller = abi.decode(_params, (address));
    _unitroller = IUnitroller(unitroller);
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

  function _stake(uint256 _amount, uint256 _index) internal override {
    ICToken(address(lpTokens[_index])).mint(_amount);
  }

  function _unstake(uint256 _amount, uint256 _index) internal override {
    ICToken(address(lpTokens[_index])).redeem(_amount);
  }

  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount.mulDiv(ICToken(address(lpTokens[_index])).exchangeRateStored(), 1e18); // eg. 1e12*1e(36-8)/1e18 = 1e18
  }

  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount.mulDiv(1e18, ICToken(address(lpTokens[_index])).exchangeRateStored()); // eg. 1e18*1e18/1e(36-8) = 1e12
  }

  function rewardsAvailable() public view override returns (uint256[] memory amounts) {
    uint256 mainReward = _unitroller.compAccrued(address(this));
    return _rewardLength == 1
      ? mainReward.toArray()
      : mainReward.toArray(_balance(rewardTokens[1]));
  }

  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    _unitroller.claimComp(address(this)); // claim for all markets
    // wrap native rewards if needed
    _wrapNative();
    for (uint256 i = 0; i < _rewardLength; i++) {
      amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
    }
  }
}
