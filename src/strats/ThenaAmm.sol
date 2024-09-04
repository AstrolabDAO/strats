// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../libs/AsArrays.sol";
import "../libs/TickMaths.sol";
import "../core/StrategyV5.sol";
import "../external/Gamma/IUniProxy.sol";
import "../external/Algebra/IVoterV3.sol";
import "../external/Algebra/IGaugeV2CL.sol";
import "../external/Gamma/IAlgebraHypervisor.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title Thena AMM - Automated market making on Thena
 * @author Astrolab DAO
 * @notice AMM strategy for Thena's CLMM (https://thena.fi/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract ThenaAmm is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  IUniProxy internal _uniProxy;
  IVoterV3 internal _voter; // governance + reward distributor
  IGaugeV2CL[8] internal _gauges; // reward staking vaults
  IAlgebraHypervisor[8] internal _hypervisors; // gamma amm (pool pos manager)
  IAlgebraPool[8] internal _pools; // algebra pools
  address[] internal _gaugeAddresses; // reward staking vaults

  constructor(address _accessController) StrategyV5(_accessController) {}

  struct Params {
    address uniProxy;
    address voter;
    address[] gauges;
  }

  function _setParams(bytes memory _params) internal override {
    Params memory params = abi.decode(_params, (Params));
    _uniProxy = IUniProxy(params.uniProxy);
    _voter = IVoterV3(params.voter);
    _gaugeAddresses = params.gauges;
    unchecked {
      for (uint256 i = 0; i < _inputLength; i++) {
        _hypervisors[i] = IAlgebraHypervisor(address(lpTokens[i]));
        _pools[i] = IAlgebraPool(_hypervisors[i].pool());
        _gauges[i] = IGaugeV2CL(params.gauges[i]);
      }
    }
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

  function _setLpTokenAllowances(uint256 _amount) internal override {
    _amount = _amount > 0 ? _amount : AsMaths.MAX_UINT256;
    unchecked {
      for (uint256 i = 0; i < _inputLength; i += 2) {
        address lp = address(lpTokens[i]);
        if ((lp) == address(0)) break;

        (IERC20Metadata token0, IERC20Metadata token1) = (
          inputs[i],
          inputs[i + 1]
        );

        if (token0.allowance(address(this), lp) < _amount) {
          token0.forceApprove(address(lpTokens[i]), _amount);
        }

        if (token1.allowance(address(this), lp) < _amount) {
          token1.forceApprove(lp, _amount);
        }

        lpTokens[i].forceApprove(address(_gauges[i]), AsMaths.MAX_UINT256);
      }
    }
  }

  function _poolIndex(uint256 _index) internal pure returns (uint256) {
    unchecked {
      return _index - (_index % 2);
    }
  }

  function _quoteIndex(uint256 _index) internal pure returns (uint256) {
    unchecked {
      return _index % 2 == 0 ? _index + 1 : _index - 1;
    }
  }

  function _pairedRequirement(
    uint256 _amount,
    uint256 _index
  ) internal view returns (uint256) {
    (uint256 min, uint256 max) = _uniProxy.getDepositAmount(
      address(_hypervisors[_index]),
      address(inputs[_index]),
      _amount
    );
    unchecked {
      return (min + max) / 2;
    }
  }

  function _token0Ratio(uint256 _index, bool _base100) public view returns (uint256) {
    _index = _poolIndex(_index);
    unchecked {
      uint256 debased =
        (1e18 * _weiPerAsset) /
        _inputToAsset(
          _pairedRequirement(_assetToInput(1e18, _index), _index),
          _index + 1 // paired input requirement to asset
        ); // input[0]/input[1] ratio in 1e18 weight (eg. 1.35e18/1e18)

      return _base100 ? (1e18 - (1e36 / (debased + 1e18))) : debased; // if rebased, the sum of weights is 1e18
    }
  }

  function _stake(uint256 _amount, uint256 _index) internal override {
    unchecked {
      if (_index % 2 == 0) {
        return; // skip the first leg of each pair since we expect both inputs to be available (swapped from assets)
      }

      // make sure to comply to the current pos ratios
      uint256 balance0 = inputs[_index - 1].balanceOf(address(this));
      uint256 deposit1Amount = AsMaths.min(
        _amount,
        inputs[_index].balanceOf(address(this))
      );
      uint256 deposit0Amount = _pairedRequirement(_amount, _index); // deducing amount[0] from amount[1]

      if (balance0 < deposit0Amount) {
        deposit0Amount = balance0;
        deposit1Amount = _pairedRequirement(deposit0Amount, _index - 1); // haircut input[1] amount to match ratio
      }

      uint256 toStake = _uniProxy.deposit({
        deposit0: deposit0Amount,
        deposit1: deposit1Amount,
        pos: address(lpTokens[_index]), // hypervisor == pool AMM wrapper
        to: address(this),
        minIn: [uint256(0), uint256(0), uint256(0), uint256(0)] // slippage control
      });
      _gauges[_index].deposit(toStake);
    }
  }

  function _unstake(uint256 _amount, uint256 _index) internal override {
    if (_index % 2 == 1) {
      return; // skip second leg of pair
    }
    _gauges[_index].withdraw(_amount);
    _hypervisors[_index].withdraw({
      shares: _amount,
      from: address(this),
      to: address(this),
      minAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)] // slippage checked in _liquidate()
    });
  }

  function _inputToAsset(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    IPriceProvider oracle = oracle();
    address base = address(inputs[_index]);
    if (!oracle.hasFeed(base)) {
      revert Errors.MissingOracle();
    }
    return oracle.convert(base, _amount, address(asset)); // chainlink->alt pancake->price
  }

  function _assetToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    IPriceProvider oracle = oracle();
    address base = address(inputs[_index]);
    if (!oracle.hasFeed(base)) {
      revert Errors.MissingOracle();
    }
    return oracle.convert(address(asset), _amount, base);
  }

  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    if (_index % 2 == 1) {
      return 0; // skip second leg of pair
    }
    IPriceProvider oracle = oracle();

    (uint256 amount0, uint256 amount1) = _hypervisors[_index].getTotalAmounts();
    uint256 posBaseValue;
    uint256 quoteIndex = _quoteIndex(_index);
    address base = address(inputs[_index]);
    address quote = address(inputs[quoteIndex]);

    bool baseIsToken0 = base == _pools[_index].token0();
    // use _excessLiquidity()'s logic to estimate the other legs optimal exposure, sum up both in base's denomination
    if (!baseIsToken0) {
      _amount = _amount.mulDiv(1e18 + _token0Ratio(_index, false), 1e18);
    } else {
      _amount = _amount.mulDiv(1e18 + (1e36 / _token0Ratio(_index, false)), 1e18);
    }

    if (oracle.hasFeed(base) && oracle.hasFeed(quote)) {
      // prioritize oracle price
      posBaseValue = baseIsToken0
        ? amount0 + oracle.convert(quote, amount1, base)
        : oracle.convert(quote, amount0, base) + amount1;
    } else {
      revert Errors.MissingOracle();
    }

    uint256 lpBasePrice = posBaseValue.mulDiv(1e18, _hypervisors[_index].totalSupply()); // hypervisors decimals == 18
    return _amount.mulDiv(1e18, lpBasePrice); // lpAmount equivalent of input (base) amount
  }

  function _stakeToInputs(
    uint256 _amount,
    uint256 _index // input index
  ) internal view returns (uint256[2] memory sizes) {
    IAlgebraHypervisor h = _hypervisors[_index];
    // uint256 stakeRatio = _amount.mulDiv(1e18, h.totalSupply()); // gamma pos ownership * 1e18 scaler
    (sizes[0], sizes[1]) = h.getTotalAmounts(); // gamma pos total size
    unchecked {
      for (uint256 i = 0; i < 2; i++) {
        // i == poolOffset
        sizes[i] = sizes[i].mulDiv(_amount, h.totalSupply()); // gamma pos ownership
      }
    }
  }

  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    unchecked {
      return _stakeToInputs(_amount, _index)[_index % 2];
    }
  }

  function _investedInput(
    uint256 _index
  ) internal view override returns (uint256) {
    return _stakeToInput(_gauges[_index].balanceOf(address(this)), _index);
  }

  function _excessLiquidity(
    uint256 _total,
    uint256 _index
  ) internal view override returns (int256) {
    if (_total == 0) {
      _total = _invested();
    }
    unchecked {
      int256 allocated = int256(_invested(_index));
      if (_totalWeight == 0) {
        return int256(_invested(_index)); // liquidation expected
      }
      uint256 legWeight = uint256(inputWeights[_poolIndex(_index)]); // == poolWeight eg. 9200
      uint256 ratio = _index == 0 ? _token0Ratio(_index, true) : (1e18 - _token0Ratio(_index, true)); // eg. 0.5e17 (WAD)
      legWeight = legWeight.mulDiv(ratio, 1e18); // eg. 9384 (bps)
      return allocated - int256(_total.mulDiv(legWeight, _totalWeight));
    }
  }

  function rewardsAvailable()
    public
    view
    override
    returns (uint256[] memory amounts)
  {
    uint256 mainReward;
    unchecked {
      for (uint256 i = 0; i < _inputLength; i += 2) {
        mainReward += _gauges[i].earned(address(this));
      }
    }
    return
      _rewardLength == 1
        ? mainReward.toArray() // THE
        : mainReward.toArray(_balance(rewardTokens[1])); // BNB+WBNB
  }

  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    _voter.claimRewards(_gaugeAddresses); // claim THE/veTHE for all gauges
    _wrapNative(); // wrap native rewards if needed eg. BNB->WBNB
    unchecked {
      for (uint256 i = 0; i < _rewardLength; i++) {
        amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
      }
    }
  }
}
