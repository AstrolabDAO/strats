// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/IAccessController.sol";
import "./AsTypes.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsPermissioned Abstract - AccessController consumer for permissioned contracts
 * @author Astrolab DAO
 * @notice Extending this contract allows for role-based access control (RBAC)
 */
abstract contract AsPermissioned {

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct PermissionedStorage {
    IAccessController ac;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  // EIP-7201 keccak256(abi.encode(uint256(keccak256("AsPermissioned.main")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant _STORAGE_SLOT =
    0x94de5bb549dc3b3f2a557f7067a0d52c6921e50388ea6bea5cf4ee301cf1a400;

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
    _storage().ac = IAccessController(_accessController);
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
    return _storage().ac.hasRole(_role, _account);
  }

  function _checkRole(bytes32 _role, address _account) internal view {
    _storage().ac.checkRole(_role, _account);
  }

  /**
   * @notice Checks if an account has the keeper role
   */
  modifier onlyKeeper() {
    _checkRole(Roles.KEEPER, msg.sender);
    _;
  }

  /**
   * @notice Checks if an account has the manager role
   */
  modifier onlyManager() {
    _checkRole(Roles.MANAGER, msg.sender);
    _;
  }

  /**
   * @notice Checks if an account has the admin role
   */
  modifier onlyAdmin() {
    _checkRole(Roles.ADMIN, msg.sender);
    _;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return $ Upgradable EIP-7201 storage slot
   */
  function _storage() internal pure virtual returns (PermissionedStorage storage $) {
    assembly {
      $.slot := _STORAGE_SLOT
    }
  }

  /**
   * @return Access controller contract
   */
  function accessController() external view returns (address) {
    return address(_storage().ac);
  }
}
