// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5.sol";
import "./interfaces/IAgave.sol";
import "../Balancer/interfaces/v2/IBalancer.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title Agave Strategy - Liquidity providing on Agave
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Agave V3 (https://aave.com/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract Agave is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  // strategy specific init parameters
  struct Params {
    address poolProvider;
    address balancerVault;
    bytes32 rewardPoolId;
  }

  // strategy specific variables
  IPoolAddressesProvider internal _poolProvider;
  IBalancerVault internal _balancerVault;
  bytes32 internal _rewardPoolId;

  constructor(address _accessController) StrategyV5(_accessController) {}

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function _setParams(bytes memory _params) internal override {
    Params memory params = abi.decode(_params, (Params));
    _poolProvider = IPoolAddressesProvider(params.poolProvider);
    _balancerVault = IBalancerVault(params.balancerVault);
    _rewardPoolId = params.rewardPoolId;
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

  /**
   * @dev Internal function to get information about the reward LP
   * @return lp The address of the reward LP
   * @return tokens An array of token addresses in the LP
   * @return balances An array of token balances in the LP
   * @return rewardIndex The index of the AGVE token in the LP
   */
  function _getRewardLpInfo()
    internal
    view
    returns (
      address lp,
      address[] memory tokens,
      uint256[] memory balances,
      uint8 rewardIndex
    )
  {
    (tokens, balances,) = _balancerVault.getPoolTokens(_rewardPoolId);
    rewardIndex = tokens[0] == rewardTokens[0] ? 0 : 1; // AGVE index in LP
    (lp,) = _balancerVault.getPool(_rewardPoolId);
  }

  /**
   * @notice Claim rewards from the third party contracts
   * @return amounts Array of rewards claimed for each reward token
   */
  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);

    (address lp, address[] memory tokens,, uint8 rewardIndex) = _getRewardLpInfo();

    ExitPoolRequest memory request = ExitPoolRequest({
      assets: tokens,
      minAmountsOut: uint256(0).toArray(0),
      userData: abi.encode(
        WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        IERC20Metadata(lp).balanceOf(address(this)),
        rewardIndex
        ),
      toInternalBalance: false
    });

    _balancerVault.exitPool({
      poolId: _rewardPoolId,
      sender: address(this),
      recipient: payable(address(this)),
      request: request
    });

    for (uint256 i = 0; i < _rewardLength; i++) {
      amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
    }
  }

  /**
   * @notice Stakes or provides `_amount` from `input[_index]` to `lpTokens[_index]`
   * @param _index Index of the input to stake
   * @param _amount Amount of underlying assets to allocate to `inputs[_index]`
   */
  function _stake(uint256 _index, uint256 _amount) internal override {
    IPool pool = IPool(_poolProvider.getLendingPool());
    pool.deposit({
      asset: address(inputs[_index]),
      amount: _amount,
      onBehalfOf: address(this),
      referralCode: 0
    });
  }

  /**
   * @notice Unstakes or liquidates `_amount` of `lpTokens[i]` back to `input[_index]`
   * @param _index Index of the input to liquidate
   * @param _amount Amount of underlying assets to recover from liquidating `inputs[_index]`
   */
  function _unstake(uint256 _index, uint256 _amount) internal override {
    IPool pool = IPool(_poolProvider.getLendingPool());
    pool.withdraw({asset: address(inputs[_index]), amount: _amount, to: address(this)});
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
   * @notice Returns the available rewards
   * @return amounts Array of rewards available for each reward token
   */
  function rewardsAvailable() public view override returns (uint256[] memory amounts) {
    (address lp,, uint256[] memory balances, uint8 rewardIndex) = _getRewardLpInfo();
    uint256 shareOfSupply = IERC20Metadata(lp).balanceOf(address(this)) * 1e18
      / IERC20Metadata(lp).totalSupply(); // 1e18+1e18-1e18 = 1e18
    uint256 rewardInPool = balances[rewardIndex]; // 1e18
    uint256[] memory weights = IBalancerManagedPool(lp).getNormalizedWeights();
    uint256 rewardValueOfPool = rewardInPool * (100 / weights[rewardIndex]); // total value of the pool in reward token 1e18
    return ((rewardValueOfPool * shareOfSupply).subBp(200) / 1e18).toArray(); // 1e18+1e18-1e18 = 1e18
  }
}
