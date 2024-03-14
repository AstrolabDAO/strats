// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IAccessController.sol";
import "./AsTypes.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsManageable Abstract - Lighter OZ AccessControlEnumerable+Pausable extension
 * @author Astrolab DAO
 * @notice Abstract contract to check roles against AccessController and contract pausing
 */
contract AsManageable is Pausable, ReentrancyGuard {

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  IAccessController private _ac;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) {
    (bool success,) = _accessController.staticcall(
      abi.encodeWithSelector(IAccessController.isAdmin.selector, msg.sender)
    );
    if (!success) {
      revert Errors.ContractNonCompliant();
    }
    _ac = IAccessController(_accessController);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                           MODIFIERS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Checks if `_account` has `_role`
   * @param _role Role to check
   * @param _account Account to check
   * @return Boolean indicating if `_account` has `_role`
   */
  function _hasRole(bytes32 _role, address _account) internal view returns (bool) {
    return _ac.hasRole(_role, _account);
  }

  /**
   * @notice Checks if an account has the keeper role
   */
  modifier onlyKeeper() {
    _ac.checkRole(Roles.KEEPER, msg.sender);
    _;
  }

  /**
   * @notice Checks if an account has the manager role
   */
  modifier onlyManager() {
    _ac.checkRole(Roles.MANAGER, msg.sender);
    _;
  }

  /**
   * @notice Checks if an account has the admin role
   */
  modifier onlyAdmin() {
    _ac.checkRole(Roles.ADMIN, msg.sender);
    _;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                        PAUSING LOGIC                           ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Unpauses the contract, resuming all operations
   */
  function unpause() public onlyAdmin {
    _unpause();
  }

  /**
   * @notice Pauses the contract, partially freezing operations
   */
  function pause() public onlyAdmin {
    _pause();
  }
}
