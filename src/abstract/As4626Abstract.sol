// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ERC20Abstract.sol";
import "./AsManageable.sol";
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
abstract contract As4626Abstract is ERC20Abstract, AsManageable {
  using SafeERC20 for IERC20Metadata;
  using AsMaths for uint256;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct As4626StorageExt {
    uint16 maxSlippageBps; // strategy default internal ops slippage
  }

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

  event RedeemRequestCanceled(
    address indexed receiver, address indexed owner, uint256 requestId, uint256 shares
  );

  event DepositRequestCanceled(
    address indexed receiver, address indexed owner, uint256 requestId, uint256 amount
  );

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  uint256 internal constant _WEI_PER_SHARE = 1e12; // weis in a share (base unit)
  uint256 internal constant _WEI_PER_SHARE_SQUARED = _WEI_PER_SHARE ** 2;

  // Upgrade dedicated storage to prevent collisions (EIP-7201)
  // keccak256(abi.encode(uint256(keccak256("As4626.ext")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant _STORAGE_EXT_SLOT =
    0x158e00504b6e2b9f9abe924926be99e72fb1fd7c6bcaafc95ce02d9dabf05300;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  // Share/underlying asset accounting
  uint256 public maxTotalAssets = 0; // maximum total assets that can be deposited
  uint256 public minLiquidity = 1e7; // minimum amount to seed liquidity is 1e7 wei (e.g., 10 USDC)

  IERC20Metadata public asset; // ERC20 token used as the base denomination
  uint8 internal _assetDecimals; // ERC20 token decimals
  uint256 internal _weiPerAsset; // amount of wei in one underlying asset unit (1e(decimals))
  Epoch public last; // epoch tracking latest events (6 slots)

  // Profit-related variables
  uint256 internal _profitCooldown = 10 days; // profit linearization period (profit locktime)
  uint256 internal _expectedProfits; // expected profits

  Fees public fees; // current fee structure (2 slots)
  address public feeCollector; // address to collect fees
  uint256 public claimableTransactionFees; // amount of asset fees (entry+exit) that can be claimed
  mapping(address => bool) public exemptionList; // list of addresses exempted from fees

  Requests internal _req; // (5 slots)
  uint256 internal _requestId; // redeem request id

  // NB: DO NOT EXTEND THIS STORAGE, TO PREVENT COLLISION USE `_4626StorageExt()`

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) AsManageable(_accessController) {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return $ Upgradable EIP-7201 As4626 storage extension slot
   */
  function _4626StorageExt() internal pure returns (As4626StorageExt storage $) {
    assembly {
      $.slot := _STORAGE_EXT_SLOT
    }
  }

  /**
   * @return Total amount of invested inputs denominated in underlying assets
   */
  function _invested() internal view virtual returns (uint256);
}
