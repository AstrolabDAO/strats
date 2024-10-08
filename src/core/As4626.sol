// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/IERC7540RedeemReceiver.sol";
import "./As4626Abstract.sol";
import "./ERC20.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title As4626 - Astrolab's ERC-4626+ERC-7540 base tokenized vault
 * @author Astrolab DAO
 * @notice Common vault/strategy back-end extended by StrategyV5Agent, delegated to by StrategyV5 implementations
 * @dev All state variables must be in As4626Abstract to match the proxy base storage layout (StrategyV5)
 */
abstract contract As4626 is ERC20, As4626Abstract {
  using AsMaths for uint256;
  using AsMaths for int256;
  using SafeERC20 for IERC20Metadata;

  /*═══════════════════════════════════════════════════════════════╗
  ║                             EVENTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  event FeeCollection(
    address indexed collector,
    uint256 totalAssets,
    uint256 sharePrice,
    uint256 profit,
    uint256 totalFees,
    uint256 sharesMinted
  );

  receive() external payable {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor() {}

  /**
   * @notice Initializes the vault with the provided `_erc20Metadata`, `_coreAddresses`, and `_fees`
   * @notice This is the end of the initialization call flow, started by `implementation.init()`
   * @param _erc20Metadata ERC20 metadata [name,symbol,decimals]
   * @param _coreAddresses Vault ops addreses [wgas,asset,feeCollector,swapper,agent]
   * @param _fees Fees structure [perf,mgmt,entry,exit,flash]
   */
  function _init(
    Erc20Metadata memory _erc20Metadata,
    CoreAddresses memory _coreAddresses,
    Fees memory _fees
  ) internal {
    if (_initialized) {
      revert Errors.InvalidInitStatus();
    }
    ERC20._init(_erc20Metadata.name, _erc20Metadata.symbol, _erc20Metadata.decimals); // super().init()
    asset = IERC20Metadata(_coreAddresses.asset);
    _assetDecimals = asset.decimals();
    _weiPerAsset = 10 ** _assetDecimals;

    // check that the fees are not too high
    setFees(_fees);
    _4626StorageExt().maxSlippageBps = 200; // 2% max internal swap slippage
    feeCollector = _coreAddresses.feeCollector;
    _req.redemptionLocktime = 6 hours;
    last.accountedSharePrice = _WEI_PER_SHARE;
    last.accountedProfit = _WEI_PER_SHARE;
    last.feeCollection = uint64(block.timestamp);
    last.liquidate = uint64(block.timestamp);
    last.harvest = uint64(block.timestamp);
    last.invest = uint64(block.timestamp);
  }

  /**
   * @notice Seeds the vault liquidity by setting its `maxTotalAssets` and depositing `_seedDeposit` into it
   * @notice This function should be called after `init()` to enable vault deposits
   * @param _seedDeposit Amount of assets to seed the vault with
   * @param _maxTotalAssets Maximum amount of assets that can be deposited
   */
  function seedLiquidity(
    uint256 _seedDeposit,
    uint256 _maxTotalAssets
  ) external onlyAdmin {
    // 1e12 is the minimum amount of assets required to seed the vault (1 USDC or .1Gwei ETH)
    // allowance should be given to the vault before calling this function
    if (_seedDeposit < minLiquidity.subMax0(totalAssets())) {
      revert Errors.AmountTooLow(_seedDeposit);
    }

    // seed the vault with some assets if it's empty
    _setMaxTotalAssets(_maxTotalAssets);

    // if the vault is still paused, unpause it
    if (paused()) {
      unpause();
    }
    deposit(_seedDeposit, msg.sender);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return Amount of underlying assets available to non-requested withdrawals, excluding `minLiquidity`
   */
  function available() public view virtual returns (uint256);

  /**
   * @return Total amount of underlying assets available to withdraw
   */
  function availableClaimable() public view virtual returns (uint256);

  /**
   * @return Sums all pending redemption requests
   */
  function totalRedemptionRequest() external view returns (uint256) {
    return _req.totalRedemption;
  }

  /**
   * @return Sums all claimable redemption requests
   */
  function totalClaimableRedemption() external view returns (uint256) {
    return _req.totalClaimableRedemption;
  }

  /**
   * @notice Gets the total redemption request for a specific `_owner` (ERC-7540)
   * @param _owner Owner of the shares to be redeemed
   * @return Amount of shares pending redemption
   */
  function pendingRedeemRequest(address _owner) external view returns (uint256) {
    return _req.byOwner[_owner].totalRedemption;
  }

  /**
   * @notice Gets the redemption request for a specific `_owner` and `_receiver` pair (ERC-7540 extension)
   * @param _receiver Receiver of the shares to be redeemed
   * @param _owner Owner of the shares to be redeemed
   * @return Amount of shares pending redemption
   */
  function pendingRedeemRequest(
    address _receiver,
    address _owner
  ) external view returns (uint256) {
    return _req.byOwner[_owner].redemptionByReceiver[_receiver].amount;
  }

  /**
   * @notice Gets the redemption request for a specific `_owner` and `_receiver` pair in underlying assets (ERC-7540 extension)
   * @param _receiver Receiver of the shares to be redeemed
   * @param _owner Owner of the shares to be redeemed
   * @return Amount of underlying assets equivalent to the pending redemption request shares
   */
  function pendingWithdrawRequest(
    address _receiver,
    address _owner
  ) external view returns (uint256) {
    Erc7540Request storage request = _req.byOwner[_owner].redemptionByReceiver[_receiver];
    return
      request.amount.mulDiv(AsMaths.min(request.sharePrice, sharePrice()), _WEI_PER_SHARE); // worst of
  }

  /**
   * @notice Gets the claimability of a redemption request
   * @param requestTimestamp Timestamp of the redemption request
   * @return True if the redemption request is claimable
   */
  function isRequestClaimable(uint256 requestTimestamp) public view returns (bool) {
    return block.timestamp
      >= AsMaths.min(requestTimestamp + _req.redemptionLocktime, last.liquidate);
  }

  /**
   * @return Maximum claimable redemption amount
   */
  function maxClaimableAsset() internal view returns (uint256) {
    return
      AsMaths.min(_convertToAssets(_req.totalRedemption, false), availableClaimable());
  }

  /**
   * @notice Gets the total claimable shares for `_owner` redeemable by `_receiver` (ERC-7540 extension)
   * @param _receiver Receiver of the underlying assets
   * @param _owner Owner of the shares to be redeemed
   * @return Owner's claimable shares for redemption
   */
  function claimableRedeemRequest(
    address _receiver,
    address _owner
  ) public view returns (uint256) {
    Erc7540Request storage request = _req.byOwner[_owner].redemptionByReceiver[_receiver];
    return isRequestClaimable(request.timestamp)
      ? AsMaths.min(request.amount, _req.totalClaimableRedemption)
      : 0;
  }

  /**
   * @notice Gets the total self redeemable claimable shares for `_owner` (ERC-7540 polyfill)
   * @param _owner Owner and receiver of the shares to be redeemed (ERC-7540 polyfill)
   * @return Owner's claimable shares for redemption
   */
  function claimableRedeemRequest(address _owner) public view returns (uint256) {
    return claimableRedeemRequest(_owner, _owner);
  }

  /**
   * @notice Previews the amount of underlying assets that has to be deposited to mint `_shares` to `_receiver` (ERC-4626 extension)
   * @param _shares Amount of shares to mint
   * @param _receiver Receiver of the shares
   * @return shares Amount of underlying assets to be deposited
   */
  function previewMint(uint256 _shares, address _receiver) public view returns (uint256) {
    return
      _convertToAssets(_shares.revAddBp(exemptionList[_receiver] ? 0 : fees.entry), true);
  }

  /**
   * @notice Previews the amount of underlying that has to be deposited to mint `_shares` to `msg.sender` (ERC-4626)
   * @dev Use `previewMint(uint256 _shares, address _receiver)` to specify a different `_receiver`
   * @param _shares Amount of shares to mint
   * @return shares Amount of underlying assets to be deposited
   */
  function previewMint(uint256 _shares) external view returns (uint256) {
    return previewMint(_shares, msg.sender);
  }

  /**
   * @notice Previews the amount of shares that will be minted to `_receiver` for `_amount` of underlying assets (ERC-4626 extension)
   * @param _amount Amount of underlying assets to deposit
   * @param _receiver Receiver of the shares
   * @return Amount of shares to be minted
   */
  function previewDeposit(
    uint256 _amount,
    address _receiver
  ) public view returns (uint256) {
    return
      _convertToShares(_amount.subBp(exemptionList[_receiver] ? 0 : fees.entry), false);
  }

  /**
   * @notice Previews the amount of shares that will be minted to `msg.sender` for `_amount` of underlying assets (ERC-4626)
   * @dev Use `previewDeposit(uint256 _amount, address _receiver)` to specify a different `_receiver`
   * @param _amount Amount of underlying assets to deposit
   * @return shares Amount of shares to be minted
   */
  function previewDeposit(uint256 _amount) external view returns (uint256) {
    return previewDeposit(_amount, msg.sender);
  }

  /**
   * @notice Previews the amount of shares that `_owner` has to burn to withdraw an underlying `_amount` equivalent (ERC-4626 extension)
   * @param _amount Amount of underlying assets to withdraw
   * @param _owner Owner of the shares to be redeemed
   * @return Amount of shares to be burnt
   */
  function previewWithdraw(uint256 _amount, address _owner) public view returns (uint256) {
    return _convertToShares(_amount.revAddBp(exemptionList[_owner] ? 0 : fees.exit), true);
  }

  /**
   * @notice Previews the amount of shares that `msg.sender` has to burn to withdraw an underlying `_amount` equivalent (ERC-4626)
   * @notice Use `previewWithdraw(uint256 _amount, address _owner)` to specify a different `_owner`
   * @param _amount Amount of underlying assets to withdraw
   * @return Amount of shares to be burnt
   */
  function previewWithdraw(uint256 _amount) external view returns (uint256) {
    return previewWithdraw(_amount, address(0));
  }

  /**
   * @notice Previews the amount of underlying assets that `_owner` would receive for burning `_shares` (ERC-4626)
   * @param _shares Amount of shares to redeem
   * @param _owner Owner of the shares to be redeemed
   * @return Amount of underlying assets received
   */
  function previewRedeem(uint256 _shares, address _owner) public view returns (uint256) {
    return _convertToAssets(_shares.subBp(exemptionList[_owner] ? 0 : fees.exit), false);
  }

  /**
   * @notice Previews the amount of underlying assets that `msg.sender` would receive for burning `_shares` (ERC-4626)
   * @notice Use `previewRedeem(uint256 _shares, address _owner)` to specify a different `_owner`
   * @param _shares Amount of shares to redeem
   * @return Amount of underlying assets received
   */
  function previewRedeem(uint256 _shares) external view returns (uint256) {
    return previewRedeem(_shares, address(0));
  }

  /**
   * @return Maximum amount of underlying assets that can be deposited in the vault based on `maxTotalAssets`
   */
  function maxDeposit(address) public view returns (uint256) {
    return paused() ? 0 : maxTotalAssets.subMax0(totalAssets());
  }

  /**
   * @return Maximum amount of shares that can be minted based on `maxDeposit()`
   */
  function maxMint(address) public view returns (uint256) {
    return paused() ? 0 : _convertToShares(maxDeposit(address(0)), false);
  }

  /**
   * @param _owner Owner of the shares to be redeemed
   * @return Maximum amount of underlying assets that can currently be withdrawn by `_owner`
   */
  function maxWithdraw(address _owner) public view returns (uint256) {
    return paused() ? 0 : _convertToAssets(maxRedeem(_owner), false);
  }

  /**
   * @param _owner Owner of the shares to be redeemed
   * @return Maximum amount of shares that can currently be redeemed by `_owner`
   */
  function maxRedeem(address _owner) public view virtual returns (uint256);

  /*═══════════════════════════════════════════════════════════════╗
  ║                     ERC4626 DERIVED VIEWS                      ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return Total assets denominated in underlying, including claimable redemptions
   */
  function totalAssets() public view virtual returns (uint256);

  /**
   * @return Total assets denominated in underlying, excluding claimable redemptions (used to calculate `sharePrice()`)
   */
  function totalAccountedAssets() public view returns (uint256) {
    return totalAssets().subMax0(
      _req.totalClaimableRedemption.mulDiv(
        last.sharePrice * _weiPerAsset, _WEI_PER_SHARE_SQUARED
      )
    ); // eg. (1e12*1e12*1e6)/(1e12*1e12) = 1e6
  }

  /**
   * @return Total amount of shares outstanding, excluding claimable redemptions (used to calculate `sharePrice()`)
   */
  function totalAccountedSupply() public view returns (uint256) {
    return totalSupply().subMax0(_req.totalClaimableRedemption);
  }

  /**
   * @return Share price - Amount of underlying assets redeemable for one share
   */
  function sharePrice() public view returns (uint256) {
    uint256 supply = totalAccountedSupply();
    return supply == 0
      ? _WEI_PER_SHARE
      : totalAccountedAssets().mulDiv( // eg. e6
        _WEI_PER_SHARE_SQUARED, // 1e12*2
        supply * _weiPerAsset
      ); // eg. (1e6*1e12*1e12)/(1e12*1e6)
  }

  /**
   * @param _owner Owner of the shares
   * @return Value of the owner's shares denominated in underlying assets
   */
  function assetsOf(address _owner) public view returns (uint256) {
    return _convertToAssets(balanceOf(_owner), false);
  }

  /**
   * @notice Converts `_amount` of underlying assets to shares at the current share price
   * @param _amount Amount of underlying assets to convert
   * @param _roundUp Round up if true, round down otherwise
   * @return Amount of shares equivalent to `_amount` assets
   */
  function _convertToShares(
    uint256 _amount,
    bool _roundUp
  ) internal view virtual returns (uint256) {
    return _amount.mulDiv(
      _WEI_PER_SHARE_SQUARED,
      sharePrice() * _weiPerAsset,
      _roundUp ? AsMaths.Rounding.Ceil : AsMaths.Rounding.Floor
    ); // eg. 1e6*(1e12*1e12)/(1e12*1e6) = 1e12
  }

  /**
   * @notice Converts `_amount` of underlying assets to shares at the current share price
   * @param _amount Amount of assets to convert
   * @return Amount of shares equivalent to `_amount` assets
   */
  function convertToShares(uint256 _amount) external view returns (uint256) {
    return _convertToShares(_amount, false);
  }

  function convertToShares(
    uint256 _amount,
    bool _roundUp
  ) external view returns (uint256) {
    return _convertToShares(_amount, _roundUp);
  }

  /**
   * @notice Converts `_shares` to underlying assets at the current share price
   * @param _shares Amount of shares to convert
   * @param _roundUp Round up if true, round down otherwise
   * @return Amount of assets equivalent to `_shares`
   */
  function _convertToAssets(
    uint256 _shares,
    bool _roundUp
  ) internal view returns (uint256) {
    return _shares.mulDiv(
      sharePrice() * _weiPerAsset,
      _WEI_PER_SHARE_SQUARED,
      _roundUp ? AsMaths.Rounding.Ceil : AsMaths.Rounding.Floor
    ); // eg. 1e12*(1e12*1e6)/(1e12*1e12) = 1e6
  }

  /**
   * @notice Converts `_shares` to underlying assets at the current share price
   * @param _shares Amount of shares to convert
   * @return Amount of assets equivalent to `_shares`
   */
  function convertToAssets(uint256 _shares) external view returns (uint256) {
    return _convertToAssets(_shares, false);
  }

  function convertToAssets(
    uint256 _shares,
    bool _roundUp
  ) external view returns (uint256) {
    return _convertToAssets(_shares, _roundUp);
  }

  /**
   * @notice Calculates the total pending redemption requests in shares
   * @dev Returns the difference between _req.totalRedemption and _req.totalClaimableRedemption
   * @return The total amount of pending redemption requests
   */
  function totalPendingRedemptionRequest() public view returns (uint256) {
    return _req.totalRedemption.subMax0(_req.totalClaimableRedemption);
  }

  /**
   * @notice Calculates the total pending asset requests based on redemption requests
   * @dev Converts the total pending redemption requests to their asset asset value for precision
   * @return The total amount of asset assets requested pending redemption
   */
  function totalPendingWithdrawRequest() public view returns (uint256) {
    return _convertToAssets(totalPendingRedemptionRequest(), false);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            SETTERS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Sets the fee collector (recipient of the collected fees)
   * @param _feeCollector Collector of the fees
   */
  function setFeeCollector(address _feeCollector) external onlyAdmin {
    if (_feeCollector == address(0)) {
      revert Errors.AddressZero();
    }
    feeCollector = _feeCollector;
  }

  /**
   * @notice Sets the vault `_4626StorageExt().maxSlippageBps` (internal swap slippage)
   * @param _bps Slippage in basis points (100 = 1%)
   */
  function setMaxSlippageBps(uint16 _bps) external onlyAdmin {
    _4626StorageExt().maxSlippageBps = _bps;
  }

  /**
   * @notice Sets the maximum amount of assets that can be deposited
   * @notice This is used to cap the vault's deposits
   * @param _maxTotalAssets Maximum amount of assets
   */
  function _setMaxTotalAssets(uint256 _maxTotalAssets) internal {
    maxTotalAssets = _maxTotalAssets;
  }

  /**
   * @notice Sets the maximum amount of assets that can be deposited
   * @notice This is used to cap the vault's deposits
   * @param _maxTotalAssets Maximum amount of assets
   */
  function setMaxTotalAssets(uint256 _maxTotalAssets) external onlyAdmin {
    _setMaxTotalAssets(_maxTotalAssets);
  }

  /**
   * @notice Sets the vault `fees`
   * @param _fees Fees structure [perf,mgmt,entry,exit,flash]
   */
  function setFees(Fees memory _fees) public onlyAdmin {
    if (!AsAccounting.checkFees(_fees)) {
      revert Errors.Unauthorized();
    }
    fees = _fees;
  }

  /**
   * @notice Sets the minimum `_amount` of assets to keep the vault running
   * @notice This minimum liquidity helps prevent `sharePrice` manipulation when liquidity is low
   * @param _amount Minimum amount of assets to seed the vault
   */
  function setMinLiquidity(uint256 _amount) external onlyAdmin {
    minLiquidity = _amount;
  }

  /**
   * @notice Sets the `_cooldown` period for realizing profits
   * @notice This profit linearization helps prevent arbitrage/MEV related to `sharePrice` front-running
   * @param _cooldown Cooldown period for realizing profits
   */
  function setProfitCooldown(uint256 _cooldown) external onlyAdmin {
    _profitCooldown = _cooldown;
  }

  /**
   * @notice Sets the redemption request `_locktime`
   * @notice This locktime helps prevent liquidity arbitrage and front-running
   * @param _locktime Redemption request locktime
   */
  function setRedemptionRequestLocktime(uint256 _locktime) external onlyAdmin {
    _req.redemptionLocktime = _locktime;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                        ERC20 OVERRIDES                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  function _ensureTransferable(address _payer, uint256 _amount) internal view {
    OwnerRequests storage request = _req.byOwner[_payer];
    if (_amount > balanceOf(_payer).subMax0(request.totalRedemption)) {
      revert Errors.AmountTooHigh(_amount);
    }
  }

  /**
   * @dev Transfers `_amount` of shares from `msg.sender` to `_receiver`
   * @param _receiver Receiver of the shares
   * @param _amount Amount of shares to transfer
   * @return Boolean indicating whether the transfer was successful or not
   */
  function transfer(
    address _receiver,
    uint256 _amount
  ) public override(ERC20) returns (bool) {
    _ensureTransferable(msg.sender, _amount);
    return ERC20.transfer(_receiver, _amount);
  }

  /**
   * @dev Transfers `_amount` tokens from `_owner` to `_receiver`
   * @param _owner Owner of the shares
   * @param _receiver Receiver of the shares
   * @param _amount Amount of shares to transfer
   * @return Boolean indicating whether the transfer was successful or not
   */
  function transferFrom(
    address _owner,
    address _receiver,
    uint256 _amount
  ) public override(ERC20) returns (bool) {
    _ensureTransferable(_owner, _amount);
    return ERC20.transferFrom(_owner, _receiver, _amount);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                      ERC-4626 SYNC LOGIC                       ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Mints shares to `_receiver` by depositing `_amount` of underlying assets
   * @param _amount Amount of underlying assets to deposit OR
   * @param _shares Amount of shares to mint
   * @param _receiver Receiver of the shares
   * @param _owner Owner of the assets to be deposited (usually `msg.sender`)
   * @return shares Amount of shares minted
   */
  function _deposit(
    uint256 _amount,
    uint256 _shares,
    address _receiver,
    address _owner
  ) internal nonReentrant whenNotPaused returns (uint256) {
    if (_receiver == address(this)) {
      revert Errors.Unauthorized();
    }

    if (_shares == 0 && _amount == 0) {
      revert Errors.AmountTooLow(0);
    }

    // do not allow minting at a price higher than the current share price
    last.sharePrice = sharePrice();

    bool minting = false;

    if (_amount == 0) {
      _amount = _shares.mulDiv(last.sharePrice * _weiPerAsset, _WEI_PER_SHARE_SQUARED);
      minting = true;
    }

    if (_amount > maxDeposit(address(0))) {
      revert Errors.AmountTooHigh(_amount);
    }

    // use balances to support tax-enabled ERC20s
    uint256 balanceBefore = asset.balanceOf(address(this));
    asset.safeTransferFrom(_owner, address(this), _amount);

    // reuse the vaulAssets variable to save gas
    uint256 received = asset.balanceOf(address(this)).subMax0(balanceBefore);

    uint256 assetFees = received.bp(exemptionList[_receiver] ? 0 : fees.entry);
    unchecked {
      claimableTransactionFees += assetFees; // safe
    }
    // compute the final shares (after fees and ERC20 tax)
    _shares = (received - assetFees).mulDiv(
      _WEI_PER_SHARE_SQUARED, last.sharePrice * _weiPerAsset
    ); // rounded down

    _mint(_receiver, _shares);

    emit Deposit(_owner, _receiver, _amount, _shares);
    return minting ? _amount : _shares; // minted shares if `deposit()` was called, the deposited amount if `mint()` was called
  }

  /**
   * @notice Mints `_shares` to `_receiver` by depositing equivalent underlying assets (ERC-4626)
   * @param _shares Amount of shares to be minted to `_receiver`
   * @param _receiver Receiver of the shares
   * @return Amount of assets deposited
   */
  function mint(uint256 _shares, address _receiver) public returns (uint256) {
    return _deposit(0, _shares, _receiver, msg.sender);
  }

  /**
   * @notice Mints shares to `_receiver` by depositing `_amount` of underlying assets (ERC-4626)
   * @notice Use `safeDeposit` for slippage control
   * @param _amount Amount of underlying assets to deposit
   * @param _receiver Receiver of the shares
   * @return shares Amount of shares minted
   */
  function deposit(uint256 _amount, address _receiver) public returns (uint256 shares) {
    return _deposit(_amount, 0, _receiver, msg.sender);
  }

  /**
   * @notice Mints `_shares` to `_receiver` by depositing equivalent underlying assets (ERC-7540)
   * @param _shares Amount of shares to be minted to `_receiver`
   * @param _receiver Receiver of the shares
   * @param _owner Owner of the assets to be deposited (usually `msg.sender`)
   * @return Amount of assets deposited
   */
  function mint(
    uint256 _shares,
    address _receiver,
    address _owner
  ) public returns (uint256) {
    return _deposit(0, _shares, _receiver, _owner);
  }

  /**
   * @notice Mints shares to `_receiver` by depositing `_amount` of underlying assets (ERC-7540)
   * @notice Use `safeDeposit` for slippage control
   * @param _amount Amount of underlying assets to deposit
   * @param _receiver Receiver of the shares
   * @param _owner Owner of the assets to be deposited (usually `msg.sender`)
   * @return shares Amount of shares minted
   */
  function deposit(
    uint256 _amount,
    address _receiver,
    address _owner
  ) public returns (uint256 shares) {
    return _deposit(_amount, 0, _receiver, _owner);
  }

  /**
   * @notice Mints `_shares` to the `_receiver` by depositing underlying assets under `_maxAmount` constraint (ERC-4626 extension)
   * @param _shares Amount of shares to mint
   * @param _maxAmount Maximum amount of assets to be deposited (1-slippage)*shares
   * @param _receiver Receiver of the shares
   * @return deposited Amount of underlying assets deposited
   */
  function safeMint(
    uint256 _shares,
    uint256 _maxAmount,
    address _receiver
  ) external returns (uint256 deposited) {
    deposited = _deposit(0, _shares, _receiver, msg.sender);
    if (deposited > _maxAmount) {
      revert Errors.AmountTooHigh(deposited);
    }
  }

  /**
   * @notice Mints shares to the `_receiver` by depositing `_amount` underlying assets under `_minShareAmount` constraint (ERC-4626 extension)
   * @param _amount Amount of underlying assets to deposit
   * @param _minShareAmount Minimum amount of shares to be minted (1-slippage)*amount
   * @param _receiver Receiver of the shares
   * @return shares Amount of shares minted
   */
  function safeDeposit(
    uint256 _amount,
    uint256 _minShareAmount,
    address _receiver
  ) external returns (uint256 shares) {
    shares = _deposit(_amount, 0, _receiver, msg.sender);
    if (shares < _minShareAmount) {
      revert Errors.AmountTooLow(shares);
    }
  }

  /**
   * @notice Burns `_shares` from `_owner` and sends the equivalent `_amount` of underlying assets to `_receiver`
   * @dev Use `safeWithdraw()` for slippage control
   * @param _amount Amount of underlying assets to withdraw OR
   * @param _shares Amount of shares to redeem
   * @param _receiver Receiver of the assets
   * @param _owner Owner of the shares to be redeemed
   * @return shares Amount of shares burnt
   */
  function _withdraw(
    uint256 _amount,
    uint256 _shares,
    address _receiver,
    address _owner
  ) internal nonReentrant whenNotPaused returns (uint256) {
    if (_amount == 0 && _shares == 0) {
      revert Errors.AmountTooLow(0);
    }

    OwnerRequests storage request = _req.byOwner[_owner];
    Erc7540Request storage receiverRequest = request.redemptionByReceiver[_receiver];

    uint256 claimableShares = (
      msg.sender == receiverRequest.operator || msg.sender == _owner
    ) ? claimableRedeemRequest(_owner, _receiver) : 0;
    last.sharePrice = sharePrice();

    uint256 worstPrice = last.sharePrice;
    uint256 claimableAmount;

    if (claimableShares > 0) {
      worstPrice = AsMaths.min(last.sharePrice, receiverRequest.sharePrice);
      claimableAmount =
        claimableShares.mulDiv(worstPrice * _weiPerAsset, _WEI_PER_SHARE_SQUARED); // rounded down
    }

    if (_amount == 0) {
      _amount = _shares.mulDiv(worstPrice * _weiPerAsset, _WEI_PER_SHARE_SQUARED); // rounded down
    } else {
      _shares = _amount.mulDiv(_WEI_PER_SHARE_SQUARED, worstPrice * _weiPerAsset); // rounded down
    }

    uint256 assetFees = _amount.bp(exemptionList[_owner] ? 0 : fees.exit);

    if (claimableShares >= _shares) {
      receiverRequest.amount = receiverRequest.amount.subMax0(_shares);
      request.totalRedemption = request.totalRedemption.subMax0(_shares);
      _req.totalRedemption = _req.totalRedemption.subMax0(_shares);
      _req.totalClaimableRedemption = _req.totalClaimableRedemption.subMax0(_shares);
    } else {
      // allowance is already consumed if requested shares are used, but not here
      if (msg.sender != _owner) {
        if (allowance(_owner, msg.sender) < _shares) {
          revert Errors.Unauthorized();
        }
        _spendAllowance(_owner, msg.sender, _shares);
      }
      // check if the vault available liquidity can cover the withdrawal
      if (
        _shares
          > available().mulDiv(_WEI_PER_SHARE_SQUARED, last.sharePrice * _weiPerAsset)
      ) {
        revert Errors.AmountTooHigh(_shares);
      }
    }

    _burn(_owner, _shares);

    // check if burning the shares will bring the totalSupply below the minLiquidity
    if (
      totalSupply()
        < minLiquidity.mulDiv(_WEI_PER_SHARE_SQUARED, last.sharePrice * _weiPerAsset) // eg. 1e6*(1e12*1e12)/(1e12*1e6) = 1e12
    ) {
      revert Errors.Unauthorized();
    }

    unchecked {
      claimableTransactionFees += assetFees; // never overflows
      _amount -= assetFees; // assetFees is always less than _amount
    }
    asset.safeTransfer(_receiver, _amount);

    // re-calculate the sharePrice dynamically to avoid sharePrice() distortion
    uint256 newSupply = totalAccountedSupply();
    if (newSupply > 1) {
      uint256 totalValueBefore = last.sharePrice * (newSupply + _shares);
      uint256 totalValueAfter = totalValueBefore - (_shares * worstPrice);
      last.sharePrice = totalValueAfter / newSupply;
    }

    emit Withdraw(msg.sender, _receiver, _owner, _amount, _shares);
    return _amount;
  }

  /**
   * @notice Burns shares from `_owner` and sends the equivalent `_amount` of underlying assets to `_receiver` (ERC-4626)
   * @dev Use `safeWithdraw()` for slippage control
   * @param _amount Amount of underlying assets to withdraw
   * @param _receiver Receiver of the assets
   * @param _owner Owner of the shares to be redeemed
   * @return shares Amount of shares burned
   */
  function withdraw(
    uint256 _amount,
    address _receiver,
    address _owner
  ) external returns (uint256) {
    return _withdraw(_amount, 0, _receiver, _owner);
  }

  /**
   * @notice Burns shares from `_owner` and sends the equivalent `_amount` of underlying assets to `_receiver` under `_minAmount` constraint (ERC-4626 extension)
   * @param _amount Amount of underlying assets to withdraw
   * @param _receiver Receiver of the assets
   * @param _owner Owner of the shares to be redeemed
   * @return amount Amount of assets withdrawn
   */
  function safeWithdraw(
    uint256 _amount,
    uint256 _minAmount,
    address _receiver,
    address _owner
  ) external returns (uint256 amount) {
    amount = _withdraw(_amount, 0, _receiver, _owner);
    if (amount < _minAmount) {
      revert Errors.AmountTooLow(amount);
    }
  }

  /**
   * @notice Burns `_shares` from `_owner` and sends the equivalent underlying assets to `_receiver` (ERC-4626)
   * @dev Use `safeRedeem()` for slippage control
   * @param _shares Amount of shares to redeem
   * @param _receiver Receiver of the assets
   * @param _owner Owner of the shares to be redeemed
   * @return Amount of assets withdrawn
   */
  function redeem(
    uint256 _shares,
    address _receiver,
    address _owner
  ) external returns (uint256) {
    return _withdraw(0, _shares, _receiver, _owner);
  }

  /**
   * @notice Burns `_shares` from `_owner` and sends the equivalent underlying assets to `_receiver` under `_minAmountOut` constraint (ERC-4626 extension)
   * @param _shares Amount of shares to redeem
   * @param _minAmountOut Minimum amount of assets to be withdrawn
   * @param _receiver Receiver of the assets
   * @param _owner Owner of the shares to be redeemed
   * @return amount Amount of assets withdrawn
   */
  function safeRedeem(
    uint256 _shares,
    uint256 _minAmountOut,
    address _receiver,
    address _owner
  ) external returns (uint256 amount) {
    amount = _withdraw(
      0,
      _shares, // _shares
      _receiver, // _receiver
      _owner // _owner
    );
    if (amount < _minAmountOut) {
      revert Errors.AmountTooLow(amount);
    }
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                      ERC-7540 ASYNC LOGIC                      ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Initiates a redeem request on behalf of `_owner` for `_shares` (ERC-7540 compliant)
   * @param _shares Amount of shares to redeem
   * @param _receiver Requested shares receiver
   * @param _owner Owner of the shares to be redeemed
   * @param _data Callback data to be passed to `IERC7540RedeemReceiver(_owner).onERC7540RedeemReceived(data)`
   * @return id Unique ID of the request
   */
  function requestRedeem(
    uint256 _shares,
    address _receiver,
    address _owner,
    bytes memory _data
  ) public nonReentrant whenNotPaused returns (uint256 id) {
    if (_shares == 0 || balanceOf(_owner) < _shares) {
      revert Errors.AmountTooLow(_shares);
    }

    if (_owner != msg.sender) {
      if (allowance(_owner, msg.sender) < _shares) {
        revert Errors.Unauthorized();
      }
      _spendAllowance(_owner, msg.sender, _shares);
    }

    OwnerRequests storage request = _req.byOwner[_owner];
    Erc7540Request storage receiverRequest = request.redemptionByReceiver[_receiver];

    last.sharePrice = sharePrice();
    if (receiverRequest.amount > 0) {
      // compute request vwap
      receiverRequest.sharePrice = (
        (last.sharePrice * _shares)
          + (receiverRequest.sharePrice * receiverRequest.amount)
      ) / (_shares + receiverRequest.amount);
    } else {
      receiverRequest.sharePrice = last.sharePrice;
    }

    // incrementing the total redemption request, made safe by previous balanceOf()
    unchecked {
      id = ++_requestId;
      _req.totalRedemption += _shares;
      request.totalRedemption += _shares;
    }

    receiverRequest.id = id;
    receiverRequest.amount += _shares;
    receiverRequest.operator = msg.sender;
    receiverRequest.timestamp = block.timestamp;

    if (_data.length != 0) {
      // the caller contract must implement onERC7540RedeemReceived callback (0x0102fde4 selector)
      if (
        IERC7540RedeemReceiver(_receiver).onERC7540RedeemReceived(
          msg.sender, _owner, id, _shares, _data
        ) != IERC7540RedeemReceiver.onERC7540RedeemReceived.selector
      ) {
        revert Errors.Unauthorized();
      }
    }
    emit RedeemRequest(_receiver, _owner, id, receiverRequest.operator, _shares);
  }

  /**
   * @notice Initiates a withdraw request on behalf of `_owner` for `_amount` of underlying assets (ERC-7540)
   * @param _amount Amount of underlying assets to withdraw
   * @param _receiver Receiver of the shares to be redeemed
   * @param _owner Owner of the shares to be redeemed
   * @param _data Callback data to be passed to `IERC7540RedeemReceiver(_owner).onERC7540RedeemReceived(data)`
   * @return _id Unique ID of the request
   */
  function requestWithdraw(
    uint256 _amount,
    address _receiver,
    address _owner,
    bytes memory _data
  ) external returns (uint256) {
    return requestRedeem(_convertToShares(_amount, false), _receiver, _owner, _data);
  }

  /**
   * @notice Cancels a redemption request on behalf of `_owner` (ERC-7540 extension)
   * @notice Not affected by `pause()`, as reduces further liquidation volumes
   * @param _receiver Receiver of the shares to be redeemed
   * @param _owner Owner of the shares to be redeemed
   */
  function cancelRedeemRequest(address _receiver, address _owner) external nonReentrant {
    OwnerRequests storage request = _req.byOwner[_owner];
    Erc7540Request storage receiverRequest = request.redemptionByReceiver[_receiver];

    uint256 shares = receiverRequest.amount;

    if (receiverRequest.operator != msg.sender && _owner != msg.sender) {
      revert Errors.Unauthorized();
    }

    if (shares == 0) {
      revert Errors.AmountTooLow(0);
    }

    last.sharePrice = sharePrice();
    uint256 opportunityCost = 0;
    if (last.sharePrice > receiverRequest.sharePrice) {
      // burn the excess shares from the loss incurred while not farming
      // with the idle funds (opportunity cost)
      opportunityCost =
        shares.mulDiv(last.sharePrice - receiverRequest.sharePrice, _WEI_PER_SHARE); // eg. 1e12*1e12/1e12 = 1e12
      _burn(_owner, opportunityCost);
    }

    _req.totalRedemption = _req.totalRedemption.subMax0(shares);

    // if the request liquidation has been processed, reduce totalClaimable by that much
    if (receiverRequest.timestamp < last.liquidate) {
      _req.totalClaimableRedemption = _req.totalClaimableRedemption.subMax0(shares);
    }

    request.totalRedemption = request.totalRedemption.subMax0(shares);
    receiverRequest.amount = 0;

    // adjust the operator's allowance after burning shares, only if operator != owner
    if (opportunityCost > 0 && _owner != msg.sender) {
      uint256 currentAllowance = allowance(_owner, msg.sender);
      _approve(_owner, msg.sender, currentAllowance.subMax0(opportunityCost));
    }

    emit RedeemRequestCanceled(_receiver, _owner, receiverRequest.id, shares);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                          FEES LOGIC                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Triggers a fee collection - Claims all fees by minting the equivalent `toMint` shares to `feeCollector`
   * @return toMint Amount of shares minted to the feeCollector
   */
  function _collectFees() internal virtual returns (uint256 toMint);

  /**
   * @notice Triggers a fee collection - Claims all fees by minting the equivalent `toMint` shares to `feeCollector`
   * @return Amount of shares minted to the `feeCollector`
   */
  function collectFees() external nonReentrant onlyManager returns (uint256) {
    return _collectFees();
  }
}
