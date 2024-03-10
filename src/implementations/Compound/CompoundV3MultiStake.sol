// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/v3/ICompoundV3.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title CompoundV3MultiStake Strategy - Liquidity providing on Compound V3 (Base & co)
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Compound (https://compound.finance/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract CompoundV3MultiStake is StrategyV5Chainlink {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  // Third party contracts
  address[8] public cTokens; // LP token/pool
  ICometRewards internal _cometRewards;
  ICometRewards.RewardConfig[8] internal _rewardConfigs;

  constructor() StrategyV5Chainlink() {}

  // Struct containing the strategy init parameters
  struct Params {
    address[] cTokens;
    address cometRewards; // rewards controller
  }

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function setParams(Params calldata _params) public onlyAdmin {
    // unitroller = IUnitroller(_params.unitroller);
    _cometRewards = ICometRewards(_params.cometRewards);

    for (uint8 i = 0; i < _params.cTokens.length; i++) {
      cTokens[i] = _params.cTokens[i];
      _rewardConfigs[i] = _cometRewards.rewardConfig(_params.cTokens[i]);
    }
    _setAllowances(_MAX_UINT256);
  }

  /**
   * @dev Initializes the strategy with the specified parameters
   * @param _baseParams StrategyBaseParams struct containing strategy parameters
   * @param _chainlinkParams Chainlink specific parameters
   * @param _compoundParams Sonne specific parameters
   */
  function init(
    StrategyBaseParams calldata _baseParams,
    ChainlinkParams calldata _chainlinkParams,
    Params calldata _compoundParams
  ) external onlyAdmin {
    for (uint8 i = 0; i < _compoundParams.cTokens.length; i++) {
      inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
      inputWeights[i] = _baseParams.inputWeights[i];
      _inputDecimals[i] = inputs[i].decimals();
    }
    _rewardLength = uint8(_baseParams.rewardTokens.length);
    _inputLength = uint8(_baseParams.inputs.length);
    setParams(_compoundParams);
    StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
  }

  /**
   * @notice Changes the strategy input tokens
   * @param _newInputs Array of input token addresses
   * @param _cTokens Array of cTokens addresses
   * @param _weights Array of input token weights
   * @param _priceFeeds Array of Chainlink price feed addresses
   */
  function setInputs(
    address[] calldata _newInputs,
    address[] calldata _cTokens,
    uint16[] calldata _weights,
    address[] calldata _priceFeeds,
    uint256[] calldata _validities
  ) external onlyAdmin {
    for (uint256 i = 0; i < _cTokens.length; i++) {
      cTokens[i] = _cTokens[i];
      _rewardConfigs[i] = _cometRewards.rewardConfig(_cTokens[i]);
    }
    _setAllowances(_MAX_UINT256);
    setInputs(_newInputs, _weights, _priceFeeds, _validities);
  }

  /**
   * @notice Claim rewards from the third party contracts
   * @return amounts Array of rewards claimed for each reward token
   */
  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    for (uint8 i = 0; i < cTokens.length; i++) {
      if (address(cTokens[i]) == address(0)) break;
      _cometRewards.claim(address(cTokens[i]), address(this), true);
    }
    for (uint8 i = 0; i < _rewardLength; i++) {
      amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
    }
  }

  /**
   * @notice Invests the asset asset into the pool
   * @param _amounts Amounts of asset to invest in each input
   * @param _params Swaps calldata
   * @return investedAmount Amount invested
   * @return iouReceived Amount of LP tokens received
   */
  function _invest(
    uint256[8] calldata _amounts, // from previewInvest()
    bytes[] calldata _params
  ) internal override nonReentrant returns (uint256 investedAmount, uint256 iouReceived) {
    uint256 toDeposit;
    uint256 spent;

    for (uint8 i = 0; i < _inputLength; i++) {
      if (_amounts[i] < 10) continue;

      // We deposit the whole asset balance
      if (asset != inputs[i] && _amounts[i] > 10) {
        (toDeposit, spent) = swapper.decodeAndSwap({
          _input: address(asset),
          _output: address(inputs[i]),
          _amount: _amounts[i],
          _params: _params[i]
        });
        investedAmount += spent;
        // pick up any input dust (eg. from previous liquidate()), not just the swap output
        toDeposit = inputs[i].balanceOf(address(this));
      } else {
        investedAmount += _amounts[i];
        toDeposit = _amounts[i];
      }

      IComet cToken = IComet(cTokens[i]);
      uint256 iouBefore = cToken.balanceOf(address(this));
      cToken.supply(address(inputs[i]), toDeposit);

      uint256 supplied = cToken.balanceOf(address(this)) - iouBefore;

      // unified slippage check (swap+add liquidity)
      if (supplied < _inputToStake(toDeposit, i).subBp(_maxSlippageBps * 2)) {
        revert AmountTooLow(supplied);
      }

      // NB: better return ious[]
      iouReceived += supplied;
    }
  }

  /**
   * @notice Withdraw asset function, can remove all funds in case of emergency
   * @param _amounts Amounts of asset to withdraw
   * @param _params Swaps calldata
   * @return assetsRecovered Amount of asset withdrawn
   */
  function _liquidate(
    uint256[8] calldata _amounts, // from previewLiquidate()
    bytes[] calldata _params
  ) internal override returns (uint256 assetsRecovered) {
    uint256 toLiquidate;
    uint256 recovered;
    uint256 balance;

    for (uint8 i = 0; i < _inputLength; i++) {
      if (_amounts[i] < 10) continue;

      IComet cToken = IComet(cTokens[i]);
      balance = cToken.balanceOf(address(this));

      // NB: we could use redeemUnderlying() here
      toLiquidate = AsMaths.min(_inputToStake(_amounts[i], i), balance);

      cToken.withdraw(address(inputs[i]), toLiquidate);

      // swap the unstaked tokens (inputs[0]) for the asset asset if different
      if (inputs[i] != asset && toLiquidate > 10) {
        (recovered,) = swapper.decodeAndSwap({
          _input: address(inputs[i]),
          _output: address(asset),
          _amount: _amounts[i],
          _params: _params[i]
        });
      } else {
        recovered = toLiquidate;
      }

      // unified slippage check (unstake+remove liquidity+swap out)
      if (recovered < _inputToAsset(_amounts[i], i).subBp(_maxSlippageBps * 2)) {
        revert AmountTooLow(recovered);
      }

      assetsRecovered += recovered;
    }
  }

  /**
   * @notice Sets allowances for third party contracts (except rewardTokens)
   * @param _amount Allowance amount
   */
  function _setAllowances(uint256 _amount) internal override {
    for (uint8 i = 0; i < _inputLength; i++) {
      inputs[i].forceApprove(address(cTokens[i]), _amount);
    }
  }

  /**
   * @notice Returns the investment in asset asset for the specified input
   * @return total Amount invested
   */
  function invested(uint256 _index) public view override returns (uint256) {
    return _inputToAsset(investedInput(_index), _index);
  }

  /**
   * @notice Returns the investment in asset asset for the specified input
   * @return total Amount invested
   */
  function investedInput(uint256 _index) internal view override returns (uint256) {
    return _stakedInput(_index);
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
  function _stakedInput(uint256 _index) internal view override returns (uint256) {
    return IComet(cTokens[_index]).balanceOf(address(this));
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

    for (uint8 i = 0; i < cTokens.length; i++) {
      if (address(cTokens[i]) == address(0)) break;
      amounts[0] +=
        _rebaseAccruedReward(IComet(cTokens[i]).baseTrackingAccrued(address(this)), i);
    }
    for (uint8 i = 0; i < _rewardLength; i++) {
      amounts[i] += IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
    }

    return amounts;
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
}
