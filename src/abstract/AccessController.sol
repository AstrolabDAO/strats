// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../libs/AsCast.sol";
import "../libs/AsIterableSet.sol";
import "./AsTypes.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AccessController - Astrolab's access controller
 * @author Astrolab DAO
 * @notice Inspired by OZ's AccessControlEnumerable, used for RBAC and contract pausing
 * @notice Default roles are KEEPER (operator/bot), MANAGER (elevated DAO member) and ADMIN (elevated DAO council multisig)
 */
contract AccessController {
  using AsIterableSet for AsIterableSet.Set;
  using AsCast for bytes32;
  using AsCast for address;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct RoleState {
    AsIterableSet.Set members;
    bytes32 adminRole;
  }

  struct PendingAcceptance {
    bytes32 role; // by default 0x00 == Roles.ADMIN
    address replacing;
    uint64 timestamp;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             EVENTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  event RoleAdminChanged(
    bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole
  );
  event RoleGranted(
    bytes32 indexed role, address indexed account, address indexed sender
  );
  event RoleRevoked(
    bytes32 indexed role, address indexed account, address indexed sender
  );

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  uint256 public constant ROLE_ACCEPTANCE_TIMELOCK = 2 days;
  uint256 public constant ROLE_ACCEPTANCE_VALIDITY = 7 days;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  mapping(address => PendingAcceptance) public pendingAcceptance;
  mapping(bytes32 => RoleState) internal _roles;

  /*═══════════════════════════════════════════════════════════════╗
  ║                           MODIFIERS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Checks if the caller has a role
   */
  modifier onlyRole(bytes32 role) {
    checkRole(role);
    _;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Checks if `_account` has `_role`
   * @param _role Role to check
   * @param account Account to check
   * @return Boolean indicating if `_account` has `_role`
   */
  function hasRole(bytes32 _role, address account) public view returns (bool) {
    return _roles[_role].members.has(account.toBytes32());
  }

  /**
   * @notice Checks if `msg.sender` has `_role`
   * @param _role Role to check
   */
  function checkRole(bytes32 _role) public view {
    checkRole(_role, msg.sender);
  }

  /**
   * @notice Checks if `_account` has `_role`
   * @param _role Role to check
   * @param _account Account to check
   */
  function checkRole(bytes32 _role, address _account) public view {
    if (!hasRole(_role, _account)) revert Errors.Unauthorized();
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
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor() {
    _grantRole(Roles.ADMIN, msg.sender);
    _grantRole(Roles.MANAGER, msg.sender);
    _setRoleAdmin(Roles.KEEPER, Roles.ADMIN);
    _setRoleAdmin(Roles.MANAGER, Roles.ADMIN);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Checks `_acceptance` state for a pending `_role` change
   * @param _acceptance Acceptance data containing a granted role and creation timestamp
   * @param _role Role to check
   */
  function checkRoleAcceptance(
    PendingAcceptance memory _acceptance,
    bytes32 _role
  ) public view {
    // make sure the role accepted is the same as the pending one
    if (_acceptance.role != _role) {
      revert Errors.Unauthorized();
    }
    // grant the keeper role instantly (no attack surface here)
    if (_acceptance.role == Roles.KEEPER) return;
    if (
      block.timestamp
        > (_acceptance.timestamp + ROLE_ACCEPTANCE_TIMELOCK + ROLE_ACCEPTANCE_VALIDITY)
    ) {
      revert Errors.AcceptanceExpired();
    }
    if (block.timestamp < (_acceptance.timestamp + ROLE_ACCEPTANCE_TIMELOCK)) {
      revert Errors.AcceptanceLocked();
    }
  }

  /**
   * @return Array of `MANAGER` addresses
   */
  function getManagers() external view returns (address[] memory) {
    return getMembers(Roles.MANAGER);
  }

  /**
   * @return Array of `KEEPER` addresses
   */
  function getKeepers() external view returns (address[] memory) {
    return getMembers(Roles.KEEPER);
  }

  /**
   * @notice Checks if `_account` is an `ADMIN`
   * @param _account Address of the account to check
   * @return Boolean indicating whether the account has the role
   */
  function isAdmin(address _account) external view returns (bool) {
    return hasRole(Roles.ADMIN, _account);
  }

  /**
   * @notice Checks if `_account` is a `MANAGER`
   * @param _account Address of the account to check
   * @return Boolean indicating whether the account has the role
   */
  function isManager(address _account) external view returns (bool) {
    return hasRole(Roles.MANAGER, _account);
  }

  /**
   * @notice Checks if `_account` is a `KEEPER`
   * @param _account Address of the account to check
   * @return Boolean indicating whether the account has the role
   */
  function isKeeper(address _account) external view returns (bool) {
    return hasRole(Roles.KEEPER, _account);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

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

  /**
   * @notice Renounces `_role` (revokes from `msg.sender`)
   * @param _role Role to renounce
   */
  function renounceRole(bytes32 _role) external virtual {
    if (_role == Roles.ADMIN) revert Errors.Unauthorized();
    _revokeRole(_role, msg.sender);
  }

  /**
   * @notice Grants `_role` to `_account`
   * @notice All other roles than KEEPER must be accepted after `ROLE_ACCEPTANCE_TIMELOCK` and before end of validity (`ROLE_ACCEPTANCE_TIMELOCK + ROLE_ACCEPTANCE_VALIDITY`)
   * @param _role Role to grant
   * @param _account Account to grant `_role` to
   */
  function grantRole(
    bytes32 _role,
    address _account
  ) public onlyRole(getRoleAdmin(_role)) {
    require(!hasRole(_role, _account));

    // no acceptance needed for keepers
    if (_role == Roles.KEEPER) {
      return _grantRole(_role, _account);
    }

    pendingAcceptance[_account] = PendingAcceptance({
      // only get replaced if admin (managers can coexist)
      replacing: _role == Roles.ADMIN ? msg.sender : address(0),
      timestamp: uint64(block.timestamp),
      role: _role
    });
  }

  /**
   * @notice Revokes `_role` from `_account`
   * @param _role Role to revoke
   * @param _account Account to revoke `_role` from
   */
  function revokeRole(
    bytes32 _role,
    address _account
  ) public onlyRole(getRoleAdmin(_role)) {
    if (_role == Roles.ADMIN) {
      revert Errors.Unauthorized();
    } // admin role can't renounce as it would brick the contract
    _revokeRole(_role, _account);
  }

  /**
   * @notice Accepts `_role` if an acceptance is pending and not expired
   * @notice Roles must be accepted after `ROLE_ACCEPTANCE_TIMELOCK` and before end of validity (`ROLE_ACCEPTANCE_TIMELOCK + ROLE_ACCEPTANCE_VALIDITY`)
   * @notice If the role is `ADMIN`, by accepting it `msg.sender` will replace the previous admin
   * @param _role Role to accept
   */
  function acceptRole(bytes32 _role) external {
    PendingAcceptance memory acceptance = pendingAcceptance[msg.sender];

    checkRoleAcceptance(acceptance, _role);
    if (acceptance.replacing != address(0)) {
      // if replacing, revoke the old role
      _revokeRole(acceptance.role, acceptance.replacing);
    }
    _grantRole(acceptance.role, msg.sender);
    delete pendingAcceptance[msg.sender];
  }
}
