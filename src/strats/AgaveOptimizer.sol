// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../libs/AsArrays.sol";
import "../core/StrategyV5.sol";
import "../external/Agave/IAgave.sol";
import "../external/Balancer/v2/IBalancerV2.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title Agave Optimizer - Dynamic liquidity providing on Agave
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Agave V3 (https://aave.com/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract AgaveOptimizer is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  struct Params {
    address poolProvider;
    address balancerVault;
    bytes32 rewardPoolId;
  }

  IPoolAddressesProvider internal _poolProvider;
  IBalancerVault internal _balancerVault;
  bytes32 internal _rewardPoolId;

  constructor(address _accessController) StrategyV5(_accessController) {}

  function _setParams(bytes memory _params) internal override {
    Params memory params = abi.decode(_params, (Params));
    _poolProvider = IPoolAddressesProvider(params.poolProvider);
    _balancerVault = IBalancerVault(params.balancerVault);
    _rewardPoolId = params.rewardPoolId;
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

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

  function _stake(uint256 _amount, uint256 _index) internal override {
    IPool pool = IPool(_poolProvider.getLendingPool());
    pool.deposit({
      asset: address(inputs[_index]),
      amount: _amount,
      onBehalfOf: address(this),
      referralCode: 0
    });
  }

  function _unstake(uint256 _amount, uint256 _index) internal override {
    IPool pool = IPool(_poolProvider.getLendingPool());
    pool.withdraw({asset: address(inputs[_index]), amount: _amount, to: address(this)});
  }

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
