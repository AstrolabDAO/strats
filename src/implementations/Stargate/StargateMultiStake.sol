// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsMaths.sol";
import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/IStargate.sol";

/**
 * _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title StargateMultiStake - Liquidity providing on Stargate
 * @author Astrolab DAO
 * @notice Basic liquidity providing strategy for Stargate (https://stargate.finance/)
 * @dev Asset->input[0]->LP->pools->LP->input[0]->asset
 */
contract StargateMultiStake is StrategyV5Chainlink {
  using AsMaths for uint256;
  using AsArrays for uint256;

  // Third party contracts
  IStargateRouter[5] internal routers; // stargate router
  ILPStaking internal lpStaker; // LP staker (one for all pools)
  IPool[5] internal lps; // LP token of the pool
  uint16[5] internal poolIds; // pool ids
  uint16[5] internal stakingIds; // pool ids for the staking
  uint256[5] internal lpWeiPerShare;

  constructor() StrategyV5Chainlink() {}

  // Struct containing the strategy init parameters
  struct Params {
    address lpStaker;
    address[] lps;
    uint16[] stakingIds;
  }

  /**
   * @notice Sets the strategy parameters
   * @param _params Strategy parameters
   */
  function setParams(Params calldata _params) public onlyAdmin {
    if (_params.lpStaker == address(0)) {
      revert AddressZero();
    }
    lpStaker = ILPStaking(_params.lpStaker);
    for (uint8 i = 0; i < _params.lps.length; i++) {
      // Specify the pools
      lps[i] = IPool(_params.lps[i]);
      stakingIds[i] = _params.stakingIds[i];
      poolIds[i] = uint16(lps[i].poolId());
      routers[i] = IStargateRouter(lps[i].router());
      lpWeiPerShare[i] = 10 ** lps[i].decimals();
    }
  }

  /**
   * @dev Initializes the strategy with the specified parameters
   * @param _baseParams StrategyBaseParams struct containing strategy parameters
   * @param _chainlinkParams Chainlink specific parameters
   * @param _stargateParams Stargate specific parameters
   */
  function init(
    StrategyBaseParams calldata _baseParams,
    ChainlinkParams calldata _chainlinkParams,
    Params calldata _stargateParams
  ) external onlyAdmin {
    for (uint8 i = 0; i < _stargateParams.lps.length; i++) {
      // these can be set externally by setInputs()
      inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
      inputWeights[i] = _baseParams.inputWeights[i];
      _inputDecimals[i] = inputs[i].decimals();
    }
    _rewardLength = uint8(_baseParams.rewardTokens.length);
    _inputLength = uint8(_baseParams.inputs.length);
    setParams(_stargateParams);
    _setAllowances(_MAX_UINT256);
    StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
  }

  /**
   * @notice Adds liquidity to the pool, single sided
   * @param _amount Max amount of asset to invest
   * @param _index Index of the input token
   * @return deposited Amount of LP tokens received
   */
  function _addLiquiditySingleSide(
    uint256 _amount,
    uint8 _index
  ) internal returns (uint256 deposited) {
    routers[_index].addLiquidity(poolIds[_index], _amount, address(this));
    return lps[_index].balanceOf(address(this));
  }

  /**
   * @notice Invests the asset asset into the pool
   * @param _amounts Amounts of asset to invest in each input
   * @param _params Swaps calldata
   * @return investedAmount Amount invested
   * @return iouReceived Amount of LP tokens received
   */
  // NB: better return ious[]
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

      // Adding liquidity to the pool with the inputs[0] balance
      uint256 toStake = _addLiquiditySingleSide(toDeposit, i);

      // unified slippage check (swap+add liquidity)
      if (toStake < _inputToStake(toDeposit, i).subBp(_4626StorageExt().maxSlippageBps * 2)) {
        revert AmountTooLow(toStake);
      }

      uint256 balanceBefore = lpStaker.userInfo(stakingIds[i], address(this)).amount;
      // we only support single rewardPool staking (index 0)
      lpStaker.deposit(stakingIds[i], toStake);

      // would make more sense to return an array of ious
      // rather than mixing them like this
      iouReceived +=
        lpStaker.userInfo(stakingIds[i], address(this)).amount - balanceBefore;
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

    for (uint8 i = 0; i < _inputLength; i++) {
      if (_amounts[i] < 10) continue;

      toLiquidate = _inputToStake(_amounts[i], i);
      // unstake LPs
      lpStaker.withdraw(stakingIds[i], toLiquidate);
      uint256 balanceBefore = inputs[i].balanceOf(address(this));
      // liquidate LPs
      routers[i].instantRedeemLocal(poolIds[i], toLiquidate, address(this));
      recovered = inputs[i].balanceOf(address(this)) - balanceBefore;

      // swap the unstaked tokens (inputs[0]) for the asset asset if different
      if (inputs[i] != asset) {
        (recovered,) = swapper.decodeAndSwap({
          _input: address(inputs[i]),
          _output: address(asset),
          _amount: _amounts[i],
          _params: _params[i]
        });
      }

      // unified slippage check (unstake+remove liquidity+swap out)
      if (recovered < _inputToAsset(_amounts[i], i).subBp(_4626StorageExt().maxSlippageBps * 2)) {
        revert AmountTooLow(recovered);
      }

      assetsRecovered += recovered;
    }
  }

  /**
   * @notice Claim rewards from the third party contracts
   * @return amounts Array of rewards claimed for each reward token
   */
  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    for (uint8 i = 0; i < _inputLength; i++) {
      if (address(inputs[i]) == address(0)) break;
      // withdraw/deposit with 0 still claims STG rewards
      lpStaker.withdraw(poolIds[i], 0);
    }
    for (uint8 i = 0; i < _rewardLength; i++) {
      amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
    }
  }

  /**
   * @notice Sets allowances for third party contracts (except rewardTokens)
   * @param _amount Allowance amount
   */
  function _setAllowances(uint256 _amount) internal override {
    for (uint8 i = 0; i < _inputLength; i++) {
      lps[i].approve(address(lpStaker), _amount);
      inputs[i].approve(address(routers[i]), _amount);
    }
  }

  /**
   * @notice Returns the investment in asset asset for the specified input
   * @return total Amount invested
   */
  function invested(uint256 _index) public view override returns (uint256) {
    return
      _stakeToAsset(lpStaker.userInfo(stakingIds[_index], address(this)).amount, _index);
  }

  

  /**
   * @notice Converts LP/staked LP to input
   * @return Input value of the LP amount
   */
  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return lps[_index].amountLPtoLD(_amount); // stake/lp -> input decimals
  }

  /**
   * @notice Converts input to LP/staked LP
   * @return LP value of the input amount
   */
  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount // input decimals
      .mulDiv(
      lpWeiPerShare[_index], // lp/stake decimals
      lps[_index].amountLPtoLD(lpWeiPerShare[_index])
    ); // input decimals
  }

  /**
   * @notice Returns the invested input converted from the staked LP token
   * @return Input value of the LP/staked balance
   */
  function _investedInput(uint256 _index) internal view override returns (uint256) {
    return
      _stakeToInput(lpStaker.userInfo(stakingIds[_index], address(this)).amount, _index);
  }

  /**
   * @notice Returns the available rewards
   * @return amounts Array of rewards available for each reward token
   */
  function rewardsAvailable() public view override returns (uint256[] memory amounts) {
    amounts = uint256(_rewardLength).toArray();
    for (uint8 i = 0; i < _inputLength; i++) {
      if (address(inputs[i]) == address(0)) break;
      amounts[0] += lpStaker.userInfo(poolIds[i], address(this)).amount;
    }
  }
}
