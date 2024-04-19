// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../interfaces/IWETH9.sol";
import "./StrategyV5Abstract.sol";
import "./As4626.sol";
import "./AsFlashLender.sol";

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
contract StrategyV5Agent is StrategyV5Abstract, As4626, AsFlashLender {
  using AsMaths for uint256;
  using AsMaths for int256;
  using SafeERC20 for IERC20Metadata;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) StrategyV5Abstract(_accessController) {}

  /**
   * @notice Initializes the strategy with base `_params`
   * @param _params Strategy parameters (Erc20Metadata, CoreAddresses, Fees, inputs, inputWeights, rewardTokens)
   */
  function init(StrategyParams calldata _params) external onlyAdmin {
    As4626._init(_params.erc20Metadata, _params.coreAddresses, _params.fees); // super().init()
    _wgas = IWETH9(_params.coreAddresses.wgas);
    if (_params.coreAddresses.swapper != address(0)) {
      swapper = ISwapper(_params.coreAddresses.swapper);
    }
    // set inputs, rewardTokens and grant swapper allowances
    IERC20Metadata(asset).forceApprove(address(swapper), AsMaths.MAX_UINT256);
    _setInputs(_params.inputs, _params.inputWeights, _params.lpTokens);
    _setRewardTokens(_params.rewardTokens);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return Proxy type (ERC-897: 1 == forwarder, 2 == upgradable)
   */
  function proxyType() external pure returns (uint256) {
    return 2;
  }

  /**
   * @return Total amount of invested inputs denominated in underlying assets
   */
  function _invested() internal view override returns (uint256) {
    return _agentStorage().delegator.invested();
  }

  /**
   * @notice Calculates the flash fee for a given borrower and amount (ERC-3156 extension)
   * @param _borrower Address of the borrower
   * @param _amount Amount of underlying assets lent
   * @return Amount of underlying assets to be charged for the loan, on top of the returned principal
   */
  function _flashFee(
    address _borrower,
    uint256 _amount
  ) internal view override returns (uint256) {
    return exemptionList[_borrower] ? 0 : _amount.bp(fees.flash);
  }

  /**
   * @notice Checks if the specified asset is lendable
   * @param _asset Address of the asset to check
   * @return Boolean indicating whether `_asset` is lendable or not
   */
  function isLendable(address _asset) public view override returns (bool) {
    return _asset == address(asset);
  }

  /**
   * @return Amount of borrowable underlying assets available to `flashLoan()`
   */
  function borrowable() public view override returns (uint256) {
    return availableClaimable();
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
  function _setSwapperAllowance(
    uint256 _amount,
    bool _inputs,
    bool _rewards,
    bool _asset
  ) internal {
    address swapperAddress = address(swapper);
    if (swapperAddress == address(0)) revert Errors.AddressZero();
    // we keep the possibility to set allowance to 0 in case of a change of swapper
    // default is to approve AsMaths.MAX_UINT256
    _amount = _amount > 0 ? _amount : AsMaths.MAX_UINT256;

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
  ) external onlyAdmin {
    _setSwapperAllowance(_amount, _inputs, _rewards, _asset);
  }

  /**
   * @notice Updates the strategy's swapper, revokes allowances to the previous and grants it to the new one
   * @param _swapper Address of the new swapper
   */
  function updateSwapper(address _swapper) public onlyAdmin {
    if (_swapper == address(0)) revert Errors.AddressZero();
    _setSwapperAllowance(0, true, true, true);
    swapper = ISwapper(_swapper);
    _setSwapperAllowance(AsMaths.MAX_UINT256, true, true, true);
  }

  /**
   * @notice Updates the strategy's underlying asset (critical, automatically pauses the strategy)
   * @notice If the new asset has a different price (USD denominated), a sudden `sharePrice()` change is expected
   * @param _asset Address of the new underlying asset
   * @param _swapData Swap calldata used to exchange the old `asset` for the new `_asset`
   * @param _exchangeRateBp Price factor to convert the old `asset` to the new `_asset` (old asset price * 1e18) / (new asset price)
   */
  function updateAsset(
    address _asset,
    bytes calldata _swapData,
    uint256 _exchangeRateBp
  ) external nonReentrant onlyAdmin {
    _updateAsset(_asset, _swapData, _exchangeRateBp);
  }

  /**
   * @notice Updates the strategy's underlying asset (critical, automatically pauses the strategy)
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
    if (_asset == address(0)) revert Errors.AddressZero();
    if (_asset == address(asset)) return;

    if (_exchangeRateBp == 0) {
      revert Errors.InvalidData();
    }

    // check if there are pending redemptions
    // liquidate() should be called first to ensure rebasing
    if (_req.totalRedemption > 0) revert Errors.Unauthorized();

    // reset all cached accounted values as a denomination change might change the accounting basis
    _expectedProfits = 0; // reset trailing profits
    _lenderStorage().totalLent = 0; // reset totalLent (broken analytics)
    _collectFees(); // claim all pending fees to reset claimableTransactionFees

    address swapperAddress = address(swapper);
    if (swapperAddress == address(0)) {
      // a swapper is required to swap from the old asset to the new one
      revert Errors.Unauthorized();
    }

    // slippage is checked within Swapper >> no need to use (received, spent)
    swapper.decodeAndSwapBalance(address(asset), _asset, _swapData);
    IERC20Metadata(asset).forceApprove(swapperAddress, 0); // revoke swapper allowance on previous asset
    IERC20Metadata(_asset).forceApprove(swapperAddress, AsMaths.MAX_UINT256);
    asset = IERC20Metadata(_asset);
    _assetDecimals = asset.decimals();
    _weiPerAsset = 10 ** _assetDecimals;
    last.accountedAssets = totalAssets();
    last.accountedSupply = totalSupply();
    last.sharePrice =
      last.sharePrice.mulDiv(_exchangeRateBp, AsMaths.BP_BASIS * _weiPerAsset); // multiply then debase
    // pre-emptively pause the strategy for manual checks
    _pause();
  }

  /**
   * @notice Sets the input weight of each input if any
   * @param _weights Array of input weights
   */
  function _setInputWeights(uint16[] calldata _weights) internal {
    if (_weights.length != _inputLength) {
      revert Errors.InvalidData();
    }
    _totalWeight = 0;
    delete inputWeights;

    for (uint256 i = 0; i < _inputLength;) {
      inputWeights[i] = _weights[i];

      // check for overflow before adding the weight
      if (_totalWeight > AsMaths.BP_BASIS - _weights[i]) {
        revert Errors.InvalidData();
      }
      _totalWeight += _weights[i];
      unchecked {
        i++;
      }
    }
  }

  /**
   * @notice Sets the input weight of each input if any
   * @param _weights Array of input weights
   */
  function setInputWeights(uint16[] calldata _weights) external onlyAdmin {
    _setInputWeights(_weights);
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
    if (
      _inputs.length > _MAX_INPUTS || _inputs.length != _weights.length
        || _lpTokens.length != _inputs.length
    ) {
      revert Errors.Unauthorized();
    }
    _setSwapperAllowance(0, true, false, false);
    _inputLength = uint8(_inputs.length); // new used length

    delete inputs;
    delete _inputDecimals;
    delete lpTokens;
    delete _lpTokenDecimals;

    for (uint256 i = 0; i < _inputLength;) {
      inputs[i] = IERC20Metadata(_inputs[i]);
      _inputDecimals[i] = inputs[i].decimals();
      lpTokens[i] = IERC20Metadata(_lpTokens[i]);
      _lpTokenDecimals[i] = lpTokens[i].decimals();
      unchecked {
        i++;
      }
    }
    _setSwapperAllowance(AsMaths.MAX_UINT256, true, false, false);
    _setInputWeights(_weights);
  }

  /**
   * @notice Sets the strategy inputs and weights if any
   * @notice In case of pre-existing inputs, a call to `liquidate()` should precede this in order to not lose track of the strategy's liquidity
   * @param _inputs Array of input addresses
   * @param _weights Array of input weights
   * @param _lpTokens Array of LP tokens
   */
  function setInputs(
    address[] calldata _inputs,
    uint16[] calldata _weights,
    address[] calldata _lpTokens
  ) external onlyAdmin {
    _setInputs(_inputs, _weights, _lpTokens);
  }

  /**
   * @notice Sets the strategy reward tokens if any
   * @param _rewardTokens Array of reward tokens
   */
  function _setRewardTokens(address[] calldata _rewardTokens) internal {
    if (_rewardTokens.length > _MAX_INPUTS) {
      revert Errors.Unauthorized();
    }
    _setSwapperAllowance(0, false, true, false);
    delete rewardTokens;
    for (uint256 i = 0; i < _rewardTokens.length;) {
      rewardTokens[i] = _rewardTokens[i];
      _rewardTokenIndexes[_rewardTokens[i]] = i + 1;
      unchecked {
        i++;
      }
    }
    _rewardLength = uint8(_rewardTokens.length);
    _setSwapperAllowance(AsMaths.MAX_UINT256, false, true, false);
  }

  /**
   * @notice Sets the strategy reward tokens if any
   * @param _rewardTokens Array of reward tokens
   */
  function setRewardTokens(address[] calldata _rewardTokens) external onlyManager {
    _setRewardTokens(_rewardTokens);
  }

  /**
   * @return Amount of underlying assets available to non-requested withdrawals, excluding `minLiquidity`
   */
  function available() public view override returns (uint256) {
    return
      availableClaimable().subMax0(_convertToAssets(_req.totalClaimableRedemption, false));
  }

  /**
   * @return Total amount of underlying assets available to withdraw
   */
  function availableClaimable() public view override returns (uint256) {
    return asset.balanceOf(address(this)).subMax0(
      claimableTransactionFees // entry + exit fees
        + _lenderStorage().claimableFlashFees // flash loan fees
        + AsAccounting.unrealizedProfits(last.harvest, _expectedProfits, _profitCooldown)
    );
  }

  /**
   * @return Total assets denominated in underlying, including claimable redemptions
   */
  function totalAssets() public view virtual override returns (uint256) {
    return availableClaimable() + _invested();
  }

  /**
   * @param _owner Owner of the shares to be redeemed
   * @return Maximum amount of shares that can currently be redeemed by `_owner`
   */
  function maxRedeem(address _owner) public view override returns (uint256) {
    return paused()
      ? 0
      : AsMaths.min(
        balanceOf(msg.sender),
        AsMaths.max(claimableRedeemRequest(_owner), _convertToShares(available(), false))
      );
  }

  /**
   * @notice Triggers a fee collection - Claims all fees by minting the equivalent `toMint` shares to `feeCollector`
   * @return toMint Amount of shares minted to the feeCollector
   */
  function _collectFees() internal override returns (uint256 toMint) {
    if (feeCollector == address(0)) {
      revert Errors.AddressZero();
    }

    (uint256 assets, uint256 price, uint256 profit, uint256 dynamicFees) =
      AsAccounting.claimableDynamicFees(IStrategyV5(address(this)));

    // sum up all fees: dynamicFees (perf+mgmt) + claimableTransactionFees (entry+exit) + flash loan fees
    uint256 totalFees =
      dynamicFees + claimableTransactionFees + _lenderStorage().claimableFlashFees;
    uint256 inflationBps = dynamicFees.mulDiv(AsMaths.BP_BASIS, assets); // claimable entry+exit+flash fees are not inflationary as subtracted from available()
    toMint = totalFees.mulDiv(_WEI_PER_SHARE_SQUARED, price * _weiPerAsset);

    // do not mint nor emit event if there are no fees to collect
    if (toMint == 0) {
      return 0;
    }

    _mint(feeCollector, toMint);

    // re-calculate the sharePrice dynamically to avoid sharePrice() distortion
    last.sharePrice = price.mulDiv(AsMaths.BP_BASIS, AsMaths.BP_BASIS + inflationBps);
    last.feeCollection = uint64(block.timestamp);
    last.accountedAssets = assets;
    last.accountedSharePrice = last.sharePrice;
    last.accountedProfit = profit;
    last.accountedSupply = totalSupply();
    claimableTransactionFees = 0; // reset entry + exit fees
    _lenderStorage().claimableFlashFees = 0; // reset flash loan fees

    emit FeeCollection(
      feeCollector,
      assets,
      last.sharePrice,
      profit, // basis AsMaths.BP_BASIS**2
      totalFees,
      toMint
    );
  }
}
