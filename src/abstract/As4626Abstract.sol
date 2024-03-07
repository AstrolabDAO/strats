// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ERC20.sol";
import "./AsManageable.sol";
import "./AsTypes.sol";
import "../libs/AsAccounting.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title As4626Abstract - inherited by all strategies
 * @author Astrolab DAO
 * @notice All As4626 calls are delegated to the agent (StrategyV5Agent)
 * @dev Make sure all As4626 state variables here to match proxy/implementation slots
 */
abstract contract As4626Abstract is ERC20, AsManageable, ReentrancyGuard {
  using SafeERC20 for IERC20Metadata;
  using AsMaths for uint256;

  // Events
  // ERC4626
  event Deposit(
    address indexed sender, address indexed owner, uint256 assets, uint256 shares
  );

  event Withdraw(
    address indexed sender,
    address indexed receiver,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );

  // ERC7540
  event DepositRequest(
      address indexed receiver,
      address indexed owner,
      uint256 indexed requestId,
      address sender, // operator
      uint256 assets // locked assets
      );
  // shares to unlock
  event RedeemRequest( // operator
    address indexed receiver,
    address indexed owner,
    uint256 indexed requestId,
    address sender,
    uint256 shares
  );

  // event DepositRequestCanceled(address indexed owner, uint256 assets);
  event RedeemRequestCanceled(address indexed owner, uint256 assets);

  // As4626 specific
  // Flash loan
  event FlashLoan(address indexed borrower, uint256 amount, uint256 fee);

  // Errors
  error AmountTooHigh(uint256 amount);
  error AmountTooLow(uint256 amount);
  error AddressZero();
  error FlashLoanDefault(address borrower, uint256 amount);
  error InvalidData(); // invalid calldata / inputs

  // Constants
  uint256 internal constant _MAX_UINT256 = type(uint256).max;

  uint256 public maxTotalAssets = 0; // maximum total assets that can be deposited
  uint256 internal _minLiquidity = 1e7; // minimum amount to seed liquidity is 1e7 wei (e.g., 10 USDC)
  uint16 internal _maxSlippageBps = 100; // strategy default internal ops slippage 1%

  // Share/underlying asset accounting
  uint256 internal constant _WEI_PER_SHARE = 1e12; // weis in a share (base unit)
  uint256 internal constant _WEI_PER_SHARE_SQUARED = _WEI_PER_SHARE ** 2;
  IERC20Metadata public asset; // ERC20 token used as the base denomination
  uint8 internal _assetDecimals; // ERC20 token decimals
  uint256 internal _weiPerAsset; // weis in an asset (underlying unit)
  Epoch public last; // epoch tracking latest events

  // Profit-related variables
  uint256 internal _profitCooldown = 10 days; // profit linearization period (profit locktime)
  uint256 internal _expectedProfits; // expected profits

  Fees public fees; // current fee structure
  address public feeCollector; // address to collect fees
  uint256 public claimableAssetFees; // amount of asset fees (entry+exit) that can be claimed
  mapping(address => bool) public exemptionList; // list of addresses exempted from fees

  Requests internal _req;
  uint256 internal _requestId; // redeem request id

  // Flash loan
  uint256 public totalLent;
  uint256 public maxLoan = 1e12; // maximum amount of flash loan allowed (default to 1e12 eg. 1m usdc)

  constructor() {
    _pause();
  }

  /**
   * @dev Transfers a specified amount of tokens to a given address
   * @param _to The address to transfer tokens to
   * @param _amount The amount of tokens to transfer
   * @return A boolean value indicating whether the transfer was successful or not
   * @dev Throws an exception if the transfer amount exceeds the balance of the sender minus the shares in the request
   */
  function transfer(address _to, uint256 _amount) public override(ERC20) returns (bool) {
    Erc7540Request storage request = _req.byOwner[msg.sender];
    if (_amount > (balanceOf(msg.sender) - request.shares)) {
      revert AmountTooHigh(_amount);
    }
    return ERC20.transfer(_to, _amount);
  }

  /**
   * @notice Exempt an account from entry/exit fees or remove its exemption
   * @param _account The account to exempt
   * @param _isExempt Whether to exempt or not
   */
  function setExemption(address _account, bool _isExempt) public onlyAdmin {
    exemptionList[_account] = _isExempt;
  }

  /**
   * @dev Abstract function to be implemented by the strategy
   * @return Total amount of invested inputs denominated in asset
   */
  function invested() public view virtual returns (uint256);

  /**
   * @return Amount of assets available to non-requested withdrawals (excluding seed)
   */
  function available() public view returns (uint256) {
    return
      availableBorrowable().subMax0(convertToAssets(_req.totalClaimableRedemption, false));
  }

  /**
   * @return Total amount of assets available to withdraw
   */
  function availableClaimable() internal view returns (uint256) {
    return asset.balanceOf(address(this)).subMax0(
      claimableAssetFees
        + AsAccounting.unrealizedProfits(last.harvest, _expectedProfits, _profitCooldown)
    );
  }

  /**
   * @return The amount of borrowable assets that are currently available
   */
  function availableBorrowable() internal view returns (uint256) {
    return availableClaimable();
  }

  /**
   * @return Amount under management denominated in asset (including claimable redemptions)
   */
  function totalAssets() public view virtual returns (uint256) {
    return availableClaimable() + invested();
  }

  /**
   * @return Amount of assets under management used for sharePrice accounting denominated in asset
   * (excluding claimable redemptions approximated with previous accounted sharePrice)
   */
  function totalAccountedAssets() public view returns (uint256) {
    return totalAssets().subMax0(
      _req.totalClaimableRedemption.mulDiv(
        last.sharePrice * _weiPerAsset, _WEI_PER_SHARE_SQUARED
      )
    ); // eg. (1e8+1e8+1e6)-(1e8+1e8) = 1e6
  }

  /**
   * @return Amount of shares used for sharePrice accounting (excluding claimable redemptions)
   */
  function totalAccountedSupply() public view returns (uint256) {
    return totalSupply().subMax0(_req.totalClaimableRedemption);
  }

  /**
   * @return The share price equal to the amount of assets redeemable for one vault token
   */
  function sharePrice() public view virtual returns (uint256) {
    uint256 supply = totalAccountedSupply();
    return supply == 0
      ? _WEI_PER_SHARE
      : totalAccountedAssets().mulDiv( // eg. e6
        _WEI_PER_SHARE_SQUARED, // 1e8*2
        supply * _weiPerAsset
      ); // eg. (1e6+1e8+1e8)-(1e8+1e6)
  }

  /**
   * @param _owner Shares owner
   * @return Value of the owner's position in asset tokens
   */
  function assetsOf(address _owner) public view returns (uint256) {
    return convertToAssets(balanceOf(_owner), false);
  }

  /**
   * @notice Convert how many shares you can get for your assets
   * @param _assets Amount of assets to convert
   * @param _roundUp Round up if true, round down otherwise
   * @return Amount of shares you can get for your assets
   */
  function convertToShares(
    uint256 _assets,
    bool _roundUp
  ) internal view returns (uint256) {
    return _assets.mulDiv(
      _WEI_PER_SHARE_SQUARED,
      sharePrice() * _weiPerAsset,
      _roundUp ? AsMaths.Rounding.Ceil : AsMaths.Rounding.Floor
    ); // eg. 1e6+(1e8+1e8)-(1e8+1e6) = 1e8
  }

  /**
   * @notice Convert how many shares you can get for your assets
   * @param _assets Amount of assets to convert
   * @return Amount of shares you can get for your assets
   */
  function convertToShares(uint256 _assets) external view returns (uint256) {
    return convertToShares(_assets, false);
  }

  /**
   * @notice Convert how much asset tokens you can get for your shares
   * @dev Bear in mind that some negative slippage may happen
   * @param _shares Amount of shares to convert
   * @param _roundUp Round up if true, round down otherwise
   * @return Amount of asset tokens you can get for your shares
   */
  function convertToAssets(
    uint256 _shares,
    bool _roundUp
  ) internal view returns (uint256) {
    return _shares.mulDiv(
      sharePrice() * _weiPerAsset,
      _WEI_PER_SHARE_SQUARED,
      _roundUp ? AsMaths.Rounding.Ceil : AsMaths.Rounding.Floor
    ); // eg. 1e8+(1e8+1e6)-(1e8+1e8) = 1e6
  }

  /**
   * @notice Convert how much asset tokens you can get for your shares
   * @dev Bear in mind that some negative slippage may happen
   * @param _shares Amount of shares to convert
   * @return Amount of asset tokens you can get for your shares
   */
  function convertToAssets(uint256 _shares) external view returns (uint256) {
    return convertToAssets(_shares, false);
  }
}
