// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsMaths.sol";
import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5.sol";
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
contract StargateMultiStake is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;

  // Third party contracts
  IStargateRouter[8] internal routers; // stargate router
  ILPStaking internal lpStaker; // LP staker (one for all pools)
  uint16[8] internal poolIds; // pool ids
  uint16[8] internal stakingIds; // pool ids for the staking
  uint256[8] internal lpWeiPerShare;

  constructor(address _accessController) StrategyV5(_accessController) {}

  // Struct containing the strategy init parameters
  struct Params {
    address lpStaker;
    uint16[] stakingIds;
  }

  /**
   * @notice Sets the strategy parameters
   * @param _params Strategy parameters
   */
  function _setParams(bytes memory _params) internal override {
    Params memory params = abi.decode(_params, (Params));
    if (params.lpStaker == address(0)) {
      revert Errors.AddressZero();
    }
    lpStaker = ILPStaking(params.lpStaker);
    for (uint8 i = 0; i < _inputLength;) {
      // Specify the pools]
      IPool lp = IPool(address(lpTokens[i]));
      stakingIds[i] = params.stakingIds[i];
      poolIds[i] = uint16(lp.poolId());
      routers[i] = IStargateRouter(lp.router());
      lpWeiPerShare[i] = 10 ** lp.decimals();
      unchecked {
        i++;
      }
    }
    _setAllowances(AsMaths.MAX_UINT256);
  }

  /**
   * @notice Adds liquidity to the pool, single sided
   * @param _amount Max amount of asset to invest
   * @param _index Index of the input token
   * @return deposited Amount of LP tokens received
   */
  function _addLiquiditySingleSide(
    uint256 _amount,
    uint256 _index
  ) internal returns (uint256 deposited) {
    routers[_index].addLiquidity(poolIds[_index], _amount, address(this));
    return lpTokens[_index].balanceOf(address(this));
  }

  /**
   * @notice Stakes or provides `_amount` from `input[_index]` to `lpTokens[_index]`
   * @param _index Index of the input to stake
   * @param _amount Amount of underlying assets to allocate to `inputs[_index]`
   */
  function _stake(uint256 _index, uint256 _amount) internal override {
    // deposit+stake
    lpStaker.deposit(stakingIds[_index], _addLiquiditySingleSide(_amount, _index));
  }

  /**
   * @notice Unstakes or liquidates `_amount` of `lpTokens[i]` back to `input[_index]`
   * @param _index Index of the input to liquidate
   * @param _amount Amount of underlying assets to recover from liquidating `inputs[_index]`
   */
  function _unstake(uint256 _index, uint256 _amount) internal override {
    // unstake LP
    lpStaker.withdraw(stakingIds[_index], _amount);
    // liquidate LP
    routers[_index].instantRedeemLocal(poolIds[_index], _amount, address(this));
  }

  /**
   * @notice Claim rewards from the third party contracts
   * @return amounts Array of rewards claimed for each reward token
   */
  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    for (uint8 i = 0; i < _inputLength;) {
      if (address(inputs[i]) == address(0)) break;
      // withdraw/deposit with 0 still claims STG rewards
      lpStaker.withdraw(poolIds[i], 0);
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

  /**
   * @notice Sets allowances for third party contracts (except rewardTokens)
   * @param _amount Allowance amount
   */
  function _setAllowances(uint256 _amount) internal override {
    for (uint8 i = 0; i < _inputLength; i++) {
      lpTokens[i].approve(address(lpStaker), _amount);
      inputs[i].approve(address(routers[i]), _amount);
    }
  }

  /**
   * @notice Converts LP/staked LP to input
   * @return Input value of the LP amount
   */
  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return IPool(address(lpTokens[_index])).amountLPtoLD(_amount); // stake/lp -> input decimals
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
      IPool(address(lpTokens[_index])).amountLPtoLD(lpWeiPerShare[_index])
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
