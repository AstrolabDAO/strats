// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5.sol";
import "./interfaces/IUniProxy.sol";
import "./interfaces/IVoterV3.sol";
import "./interfaces/IGaugeV2CL.sol";
import "./interfaces/IHypervisor.sol";

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
  IHypervisor[8] internal _hypervisors; // gamma amm (pool pos manager)
  IAlgebraPool[8] internal _pools; // algebra pools
  uint256[8] internal _pendingAmounts; // pending amounts for staking leg by leg
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
    for (uint256 i = 0; i < _inputLength / 2;) {
      unchecked {
        _hypervisors[i] = IHypervisor(address(lpTokens[i]));
        _pools[i] = IAlgebraPool(_hypervisors[i].pool());
        _gauges[i] = IGaugeV2CL(params.gauges[i]);
        i++;
      }
    }
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
  }

  function _setLpTokenAllowances(uint256 _amount) internal override {

    _amount = _amount > 0 ? _amount : AsMaths.MAX_UINT256;
    for (uint256 i = 0; i < _inputLength / 2;) {
      address lp = address(lpTokens[i]);
      if ((lp) == address(0)) break;

      (IERC20Metadata token0, IERC20Metadata token1) = (inputs[i * 2], inputs[i * 2 + 1]);

      if (token0.allowance(address(this), lp) < _amount) {
        token0.forceApprove(address(lpTokens[i]), _amount);
      }

      if (token1.allowance(address(this), lp) < _amount) {
        token1.forceApprove(lp, _amount);
      }

      lpTokens[i].forceApprove(address(_gauges[i]), AsMaths.MAX_UINT256);
      unchecked {
        i++;
      }
    }
  }

  function _token0Ratio(uint256 _index) internal view returns (uint256) {
    (uint256 posSize0, uint256 posSize1) = _hypervisors[_index / 2].getTotalAmounts(); // gamma pos total size
    return posSize0.mulDiv(1e18, posSize0 + posSize1);
  }

  function _stake(uint256 _index, uint256 _amount) internal override {
    if (_index % 2 == 0) {
      _pendingAmounts[_index] = _amount;
      return; // skip first leg of pair
    }

    // make sure to comply to the current pos ratios
    uint256 ratio = _token0Ratio(_index);
    uint256 deposit0Amount = _pendingAmounts[_index - 1];
    uint256 deposit1Amount = deposit0Amount * 1e18 / ratio;

    if (_amount < deposit1Amount) {
      deposit1Amount = _amount;
      deposit0Amount = deposit1Amount * ratio / 1e18; // haircut to match ratio
    }

    uint256 toStake = _uniProxy.deposit({
      deposit0: deposit0Amount,
      deposit1: deposit1Amount,
      pos: address(lpTokens[_index / 2]), // hypervisor == pool AMM wrapper
      to: address(this),
      minIn: [uint256(0), uint256(0), uint256(0), uint256(0)] // slippage control
    });
    _gauges[_index / 2].deposit(toStake);
  }

  function _unstake(uint256 _index, uint256 _amount) internal override {
    if (_index % 2 == 1) {
      // _pendingAmounts[_index] = _amount;
      return; // skip second leg of pair
    }
    _gauges[_index / 2].withdraw(_amount);
    (uint256 amount0, uint256 amount1) = _hypervisors[_index / 2].withdraw({
      shares: _amount,
      from: address(this),
      to: address(this),
      minAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)] // slippage control
    });
  }

  function _getPrice(IAlgebraPool pool, address base, address quote, uint8 baseDecimals, uint8 quoteDecimals) internal view returns (uint256) {
    (uint160 sqrtPriceX96,,,,,,) = pool.globalState();
    uint256 priceX96 = base == pool.token0() ?
      uint256(sqrtPriceX96) : (2**192) / uint256(sqrtPriceX96); // invert if base is token1
    uint256 rebased = (priceX96**2 * 10**baseDecimals) / (2**192 * 10**quoteDecimals);
    return rebased;
  }

  function _getPrice(uint256 _indexBase, uint256 _indexQuote) internal view returns (uint256) {
    return _getPrice(
      _pools[_indexBase / 2],
      address(inputs[_indexBase]),
      address(inputs[_indexQuote]),
      _inputDecimals[_indexBase],
      _inputDecimals[_indexQuote]);
  }

  function _inputToAsset(
    uint256 _index,
    uint256 _amount
  ) internal view override returns (uint256) {
    IPriceProvider oracle = _priceAwareStorage().oracle;
    address base = address(inputs[_index]);
    if (oracle.hasFeed(base)) {
      return oracle.convert(base, _amount, address(asset));
    } else {
      bool isBaseToken0 = _index % 2 == 0;
      uint256 quoteIndex = isBaseToken0 ? _index + 1 : _index - 1;
      address quote = address(inputs[quoteIndex]);
      if (!oracle.hasFeed(quote)) {
          revert Errors.MissingOracle(); // neither pool token has a price feed, cannot convert
      }
      uint256 quoteAmount = _amount * _getPrice(_index, quoteIndex);
      return oracle.convert(quote, quoteAmount, address(asset));
    }
  }

  function _assetToInput(
    uint256 _index,
    uint256 _amount
  ) internal view override returns (uint256) {
    IPriceProvider oracle = _priceAwareStorage().oracle;
    address base = address(inputs[_index]);
    if (oracle.hasFeed(base)) {
      return oracle.convert(address(asset), _amount, base);
    } else {
      bool isBaseToken0 = _index % 2 == 0;
      uint256 quoteIndex = isBaseToken0 ? _index + 1 : _index - 1;
      address quote = address(inputs[quoteIndex]);
      if (!oracle.hasFeed(quote)) {
          revert Errors.MissingOracle(); // neither pool token has a price feed, cannot convert
      }
      uint256 quoteAmount = oracle.convert(address(asset), _amount, quote);
      return quoteAmount / _getPrice(_index, quoteIndex);
    }
  }

  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    IHypervisor hypervisor = _hypervisors[_index / 2];
    IPriceProvider oracle = _priceAwareStorage().oracle;
    
    (uint256 amount0, uint256 amount1) = hypervisor.getTotalAmounts();
    uint256 posBaseValue;
    address base = address(inputs[_index]);
    address quote = address(inputs[_index % 2 == 0 ? _index + 1 : _index - 1]);
    
    bool baseIsToken0 = base == _pools[_index / 2].token0();
    
    if (oracle.hasFeed(base) && oracle.hasFeed(quote)) {
      // prioritize oracle price
      posBaseValue = baseIsToken0 
        ? amount0 + oracle.convert(quote, amount1, base)
        : oracle.convert(quote, amount0, base) + amount1;
    } else {
      // fallback to pool price
      uint256 priceRatio = _getPrice(_index, _index % 2 == 0 ? _index + 1 : _index - 1);
      posBaseValue = baseIsToken0
        ? amount0 + amount1 * priceRatio / 1e18
        : amount0 * 1e18 / priceRatio + amount1;
    }

    uint256 lpBasePrice = posBaseValue.mulDiv(1e18, hypervisor.totalSupply()); // hypervisors decimals == 18
    return _amount.mulDiv(1e18, lpBasePrice); // lpAmount equivalent of input (base) amount
  }

  function _stakeToInputs(
    uint256 _amount,
    uint256 _index // input index
  ) internal view returns (uint256[2] memory sizes) {

    IHypervisor h = _hypervisors[_index / 2];
    IAlgebraPool p = _pools[_index / 2];

    uint256 stakeRatio = _amount.mulDiv(1e18, h.totalSupply()); // gamma pos ownership * 1e18 scaler
    uint256[2] memory posSizes;
    (posSizes[0], posSizes[1]) = h.getTotalAmounts(); // gamma pos total size
    for (uint256 i = 0; i < 2;) { // i == poolOffset
      sizes[i] = posSizes[i].mulDiv(_amount, h.totalSupply()); // gamma pos ownership
      unchecked {
        i++;
      }
    }
    return sizes;
  }

  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    uint256[2] memory sizes = _stakeToInputs(_amount, _index);
    return _index % 2 == 0 ? sizes[0] : sizes[1];
  }

  function _invested(uint256 _index) internal view override returns (uint256) {
    return _stakeToAsset(_gauges[_index / 2].balanceOf(address(this)), _index);
  }

  function _excessLiquidity(
    uint256 _index,
    uint256 _total
  ) internal view override returns (int256) {
    if (_total == 0) {
      _total = _invested();
    }
    int256 allocated = int256(_invested(_index));
    uint256 poolWeight = uint256(inputWeights[_index / 2]);
    uint256 ratio = _token0Ratio(_index);
    uint256 legWeight = _index % 2 == 0 ? poolWeight.mulDiv(ratio, 1e18) : poolWeight.mulDiv(1e18, ratio);

    return _totalWeight == 0 ? allocated : (allocated - int256(_total.mulDiv(legWeight, _totalWeight)));
  }

  function rewardsAvailable() public view override returns (uint256[] memory amounts) {
    uint256 mainReward;
    for (uint256 i = 0; i < _inputLength / 2;) {
      mainReward += _gauges[i].earned(address(this));
      unchecked {
        i++;
      }
    }
    return _rewardLength == 1
      ? mainReward.toArray() // THE
      : mainReward.toArray(_balance(rewardTokens[1])); // BNB+WBNB
  }

  function claimRewards() public override returns (uint256[] memory amounts) {

    amounts = new uint256[](_rewardLength);
    _voter.claimRewards(_gaugeAddresses); // claim THE/veTHE for all gauges
    _wrapNative(); // wrap native rewards if needed eg. BNB->WBNB
    for (uint256 i = 0; i < _rewardLength;) {
      amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
      unchecked {
        i++;
      }
    }
  }
}
