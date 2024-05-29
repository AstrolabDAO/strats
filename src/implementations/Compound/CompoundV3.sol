// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5.sol";
import "./interfaces/v3/ICompoundV3.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title CompoundV3 Strategy - Liquidity providing on Compound V3 (Base & co)
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Compound (https://compound.finance/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
abstract contract CompoundV3Abstract is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  // strategy specific variables
  ICometRewards internal _rewardController;
  ICometRewards.RewardConfig[8] internal _rewardConfigs;
  bool internal _legacy;

  constructor(address _accessController) StrategyV5(_accessController) {}

  /**
   * @notice Checks if the given `ICometRewards` contract is a legacy contract
   * @notice A legacy contract is determined by whether the `rewardConfig` returned `RewardConfig` struct contains a `multiplier` field
   * @notice If the call is successful, it means the `multiplier` field exists in the struct, indicating that the contract is not a legacy contract
   * @param _controller The `ICometRewards` contract to check
   * @return A boolean value indicating whether the contract is a legacy contract or not
   */
  function _isLegacy(ICometRewards _controller) internal view returns (bool) {
    bool isLegacy;
    try _controller.rewardConfig(_lpTokens[0]) returns (ICometRewards.RewardConfig memory config) {
      isLegacy = false; // `multiplier` field exists in the struct
    } catch {
      isLegacy = true;
    }
    return isLegacy;
  }

  /**
   * @notice Internal function to load reward configurations for each LP token
   * @dev If the reward controller is a legacy contract, a polyfill is used to set the multiplier to 1
   */
  function _loadConfigs() internal {
    for (uint256 i = 0; i < _inputLength;) {
      if (_legacy) {
        ICometRewardsLegacy.RewardConfig memory tmp = _rewardController.rewardConfig(address(lpTokens[i]));
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

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function _setParams(bytes memory _params) internal override {
    (address rewardController) = abi.decode(_params, (address));
    _rewardController = ICometRewards(rewardController);
    _legacy = _isLegacy(_rewardController);
    _loadConfigs();
    _setAllowances(AsMaths.MAX_UINT256);
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
    _loadConfigs();
    _setAllowances(AsMaths.MAX_UINT256);
  }

  /**
   * @notice Stakes or provides `_amount` from `input[_index]` to `lpTokens[_index]`
   * @param _index Index of the input to stake
   * @param _amount Amount of underlying assets to allocate to `inputs[_index]`
   */
  function _stake(uint256 _index, uint256 _amount) internal override {
    IComet(address(lpTokens[_index])).supply(address(inputs[_index]), _amount);
  }

  /**
   * @notice Unstakes or liquidates `_amount` of `lpTokens[i]` back to `input[_index]`
   * @param _index Index of the input to liquidate
   * @param _amount Amount of underlying assets to recover from liquidating `inputs[_index]`
   */
  function _unstake(uint256 _index, uint256 _amount) internal override {
    IComet(address(lpTokens[_index])).withdraw(address(inputs[_index]), _amount);
  }

  /**
   * @dev Calculates the rebased accrued reward based on the given amount and reward index
   * @param _amount The amount of reward to be rebased
   * @param _index The index of the reward configuration
   * @return The rebased accrued reward
   */
  function _rebaseAccruedReward(
    uint256 _amount,
    uint256 _index
  ) internal view returns (uint256) {
    ICometRewards.RewardConfig memory config = _rewardConfigs[_index];
    return config.shouldUpscale
      ? _amount.mulDiv(config.rescaleFactor, 1e18)
      : _amount.mulDiv(1e18, config.rescaleFactor);
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
    amounts = new uint256[](_rewardLength);

    for (uint8 i = 0; i < lpTokens.length;) {
      if (address(lpTokens[i]) == address(0)) break;
      amounts[0] += _rebaseAccruedReward(
        IComet(address(lpTokens[i])).baseTrackingAccrued(address(this)), i
      );
      unchecked {
        i++;
      }
    }
    for (uint8 i = 0; i < _rewardLength;) {
      amounts[i] += IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
      unchecked {
        i++;
      }
    }

    return amounts;
  }

  /**
   * @notice Claim rewards from the third party contracts
   * @return amounts Array of rewards claimed for each reward token
   */
  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    for (uint8 i = 0; i < lpTokens.length;) {
      if (address(lpTokens[i]) == address(0)) break;
      _rewardController.claim(address(lpTokens[i]), address(this), true);
      unchecked {
        i++;
      }
    }
    for (uint8 i = 0; i < _rewardLength;) {
      amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
      unchecked {
        i++;
      }
    }
  }
}
