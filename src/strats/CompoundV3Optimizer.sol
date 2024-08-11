// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../libs/AsArrays.sol";
import "../core/StrategyV5.sol";
import "../external/Compound/v3/ICompoundV3.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title CompoundV3 Optimizer - Dynamic liquidity providing on Compound V3
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Compound (https://compound.finance/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract CompoundV3Optimizer is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  ICometRewards internal _rewardController;
  ICometRewards.RewardConfig[8] internal _rewardConfigs;
  bool internal _legacy;

  constructor(address _accessController) StrategyV5(_accessController) {}

  function _isLegacy(ICometRewards _controller) internal view returns (bool) {
    bool isLegacy;
    try _controller.rewardConfig(address(lpTokens[0])) returns (ICometRewards.RewardConfig memory) {
      isLegacy = false; // `multiplier` field exists in the struct
    } catch {
      isLegacy = true;
    }
    return isLegacy;
  }

  function _loadConfigs() internal {
    for (uint256 i = 0; i < _inputLength;) {
      if (_legacy) {
        ICometRewardsLegacy.RewardConfig memory tmp = ICometRewardsLegacy(address(_rewardController)).rewardConfig(address(lpTokens[i]));
        _rewardConfigs[i] = ICometRewards.RewardConfig({
          token: tmp.token,
          rescaleFactor: tmp.rescaleFactor,
          shouldUpscale: tmp.shouldUpscale,
          multiplier: 1 // polyfill for legacy deployments
        });
      } else {
        _rewardConfigs[i] = _rewardController.rewardConfig(address(lpTokens[i]));
      }
      unchecked {
        i++;
      }
    }
  }

  function _setParams(bytes memory _params) internal override {
    (address rewardController) = abi.decode(_params, (address));
    _rewardController = ICometRewards(rewardController);
    _legacy = _isLegacy(_rewardController);
    _loadConfigs();
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

  function setInputs( // agent override
    address[] calldata _inputs,
    uint16[] calldata _weights,
    address[] calldata _lpTokens
  ) external onlyAdmin {
    // update inputs and lpTokens
    _setInputs(_inputs, _weights, _lpTokens);
    _loadConfigs();
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

  function _stake(uint256 _amount, uint256 _index) internal override {
    IComet(address(lpTokens[_index])).supply(address(inputs[_index]), _amount);
  }

  function _unstake(uint256 _amount, uint256 _index) internal override {
    IComet(address(lpTokens[_index])).withdraw(address(inputs[_index]), _amount);
  }

  function _rebaseAccruedReward(
    uint256 _amount,
    uint256 _index
  ) internal view returns (uint256) {
    ICometRewards.RewardConfig memory config = _rewardConfigs[_index];
    return config.shouldUpscale
      ? _amount.mulDiv(config.rescaleFactor, 1e18)
      : _amount.mulDiv(1e18, config.rescaleFactor);
  }

  function rewardsAvailable()
    public
    view
    virtual
    override
    returns (uint256[] memory amounts)
  {
    amounts = new uint256[](_rewardLength);

    for (uint256 i = 0; i < lpTokens.length;) {
      if (address(lpTokens[i]) == address(0)) break;
      amounts[0] += _rebaseAccruedReward(
        IComet(address(lpTokens[i])).baseTrackingAccrued(address(this)), i
      );
      unchecked {
        i++;
      }
    }
    for (uint256 i = 0; i < _rewardLength;) {
      amounts[i] += IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
      unchecked {
        i++;
      }
    }

    return amounts;
  }

  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    for (uint256 i = 0; i < lpTokens.length;) {
      if (address(lpTokens[i]) == address(0)) break;
      _rewardController.claim(address(lpTokens[i]), address(this), true);
      unchecked {
        i++;
      }
    }
    for (uint256 i = 0; i < _rewardLength;) {
      amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
      unchecked {
        i++;
      }
    }
  }
}
