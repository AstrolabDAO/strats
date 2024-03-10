// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../interfaces/IStrategyV5.sol";
import "./StrategyV5Abstract.sol";
import "./As4626.sol";
import "./AsRescuable.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title StrategyV5Agent - Astrolab's strategy back-end implementation
 * @author Astrolab DAO
 * @notice Common strategy back-end, implementing shared vault/strategy accounting logic
 * @notice All state variables must be in StrategyV5Abstract to match the proxy base storage layout (StrategyV5)
 */
contract StrategyV5Agent is StrategyV5Abstract, AsRescuable, As4626 {
  using AsMaths for uint256;
  using AsMaths for int256;
  using SafeERC20 for IERC20Metadata;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor() StrategyV5Abstract() {}

  /**
   * @notice Initializes the strategy with base `_params`
   * @param _params StrategyBaseParams struct containing strategy parameters (Erc20Metadata, CoreAddresses, Fees, inputs, inputWeights, rewardTokens)
   */
  function init(StrategyBaseParams calldata _params) public onlyAdmin {
    swapper = ISwapper(_params.coreAddresses.swapper);
    // setInputs(_params.inputs, _params.inputWeights); // done in parent strategy init()
    setRewardTokens(_params.rewardTokens);
    asset = IERC20Metadata(_params.coreAddresses.asset);
    _assetDecimals = asset.decimals();
    _weiPerAsset = 10 ** _assetDecimals;
    As4626.init(_params.erc20Metadata, _params.coreAddresses, _params.fees);
    setSwapperAllowance(_MAX_UINT256, true, false, true); // reward allowances already set
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Retrieves the share price from the strategy via the proxy
   * @notice Calls sharePrice function on the IStrategyV5 contract through `_stratProxy` (delegator's address)
   * @return Strategy share price - Amount of underlying assets redeemable for one share
   */
  function sharePrice() public view override returns (uint256) {
    return _agentStorageExt().delegator.sharePrice();
  }

  /**
   * @return Total assets denominated in underlying assets, including claimable redemptions (strategy delegator `_stratProxy.totalAssets()`)
   */
  function totalAssets() public view override returns (uint256) {
    return _agentStorageExt().delegator.totalAssets();
  }

  /**
   * @return Total amount of invested inputs denominated in underlying assets
   */
  function invested() public view override returns (uint256) {
    return _agentStorageExt().delegator.invested();
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            SETTERS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Toggles fee exemption for an account
   * @param _account Account to exempt
   * @param _isExempt Whether to exempt or not
   */
  function setExemption(address _account, bool _isExempt) public onlyAdmin {
    exemptionList[_account] = _isExempt;
  }

  /**
   * @notice Sets the swapper's allowance
   * @param _amount Amount of allowance to set
   * @param _inputs Boolean indicating whether to set input allowances
   * @param _rewards Boolean indicating whether to set reward allowances
   * @param _asset Boolean indicating whether to set asset allowances
   */
  function setSwapperAllowance(
    uint256 _amount,
    bool _inputs,
    bool _rewards,
    bool _asset
  ) public onlyAdmin {
    address swapperAddress = address(swapper);
    if (swapperAddress == address(0)) revert AddressZero();
    // we keep the possibility to set allowance to 0 in case of a change of swapper
    // default is to approve _MAX_UINT256
    _amount = _amount > 0 ? _amount : _MAX_UINT256;

    if (_inputs) {
      for (uint256 i = 0; i < _inputLength;) {
        if (address(inputs[i]) == address(0)) break;
        inputs[i].forceApprove(swapperAddress, _amount);
        unchecked {
          i++;
        }
      }
    }
    if (_rewards) {
      for (uint256 i = 0; i < _rewardLength;) {
        if (rewardTokens[i] == address(0)) break;
        IERC20Metadata(rewardTokens[i]).forceApprove(swapperAddress, _amount);
        unchecked {
          i++;
        }
      }
    }
    if (_asset) {
      asset.forceApprove(swapperAddress, _amount);
    }
  }

  /**
   * @notice Updates the strategy's swapper, revokes allowances to the previous and grants it to the new one
   * @param _swapper Address of the new swapper
   */
  function updateSwapper(address _swapper) public onlyAdmin {
    if (_swapper == address(0)) revert AddressZero();
    setSwapperAllowance(0, true, true, true);
    swapper = ISwapper(_swapper);
    setSwapperAllowance(_MAX_UINT256, true, true, true);
  }

  /**
   * @notice Updates the strategy's underlying asset (critical, automatically pauses the strategy)
   * @notice If the new asset has a different price (USD denominated), a sudden `sharePrice()` change is expected
   * @param _asset Address of the new underlying asset
   * @param _swapData Swap calldata used to exchange the old `asset` for the new `_asset`
   * @param _priceFactor Price factor to convert the old `asset` to the new `_asset` (old asset price * 1e18) / (new asset price)
   */
  function updateAsset(
    address _asset,
    bytes calldata _swapData,
    uint256 _priceFactor
  ) external virtual onlyAdmin {
    if (_asset == address(0)) revert AddressZero();
    if (_asset == address(asset)) return;

    // check if there are pending redemptions
    // liquidate() should be called first to ensure rebasing
    if (_req.totalRedemption > 0) revert Unauthorized();

    // pre-emptively pause the strategy for manual checks
    _pause();

    // slippage is checked within Swapper >> no need to use (received, spent)
    swapper.decodeAndSwapBalance(address(asset), _asset, _swapData);

    // reset all cached accounted values as a denomination change might change the accounting basis
    _expectedProfits = 0; // reset trailing profits
    _as4626StorageExt().totalLent = 0; // reset totalLent (broken analytics)
    _collectFees(); // claim all pending fees to reset claimableAssetFees
    address swapperAddress = address(swapper);
    if (swapperAddress != address(0)) {
      IERC20Metadata(asset).forceApprove(swapperAddress, 0); // revoke swapper allowance on previous asset
      IERC20Metadata(_asset).forceApprove(swapperAddress, _MAX_UINT256);
    }
    asset = IERC20Metadata(_asset);
    _assetDecimals = asset.decimals();
    _weiPerAsset = 10 ** _assetDecimals;
    last.accountedAssets = totalAssets();
    last.accountedSupply = totalSupply();
    last.sharePrice = last.sharePrice.mulDiv(_priceFactor, 1e18); // multiply then debase
  }

  /**
   * @notice Sets the input weight of each input
   * @param _weights Array of input weights
   */
  function setInputWeights(uint16[] calldata _weights) public onlyAdmin {
    if (_weights.length != _inputLength) revert InvalidData();
    uint16 totalWeight = 0;
    for (uint8 i = 0; i < _inputLength; i++) {
      inputWeights[i] = _weights[i];

      // check for overflow before adding the weight
      if (totalWeight > AsMaths._BP_BASIS - _weights[i]) {
        revert InvalidData();
      }

      totalWeight += _weights[i];
    }
  }

  /**
   * @notice Sets the strategy inputs and weights
   * @notice In case of pre-existing inputs, a call to `liquidate()` should precede this in order to not lose track of the strategy's liquidity
   * @param _inputs Array of input addresses
   * @param _weights Array of input weights
   */
  function setInputs(
    address[] calldata _inputs,
    uint16[] calldata _weights
  ) public onlyAdmin {
    if (_inputs.length > 8) revert Unauthorized();
    setSwapperAllowance(0, true, false, false);
    for (uint256 i = 0; i < _inputs.length;) {
      inputs[i] = IERC20Metadata(_inputs[i]);
      _inputDecimals[i] = inputs[i].decimals();
      inputWeights[i] = _weights[i];
      unchecked {
        i++;
      }
    }
    setSwapperAllowance(_MAX_UINT256, true, false, false);
    _inputLength = uint8(_inputs.length);
    setInputWeights(_weights);
  }

  /**
   * @notice Sets the strategy reward tokens
   * @param _rewardTokens Array of reward tokens
   */
  function setRewardTokens(address[] calldata _rewardTokens) public onlyManager {
    if (_rewardTokens.length > 8) revert Unauthorized();
    setSwapperAllowance(0, false, true, false);
    for (uint256 i = 0; i < _rewardTokens.length;) {
      rewardTokens[i] = _rewardTokens[i];
      _rewardTokenIndexes[_rewardTokens[i]] = i + 1;
      unchecked {
        i++;
      }
    }
    _rewardLength = uint8(_rewardTokens.length);
    setSwapperAllowance(_MAX_UINT256, false, true, false);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
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
