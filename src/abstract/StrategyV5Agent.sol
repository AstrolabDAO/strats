// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../interfaces/IStrategyV5.sol";
import "../interfaces/IERC3156FlashBorrower.sol";
import "./StrategyV5Abstract.sol";
import "./AsRescuableAbstract.sol";
import "./As4626.sol";

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
contract StrategyV5Agent is StrategyV5Abstract, As4626, AsRescuableAbstract {
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
    _agentStorageExt().maxLoan = 1e12;
    As4626.init(_params.erc20Metadata, _params.coreAddresses, _params.fees);
    setSwapperAllowance(_MAX_UINT256, true, false, true); // reward allowances already set
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
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
    return _agentStorageExt().delegator.invested();
  }

  /**
   * @dev Returns the total amount lent by `flashLoan()` in the current underlying assets
   * @return The total amount lent as a uint256 value
   */
  function totalLent() external view returns (uint256) {
    return _agentStorageExt().totalLent;
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
    if (swapperAddress == address(0)) revert Errors.AddressZero();
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
    if (_swapper == address(0)) revert Errors.AddressZero();
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
    if (_asset == address(0)) revert Errors.AddressZero();
    if (_asset == address(asset)) return;

    // check if there are pending redemptions
    // liquidate() should be called first to ensure rebasing
    if (_req.totalRedemption > 0) revert Errors.Unauthorized();

    // pre-emptively pause the strategy for manual checks
    pause();

    // slippage is checked within Swapper >> no need to use (received, spent)
    swapper.decodeAndSwapBalance(address(asset), _asset, _swapData);

    // reset all cached accounted values as a denomination change might change the accounting basis
    _expectedProfits = 0; // reset trailing profits
    _agentStorageExt().totalLent = 0; // reset totalLent (broken analytics)
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
    if (_weights.length != _inputLength) revert Errors.InvalidData();
    uint16 totalWeight = 0;
    for (uint8 i = 0; i < _inputLength; i++) {
      inputWeights[i] = _weights[i];

      // check for overflow before adding the weight
      if (totalWeight > AsMaths._BP_BASIS - _weights[i]) {
        revert Errors.InvalidData();
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
    if (_inputs.length > 8) revert Errors.Unauthorized();
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
    if (_rewardTokens.length > 8) revert Errors.Unauthorized();
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

  /**
   * @return Amount of underlying assets available to non-requested withdrawals, excluding `minLiquidity`
   */
  function _available() internal view override returns (uint256) {
    return
      availableBorrowable().subMax0(convertToAssets(_req.totalClaimableRedemption, false));
  }

  /**
   * @return Amount of underlying assets available to non-requested withdrawals, excluding `minLiquidity`
   */
  function available() public view returns (uint256) {
    return _available();
  }

  /**
   * @return Total amount of underlying assets available to withdraw
   */
  function availableClaimable() public view override returns (uint256) {
    return asset.balanceOf(address(this)).subMax0(
      claimableAssetFees
        + AsAccounting.unrealizedProfits(last.harvest, _expectedProfits, _profitCooldown)
    );
  }

  /**
   * @return Amount of borrowable underlying assets available to `flashLoan()`
   */
  function availableBorrowable() internal view returns (uint256) {
    return availableClaimable();
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
        AsMaths.max(claimableRedeemRequest(_owner), convertToShares(_available(), false))
      );
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                       ERC-3156 LOANS LOGIC                     ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Sets the vault `_maxLoan` originated in underlying assets
   * @param _amount Maximum loan amount
   */
  function setMaxLoan(uint256 _amount) external onlyAdmin {
    _agentStorageExt().maxLoan = _amount;
  }

  /**
   * @notice Calculates the flash fee for a given borrower and amount (ERC-3156 extension)
   * @param _borrower Address of the borrower
   * @param _amount Amount of underlying assets lent
   * @return Amount of underlying assets to be charged for the loan, on top of the returned principal
   */
  function _flashFee(address _borrower, uint256 _amount) internal view returns (uint256) {
    return exemptionList[_borrower] ? 0 : _amount.bp(fees.flash);
  }

  /**
   * @notice Fee to be charged for a given loan (ERC-3156 extension)
   * @param _token Loan currency
   * @param _borrower Address of the borrower
   * @param _amount Amount of `_token` lent
   * @return Amount of `_token` to be charged for the loan, on top of the returned principal
   */
  function flashFee(
    address _token,
    address _borrower,
    uint256 _amount
  ) external view returns (uint256) {
    if (_token != address(asset)) {
      revert Errors.Unauthorized();
    }
    return _flashFee(_borrower, _amount);
  }

  /**
   * @notice Fee to be charged for a given loan (ERC-3156 polyfill)
   * @notice Use `flashFee(address _token, address _borrower, uint256 _amount)` to specify a different `_borrower`
   * @param _token Loan currency
   * @param _amount Amount of `_token` lent
   * @return Amount of `_token` to be charged for the loan, on top of the returned principal
   */
  function flashFee(address _token, uint256 _amount) external view returns (uint256) {
    if (_token != address(asset)) {
      revert Errors.Unauthorized();
    }
    return _flashFee(msg.sender, _amount);
  }

  /**
   * @notice Amount of underlying assets available to be lent (ERC-3156 polyfill)
   * @param _token Loan currency
   * @return Amount of `_token` that can currently be borrowed through `flashLoan`
   */
  function maxFlashLoan(address _token) external view returns (uint256) {
    return address(asset) == _token ? AsMaths.min(availableBorrowable(), _agentStorageExt().maxLoan) : 0;
  }

  /**
   * @notice Lends `_amount` of underlying assets to `_receiver` contract while executing `_dataparams` (ERC-3156 extension)
   * @param _receiver Borrower executing the flash loan, must be a contract implementing `ISimpleLoanReceiver` and not an EOA
   * @param _amount Amount of underlying assets to lend
   * @param _data Callback data to be passed to `_receiver.executeOperation(_data)` function
   */
  function _flashLoan(
    address _receiver,
    uint256 _amount,
    bytes calldata _data
  ) internal nonReentrant whenNotPaused {
    address token = address(asset); // Assuming 'asset' is your ERC20 Address of the token

    AgentStorageExt storage $ = _agentStorageExt();

    if (_amount > availableBorrowable() || _amount > $.maxLoan) {
      revert Errors.AmountTooHigh(_amount);
    }

    uint256 fee = _flashFee(_receiver, _amount);
    uint256 balanceBefore = asset.balanceOf(address(this));

    $.totalLent += _amount;

    // Transfer the tokens to the receiver
    asset.safeTransfer(_receiver, _amount);

    // Callback to the receiver's onFlashLoan method
    require(
      IERC3156FlashBorrower(_receiver).onFlashLoan(msg.sender, token, _amount, fee, _data)
        == _FLASH_LOAN_SIG
    ); // callback failure

    // Verify the repayment and fee
    uint256 balanceAfter = asset.balanceOf(address(this));
    if (balanceAfter < balanceBefore + fee) {
      revert Errors.FlashLoanDefault(_receiver, _amount);
    }

    emit FlashLoan(msg.sender, _amount, fee);
  }

  /**
   * @notice Lends `_amount` of underlying assets to `_receiver` contract while executing `_dataparams` (ERC-3156 polyfill)
   * @param _receiver Borrower executing the flash loan, must be a contract implementing `ISimpleLoanReceiver` and not an EOA
   * @param _token Loan currency
   * @param _amount Amount of `_token` lent
   * @param _data Callback data to be passed to `_receiver.executeOperation(_data)` function
   */
  function flashLoan(
    address _receiver,
    address _token,
    uint256 _amount,
    bytes calldata _data
  ) external returns (bool) {
    if (_token != address(asset)) {
      revert Errors.Unauthorized();
    }
    _flashLoan(_receiver, _amount, _data);
    return true;
  }
}
