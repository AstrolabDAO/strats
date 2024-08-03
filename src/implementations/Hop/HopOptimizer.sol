// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../../abstract/StrategyV5.sol";
import "./interfaces/IStableRouter.sol";
import "./interfaces/IStakingRewards.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title Hop Optimizer - Dynamic liquidity providing on Hop
 * @author Astrolab DAO
 * @notice Basic liquidity providing strategy for Hop protocol (https://hop.exchange/)
 * @dev Asset->input[0]->LP->rewardPools->LP->input[0]->asset
 */
contract HopOptimizer is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  IStableRouter[8] internal _stableRouters; // SaddleSwap
  IStakingRewards[8][4] internal _rewardPools; // Reward pool
  mapping(address => address) internal _tokenByRewardPool;
  uint8[8] internal _tokenIndexes;

  constructor(address _accessController) StrategyV5(_accessController) {}

  struct Params {
    address[][] rewardPools;
    address[] stableRouters;
    uint8[] tokenIndexes;
  }

  function _setParams(bytes memory _params) internal override {
    Params memory params = abi.decode(_params, (Params));
    for (uint256 i = 0; i < _inputLength;) {
      _tokenIndexes[i] = params.tokenIndexes[i];
      _stableRouters[i] = IStableRouter(params.stableRouters[i]);
      setRewardPools(params.rewardPools[i], i);
      unchecked {
        i++;
      }
    }
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

  function setRewardPools(address[] memory rewardPools, uint256 _index) public onlyAdmin {
    // for (uint256 j = 0; j < _rewardPools[_index].length; j++) {
    IStakingRewards pool = IStakingRewards(rewardPools[0]);
    // if (addr == address(0)) break;
    _rewardPools[_index][0] = pool;
    address rewardToken = pool.rewardsToken();
    _tokenByRewardPool[address(pool)] = rewardToken;
    // }
  }

  function _addLiquiditySingleSide(
    uint256 _amount,
    uint256 _index
  ) internal returns (uint256 deposited) {
    deposited = _stableRouters[_index].addLiquidity({
      amounts: _tokenIndexes[_index] == 0 ? _amount.toArray(0) : uint256(0).toArray(_amount), // determine the side from the token index
      minToMint: 1, // minToMint
      deadline: block.timestamp // blocktime only
    });
  }

  function _stake(uint256 _amount, uint256 _index) internal override {
    _rewardPools[_index][0].stake(_addLiquiditySingleSide(_amount, _index));
  }

  function _unstake(uint256 _amount, uint256 _index) internal override {
    _rewardPools[_index][0].withdraw(_amount);
    _stableRouters[_index].removeLiquidityOneToken({
      tokenAmount: lpTokens[_index].balanceOf(address(this)),
      tokenIndex: _tokenIndexes[_index],
      minAmount: 1, // slippage is checked after swap
      deadline: block.timestamp
    });
  }

  function _setLpTokenAllowances(uint256 _amount) internal override {
    for (uint256 i = 0; i < _inputLength;) {
      inputs[i].forceApprove(address(_stableRouters[i]), _amount);
      lpTokens[i].forceApprove(address(_stableRouters[i]), _amount);
      // for (uint256 j = 0; j < _rewardPools[i].length; j++) {
      if (address(_rewardPools[i][0]) == address(0)) break; // no overflow (static array)
      lpTokens[i].forceApprove(address(_rewardPools[i][0]), _amount);
      // }
      unchecked {
        i++;
      }
    }
  }

  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount.mulDiv(
      _stableRouters[_index].getVirtualPrice(), 10 ** (36 - _inputDecimals[_index])
    ); // 1e18 == lpToken[i] decimals
  }

  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount.mulDiv(
      10 ** (36 - _inputDecimals[_index]), _stableRouters[_index].getVirtualPrice()
    );
  }

  function _investedInput(uint256 _index) internal view override returns (uint256) {
    return _stakeToInput(_rewardPools[_index][0].balanceOf(address(this)), _index);
  }

  function rewardsAvailable() public view override returns (uint256[] memory amounts) {
    amounts = uint256(_rewardLength).toArray();
    for (uint256 i = 0; i < _inputLength;) {
      // uint8 length = uint8(rewardPools[i].length);
      // for (uint256 j = 0; j < length; j++) {
      IStakingRewards pool = _rewardPools[i][0];
      if (address(pool) == address(0)) break; // no overflow (static array)
      address rewardToken = _tokenByRewardPool[address(_rewardPools[i][0])];
      uint256 index = _rewardTokenIndexes[rewardToken];
      if (index == 0) continue;
      amounts[index - 1] += pool.earned(address(this));
      // }
      unchecked {
        i++;
      }
    }
  }

  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    for (uint256 i = 0; i < _inputLength;) {
      // for (uint256 j = 0; j < _rewardPools[i].length; j++) {
      if (address(_rewardPools[i][0]) == address(0)) break;
      _rewardPools[i][0].getReward();
      // }
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
