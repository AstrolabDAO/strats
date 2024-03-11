// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsMaths.sol";
import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/IStableRouter.sol";
import "./interfaces/IStakingRewards.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title HopMultiStake - Liquidity providing on Hop (n stable (max 5), eg. USDC+USDT+DAI)
 * @author Astrolab DAO
 * @notice Basic liquidity providing strategy for Hop protocol (https://hop.exchange/)
 * @dev Asset->input[0]->LP->rewardPools->LP->input[0]->asset
 */
contract HopMultiStake is StrategyV5Chainlink {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  // Third party contracts
  IERC20Metadata[5] internal _lpTokens; // LP token of the pool
  IStableRouter[5] internal _stableRouters; // SaddleSwap
  IStakingRewards[5][4] internal _rewardPools; // Reward pool
  mapping(address => address) internal _tokenByRewardPool;
  uint8[5] internal _tokenIndexes;

  constructor() StrategyV5Chainlink() {}

  // Struct containing the strategy init parameters
  struct Params {
    address[] lpTokens;
    address[][] rewardPools;
    address[] stableRouters;
    uint8[] tokenIndexes;
  }

  /**
   * @notice Sets the strategy parameters
   * @param _params Strategy parameters
   */
  function setParams(Params calldata _params) public onlyAdmin {
    for (uint8 i = 0; i < _params.lpTokens.length; i++) {
      _lpTokens[i] = IERC20Metadata(_params.lpTokens[i]);
      _tokenIndexes[i] = _params.tokenIndexes[i];
      _stableRouters[i] = IStableRouter(_params.stableRouters[i]);
      setRewardPools(_params.rewardPools[i], i);
    }
    _setAllowances(_MAX_UINT256);
  }

  /**
   * @notice Sets the reward pools
   * @param rewardPools Array of reward pools
   */
  function setRewardPools(address[] calldata rewardPools, uint8 _index) public onlyAdmin {
    // for (uint8 j = 0; j < _rewardPools[_index].length; j++) {
    IStakingRewards pool = IStakingRewards(rewardPools[0]);
    // if (addr == address(0)) break;
    _rewardPools[_index][0] = pool;
    address rewardToken = pool.rewardsToken();
    _tokenByRewardPool[address(pool)] = rewardToken;
    // }
  }

  /**
   * @dev Initializes the strategy with the specified parameters
   * @param _baseParams StrategyBaseParams struct containing strategy parameters
   * @param _chainlinkParams Chainlink specific parameters
   * @param _hopParams Hop specific parameters
   */
  function init(
    StrategyBaseParams calldata _baseParams,
    ChainlinkParams calldata _chainlinkParams,
    Params calldata _hopParams
  ) external onlyAdmin {
    for (uint8 i = 0; i < _hopParams.lpTokens.length; i++) {
      // these can be set externally by setInputs()
      inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
      inputWeights[i] = _baseParams.inputWeights[i];
      _inputDecimals[i] = inputs[i].decimals();
    }
    _rewardLength = uint8(_baseParams.rewardTokens.length);
    _inputLength = uint8(_baseParams.inputs.length);
    setParams(_hopParams);
    StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
  }

  /**
   * @notice Claim rewards from the third party contracts
   * @return amounts Array of rewards claimed for each reward token
   */
  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    for (uint8 i = 0; i < _inputLength; i++) {
      // for (uint8 j = 0; j < _rewardPools[i].length; j++) {
      if (address(_rewardPools[i][0]) == address(0)) break;
      _rewardPools[i][0].getReward();
      // }
    }
    for (uint8 i = 0; i < _rewardLength; i++) {
      amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
    }
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
    deposited = _stableRouters[_index].addLiquidity({
      amounts: _tokenIndexes[_index] == 0 ? _amount.toArray(0) : uint256(0).toArray(_amount), // determine the side from the token index
      minToMint: 1, // minToMint
      deadline: block.timestamp // blocktime only
    });
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

      // we only support single rewardPool staking (index 0)
      _rewardPools[i][0].stake(toStake);

      // would make more sense to return an array of ious
      // rather than mixing them like this
      iouReceived += toStake;
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
      // we only support single rewardPool staking (index 0)
      _rewardPools[i][0].withdraw(toLiquidate);

      recovered = _stableRouters[i].removeLiquidityOneToken({
        tokenAmount: _lpTokens[i].balanceOf(address(this)),
        tokenIndex: _tokenIndexes[i],
        minAmount: 1, // slippage is checked after swap
        deadline: block.timestamp
      });

      // swap the unstaked tokens (inputs[0]) for the asset asset if different
      if (inputs[i] != asset) {
        (recovered,) = swapper.decodeAndSwap({
          _input: address(inputs[i]),
          _output: address(asset),
          _amount: recovered,
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
   * @notice Sets allowances for third party contracts (except rewardTokens)
   * @param _amount Allowance amount
   */
  function _setAllowances(uint256 _amount) internal override {
    for (uint8 i = 0; i < _inputLength; i++) {
      inputs[i].forceApprove(address(_stableRouters[i]), _amount);
      _lpTokens[i].forceApprove(address(_stableRouters[i]), _amount);
      // for (uint8 j = 0; j < _rewardPools[i].length; j++) {
      if (address(_rewardPools[i][0]) == address(0)) break; // no overflow (static array)
      _lpTokens[i].forceApprove(address(_rewardPools[i][0]), _amount);
      // }
    }
  }

  /**
   * @notice Returns the investment in asset asset for the specified input
   * @return total Amount invested
   */
  function invested(uint256 _index) public view override returns (uint256) {
    return _stakeToAsset(_rewardPools[_index][0].balanceOf(address(this)), _index);
  }

  /**
   * @notice Converts LP/staked LP to input
   * @return Input value of the LP amount
   */
  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount.mulDiv(
      _stableRouters[_index].getVirtualPrice(), 10 ** (36 - _inputDecimals[_index])
    ); // 1e18 == lpToken[i] decimals
  }

  /**
   * @notice Converts input to LP/staked LP
   * @return LP value of the input amount
   */
  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount.mulDiv(
      10 ** (36 - _inputDecimals[_index]), _stableRouters[_index].getVirtualPrice()
    );
  }

  /**
   * @notice Returns the invested input converted from the staked LP token
   * @return Input value of the LP/staked balance
   */
  function _investedInput(uint256 _index) internal view override returns (uint256) {
    return _stakeToInput(_rewardPools[_index][0].balanceOf(address(this)), _index);
  }

  /**
   * @notice Returns the available rewards
   * @return amounts Array of rewards available for each reward token
   */
  function rewardsAvailable() public view override returns (uint256[] memory amounts) {
    amounts = uint256(_rewardLength).toArray();
    for (uint8 i = 0; i < _inputLength; i++) {
      // uint8 length = uint8(rewardPools[i].length);
      // for (uint8 j = 0; j < length; j++) {
      IStakingRewards pool = _rewardPools[i][0];
      if (address(pool) == address(0)) break; // no overflow (static array)
      address rewardToken = _tokenByRewardPool[address(_rewardPools[i][0])];
      uint256 index = _rewardTokenIndexes[rewardToken];
      if (index == 0) continue;
      amounts[index - 1] += pool.earned(address(this));
      // }
    }
  }
}
