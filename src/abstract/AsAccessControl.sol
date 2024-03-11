// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../libs/AsCast.sol";
import "../libs/AsIterableSet.sol";
import "./AsAccessControlAbstract.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsAccessControl - Astrolab's access controller
 * @author Astrolab DAO
 * @notice Inspired by OZ's AccessControlEnumerable, used for RBAC and contract pausing
 */
abstract contract AsAccessControl is AsAccessControlAbstract {
  using AsIterableSet for AsIterableSet.Set;
  using AsCast for bytes32;
  using AsCast for address;

  /*═══════════════════════════════════════════════════════════════╗
  ║                           MODIFIERS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Checks if the caller has a role
   */
  modifier onlyRole(bytes32 role) override {
    _checkRole(role);
    _;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Checks if `_account` has `_role`
   * @param _role Role to check
   * @param account Account to check
   * @return Boolean indicating if `_account` has `_role`
   */
  function hasRole(bytes32 _role, address account) public view virtual returns (bool) {
    return _roles[_role].members.has(account.toBytes32());
  }

  /**
   * @notice Checks if `msg.sender` has `_role`
   * @param _role Role to check
   */
  function _checkRole(bytes32 _role) internal view virtual {
    _checkRole(_role, msg.sender);
  }

  /**
   * @notice Checks if `_account` has `_role`
   * @param _role Role to check
   * @param _account Account to check
   */
  function _checkRole(bytes32 _role, address _account) internal view virtual {
    if (!hasRole(_role, _account)) revert Unauthorized();
  }

  /**
   * @notice Gets the admin role of a _role
   * @param _role Role to query the admin role of
   * @return Admin role of `_role`
   */
  function getRoleAdmin(bytes32 _role) public view virtual returns (bytes32) {
    return _roles[_role].adminRole;
  }

  /**
   * @notice Gets the members of `_role`
   * @param _role Role to get members of
   * @return Array of `_role` members
   */
  function getMembers(bytes32 _role) public view virtual returns (address[] memory) {
    return _roles[_role].members.valuesAsAddress();
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Grants `_role` to `_account`
   * @param _role Role to grant
   * @param _account Account to grant `_role` to
   */
  function grantRole(
    bytes32 _role,
    address _account
  ) public virtual onlyRole(getRoleAdmin(_role)) {
    _grantRole(_role, _account);
  }

  /**
   * @notice Revokes `_role` from `_account`
   * @param _role Role to revoke
   * @param _account Account to revoke `_role` from
   */
  function revokeRole(
    bytes32 _role,
    address _account
  ) public virtual onlyRole(getRoleAdmin(_role)) {
    _revokeRole(_role, _account);
  }

  /**
   * @notice Renounces `_role` (revokes from `msg.sender`)
   * @param _role Role to renounce
   */
  function renounceRole(bytes32 _role) external virtual {
    if (_role == DEFAULT_ADMIN_ROLE) revert Unauthorized();
    _revokeRole(_role, msg.sender);
  }

  /**
   * @notice Sets `_role`'s admin role
   * @param _role Role to set the admin role of
   * @param _adminRole Admin role to be set
   */
  function _setRoleAdmin(bytes32 _role, bytes32 _adminRole) internal virtual {
    RoleState storage role = _roles[_role];
    emit RoleAdminChanged(_role, role.adminRole, _adminRole);
    role.adminRole = _adminRole;
  }

  /**
   * @notice Grants `_role` to `_account`
   * @param _role Role to grant
   * @param _account Account to grant `_role` to
   */
  function _grantRole(bytes32 _role, address _account) internal virtual {
    RoleState storage role = _roles[_role];
    bytes32 accSig = _account.toBytes32();
    if (!role.members.has(accSig)) {
      role.members.push(accSig);
      emit RoleGranted(_role, _account, msg.sender);
    }
  }

  /**
   * @notice Revokes `_role` from `_account`
   * @param _role Role to revoke
   * @param _account Account to revoke `_role` from
   */
  function _revokeRole(bytes32 _role, address _account) internal virtual {
    RoleState storage role = _roles[_role];
    bytes32 accSig = _account.toBytes32();
    if (role.members.has(accSig)) {
      role.members.remove(accSig);
      emit RoleRevoked(_role, _account, msg.sender);
    }
  }
}
