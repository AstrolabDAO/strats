// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5.sol";
import "./interfaces/v3/ICompoundV3Mainnet.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title CompoundV3MultiStake L1 Strategy - Liquidity providing on Compound V3 (Base & co)
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Compound (https://compound.finance/)
 * @dev Asset->inputs->LPs->inputs->asset
 * @dev Specific implementation with ETH-mainnet interface (diff in structure type)
 */
contract CompoundV3MultiStakeL1 is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  // strategy specific variables
  ICometRewards internal _rewardController;
  ICometRewards.RewardConfig[8] internal _rewardConfigs;

  constructor(address _accessController) StrategyV5(_accessController) {}

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function _setParams(bytes memory _params) internal override {
    (address rewardController) = abi.decode(_params, (address));
    _rewardController = ICometRewards(rewardController);
    for (uint8 i = 0; i < _inputLength;) {
      _rewardConfigs[i] = _rewardController.rewardConfig(address(lpTokens[i]));
      unchecked {
        i++;
      }
    }
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
    // update reward configs based on new lpTokens
    for (uint256 i = 0; i < _inputLength;) {
      _rewardConfigs[i] = _rewardController.rewardConfig(address(lpTokens[i]));
      unchecked {
        i++;
      }
    }
    _setAllowances(AsMaths.MAX_UINT256);
  }

  /**
   * @notice Stakes or provides `_amount` from `input[_index]` to `lpTokens[_index]`
   * @param _index Index of the input to stake
   * @param _amount Amount of underlying assets to allocate to `inputs[_index]`
   */
  function _stake(uint8 _index, uint256 _amount) internal override {
    IComet(address(lpTokens[_index])).supply(address(inputs[_index]), _amount);
  }

  /**
   * @notice Unstakes or liquidates `_amount` of `lpTokens[i]` back to `input[_index]`
   * @param _index Index of the input to liquidate
   * @param _amount Amount of underlying assets to recover from liquidating `inputs[_index]`
   */
  function _unstake(uint8 _index, uint256 _amount) internal override {
    IComet(address(lpTokens[_index])).withdraw(address(inputs[_index]), _amount);
  }

  /**
   * @notice Sets allowances for third party contracts (except rewardTokens)
   * @param _amount Allowance amount
   */
  function _setAllowances(uint256 _amount) internal override {
    for (uint8 i = 0; i < _inputLength; i++) {
      inputs[i].forceApprove(address(lpTokens[i]), _amount);
    }
  }

  /**
   * @notice Converts LP/staked LP to input
   * @return Input value of the LP amount
   */
  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal pure override returns (uint256) {
    return _amount; // 1:1 (rebasing, oracle value based)
  }

  /**
   * @notice Converts input to LP/staked LP
   * @return LP value of the input amount
   */
  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal pure override returns (uint256) {
    return _amount; // 1:1 (rebasing, oracle value based)
  }

  /**
   * @notice Returns the invested input converted from the staked LP token
   * @return Input value of the LP/staked balance
   */
  function _investedInput(uint256 _index) internal view override returns (uint256) {
    return IComet(address(lpTokens[_index])).balanceOf(address(this));
  }

  /**
   * @dev Calculates the rebased accrued reward based on the given amount and reward index
   * @param _amount The amount of reward to be rebased
   * @param _index The index of the reward configuration
   * @return The rebased accrued reward
   */
  function _rebaseAccruedReward(
    uint256 _amount,
    uint8 _index
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
