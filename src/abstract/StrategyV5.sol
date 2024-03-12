// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../interfaces/IStrategyV5.sol";
import "../libs/AsArrays.sol";
import "../libs/AsMaths.sol";
import "./AsManageable.sol";
import "./AsRescuable.sol";
import "./AsProxy.sol";
import "./ERC20Abstract.sol";
import "./As4626Abstract.sol";
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
 */
contract StrategyV5 is StrategyV5Abstract, As4626Abstract, ERC20Abstract, AsProxy, AsManageable, AsRescuable {
  using AsMaths for uint256;
  using AsMaths for int256;
  using AsArrays for bytes[];

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor() StrategyV5Abstract() {
    _pause();
  }

  /**
   * @notice Initializes the strategy using `_params`
   * @param _params StrategyBaseParams struct containing strategy parameters
   */
  function _init(StrategyBaseParams calldata _params) internal onlyAdmin {
    if (_params.coreAddresses.agent == address(0)) revert AddressZero();
    // setExemption(msg.sender, true);
    // done in As4626 but required for swapper
    _wgas = IWETH9(_params.coreAddresses.wgas);
    agent = IStrategyV5(_params.coreAddresses.agent);
    _agentStorageExt().delegator = IStrategyV5(address(this));
    _delegateToSelector(
      _params.coreAddresses.agent, // erc20Metadata.................coreAddresses................................fees...................inputs.inputWeights.rewardTokens
      0x83904ca7, // keccak256("init(((string,string,uint8),(address,address,address,address,address),(uint64,uint64,uint64,uint64,uint64),address[],uint16[],address[]))") == StrategyV5Agent.init(_params)
      msg.data[4:]
    );
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return Agent's initialization state (ERC-897)
   */
  function initialized() public view virtual returns (bool) {
    return _initialized && address(agent) != address(0) && address(asset) != address(0);
  }

  /**
   * @return Agent's implementation address (OZ Proxy's internal override)
   */
  function _implementation() internal view override returns (address) {
    return address(agent);
  }

  /**
   * @return Agent's implementation address (ERC-897)
   */
  function implementation() external view returns (address) {
    return address(agent);
  }

  /**
   * @notice Converts `_amount` of underlying assets to a specific input (`inputs[_index]`)
   * @param _amount Amount of underlying assets
   * @param _index Index of the input to convert to
   * @return Input amount equivalent to `_amount` underlying assets
   * @dev This should be overriden by strategy implementations
   */
  function _assetToInput(
    uint256 _amount,
    uint256 _index
  ) internal view virtual returns (uint256) {
    return _amount;
  }

  /**
   * @notice Converts `_amount` of a specific input (`inputs[_index]`) to underlying assets
   * @param _amount Amount of input
   * @param _index Index of the input to convert from
   * @return Underlying asset amount equivalent to `_amount` input
   * @dev This should be overriden by strategy implementations
   */
  function _inputToAsset(
    uint256 _amount,
    uint256 _index
  ) internal view virtual returns (uint256) {
    return _amount;
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
    return _amount;
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
    return _amount;
  }

  /**
   * @notice Converts `_amount` of a specific LP/staked LP to underlying assets
   * @param _amount Amount of LP/staked LP
   * @param _index Index of the input
   * @return Underlying asset amount equivalent to `_amount` LP/staked LP
   */
  function _stakeToAsset(uint256 _amount, uint256 _index) internal view returns (uint256) {
    return _inputToAsset(_stakeToInput(_amount, _index), _index);
  }

  /**
   * @notice Converts `_amount` of underlying assets to a specific LP/staked LP
   * @param _amount Amount of underlying assets
   * @param _index Index of the input
   * @return LP/staked LP equivalent to `_amount` underlying assets
   */
  function _assetToStake(uint256 _amount, uint256 _index) internal view returns (uint256) {
    return _inputToStake(_assetToInput(_amount, _index), _index);
  }

  /**
   * @notice Converts a full LP/staked LP balance to its underlying input (`inputs[_index]`)
   * @param _index Index of the input
   * @return Input equivalent to the full LP/staked LP balance
   * @dev This should be overriden by strategy implementations
   */
  function _investedInput(uint256 _index) internal view virtual returns (uint256) {
    return 0;
  }

  /**
   * @notice Converts a full input balance (`inputs[_index]`) to underlying assets
   * @param _index Index of the input
   * @return Amount of underlying assets equivalent to the full input balance
   */
  function _invested(uint256 _index) internal view virtual returns (uint256) {
    _inputToAsset(investedInput(_index), _index);
  }

  /**
   * @notice Converts a full input balance (`inputs[_index]`) to underlying assets
   * @param _index Index of the input
   * @return Amount of underlying assets equivalent to the full input balance
   */
  function invested(uint256 _index) external view virtual returns (uint256) {
    return _invested(_index);
  }

  /**
   * @notice Gets the amount of a specific input (`inputs[_index]`) invested in the strategy, LP or staked
   * @param _index Index of the input
   * @return Amount of input invested
   * @dev This should be overriden by strategy implementations
   */
  function investedInput(uint256 _index) internal view virtual returns (uint256) {}

  /**
   * @notice Sums all inputs invested in the strategy, LP or staked, in underlying assets
   * @return total Amount invested
   */
  function _invested() internal view virtual override returns (uint256 total) {
    for (uint256 i = 0; i < _inputLength;) {
      total += _invested(i);
      unchecked {
        i++;
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
   * @dev Calculates the excess weight for a given input (inputs[`_index`]) in basis points
   * @param _index Index of the input
   * @param _total Sum of all invested inputs (`0 == 100% == invested()`)
   * @return Excess input weight in basis points
   */
  function _excessWeight(uint256 _index, uint256 _total) internal view returns (int256) {
    if (_total == 0) _total = _invested();
    return int256(_invested(_index).mulDiv(AsMaths._BP_BASIS, _total))
      - int256(uint256(inputWeights[_index])); // de-facto safe as weights are sanitized
  }

  /**
   * @dev Calculates the excess weights for all inputs
   * @param _total Sum of all invested inputs (`0 == 100% == invested()`)
   * @return excessWeights Array[8] of excess input weights in basis points
   */
  function _excessWeights(uint256 _total)
    internal
    view
    returns (int256[8] memory excessWeights)
  {
    if (_total == 0) _total = _invested();
    for (uint256 i = 0; i < _inputLength;) {
      excessWeights[i] = _excessWeight(i, _total);
      unchecked {
        i++;
      }
    }
  }

  /**
   * @dev Calculates the excess liquidity for a given input (inputs[`_index`])
   * @param _index Index of the input
   * @param _total Sum of all invested inputs (`0 == 100% == invested()`)
   * @return Excess input liquidity
   */
  function _excessInputLiquidity(
    uint256 _index,
    uint256 _total
  ) internal view returns (int256) {
    if (_total == 0) _total = _invested();
    return int256(investedInput(_index))
      - int256(
        _assetToInput(
          _total.mulDiv(uint256(inputWeights[_index]), AsMaths._BP_BASIS), _index
        )
      );
  }

  /**
   * @dev Calculates the excess liquidity for all inputs
   * @param _total Sum of all invested inputs (`0 == 100% == invested()`)
   * @return excessLiquidity Array[8] of excess input liquidities
   */
  function _excessInputLiquidity(uint256 _total)
    internal
    view
    returns (int256[8] memory excessLiquidity)
  {
    if (_total == 0) _total = _invested();
    for (uint256 i = 0; i < _inputLength;) {
      excessLiquidity[i] = _excessInputLiquidity(i, _total);
      unchecked {
        i++;
      }
    }
  }

  /**
   * @dev Previews the amounts that would be liquidated to recover `_amount + totalPendingAssetRequest() + allocated.bp(150)` of liquidity
   * @param _amount Amount of underlying assets to recover
   * @return amounts Array[8] of previewed liquidated amounts
   */
  function previewLiquidate(uint256 _amount) public returns (uint256[8] memory amounts)
  {
    uint256 allocated = _invested();
    uint256 pending = _pendingAssetsRequest();
    _amount += pending + allocated.bp(150);
    _amount = AsMaths.min(_amount, allocated);
    // excessInput accounts for the weights and the cash available in the strategy
    int256[8] memory excessInput = _excessInputLiquidity(allocated - _amount);
    for (uint256 i = 0; i < _inputLength;) {
      if (_amount < 10) break; // no leftover
      if (excessInput[i] > 0) {
        unchecked {
          uint256 need = _inputToAsset(excessInput[i].abs(), i);
          if (need > _amount) {
            need = _amount;
          }
          amounts[i] = need;
          _amount -= need;
        }
      }
      unchecked {
        i++;
      }
    }
  }

  /**
   * @dev Previews the breakdown of `_amount` underlying assets that would be invested in each input based on the current excess liquidities
   * @param _amount Amount of underlying assets to invest
   * @return amounts Array[8] of previewed invested amounts
   */
  function previewInvest(uint256 _amount) public returns (uint256[8] memory amounts) {
    if (_amount == 0) {
      _amount = _available();
    }
    // compute the excess liquidity
    // NB: max allocated would be 90% for buffering flows if inputWeights are [30_00,30_00,30_00]
    int256[8] memory excessInput = _excessInputLiquidity(_invested() + _amount);
    for (uint256 i = 0; i < _inputLength;) {
      if (_amount < 10) break; // no leftover
      if (excessInput[i] < 0) {
        unchecked {
          uint256 need = _inputToAsset(excessInput[i].abs(), i);
          if (need > _amount) {
            need = _amount;
          }
          amounts[i] = need;
          _amount -= need;
        }
      }
      unchecked {
        i++;
      }
    }
  }

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
    return (_token == address(1) || _token == address(_wgas))
      ? address(this).balance + _wgas.balanceOf(address(this)) // native+wrapped native
      : IERC20Metadata(_token).balanceOf(address(this));
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            SETTERS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Updates the strategy underlying asset (critical, automatically pauses the strategy)
   * @notice If the new asset has a different price (USD denominated), a sudden `sharePrice()` change is expected
   * @param _asset Address of the new underlying asset
   * @param _swapData Swap calldata used to exchange the old `asset` for the new `_asset`
   * @param _priceFactor Price factor to convert the old `asset` to the new `_asset` (old asset price * 1e18) / (new asset price)
   */
  function _updateAsset(
    address _asset,
    bytes calldata _swapData,
    uint256 _priceFactor
  ) internal {
    _delegateToSelectorMemory(
      address(agent),
      0x7a1ed234, // keccak256("updateAsset(address,bytes,uint256)") == StrategyV5Agent.updateAsset(_asset, _swapData, _priceFactor)
      abi.encode(_asset, _swapData, _priceFactor)
    );
  }

  /**
   * @notice Sets the strategy inputs and weights
   * @notice In case of pre-existing inputs, a call to `liquidate()` should precede this in order to not lose track of the strategy's liquidity
   * @param _inputs Array of input addresses
   * @param _weights Array of input weights
   */
  function _setInputs(address[] calldata _inputs, uint16[] calldata _weights) internal {
    _delegateToSelectorMemory(
      address(agent),
      0xd0d37333, // keccak256("setInputs(address[],uint16[])") == StrategyV5Agent.setInputs(_inputs, _weights)
      abi.encode(_inputs, _weights)
    );
  }

  /**
   * @notice Calculates the total pending redemption requests in underlying assets
   * @dev Returns the difference between _req.totalRedemption and _req.totalClaimableRedemption
   * @return Underlying assets equivalent of the total pending redemption requests
   */
  function _pendingAssetsRequest() internal returns (uint256) {
    (bool success, bytes memory result) = _delegateToSelector(
      address(agent),
      0x4d5b6164, // keccak256("totalPendingAssetRequest()") == StrategyV5Agent.totalPendingAssetRequest()
      msg.data
    );
    return success ? abi.decode(result, (uint256)) : 0;
  }

  /**
   * @notice Calculates the total pending redemption requests in shares
   * @dev Returns the difference between _req.totalRedemption and _req.totalClaimableRedemption
   * @return The total amount of pending redemption requests
   */
  function _pendingRedemptionRequest() internal returns (uint256) {
    (bool success, bytes memory result) = _delegateToSelector(
      address(agent),
      0x7ed76e63, // keccak256("totalPendingRedemptionRequest()") == StrategyV5Agent.totalPendingRedemptionRequest()
      msg.data
    );
    return success ? abi.decode(result, (uint256)) : 0;
  }

  /**
   * @return Total amount of underlying assets available to withdraw
   */
  function _availableClaimable() internal returns (uint256) {
    (bool success, bytes memory result) = _delegateToSelector(
      address(agent),
      0x8f1c290a, // keccak256("availableClaimable()") == StrategyV5Agent.availableClaimable()
      msg.data
    );
    return success ? abi.decode(result, (uint256)) : 0;
  }

  /**
   * @return Amount of underlying assets available to non-requested withdrawals, excluding `minLiquidity`
   */
  function _available() internal virtual returns (uint256) {
    (bool success, bytes memory result) = _delegateToSelector(
      address(agent),
      0x48a0d754, // keccak256("available()") == StrategyV5Agent.available()
      msg.data
    );
    return success ? abi.decode(result, (uint256)) : 0;
  }

  /**
   * @return Share price - Amount of underlying assets redeemable for one share
   */
  function _sharePrice() internal virtual returns (uint256) {
    (bool success, bytes memory result) = _delegateToSelector(
      address(agent),
      0x87269729, // keccak256("sharePrice()") == StrategyV5Agent.sharePrice()
      msg.data
    );
    return success ? abi.decode(result, (uint256)) : 0;
  }

  /**
   * @notice Sets the strategy agent implementation
   * @param _agent Address of the new agent
   */
  function updateAgent(address _agent) external onlyAdmin {
    if (_agent == address(0)) revert AddressZero();
    agent = IStrategyV5(_agent);
  }

  /**
   * @notice Sets the strategy allowances
   * @notice This should be overriden by strategy implementations
   * @param _amount Amount for which to set the allowances
   */
  function _setAllowances(uint256 _amount) internal virtual {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Liquidates inputs according to `_amounts`, using `_params` for swaps
   * @param _amounts Amounts of asset to liquidate from each input
   * @param _params Swaps calldata
   * @return assetsRecovered Amount of underlying assets recovered
   */
  function _liquidate(
    uint256[8] calldata _amounts, // from previewLiquidate()
    bytes[] calldata _params
  ) internal virtual returns (uint256 assetsRecovered) {}

  /**
   * @notice Liquidates inputs according to `_amounts` using `_params` for swaps, expecting to recover at least `_minLiquidity` of underlying assets
   * @param _amounts Amount of each inputs to liquidate (in asset)
   * @param _minLiquidity Minimum amount of assets to receive
   * @param _panic Sets to true to ignore slippage when liquidating
   * @param _params Generic calldata (e.g., SwapperParams)
   * @return liquidityAvailable Updated vault available liquidity
   */
  function liquidate(
    uint256[8] calldata _amounts,
    uint256 _minLiquidity,
    bool _panic,
    bytes[] calldata _params
  ) external nonReentrant onlyManager returns (uint256 liquidityAvailable) {
    // pre-liquidation sharePrice
    last.sharePrice = _sharePrice();

    // in share
    uint256 pendingRedemption = _pendingRedemptionRequest();

    // liquidate protocol positions
    uint256 liquidated = _liquidate(_amounts, _params);

    _req.totalClaimableRedemption += pendingRedemption;

    // we use availableClaimable() and not availableBorrowable() to avoid intra-block cash variance (absorbed by the redemption claim delays)
    liquidityAvailable = _availableClaimable().subMax0(
      _req.totalClaimableRedemption.mulDiv(
        last.sharePrice * _weiPerAsset, _WEI_PER_SHARE_SQUARED
      )
    );
    // check if we have enough cash to repay redemption requests
    if (liquidityAvailable < _minLiquidity && !_panic) {
      revert AmountTooLow(liquidityAvailable);
    }

    last.liquidate = uint64(block.timestamp);
    emit Liquidate(liquidated, liquidityAvailable, block.timestamp);
    return liquidityAvailable;
  }

  /**
   * @notice Requests a liquidation for `_amount` of underlying assets
   * @param _amount Amount to be liquidated
   * @return Amount of underlying assets to be liquidated
   * @dev This should be overriden by strategy implementations, used for lockable strategies
   */
  function _liquidateRequest(uint256 _amount)
    internal
    virtual
    returns (uint256) {
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
  function claimRewards() public virtual returns (uint256[] memory amounts) {
    return new uint256[](_rewardLength);
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
    for (uint256 i = 0; i < _rewardLength;) {
      if (rewardTokens[i] != address(asset) && _balances[i] > 10) {
        (received,) = swapper.decodeAndSwap({
          _input: rewardTokens[i],
          _output: address(asset),
          _amount: _balances[i],
          _params: _params[i]
        });
        assetsReceived += received;
      } else {
        assetsReceived += _balances[i];
      }
      unchecked {
        i++;
      }
    }
  }

  /**
   * @notice Harvests the strategy underlying protocols' rewards (claim+swap)
   * @param _params Swaps calldata
   * @return assetsReceived Amount of underlying assets received (after swap)
   * @dev This should be overriden by strategy implementations
   */
  function _harvest(bytes[] calldata _params)
    internal
    virtual
    nonReentrant
    returns (uint256 assetsReceived)
  {
    return _swapRewards(claimRewards(), _params);
  }

  /**
   * @notice Harvests the strategy underlying protocols' rewards (claim+swap)
   * @param _params Swaps calldata
   * @return assetsReceived Amount of underlying assets received (after swap)
   */
  function harvest(bytes[] calldata _params) public onlyKeeper returns (uint256 assetsReceived) {
    assetsReceived = _harvest(_params);
    // reset expected profits to updated value + amount
    _expectedProfits = AsAccounting.unrealizedProfits(
      last.harvest, _expectedProfits, _profitCooldown
    ) + assetsReceived;
    last.harvest = uint64(block.timestamp);
    emit Harvest(assetsReceived, block.timestamp);
  }

  /**
   * @notice Invests `_amounts` of underlying assets in the strategy inputs
   * @param _amounts Amounts of asset to invest in each input
   * @param _params Swaps calldata
   * @return investedAmount Sum of underlying assets invested
   * @return iouReceived Amount of stakes/LP tokens received
   */
  function _invest(
    uint256[8] calldata _amounts, // from previewInvest()
    bytes[] calldata _params
  ) internal virtual returns (uint256 investedAmount, uint256 iouReceived) {}

  /**
   * @notice Invests `_amounts` of underlying assets in the strategy inputs
   * @param _amounts Amounts of asset to invest in each input
   * @param _params Swaps calldata
   * @return investedAmount Sum of underlying assets invested
   * @return iouReceived Amount of stakes/LP tokens received
   */
  function invest(
    uint256[8] calldata _amounts, // from previewInvest()
    bytes[] calldata _params
  ) public onlyKeeper returns (uint256 investedAmount, uint256 iouReceived) {
    (investedAmount, iouReceived) = _invest(_amounts, _params);
    last.invest = uint64(block.timestamp);
    emit Invest(investedAmount, block.timestamp);
    return (investedAmount, iouReceived);
  }

  /**
   * @notice Compounds by investing `_amounts` of underlying assets and rewards back into the strategy, using swap calldata for both harvest and invest
   * @dev Pass a conservative _amount (e.g., available() + 90% of rewards valued in asset) to ensure the asset->inputs swaps success
   * @dev Off-chain `harvest() + invest()` call flow should be used for more accuracy
   * @param _amounts Amount of inputs to invest (in asset, after harvest-> should include rewards)
   * @param _harvestParams Swap calldata for harvesting
   * @param _investParams Swap calldata for investing
   * @return iouReceived Stakes/LP tokens received from the compound operation
   * @return harvestedRewards Amount of rewards harvested
   */
  function _compound(
    uint256[8] calldata _amounts,
    bytes[] calldata _harvestParams,
    bytes[] calldata _investParams
  ) internal virtual returns (uint256 iouReceived, uint256 harvestedRewards) {
    // we expect the SwapData to cover harvesting + investing
    if (_harvestParams.length != _rewardLength || _investParams.length != _inputLength) {
      revert InvalidData();
    }

    // harvest using the first calldata bytes (swap rewards->asset)
    harvestedRewards = harvest(_harvestParams);
    (, iouReceived) = invest(_amounts, _investParams);
    return (iouReceived, harvestedRewards);
  }

  /**
   * @notice Compounds by investing `_amounts` of underlying assets and rewards back into the strategy, using swap calldata for both harvest and invest
   * @dev Pass a conservative _amount (e.g., available() + 90% of rewards valued in asset) to ensure the asset->inputs swaps success
   * @dev Off-chain `harvest() + invest()` call flow should be used for more accuracy
   * @param _amounts Amount of inputs to invest (in asset, after harvest-> should include rewards)
   * @param _harvestParams Swap calldata for harvesting
   * @param _investParams Swap calldata for investing
   * @return iouReceived Stakes/LP tokens received from the compound operation
   * @return harvestedRewards Amount of rewards harvested
   */
  function compound(
    uint256[8] calldata _amounts,
    bytes[] calldata _harvestParams,
    bytes[] calldata _investParams
  ) external returns (uint256 iouReceived, uint256 harvestedRewards) {
    (iouReceived, harvestedRewards) = _compound(_amounts, _harvestParams, _investParams);
  }

  /**
   * @dev Wraps the contract full native balance (the contract does not need gas)
   * @return amount of native asset wrapped
   */
  function _wrapNative() internal virtual returns (uint256 amount) {
    amount = address(this).balance;
    if (amount > 0) {
      _wgas.deposit{value: amount}();
    }
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                          RESCUE LOGIC                          ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Requests a rescue for `_token`, setting `msg.sender` as the receiver
   * @param _token Token to be rescued - Use address(1) for native/gas tokens (ETH)
   */
  function requestRescue(address _token) external override onlyAdmin {
    AsRescuable._requestRescue(_token);
  }

  /**
   * @notice Rescues the contract's `_token` (ERC20 or native) full balance by sending it to `req.receiver`if a valid rescue request exists
   * @notice Rescue request must be executed after `RESCUE_TIMELOCK` and before end of validity (`RESCUE_TIMELOCK + RESCUE_VALIDITY`)
   * @param _token Token to be rescued - Use address(1) for native/gas tokens (ETH)
   */
  function rescue(address _token) external override onlyManager {
    _rescue(_token);
  }
}
