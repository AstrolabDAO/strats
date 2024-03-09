// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/ISonne.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title SonneMultiStake Strategy - Liquidity providing on Sonne
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Sonne (https://sonne.finance/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract SonneMultiStake is StrategyV5Chainlink {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  // Third party contracts
  ICToken[8] internal _cTokens; // LP token/pool
  uint8[8] internal _cTokenDecimals; // Decimals of the LP tokens
  IUnitroller internal _unitroller;

  constructor() StrategyV5Chainlink() {}

  // Struct containing the strategy init parameters
  struct Params {
    address[] cTokens;
    address unitroller; // rewards controller
  }

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function setParams(Params calldata _params) public onlyAdmin {
    _unitroller = IUnitroller(_params.unitroller);
    for (uint8 i = 0; i < _params.cTokens.length; i++) {
      _cTokens[i] = ICToken(_params.cTokens[i]);
      _cTokenDecimals[i] = _cTokens[i].decimals();
    }
    _setAllowances(_MAX_UINT256);
  }

  /**
   * @dev Initializes the strategy with the specified parameters
   * @param _baseParams StrategyBaseParams struct containing strategy parameters
   * @param _chainlinkParams Chainlink specific parameters
   * @param _sonneParams Sonne specific parameters
   */
  function init(
    StrategyBaseParams calldata _baseParams,
    ChainlinkParams calldata _chainlinkParams,
    Params calldata _sonneParams
  ) external onlyAdmin {
    for (uint8 i = 0; i < _sonneParams.cTokens.length; i++) {
      inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
      inputWeights[i] = _baseParams.inputWeights[i];
      _inputDecimals[i] = inputs[i].decimals();
    }
    _rewardLength = uint8(_baseParams.rewardTokens.length);
    _inputLength = uint8(_baseParams.inputs.length);
    setParams(_sonneParams);
    StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
  }

  /**
   * @notice Claim rewards from the third party contracts
   * @return amounts Array of rewards claimed for each reward token
   */
  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    _unitroller.claimComp(address(this)); // claim for all markets
    // wrap native rewards if needed
    _wrapNative();
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

      uint256 iouBefore = _cTokens[i].balanceOf(address(this));
      _cTokens[i].mint(toDeposit);

      uint256 supplied = _cTokens[i].balanceOf(address(this)) - iouBefore;

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

      balance = _cTokens[i].balanceOf(address(this));

      // NB: we could use redeemUnderlying() here
      toLiquidate = AsMaths.min(_inputToStake(_amounts[i], i), balance);

      _cTokens[i].redeem(toLiquidate);

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
      inputs[i].forceApprove(address(_cTokens[i]), _amount);
    }
  }

  /**
   * @notice Returns the investment in asset asset for the specified input
   * @param _index Index of the input
   * @return total Amount invested
   */
  function invested(uint256 _index) public view override returns (uint256) {
    return _inputToAsset(investedInput(_index), _index);
  }

  /**
   * @notice Returns the investment in asset asset for the specified input
   * @param _index Index of the input
   * @return total Amount invested
   */
  function investedInput(uint256 _index) internal view override returns (uint256) {
    return _stakedInput(_index);
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
    return _amount.mulDiv(_cTokens[_index].exchangeRateStored(), 1e18); // eg. 1e12+1e(36-8)-1e18 = 1e18
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
    return _amount.mulDiv(1e18, _cTokens[_index].exchangeRateStored()); // eg. 1e18+1e18-1e(36-8) = 1e12
  }

  /**
   * @notice Returns the invested input converted from the staked LP token
   * @param _index Index of the LP token
   * @return Input value of the LP/staked balance
   */
  function _stakedInput(uint256 _index) internal view override returns (uint256) {
    return _stakeToInput(_cTokens[_index].balanceOf(address(this)), _index);
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
