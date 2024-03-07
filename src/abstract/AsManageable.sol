// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "./AsAccessControl.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsManageable Abstract - OZ AccessControl+Pausable extension
 * @author Astrolab DAO
 * @notice Abstract contract to manage roles and contract pausing
 * @dev keeper (routine operator/bot), manager (elevated 1) and admin (elevated 2-multisig)
 * roles are defined by default
 */
abstract contract AsManageable is AsAccessControl, Pausable {
  using AsIterableSet for AsIterableSet.Set;

  struct PendingAcceptance {
    bytes32 role; // by default 0x00 == DEFAULT_ADMIN_ROLE
    address replacing;
    uint64 timestamp;
  }

  bytes32 public constant KEEPER_ROLE = keccak256("KEEPER");
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER");
  uint256 public constant TIMELOCK_PERIOD = 2 days;
  uint256 public constant VALIDITY_PERIOD = 7 days;

  mapping(address => PendingAcceptance) public pendingAcceptance;

  // Errors
  error AcceptanceExpired();
  error AcceptanceLocked();

  constructor() {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(MANAGER_ROLE, msg.sender);
    _setRoleAdmin(KEEPER_ROLE, DEFAULT_ADMIN_ROLE);
    _setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
  }

  /**
   * @notice Check if an account has the keeper role
   */
  modifier onlyKeeper() {
    _checkRole(KEEPER_ROLE, msg.sender);
    _;
  }

  /**
   * @notice Check if an account has the manager role
   */
  modifier onlyManager() {
    _checkRole(MANAGER_ROLE, msg.sender);
    _;
  }

  /**
   * @notice Check if an account has the admin role
   */
  modifier onlyAdmin() {
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _;
  }

  /**
   * @notice Grant a role to an account
   * @dev If the role is admin, the account will have to accept the role
   * The acceptance period will expire after TIMELOCK_PERIOD has passed
   * @param role The role to grant
   * @param account The account to grant the role to
   */
  function grantRole(
    bytes32 role,
    address account
  ) public override onlyRole(getRoleAdmin(role)) {
    require(!hasRole(role, account));

    // no acceptance needed for keepers
    if (role == KEEPER_ROLE) {
      return _grantRole(role, account);
    }

    pendingAcceptance[account] = PendingAcceptance({
      // only get replaced if admin (managers can coexist)
      replacing: role == DEFAULT_ADMIN_ROLE ? msg.sender : address(0),
      timestamp: uint64(block.timestamp),
      role: role
    });
  }

  /**
   * @dev Revokes `role` from `account`
   * If `account` had been granted `role`, emits a {RoleRevoked} event
   * Requirements:
   * - the caller must have ``role``'s admin role
   * - admin role can't revoke itself
   * May emit a {RoleRevoked} event
   * @param role The role to revoke
   * @param account The account to revoke the role from
   */
  function revokeRole(
    bytes32 role,
    address account
  ) public override onlyRole(getRoleAdmin(role)) {
    if (role == DEFAULT_ADMIN_ROLE) {
      revert Unauthorized();
    } // admin role can't renounce as it would brick the contract
    _revokeRole(role, account);
  }

  /**
   * @notice Accept an admin role and revoke the old admin
   * @dev If the role is admin or manager, the account will have to accept the role
   * The acceptance will expire after TIMELOCK_PERIOD + VALIDITY_PERIOD has passed
   * Old admin will be revoked and new admin will be granted
   * @param role The role to accept
   */
  function acceptRole(bytes32 role) external {
    PendingAcceptance memory acceptance = pendingAcceptance[msg.sender];

    _checkRoleAcceptance(acceptance, role);
    if (acceptance.replacing != address(0)) {
      // if replacing, revoke the old role
      _revokeRole(acceptance.role, acceptance.replacing);
    }
    _grantRole(acceptance.role, msg.sender);
    delete pendingAcceptance[msg.sender];
  }

  /**
   * @dev Checks the acceptance of a role change
   * @param acceptance The acceptance data containing the role and timestamp
   * @param role The role to check
   */
  function _checkRoleAcceptance(
    PendingAcceptance memory acceptance,
    bytes32 role
  ) private view {
    // make sure the role accepted is the same as the pending one
    if (acceptance.role == role) {
      revert Unauthorized();
    }
    // grant the keeper role instantly (no attack surface here)
    if (acceptance.role == KEEPER_ROLE) return;
    if (block.timestamp > (acceptance.timestamp + TIMELOCK_PERIOD + VALIDITY_PERIOD)) {
      revert AcceptanceExpired();
    }
    if (block.timestamp < (acceptance.timestamp + TIMELOCK_PERIOD)) {
      revert AcceptanceLocked();
    }
  }

  /**
   * @return An array of addresses with the manager role
   */
  function getManagers() external view returns (address[] memory) {
    return getMembers(MANAGER_ROLE);
  }

  /**
   * @return An array of addresses with the keeper role
   */
  function getKeepers() external view returns (address[] memory) {
    return getMembers(KEEPER_ROLE);
  }

  /**
   * @dev Checks if an account has the admin role
   * @param _account The address of the account to check
   * @return A boolean indicating whether the account has the admin role
   */
  function isAdmin(address _account) external view returns (bool) {
    return hasRole(DEFAULT_ADMIN_ROLE, _account);
  }

  /**
   * @dev Checks if an account has the manager role
   * @param _account The address of the account to check
   * @return A boolean indicating whether the account has the manager role
   */
  function isManager(address _account) external view returns (bool) {
    return hasRole(MANAGER_ROLE, _account);
  }

  /**
   * @dev Checks if an account has the keeper role
   * @param _account The address of the account to check
   * @return A boolean indicating whether the account has the keeper role
   */
  function isKeeper(address _account) external view returns (bool) {
    return hasRole(KEEPER_ROLE, _account);
  }
}
