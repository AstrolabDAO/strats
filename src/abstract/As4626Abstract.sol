// SPDX-License-Identifier: BUSL-1.1
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
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title As4626Abstract - Extended by all strategies
 * @author Astrolab DAO
 * @notice This contract lays out the common storage for all strategies
 * @dev All state variables must be here to match the proxy base storage layout (StrategyV5)
 */
abstract contract As4626Abstract is ERC20, AsManageable, ReentrancyGuard {
  using SafeERC20 for IERC20Metadata;
  using AsMaths for uint256;

  /*═══════════════════════════════════════════════════════════════╗
  ║                             ERRORS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  // Errors
  error AmountTooHigh(uint256 amount);
  error AmountTooLow(uint256 amount);
  error AddressZero();
  error FlashLoanDefault(address borrower, uint256 amount);
  error InvalidData(); // invalid calldata / inputs

  /*═══════════════════════════════════════════════════════════════╗
  ║                             EVENTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  // ERC-4626
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

  // ERC-7540
  event DepositRequest(
    address indexed receiver,
    address indexed owner,
    uint256 indexed requestId,
    address sender,
    uint256 assets
  );

  event RedeemRequest(
    address indexed receiver,
    address indexed owner,
    uint256 indexed requestId,
    address sender,
    uint256 shares
  );

  // event DepositRequestCanceled(address indexed owner, uint256 assets);
  event RedeemRequestCanceled(address indexed owner, uint256 assets);

  // Flash loan
  event FlashLoan(address indexed borrower, uint256 amount, uint256 fee);

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  uint256 internal constant _MAX_UINT256 = type(uint256).max;
  uint256 internal constant _WEI_PER_SHARE = 1e12; // weis in a share (base unit)
  uint256 internal constant _WEI_PER_SHARE_SQUARED = _WEI_PER_SHARE ** 2;
  bytes32 internal constant _FLASH_LOAN_SIG = keccak256("ERC3156FlashBorrower.onFlashLoan");

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  // Share/underlying asset accounting
  uint256 public maxTotalAssets = 0; // maximum total assets that can be deposited
  uint256 internal minLiquidity = 1e7; // minimum amount to seed liquidity is 1e7 wei (e.g., 10 USDC)
  uint16 internal _maxSlippageBps = 100; // strategy default internal ops slippage 1%

  IERC20Metadata public asset; // ERC20 token used as the base denomination
  uint8 internal _assetDecimals; // ERC20 token decimals
  uint256 internal _weiPerAsset; // amount of wei in one underlying asset unit (1e(decimals))
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

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor() {
    _pause();
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @dev Must be overridden by StrategyV5 implementations
   * @return Total amount of invested inputs denominated in underlying assets
   */
  function invested() public view virtual returns (uint256);

  /**
   * @return Amount of underlying assets available to non-requested withdrawals, excluding `minLiquidity`
   */
  function available() public view returns (uint256) {
    return
      availableBorrowable().subMax0(convertToAssets(_req.totalClaimableRedemption, false));
  }

  /**
   * @return Total amount of underlying assets available to withdraw
   */
  function availableClaimable() internal view returns (uint256) {
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
  function totalAssets() public view virtual returns (uint256) {
    return availableClaimable() + invested();
  }

  /**
   * @return Total assets denominated in underlying, excluding claimable redemptions (used to calculate `sharePrice()`)
   */
  function totalAccountedAssets() public view returns (uint256) {
    return totalAssets().subMax0(
      _req.totalClaimableRedemption.mulDiv(
        last.sharePrice * _weiPerAsset, _WEI_PER_SHARE_SQUARED
      )
    ); // eg. (1e12+1e12+1e6)-(1e12+1e12) = 1e6
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
  function sharePrice() public view virtual returns (uint256) {
    uint256 supply = totalAccountedSupply();
    return supply == 0
      ? _WEI_PER_SHARE
      : totalAccountedAssets().mulDiv( // eg. e6
        _WEI_PER_SHARE_SQUARED, // 1e12*2
        supply * _weiPerAsset
      ); // eg. (1e6+1e12+1e12)-(1e12+1e6)
  }

  /**
   * @param _owner Owner of the shares
   * @return Value of the owner's shares denominated in underlying assets
   */
  function assetsOf(address _owner) public view returns (uint256) {
    return convertToAssets(balanceOf(_owner), false);
  }

  /**
   * @notice Converts `_amount` of underlying assets to shares at the current share price
   * @param _amount Amount of underlying assets to convert
   * @param _roundUp Round up if true, round down otherwise
   * @return Amount of shares equivalent to `_amount` assets
   */
  function convertToShares(
    uint256 _amount,
    bool _roundUp
  ) internal view returns (uint256) {
    return _amount.mulDiv(
      _WEI_PER_SHARE_SQUARED,
      sharePrice() * _weiPerAsset,
      _roundUp ? AsMaths.Rounding.Ceil : AsMaths.Rounding.Floor
    ); // eg. 1e6+(1e12+1e12)-(1e12+1e6) = 1e12
  }

  /**
   * @notice Converts `_amount` of underlying assets to shares at the current share price
   * @param _amount Amount of assets to convert
   * @return Amount of shares equivalent to `_amount` assets
   */
  function convertToShares(uint256 _amount) external view returns (uint256) {
    return convertToShares(_amount, false);
  }

  /**
   * @notice Converts `_shares` to underlying assets at the current share price
   * @param _shares Amount of shares to convert
   * @param _roundUp Round up if true, round down otherwise
   * @return Amount of assets equivalent to `_shares`
   */
  function convertToAssets(
    uint256 _shares,
    bool _roundUp
  ) internal view returns (uint256) {
    return _shares.mulDiv(
      sharePrice() * _weiPerAsset,
      _WEI_PER_SHARE_SQUARED,
      _roundUp ? AsMaths.Rounding.Ceil : AsMaths.Rounding.Floor
    ); // eg. 1e12+(1e12+1e6)-(1e12+1e12) = 1e6
  }

  /**
   * @notice Converts `_shares` to underlying assets at the current share price
   * @param _shares Amount of shares to convert
   * @return Amount of assets equivalent to `_shares`
   */
  function convertToAssets(uint256 _shares) external view returns (uint256) {
    return convertToAssets(_shares, false);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @dev Transfers `_amount` of shares from `msg.sender` to `_receiver`
   * @param _receiver Receiver of the shares
   * @param _amount Amount of shares to transfer
   * @return Boolean indicating whether the transfer was successful or not
   */
  function transfer(address _receiver, uint256 _amount) public override(ERC20) returns (bool) {
    Erc7540Request storage request = _req.byOwner[msg.sender];
    if (_amount > (balanceOf(msg.sender) - request.shares)) {
      revert AmountTooHigh(_amount);
    }
    return ERC20.transfer(_receiver, _amount);
  }
}
