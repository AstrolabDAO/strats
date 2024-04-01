// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IERC3156FlashBorrower.sol";
import "./AsPermissioned.sol";
import "./AsTypes.sol";
import "../libs/AsMaths.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsFlashLender Abstract - Flash loan provider for ERC-3156 compliant contracts
 * @author Astrolab DAO
 * @notice Extending this contract allows for flash loan provision
 */
abstract contract AsFlashLender is AsPermissioned, Pausable, ReentrancyGuard {
  using SafeERC20 for IERC20Metadata;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STRUCTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct FlashLenderStorage {
    uint256 maxLoan;
    uint256 totalLent;
    uint256 claimableFlashFees;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             EVENTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  event FlashLoan(address indexed borrower, uint256 amount, uint256 fee);

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  // keccak256("ERC3156FlashBorrower.onFlashLoan")
  bytes32 internal constant _FLASH_LOAN_SIG =
    0x439148f0bbc682ca079e46d6e2c2f0c1e3b820f1a291b069d8882abf8cf18dd9;
  // EIP-7201 keccak256(abi.encode(uint256(keccak256("AsFlashLender.main")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant _STORAGE_SLOT =
    0xfd382666e8596978613337f844976274bd88962cef48a129cf342c2e9f221300;

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return $ Upgradable EIP-7201 storage slot
   */
  function _lenderStorage() internal pure returns (FlashLenderStorage storage $) {
    assembly {
      $.slot := _STORAGE_SLOT
    }
  }

  /**
   * @notice Calculates the flash fee for `_borrower` and `_amount` (ERC-3156 extension)
   * @param _borrower Address of the borrower
   * @param _amount Amount of underlying assets lent
   * @return Amount of underlying assets to be charged for the loan, on top of the returned principal
   */
  function _flashFee(
    address _borrower,
    uint256 _amount
  ) internal view virtual returns (uint256);

  /**
   * @notice Checks if the specified asset is lendable
   * @param _asset Address of the asset to check
   * @return Boolean indicating whether `_asset` is lendable or not
   */
  function isLendable(address _asset) public view virtual returns (bool);

  /**
   * @notice Amount of underlying assets available to be lent (ERC-3156 extension)
   * @return Amount of underlying assets that can currently be borrowed through `flashLoan`
   */
  function borrowable() public view virtual returns (uint256);

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
  ) public view returns (uint256) {
    if (!isLendable(_token) || _amount > maxFlashLoan(_token)) {
      revert Errors.Unauthorized();
    }
    return _flashFee(_borrower, _amount);
  }

  /**
   * @notice Fee to be charged for a given loan (ERC-3156)
   * @notice Use `flashFee(address _token, address _borrower, uint256 _amount)` to specify a different `_borrower`
   * @param _token Loan currency
   * @param _amount Amount of `_token` lent
   * @return Amount of `_token` to be charged for the loan, on top of the returned principal
   */
  function flashFee(address _token, uint256 _amount) external view returns (uint256) {
    return flashFee(_token, msg.sender, _amount);
  }

  /**
   * @notice Amount of underlying assets available to be lent (ERC-3156)
   * @param _token Loan currency
   * @return Amount of `_token` that can currently be borrowed through `flashLoan`
   */
  function maxFlashLoan(address _token) public view returns (uint256) {
    return isLendable(_token) ? AsMaths.min(borrowable(), _lenderStorage().maxLoan) : 0;
  }

  /**
   * @notice Returns the amount of flash fees that can be claimed by the lender
   * @return Amount of flash fees that can be claimed
   */
  function claimableFlashFees() public view returns (uint256) {
    return _lenderStorage().claimableFlashFees;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                          INITIALIZERS                          ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor() {
    _lenderStorage().maxLoan = AsMaths.MAX_UINT256;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            SETTERS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Sets the vault `_maxLoan` originated in underlying assets
   * @param _amount Maximum loan amount
   */
  function setMaxLoan(uint256 _amount) external onlyAdmin {
    _lenderStorage().maxLoan = _amount;
  }

  /**
   * @notice Lends `_amount` of underlying assets to `_receiver` contract while executing `_dataparams` (ERC-3156 extension)
   * @param _receiver Borrower executing the flash loan, must be a contract implementing `ISimpleLoanReceiver` and not an EOA
   * @param _token Loan currency
   * @param _amount Amount of underlying assets to lend
   * @param _data Callback data to be passed to `_receiver.executeOperation(_data)` function
   */
  function _flashLoan(
    address _receiver,
    address _token,
    uint256 _amount,
    bytes calldata _data
  ) internal virtual {
    IERC20Metadata asset = IERC20Metadata(_token); // Assuming 'asset' is your ERC20 Address of the token

    if (_amount > borrowable()) {
      revert Errors.AmountTooHigh(_amount);
    }

    uint256 fee = _flashFee(_receiver, _amount);
    uint256 balanceBefore = asset.balanceOf(address(this));

    // Transfer the tokens to the receiver
    asset.safeTransfer(_receiver, _amount);

    // Callback to the receiver's onFlashLoan method
    if (
      IERC3156FlashBorrower(_receiver).onFlashLoan(
        msg.sender, _token, _amount, fee, _data
      ) != _FLASH_LOAN_SIG
    ) {
      revert Errors.FlashLoanCallbackFailed();
    }

    // Verify the repayment and fee
    uint256 balanceAfter = asset.balanceOf(address(this));
    if (balanceAfter < balanceBefore + fee) {
      revert Errors.FlashLoanDefault(_receiver, _amount);
    }

    _lenderStorage().totalLent += _amount;
    _lenderStorage().claimableFlashFees += fee;
    emit FlashLoan(msg.sender, _amount, fee);
  }

  /**
   * @notice Lends `_amount` of underlying assets to `_receiver` contract while executing `_dataparams` (ERC-3156)
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
  ) external nonReentrant whenNotPaused returns (bool) {
    _flashLoan(_receiver, _token, _amount, _data);
    return true;
  }
}
