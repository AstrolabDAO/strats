// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5.sol";
import "./interfaces/IMoonwell.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title Moonwell Strategy - Liquidity providing on Moonwell (Base & co)
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Moonwell (https://moonwell.fi/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract Moonwell is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  // strategy specific variables
  IUnitroller internal _unitroller;
  bool internal _legacy;

  constructor(address _accessController) StrategyV5(_accessController) {}

  function _isLegacy(IUnitroller _unitroller) internal view returns (bool) {
    bool isLegacy;
    try unitroller.claimReward(uint8(0), address(this)) {
      isLegacy = true; // `rewardType` parameter exists
    } catch {
      isLegacy = false;
    }
    return isLegacy;
  }

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function _setParams(bytes memory _params) internal override {
    address unitroller = abi.decode(_params, (address));
    _unitroller = IUnitroller(unitroller);
    _legacy = _isLegacy(_unitroller);
    _setAllowances(AsMaths.MAX_UINT256);
  }

  /**
   * @notice Claim rewards from the third party contracts
   * @return amounts Array of rewards claimed for each reward token
   */
  function claimRewards() public virtual override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    if (_legacy) {
      _unitroller.claimReward(0, address(this)); // WELL for all markets
      _unitroller.claimReward(1, address(this)); // WGAS for all markets
    } else {
      _unitroller.claimReward(address(this)); // claim for all markets
    }
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
  function _stake(uint256 _index, uint256 _amount) internal override {
    IMToken(address(lpTokens[_index])).mint(_amount);
  }

  /**
   * @notice Unstakes or liquidates `_amount` of `lpTokens[i]` back to `input[_index]`
   * @param _index Index of the input to liquidate
   * @param _amount Amount of underlying assets to recover from liquidating `inputs[_index]`
   */
  function _unstake(uint256 _index, uint256 _amount) internal override {
    IMToken(address(lpTokens[_index])).redeem(_amount);
  }

  /**
   * @notice Converts LP/staked LP to input
   * @param _amount Amount of LP/staked LP
   * @param _index Index of the LP token
   * @return Input value of the LP amount
   */
  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount.mulDiv(IMToken(address(lpTokens[_index])).exchangeRateStored(), 1e18);
  }

  /**
   * @notice Converts input to LP/staked LP
   * @param _amount Amount of input
   * @param _index Index of the input
   * @return LP value of the input amount
   */
  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount.mulDiv(1e18, IMToken(address(lpTokens[_index])).exchangeRateStored());
  }

  /**
   * @notice Returns the available rewards
   * @return amounts Array of rewards available for each reward token
   */
  function rewardsAvailable()
    public
    view
    virtual
    override
    returns (uint256[] memory amounts)
  {
    if (_legacy) {
      return _unitroller.rewardAccrued(uint8(0), address(this)) // WELL
      .toArray(_unitroller.rewardAccrued(uint8(1), address(this))); // WGLMR/WMOVR
    }
    IMultiRewardDistributor distributor =
      IMultiRewardDistributor(_unitroller.rewardDistributor());
    MultiRewardDistributorCommon.RewardWithMToken[] memory pendingRewards =
      distributor.getOutstandingRewardsForUser(address(this));

    amounts = new uint256[](_rewardLength);

    for (uint256 i = 0; i < pendingRewards.length; i++) {
      for (uint256 j = 0; j < pendingRewards[i].rewards.length; j++) {
        MultiRewardDistributorCommon.RewardInfo memory info = pendingRewards[i].rewards[j];
        address token = info.emissionToken;
        uint256 index = _rewardTokenIndexes[token];
        if (index == 0) continue;
        amounts[index - 1] += info.totalAmount;
        info.totalAmount;
      }
    }

    for (uint256 i = 0; i < _rewardLength; i++) {
      amounts[i] += _balance(rewardTokens[i]);
    }

    return amounts;
  }
}
