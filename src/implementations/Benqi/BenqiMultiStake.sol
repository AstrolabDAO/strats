// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5.sol";
import "./interfaces/IBenqi.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title BenqiMultiStake Strategy - Liquidity providing on Benqi
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Sonne (https://benqi.fi/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract BenqiMultiStake is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  // strategy specific variables
  IUnitroller internal _unitroller;

  constructor(address _accessController) StrategyV5(_accessController) {}

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function _setParams(bytes memory _params) internal override {
    address unitroller = abi.decode(_params, (address));
    _unitroller = IUnitroller(unitroller);
    _setAllowances(AsMaths.MAX_UINT256);
  }

  /**
   * @notice Claim rewards from the third party contracts
   * @return amounts Array of rewards claimed for each reward token
   */
  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    _unitroller.claimReward(0, address(this)); // QI for all markets
    _unitroller.claimReward(1, address(this)); // WGAS for all markets

    // wrap native rewards if needed
    _wrapNative();
    for (uint8 i = 0; i < _rewardLength; i++) {
      amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
    }
  }

  /**
   * @notice Stakes or provides `_amount` from `input[_index]` to `lpTokens[_index]`
   * @param _index Index of the input to stake
   * @param _amount Amount of underlying assets to allocate to `inputs[_index]`
   */
  function _stake(uint8 _index, uint256 _amount) internal override {
    IQiToken(address(lpTokens[_index])).mint(_amount);
  }

  /**
   * @notice Unstakes or liquidates `_amount` of `lpTokens[i]` back to `input[_index]`
   * @param _index Index of the input to liquidate
   * @param _amount Amount of underlying assets to recover from liquidating `inputs[_index]`
   */
  function _unstake(uint8 _index, uint256 _amount) internal override {
    IQiToken(address(lpTokens[_index])).redeem(_amount);
  }

  /**
   * @notice Sets allowances for third party contracts (except rewardTokens)
   * @param _amount Allowance amount
   */
  function _setAllowances(uint256 _amount) internal override {
    for (uint8 i = 0; i < _inputLength;) {
      inputs[i].forceApprove(address(lpTokens[i]), _amount);
      unchecked {
        i++;
      }
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
    return _amount.mulDiv(IQiToken(address(lpTokens[_index])).exchangeRateStored(), 1e18); // eg. 1e12*1e(36-8)/1e18 = 1e18
  }

  /**
   * @notice Converts input to LP/staked LP
   * @return LP value of the input amount
   */
  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount.mulDiv(1e18, IQiToken(address(lpTokens[_index])).exchangeRateStored()); // eg. 1e18*1e18/1e(36-8) = 1e12
  }

  /**
   * @notice Returns the invested input converted from the staked LP token
   * @return Input value of the LP/staked balance
   */
  function _investedInput(uint256 _index) internal view override returns (uint256) {
    return _stakeToInput(lpTokens[_index].balanceOf(address(this)), _index);
  }

  /**
   * @notice Returns the available rewards
   * @return amounts Array of rewards available for each reward token
   */
  function rewardsAvailable() public view override returns (uint256[] memory amounts) {
    uint256 mainReward = _unitroller.compAccrued(address(this));
    return _rewardLength == 1
      ? mainReward.toArray()
      : mainReward.toArray(_balance(rewardTokens[1]));
  }
}
