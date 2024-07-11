// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../abstract/StrategyV5.sol";
import "./interfaces/v1/IStargate.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title Stargate Optimizer - Dynamic liquidity providing on Stargate
 * @author Astrolab DAO
 * @notice Basic liquidity providing strategy for Stargate V1 and V2 (https://stargate.finance/)
 * @dev Asset->input[0]->LP->pools->LP->input[0]->asset
 */
contract StargateV1Optimizer is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;

  IStargateRouter internal _router; // stargate router
  ILPStaking internal lpStaker; // LP staker (one for all pools)
  uint16[8] internal poolIds; // pool ids
  uint16[8] internal stakingIds; // pool ids for the staking
  uint256[8] internal lpWeiPerShare;

  constructor(address _accessController) StrategyV5(_accessController) {}

  struct Params {
    address lpStaker;
    uint16[] stakingIds;
  }

  function _setParams(bytes memory _params) internal override {
    Params memory params = abi.decode(_params, (Params));
    if (params.lpStaker == address(0)) {
      revert Errors.AddressZero();
    }
    lpStaker = ILPStaking(params.lpStaker);
    for (uint256 i = 0; i < _inputLength;) {
      // Specify the pools]
      IPool lp = IPool(address(lpTokens[i]));
      stakingIds[i] = params.stakingIds[i];
      poolIds[i] = uint16(lp.poolId());
      _routers[i] = IStargateRouter(lp.router());
      lpWeiPerShare[i] = 10 ** lp.decimals();
      unchecked {
        i++;
      }
    }
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

  function _addLiquiditySingleSide(
    uint256 _amount,
    uint256 _index
  ) internal returns (uint256 deposited) {
    _router.addLiquidity(poolIds[_index], _amount, address(this));
    return lpTokens[_index].balanceOf(address(this));
  }

  function _stake(uint256 _index, uint256 _amount) internal override {
    // deposit+stake
    lpStaker.deposit(stakingIds[_index], _addLiquiditySingleSide(_amount, _index));
  }

  function _unstake(uint256 _index, uint256 _amount) internal override {
    // unstake LP
    lpStaker.withdraw(stakingIds[_index], _amount);
    // liquidate LP
    _router.instantRedeemLocal(poolIds[_index], _amount, address(this));
  }

  function _setLpTokenAllowances(uint256 _amount) internal override {
    for (uint256 i = 0; i < _inputLength; i++) {
      lpTokens[i].approve(address(lpStaker), _amount);
      inputs[i].approve(address(_routers[i]), _amount);
    }
  }

  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return IPool(address(lpTokens[_index])).amountLPtoLD(_amount); // stake/lp -> input decimals
  }

  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount // input decimals
      .mulDiv(
      lpWeiPerShare[_index], // lp/stake decimals
      IPool(address(lpTokens[_index])).amountLPtoLD(lpWeiPerShare[_index])
    ); // input decimals
  }

  function _investedInput(uint256 _index) internal view override returns (uint256) {
    return
      _stakeToInput(lpStaker.userInfo(stakingIds[_index], address(this)).amount, _index);
  }

  function rewardsAvailable() public view override returns (uint256[] memory amounts) {
    amounts = uint256(_rewardLength).toArray();
    for (uint256 i = 0; i < _inputLength; i++) {
      if (address(inputs[i]) == address(0)) break;
      amounts[0] += lpStaker.userInfo(poolIds[i], address(this)).amount;
    }
  }

  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    for (uint256 i = 0; i < _inputLength;) {
      if (address(inputs[i]) == address(0)) break;
      // withdraw/deposit with 0 still claims STG rewards
      lpStaker.withdraw(poolIds[i], 0);
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
