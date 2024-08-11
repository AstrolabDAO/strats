// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "../interfaces/IAs4626.sol";
import "../libs/AsArrays.sol";
import "../libs/AsMaths.sol";
import "../access-control/AsRescuable.sol";
import "./StrategyV5Abstract.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title StrategyV5 - Astrolab's base Strategy to be extended by implementations
 * @author Astrolab DAO
 * @notice Common strategy back-end extended by implementations, delegating vault logic to StrategyV5Agent
 * @dev All state variables must be in StrategyV5abstract to match the proxy base storage layout (StrategyV5)
 * @dev Can be deplpoyed standalone for dummy strategy testing
 */
abstract contract StrategyV5 is
  StrategyV5Abstract,
  AsRescuable,
  AsPriceAware,
  Proxy
{
  using AsMaths for uint256;
  using AsMaths for int256;
  using AsMaths for int256[8];
  using AsArrays for int256[8];
  using AsArrays for bytes[];
  using SafeERC20 for IERC20Metadata;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(
    address _accessController
  ) StrategyV5Abstract(_accessController) AsRescuable() {
    _pause();
  }

  receive() external payable {}

  /**
   * @notice Strategy specific initializer
   * @param _params StrategyParams struct containing strategy parameters
   */
  function _setParams(bytes memory _params) internal virtual;

  /**
   * @notice Strategy specific initializer
   * @param _params StrategyParams struct containing strategy parameters
   */
  function setParams(bytes memory _params) external onlyAdmin {
    _setParams(_params);
  }

  /**
   * @notice Initializes the strategy using `_params`
   * @param _params StrategyParams struct containing strategy parameters
   */
  function init(StrategyParams calldata _params) external onlyAdmin {
    if (_params.coreAddresses.agent == address(0)) {
      revert Errors.AddressZero();
    }
    _updateAgent(_params.coreAddresses.agent);
    if (_params.coreAddresses.oracle != address(0)) {
      _updateOracle(_params.coreAddresses.oracle);
    }
    _agentStorage().delegator = IStrategyV5(address(this));
    (bool success, ) = _baseStorageExt().agent.delegatecall(
      abi.encodeWithSelector(IStrategyV5Agent.init.selector, _params)
    );
    if (!success) {
      revert Errors.FailedDelegateCall();
    }
    // strategy specific initialization
    if (_params.extension.length > 0) {
      _setParams(_params.extension);
    }
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return Agent's initialization state (ERC-897)
   */
  function initialized() public view virtual returns (bool) {
    return
      _initialized &&
      _baseStorageExt().agent != address(0) &&
      address(asset) != address(0);
  }

  /**
   * @return Agent's implementation address (OZ Proxy's internal override)
   */

  function _implementation() internal view override returns (address) {
    return _baseStorageExt().agent;
  }

  /**
   * @return Agent's implementation address (ERC-897)
   */
  function implementation() external view returns (address) {
    return _implementation();
  }

  /**
   * @return This agent implementation address
   */
  function agent() external view returns (address) {
    return _implementation(); // address(this)
  }

  /**
   * @notice Converts `_amount` of a specific input to USD
   * @param _amount Amount of the specific input
   * @param _index Index of the input to convert
   * @return Equivalent USD amount
   */
  function _inputToUsd(
    uint256 _amount,
    uint256 _index
  ) internal view whenPriceAware returns (uint256) {
    return
      _priceAwareStorage().oracle.toUsdBp(address(inputs[_index]), _amount) /
      AsMaths.BP_BASIS;
  }

  /**
   * @notice Converts `_amount` of USD to a specific input
   * @param _amount Amount of USD
   * @param _index Index of the input to convert to
   * @return Equivalent amount of the specific input
   */
  function _usdToInput(
    uint256 _amount,
    uint256 _index
  ) internal view whenPriceAware returns (uint256) {
    return
      _priceAwareStorage().oracle.fromUsdBp(address(inputs[_index]), _amount) /
      AsMaths.BP_BASIS;
  }

  /**
   * @notice Converts `_amount` of underlying asset to USD
   * @param _amount Amount of underlying asset
   * @return Equivalent USD amount
   */
  function _assetToUsd(
    uint256 _amount
  ) internal view whenPriceAware returns (uint256) {
    return
      _priceAwareStorage().oracle.toUsdBp(address(asset), _amount) /
      AsMaths.BP_BASIS;
  }

  /**
   * @notice Converts `_amount` of USD to underlying asset
   * @param _amount Amount of USD
   * @return Equivalent amount of underlying asset
   */
  function _usdToAsset(
    uint256 _amount
  ) internal view whenPriceAware returns (uint256) {
    return
      _priceAwareStorage().oracle.fromUsdBp(address(asset), _amount) /
      AsMaths.BP_BASIS;
  }

  /**
   * @notice Converts `_amount` of underlying asset to a specific input
   * @param _amount Amount of underlying asset
   * @param _index Index of the input to convert to
   * @return Equivalent amount of the specific input
   * @dev This should be overridden by strategy implementations
   */
  function _assetToInput(
    uint256 _amount,
    uint256 _index
  ) internal view virtual returns (uint256) {
    return
      _priceAwareStorage().oracle.convert(
        address(asset),
        _amount,
        address(inputs[_index])
      );
  }

  /**
   * @notice Converts `_amount` of a specific input to underlying asset
   * @param _amount Amount of the specific input
   * @param _index Index of the input to convert from
   * @return Equivalent amount of underlying asset
   * @dev This should be overridden by strategy implementations
   */
  function _inputToAsset(
    uint256 _amount,
    uint256 _index
  ) internal view virtual returns (uint256) {
    return
      _priceAwareStorage().oracle.convert(
        address(inputs[_index]),
        _amount,
        address(asset)
      );
  }

  /**
   * @notice Converts `_amount` of a specific LP/staked LP to its underlying input (`inputs[_index]`)
   * @param _amount Amount of LP/staked LP
   * @param _index Index of the input
   * @return Input equivalent to `_amount` LP/staked LP
   * @dev This should be overriden by strategy implementations
   */
  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view virtual returns (uint256) {
    return _amount; // defaults to 1:1 (eg. USDC:aUSDC, ETH:stETH)
  }

  /**
   * @notice Converts `_amount` of a specific input (`inputs[_index]`) to LP/staked LP
   * @param _amount Amount of input
   * @param _index Index of the input
   * @return LP/staked LP equivalent to `_amount` input
   * @dev This should be overriden by strategy implementations
   */
  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view virtual returns (uint256) {
    return _amount; // defaults to 1:1 (eg. aUSDC:USDC, stETH:ETH)
  }

  /**
   * @notice Converts `_amount` of a specific LP/staked LP to underlying assets
   * @param _amount Amount of LP/staked LP
   * @param _index Index of the input
   * @return Underlying asset amount equivalent to `_amount` LP/staked LP
   */
  function _stakeToAsset(
    uint256 _amount,
    uint256 _index
  ) internal view returns (uint256) {
    return _inputToAsset(_stakeToInput(_amount, _index), _index);
  }

  /**
   * @notice Converts `_amount` of underlying assets to a specific LP/staked LP
   * @param _amount Amount of underlying assets
   * @param _index Index of the input
   * @return LP/staked LP equivalent to `_amount` underlying assets
   */
  function _assetToStake(
    uint256 _amount,
    uint256 _index
  ) internal view returns (uint256) {
    return _inputToStake(_assetToInput(_amount, _index), _index);
  }

  /**
   * @notice Converts a full LP/staked LP balance to its underlying input (`inputs[_index]`)
   * @param _index Index of the input
   * @return Input equivalent to the full LP/staked LP balance
   * @dev This should be overriden by strategy implementations
   */
  function _investedInput(
    uint256 _index
  ) internal view virtual returns (uint256) {
    return
      _stakeToInput(
        IERC20Metadata(lpTokens[_index]).balanceOf(address(this)),
        _index
      );
  }

  function investedInput(uint256 _index) external view returns (uint256) {
    return _investedInput(_index);
  }

  /**
   * @notice Converts a full input balance (`inputs[_index]`) to underlying assets
   * @param _index Index of the input
   * @return Amount of underlying assets equivalent to the full input balance
   */
  function _invested(uint256 _index) internal view virtual returns (uint256) {
    unchecked {
      uint256 staked = _inputToAsset(_investedInput(_index), _index);
      return inputs[_index] == asset ? staked : staked + inputs[_index].balanceOf(address(this));
    }
  }

  function invested(uint256 _index) external view virtual returns (uint256) {
    return _invested(_index);
  }

  /**
   * @notice Sums all inputs invested in the strategy, LP or staked, in underlying assets
   * @return total Amount invested
   */
  function _invested() internal view virtual override returns (uint256 total) {
    unchecked {
      for (uint256 i = 0; i < _inputLength; i++) {
        total += _invested(i);
      }
    }
  }

  /**
   * @notice Sums all inputs invested in the strategy, LP or staked, in underlying assets
   * @return total Amount invested
   */
  function invested() external view virtual returns (uint256 total) {
    return _invested();
  }

  /**
   * @notice Calculates the excess weight for a given input (inputs[`_index`]) in basis points
   * @param _total Sum of all invested inputs (`0 == 100% == invested()`)
   * @param _index Index of the input
   * @return Excess input weight in basis points
   */
  function _excessWeight(
    uint256 _total,
    uint256 _index
  ) internal view returns (int256) {
    if (_total == 0) _total = _invested();
    return
      int256(_invested(_index).mulDiv(AsMaths.BP_BASIS, _total)) -
      int256(uint256(inputWeights[_index])); // de-facto safe as weights are sanitized
  }

  /**
   * @notice Calculates the excess weights for all inputs
   * @param _total Sum of all invested inputs (`0 == 100% == invested()`)
   * @return excessWeights Array[8] of excess input weights in basis points
   */
  function _excessWeights(
    uint256 _total
  ) internal view returns (int256[8] memory excessWeights) {
    if (_total == 0) _total = _invested();
    unchecked {
      for (uint256 i = 0; i < _inputLength; i++) {
        excessWeights[i] = _excessWeight(i, _total);
      }
    }
  }

  /**
   * @notice Calculates the excess liquidity for a given input (inputs[`_index`])
   * @param _index Index of the input
   * @param _total Sum of all invested inputs (`0 == 100% == invested()`)
   * @return Excess input liquidity
   */
  function _excessLiquidity(
    uint256 _total,
    uint256 _index
  ) internal view virtual returns (int256) {
    if (_total == 0) {
      _total = _invested();
    }
    int256 allocated = int256(_invested(_index));
    return
      _totalWeight == 0
        ? allocated
        : (allocated -
          int256(_total.mulDiv(uint256(inputWeights[_index]), _totalWeight)));
  }

  /**
   * @notice Calculates the excess liquidity for all inputs
   * @param _total Sum of all invested inputs (`0 == 100% == invested()`)
   * @return excessLiquidity Array[8] of excess input liquidities
   */
  function _excessLiquidity(
    uint256 _total
  ) internal view virtual returns (int256[8] memory excessLiquidity) {
    if (_total == 0) _total = _invested();
    unchecked {
      for (uint256 i = 0; i < _inputLength; i++) {
        excessLiquidity[i] = _excessLiquidity(_total, i);
      }
    }
  }

  /**
   * @notice Previews the amounts that would be liquidated to recover `_amount + totalPendingWithdrawRequest() + allocated.bp(150)` of liquidity
   * @param _amount Amount of underlying assets to recover
   * @return amounts Array[8] of previewed liquidated amounts in input tokens
   */
  function _previewLiquidate(
    uint256 _amount
  ) internal returns (uint256[8] memory amounts) {
    (uint256 allocated, uint256 cash) = (_invested(), _available());
    unchecked {
      uint256 total = allocated + cash;
      uint256 targetAlloc = total.mulDiv(_totalWeight, AsMaths.BP_BASIS);
      uint256 pending = _totalPendingAssetsRequest();
      _amount += pending + targetAlloc.bp(50); // overliquidate (0.5% of allocated) to buffer withdraw-ready liquidity
      _amount = AsMaths.min(_amount, allocated);

      // excesses accounts for the weights and the cash available in the strategy
      int256[8] memory targetExcesses = _excessLiquidity(targetAlloc - _amount);
      int256 totalExcess = targetExcesses.sum();

      if (totalExcess > 0 && uint256(totalExcess) > _amount) {
        _amount = uint256(totalExcess);
      }

      for (uint256 i = 0; i < _inputLength; i++) {
        if (_amount < 10) break; // no leftover
        if (targetExcesses[i] > 0) {
          uint256 need = targetExcesses[i].abs();
          if (need > _amount) {
            need = _amount;
          }
          amounts[i] = _assetToInput(need, i);
          _amount -= need;
        }
      }
    }
  }

  /**
   * @notice Previews the breakdown of `_amount` underlying assets that would be invested in each input based on the current excess liquidities
   * @param _amount Amount of underlying assets to invest
   * @return amounts Array[8] of previewed invested amounts
   */
  function preview(
    uint256 _amount,
    bool _investing
  ) public onlyKeeper returns (uint256[8] memory amounts) {
    return _investing ? _previewInvest(_amount) : _previewLiquidate(_amount);
  }

  /**
   * @notice Previews the breakdown of `_amount` underlying assets that would be invested in each input based on the current excess liquidities
   * @param _amount Amount of underlying assets to invest
   * @return amounts Array[8] of previewed invested amounts
   */
  function _previewInvest(
    uint256 _amount
  ) internal returns (uint256[8] memory amounts) {
    (uint256 allocated, uint256 cash) = (_invested(), _available());
    unchecked {
      uint256 total = allocated + cash;

      if (_amount == 0) {
        uint256 targetCash = total.mulDiv(
          AsMaths.BP_BASIS - _totalWeight,
          AsMaths.BP_BASIS
        );
        _amount = cash.subMax0(targetCash);
      }

      // compute the excess liquidity
      int256[8] memory targetExcesses = _excessLiquidity(allocated + _amount);

      for (uint256 i = 0; i < _inputLength; i++) {
        if (_amount < 10) break; // no leftover
        if (targetExcesses[i] < 0) {
          uint256 need = targetExcesses[i].abs();
          if (need > _amount) {
            need = _amount;
          }
          amounts[i] = need;
          _amount -= need;
        }
      }
    }
  }

  /**
   * @notice Previews strategy specific swap needs for `_amount` underlying assets to be invested or liquidated
   * @param _previewAmounts Array[8] of previewed amounts in each input tokens
   * @param _investing True if the swaps are for investing, false if the swaps are for liquidating
   * @return from Array[8] of swap input (base) tokens
   * @return to Array[8] of swap output (quote) tokens
   * @return amounts Array[8] of swap amounts in input tokens
   */
  function previewSwapAddons(
    uint256[8] calldata _previewAmounts,
    bool _investing
  )
    external
    onlyKeeper
    returns (
      address[8] memory from,
      address[8] memory to,
      uint256[8] memory amounts
    )
  {
    return _previewSwapAddons(_previewAmounts, _investing);
  }

  function _previewSwapAddons(
    uint256[8] calldata _previewAmounts,
    bool _investing
  )
    internal
    virtual
    returns (
      address[8] memory from,
      address[8] memory to,
      uint256[8] memory amounts
    )
  {}

  /**
   * @notice ERC-165 `supportsInterface` check
   * @param _interfaceId Interface identifier
   * @return True if the interface is supported
   */
  function supportsInterface(bytes4 _interfaceId) public pure returns (bool) {
    return _interfaceId == type(IStrategyV5).interfaceId;
  }

  /**
   * @return Amount of reward tokens available to harvest
   * @dev This should be overriden by strategy implementations
   */
  function rewardsAvailable() public view virtual returns (uint256[] memory) {
    return new uint256[](_rewardLength);
  }

  /**
   * @param _token Token address - Use address(1) for native/gas tokens (ETH)
   * @return Balance of `_token` in the strategy
   */
  function _balance(address _token) internal view virtual returns (uint256) {
    unchecked {
      return
        (_token == address(1) || _token == address(_wgas))
          ? address(this).balance + _wgas.balanceOf(address(this)) // native+wrapped native
          : IERC20Metadata(_token).balanceOf(address(this));
    }
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            SETTERS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Updates the strategy underlying asset (critical, automatically pauses the strategy)
   * @notice If the new asset has a different price (USD denominated), a sudden `sharePrice()` change is expected
   * @param _asset Address of the new underlying asset
   * @param _swapData Swap calldata used to exchange the old `asset` for the new `_asset`
   * @param _exchangeRateBp Price factor to convert the old `asset` to the new `_asset` (old asset price * 1e18) / (new asset price)
   */
  function _updateAsset(
    address _asset,
    bytes calldata _swapData,
    uint256 _exchangeRateBp
  ) internal {
    PriceAwareStorage storage $ = _priceAwareStorage();
    if (_exchangeRateBp == 0) {
      if (address($.oracle) != address(0)) {
        _exchangeRateBp = $.oracle.exchangeRateBp(address(asset), _asset);
      } else {
        revert Errors.MissingOracle();
      }
    }
    (bool success, ) = _baseStorageExt().agent.delegatecall(
      abi.encodeWithSelector(
        IStrategyV5Agent.updateAsset.selector,
        _asset,
        _swapData,
        _exchangeRateBp
      )
    );
    if (!success) {
      revert Errors.FailedDelegateCall();
    }
  }

  /**
   * @notice Updates the strategy underlying asset (critical, automatically pauses the strategy)
   * @notice If the new asset has a different price (USD denominated), a sudden `sharePrice()` change is expected
   * @param _asset Address of the new underlying asset
   * @param _swapData Swap calldata used to exchange the old `asset` for the new `_asset`
   * @param _exchangeRateBp Price factor to convert the old `asset` to the new `_asset` (old asset price * 1e18) / (new asset price)
   */
  function updateAsset(
    address _asset,
    bytes calldata _swapData,
    uint256 _exchangeRateBp
  ) external {
    _updateAsset(_asset, _swapData, _exchangeRateBp);
  }

  /**
   * @notice Updates the strategy underlying asset (critical, automatically pauses the strategy)
   * @notice If the new asset has a different price (USD denominated), a sudden `sharePrice()` change is expected
   * @param _asset Address of the new underlying asset
   * @param _swapData Swap calldata used to exchange the old `asset` for the new `_asset`
   */
  function updateAsset(address _asset, bytes calldata _swapData) external {
    _updateAsset(_asset, _swapData, 0);
  }

  /**
   * @notice Sets the strategy inputs and weights if any
   * @notice In case of pre-existing inputs, a call to `liquidate()` should precede this in order to not lose track of the strategy's liquidity
   * @param _inputs Array of input addresses
   * @param _weights Array of input weights
   * @param _lpTokens Array of LP tokens
   */
  function _setInputs(
    address[] calldata _inputs,
    uint16[] calldata _weights,
    address[] calldata _lpTokens
  ) internal {
    (bool success, ) = _baseStorageExt().agent.delegatecall(
      abi.encodeWithSelector(
        IStrategyV5Agent.setInputs.selector,
        _inputs,
        _weights,
        _lpTokens
      )
    );
    if (!success) {
      revert Errors.FailedDelegateCall();
    }
  }

  /**
   * @notice Sets the strategy reward tokens if any
   * @notice In case of pre-existing rewardTokens, a call to `harvest()` should precede this in order to not lose track of the strategy's pending rewards
   * @param _rewardTokens Array of input addresses
   */
  function _setRewardTokens(address[] calldata _rewardTokens) internal {
    (bool success, ) = _baseStorageExt().agent.delegatecall(
      abi.encodeWithSelector(
        IStrategyV5Agent.setRewardTokens.selector,
        _rewardTokens
      )
    );
    if (!success) {
      revert Errors.FailedDelegateCall();
    }
  }

  /**
   * @notice Calculates the total pending redemption requests in shares
   * @dev Returns the difference between _req.totalRedemption and _req.totalClaimableRedemption in underlying assets
   * @return Total amount of pending redemption requests
   */
  function _totalPendingAssetsRequest() internal returns (uint256) {
    (bool success, bytes memory res) = _baseStorageExt().agent.delegatecall(
      abi.encodeWithSelector(IAs4626.totalPendingWithdrawRequest.selector)
    );
    return success ? abi.decode(res, (uint256)) : 0;
  }

  /**
   * @notice Calculates the total pending redemption requests in shares
   * @dev Returns the difference between _req.totalRedemption and _req.totalClaimableRedemption in shares
   * @return Total amount of pending redemption requests
   */
  function _totalPendingRedemptionRequest() internal returns (uint256) {
    (bool success, bytes memory res) = _baseStorageExt().agent.delegatecall(
      abi.encodeWithSelector(IAs4626.totalPendingRedemptionRequest.selector)
    );
    return success ? abi.decode(res, (uint256)) : 0;
  }

  /**
   * @return Total amount of underlying assets available to withdraw
   */
  function _availableClaimable() internal returns (uint256) {
    (bool success, bytes memory res) = _baseStorageExt().agent.delegatecall(
      abi.encodeWithSelector(IAs4626.availableClaimable.selector)
    );
    return success ? abi.decode(res, (uint256)) : 0;
  }

  /**
   * @return Amount of underlying assets available to non-requested withdrawals, excluding `minLiquidity`
   */
  function _available() internal virtual returns (uint256) {
    (bool success, bytes memory res) = _baseStorageExt().agent.delegatecall(
      abi.encodeWithSelector(IStrategyV5Agent.available.selector)
    );
    return success ? abi.decode(res, (uint256)) : 0;
  }

  /**
   * @return Share price - Amount of underlying assets redeemable for one share
   */
  function _sharePrice() internal virtual returns (uint256) {
    (bool success, bytes memory res) = _baseStorageExt().agent.delegatecall(
      abi.encodeWithSelector(IAs4626.sharePrice.selector)
    );
    return success ? abi.decode(res, (uint256)) : 0;
  }

  /**
   * @notice Sets the strategy agent implementation
   * @param _agent Address of the new agent
   */
  function _updateAgent(address _agent) internal {
    if (_agent == address(0)) {
      revert Errors.AddressZero();
    }
    (bool success, ) = _agent.staticcall(
      abi.encodeWithSelector(IStrategyV5Agent.proxyType.selector)
    );
    if (!success) {
      revert Errors.ContractNonCompliant();
    }
    _baseStorageExt().agent = _agent;
  }

  /**
   * @notice Sets the strategy agent implementation
   * @param _agent Address of the new agent
   */
  function updateAgent(address _agent) external onlyAdmin {
    _updateAgent(_agent);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             HOOKS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Called before investing underlying assets into the strategy inputs
   * @param _amounts Amount of underlying assets to invest in each input
   * @param _params Swaps calldata
   */
  function _beforeInvest(
    uint256[8] calldata _amounts,
    bytes[] calldata _params
  ) internal virtual {}

  /**
   * @notice Called after investing underlying assets into the strategy inputs
   * @param _totalInvested Sum of underlying assets invested
   */
  function _afterInvest(
    uint256 _totalInvested,
    bytes[] calldata _params
  ) internal virtual {}

  /**
   * @notice Called before harvesting rewards from the strategy
   */
  function _beforeHarvest() internal virtual {}

  /**
   * @notice Called after harvesting rewards from the strategy
   * @param _assetsReceived Amount of underlying assets received from harvesting
   */
  function _afterHarvest(uint256 _assetsReceived) internal virtual {}

  /**
   * @notice Called before liquidating strategy inputs
   * @param _amounts Amount of each input to liquidate
   */
  function _beforeLiquidate(
    uint256[8] calldata _amounts,
    bytes[] calldata _params
  ) internal virtual {}

  /**
   * @notice Called after liquidating strategy inputs
   * @param _totalRecovered Total amount of underlying assets recovered from liquidation
   */
  function _afterLiquidate(
    uint256 _totalRecovered,
    bytes[] calldata _params
  ) internal virtual {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Sets the lpTokens's allowances on inputs
   * @param _amount Amount of allowance to set
   */
  function _setLpTokenAllowances(uint256 _amount) internal virtual {
    // default is to approve AsMaths.MAX_UINT256
    unchecked {
      _amount = _amount > 0 ? _amount : AsMaths.MAX_UINT256;
      for (uint256 i = 0; i < _inputLength; i++) {
        if (address(lpTokens[i]) == address(0)) break;
        inputs[i].forceApprove(address(lpTokens[i]), _amount);
      }
    }
  }

  /**
   * @notice Stakes or provides `_amount` from `input[_index]` to `lpTokens[_index]`
   * @param _amount Amount of underlying assets to allocate to `inputs[_index]`
   * @param _index Index of the input to stake
   * @param _params Swaps calldata
   */
  function _stake(uint256 _amount, uint256 _index, bytes[] calldata _params) internal virtual {
    _stake(_amount, _index);
  }

  function _stake(uint256 _amount, uint256 _index) internal virtual {
    revert Errors.NotImplemented(); // either this function or the above needs an override, this should never be called
  }

  /**
   * @notice Unstakes or liquidates `_amount` of `lpTokens[i]` back to `input[_index]`
   * @param _amount Amount of underlying assets to recover from liquidating `inputs[_index]`
   * @param _index Index of the input to liquidate
   * @param _params Swaps calldata
   */
  function _unstake(uint256 _amount, uint256 _index, bytes[] calldata _params) internal virtual {
    _unstake(_amount, _index);
  }

  function _unstake(uint256 _amount, uint256 _index) internal virtual {
    revert Errors.ContractNonCompliant();
  }

  /**
   * @notice Invests `_amounts` of underlying assets in the strategy inputs
   * @param _amounts Amount of underlying assets to invest in each input
   * @param _params Swaps calldata
   * @return totalInvested Sum of underlying assets invested
   */
  function _invest(
    uint256[8] calldata _amounts, // from previewInvest()
    bytes[] calldata _params
  ) internal virtual returns (uint256 totalInvested) {
    _beforeInvest(_amounts, _params); // strat specific hook
    unchecked {
      uint256 spent;
      uint256 toStake;

      for (uint256 i = 0; i < _inputLength; i++) {
        if (_amounts[i] < 10) {
          continue;
        }

        if (asset != inputs[i]) {
          (toStake, spent) = swapper.decodeAndSwap({
            _input: address(asset),
            _output: address(inputs[i]),
            _amount: _amounts[i],
            _params: _params[i]
          });
          // pick up any input dust (eg. from previous liquidate()), not just the swap output
          toStake = inputs[i].balanceOf(address(this));
        } else {
          toStake = _amounts[i];
          spent = _amounts[i];
        }

        uint256 stakeOut = _investedInput(i);
        uint256 stakeIn = toStake == _amounts[i] ? inputs[i].balanceOf(address(this)) : toStake; // force balanceOf only if required

        _stake(toStake, i, _params);
        stakeOut = _investedInput(i) - stakeOut; // new stakes in input[i]
        stakeIn = stakeIn - inputs[i].balanceOf(address(this));

        if (stakeOut < stakeIn.subBp(_4626StorageExt().maxSlippageBps)) {
          revert Errors.AmountTooLow(stakeOut);
        }

        totalInvested += spent;
      }

      _afterInvest(totalInvested, _params); // strat specific hook

      last.invest = uint64(block.timestamp);
      emit Invest(totalInvested, block.timestamp);
    }
  }

  /**
   * @notice Invests `_amounts` of underlying assets in the strategy inputs
   * @param _amounts Amounts of asset to invest in each input
   * @param _params Swaps calldata
   * @return totalInvested Sum of underlying assets invested
   */
  function invest(
    uint256[8] calldata _amounts, // from previewInvest()
    bytes[] calldata _params
  ) external nonReentrant onlyKeeper returns (uint256 totalInvested) {
    return _invest(_amounts, _params);
  }

  /**
   * @notice Liquidates inputs according to `_amounts` using `_params` for swaps, expecting to recover at least `_minLiquidity` of underlying assets
   * @param _amounts Amount of each inputs to liquidate in input tokens
   * @param _minLiquidity Minimum amount of assets to retrieve
   * @param _panic Sets to true to ignore slippage when liquidating
   * @param _params Generic calldata (e.g., SwapperParams)
   * @return totalRecovered Total amount of asset withdrawn
   */
  function _liquidate(
    uint256[8] calldata _amounts,
    uint256 _minLiquidity,
    bool _panic,
    bytes[] calldata _params
  ) internal virtual returns (uint256 totalRecovered) {
    _beforeLiquidate(_amounts, _params); // strat specific hook
    unchecked {
      // pre-liquidation sharePrice
      last.sharePrice = _sharePrice();

      // in share
      uint256 pendingRedemption = _totalPendingRedemptionRequest();

      // liquidate protocol positions
      uint256 toUnstake;
      uint256 recovered;

      for (uint256 i = 0; i < _inputLength; i++) {
        if (_amounts[i] < 10) {
          continue;
        }
        toUnstake = _inputToStake(_amounts[i], i);
        // AsMaths.min(_inputToStake(_amounts[i], i), lpTokens[i].balanceOf(address(this)));
        uint256 balanceBefore = inputs[i].balanceOf(address(this));
        _unstake(toUnstake, i, _params);
        recovered = inputs[i].balanceOf(address(this)) - balanceBefore; // `inputs[i]` recovered
        // swap the unstaked `input[i]` tokens for underlying assets if necessary
        if (inputs[i] != asset) {
          // check for missing swapData
          if (_params[i].length == 0) {
            revert Errors.InvalidData();
          }
          // check for natives to before swapping
          if (address(inputs[i]) == address(1)) {
            _wrapNative(recovered); // ETH->WETH to swap with
          }
          (recovered, ) = swapper.decodeAndSwap({ // `asset` recovered
            _input: address(inputs[i]),
            _output: address(asset),
            _amount: _amounts[i],
            _params: _params[i]
          });
        } else {
          recovered = _amounts[i];
        }

        // unified slippage check (unstake+remove liquidity+swap out)
        if (
          recovered <
          _inputToAsset(_amounts[i], i).subBp(_4626StorageExt().maxSlippageBps)
        ) {
          revert Errors.AmountTooLow(recovered);
        }

        // sum up the recovered underlying assets
        totalRecovered += recovered;
      }

      _req.totalClaimableRedemption += pendingRedemption;

      // use availableClaimable() and not borrowable() to avoid intra-block cash variance (absorbed by the redemption claim delays)
      uint256 liquidityAvailable = _availableClaimable().subMax0(
        _req.totalClaimableRedemption.mulDiv(
          last.sharePrice * _weiPerAsset,
          _WEI_PER_SHARE_SQUARED
        )
      );

      // check if we have enough cash to repay redemption requests
      if (liquidityAvailable < _minLiquidity && !_panic) {
        revert Errors.AmountTooLow(liquidityAvailable);
      }
      _afterLiquidate(totalRecovered, _params); // strat specific hook
      last.liquidate = uint64(block.timestamp);
      emit Liquidate(totalRecovered, liquidityAvailable, block.timestamp);
    }
  }

  /**
   * @notice Liquidates inputs according to `_amounts` using `_params` for swaps, expecting to recover at least `_minLiquidity` of underlying assets
   * @param _amounts Amount of each inputs to liquidate in input tokens
   * @param _minLiquidity Minimum amount of assets to retrieve
   * @param _panic Sets to true to ignore slippage when liquidating
   * @param _params Generic calldata (e.g., SwapperParams)
   * @return totalRecovered Total amount of asset withdrawn
   */
  function liquidate(
    uint256[8] calldata _amounts,
    uint256 _minLiquidity,
    bool _panic,
    bytes[] calldata _params
  ) external nonReentrant onlyKeeper returns (uint256 totalRecovered) {
    return _liquidate(_amounts, _minLiquidity, _panic, _params);
  }

  /**
   * @notice Requests a liquidation for `_amount` of underlying assets
   * @param _amount Amount to be liquidated
   * @return Amount of underlying assets to be liquidated
   * @dev This should be overriden by strategy implementations, used for lockable strategies
   */
  function _liquidateRequest(
    uint256 _amount
  ) internal virtual returns (uint256) {
    return 0;
  }

  /**
   * @notice Requests a liquidation for `_amount` of underlying assets
   * @param _amount Amount to be liquidated
   * @return Amount of underlying assets to be liquidated
   * @dev This should be overriden by strategy implementations, used for lockable strategies
   */
  function liquidateRequest(uint256 _amount) external returns (uint256) {
    return _liquidateRequest(_amount);
  }

  /**
   * @notice Claims rewards from the strategy underlying protocols
   * @return amounts Array of amounts of reward tokens claimed
   * @dev Should be overriden by strategy implementations
   */
  function _claimRewards() internal virtual returns (uint256[] memory amounts) {
    return new uint256[](_rewardLength);
  }

  /**
   * @notice Claims rewards from the strategy underlying protocols
   * @return amounts Array of amounts of reward tokens claimed
   * @dev Should be overriden by strategy implementations
   */
  function claimRewards()
    public
    virtual
    onlyKeeper
    returns (uint256[] memory amounts)
  {
    return _claimRewards();
  }

  /**
   * @notice Swaps `_balances` of reward tokens to underlying asset
   * @param _balances Array of amounts of rewards to swap
   * @param _params Swaps calldata
   * @return assetsReceived Amount of underlying assets received (after swap)
   */
  function _swapRewards(
    uint256[] memory _balances,
    bytes[] calldata _params
  ) internal virtual onlyKeeper returns (uint256 assetsReceived) {
    uint256 received;
    unchecked {
      for (uint256 i = 0; i < _rewardLength; i++) {
        if (rewardTokens[i] != address(asset) && _balances[i] > 10) {
          (received, ) = swapper.decodeAndSwap({
            _input: rewardTokens[i],
            _output: address(asset),
            _amount: _balances[i],
            _params: _params[i]
          });
          assetsReceived += received;
        } else {
          assetsReceived += _balances[i];
        }
      }
    }
  }

  /**
   * @notice Harvests the strategy underlying protocols' rewards (claim+swap)
   * @param _params Swaps calldata
   * @return assetsReceived Amount of underlying assets received (after swap)
   */
  function _harvest(
    bytes[] calldata _params
  ) internal virtual returns (uint256 assetsReceived) {
    _beforeHarvest(); // strat specific hook
    unchecked {
      assetsReceived = _swapRewards(_claimRewards(), _params);
      // reset expected profits to updated value + amount
      _expectedProfits =
        AsAccounting.unrealizedProfits(
          last.harvest,
          _expectedProfits,
          _profitCooldown
        ) +
        assetsReceived;
      _afterHarvest(assetsReceived); // strat specific hook
      last.harvest = uint64(block.timestamp);
      emit Harvest(assetsReceived, block.timestamp);
    }
  }

  /**
   * @notice Harvests the strategy underlying protocols' rewards (claim+swap)
   * @param _params Swaps calldata
   * @return assetsReceived Amount of underlying assets received (after swap)
   */
  function harvest(
    bytes[] calldata _params
  ) external onlyKeeper nonReentrant returns (uint256) {
    return _harvest(_params);
  }

  /**
   * @notice Compounds by investing `_amounts` of underlying assets and rewards back into the strategy, using swap calldata for both harvest and invest
   * @dev Pass a conservative _amount (e.g., available() + 90% of rewards valued in asset) to ensure the asset->inputs swaps success
   * @dev Off-chain `harvest() + invest()` call flow should be used for more accuracy
   * @param _amounts Amount of inputs to invest (in asset, after harvest-> should include rewards)
   * @param _harvestParams Swap calldata for harvesting
   * @param _investParams Swap calldata for investing
   * @return totalHarvested Amount of rewards harvested
   * @return totalInvested Amount of underlying assets re-invested
   */
  function _compound(
    uint256[8] calldata _amounts,
    bytes[] calldata _harvestParams,
    bytes[] calldata _investParams
  ) internal virtual returns (uint256 totalHarvested, uint256 totalInvested) {
    // we expect the SwapData to cover harvesting + investing
    if (
      _harvestParams.length != _rewardLength ||
      _investParams.length != _inputLength
    ) {
      revert Errors.InvalidData();
    }

    // harvest using the first calldata bytes (swap rewards->asset)
    totalHarvested = _harvest(_harvestParams);
    totalInvested = _invest(_amounts, _investParams);
  }

  /**
   * @notice Compounds by investing `_amounts` of underlying assets and rewards back into the strategy, using swap calldata for both harvest and invest
   * @dev Pass a conservative _amount (e.g., available() + 90% of rewards valued in asset) to ensure the asset->inputs swaps success
   * @dev Off-chain `harvest() + invest()` call flow should be used for more accuracy
   * @param _amounts Amount of inputs to invest (in asset, after harvest-> should include rewards)
   * @param _harvestParams Swap calldata for harvesting
   * @param _investParams Swap calldata for investing
   * @return totalHarvested Amount of rewards harvested
   * @return totalInvested Amount of underlying assets re-invested
   */
  function compound(
    uint256[8] calldata _amounts,
    bytes[] calldata _harvestParams,
    bytes[] calldata _investParams
  )
    external
    nonReentrant
    onlyKeeper
    returns (uint256 totalHarvested, uint256 totalInvested)
  {
    (totalHarvested, totalInvested) = _compound(
      _amounts,
      _harvestParams,
      _investParams
    );
  }

  /**
   * @notice Wraps `_amount` native tokens from the contract's balance
   * @param _amount Amount of native assets to wrap
   */
  function _wrapNative(uint256 _amount) internal {
    if (_amount > address(this).balance) {
      revert Errors.AmountTooHigh(_amount);
    }
    if (_amount > 0) {
      _wgas.deposit{value: _amount}();
    }
  }

  /**
   * @notice Wraps the contract full native balance (the contract does not need gas)
   */
  function _wrapNative() internal {
    _wrapNative(address(this).balance);
  }
}
