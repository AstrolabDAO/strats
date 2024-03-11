// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AsAccessControl.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsManageable Abstract - Lighter OZ AccessControlEnumerable+Pausable extension
 * @author Astrolab DAO
 * @notice Abstract contract to manage roles and contract pausing
 * @notice Default roles are KEEPER (operator/bot), MANAGER (elevated DAO member) and ADMIN (elevated DAO council multisig)
 */
contract AsManageable is AsAccessControl, Pausable, ReentrancyGuard {
  using AsIterableSet for AsIterableSet.Set;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct PendingAcceptance {
    bytes32 role; // by default 0x00 == DEFAULT_ADMIN_ROLE
    address replacing;
    uint64 timestamp;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             ERRORS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  error AcceptanceExpired();
  error AcceptanceLocked();

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  bytes32 public constant KEEPER_ROLE = keccak256("KEEPER");
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER");
  uint256 public constant ROLE_ACCEPTANCE_TIMELOCK = 2 days;
  uint256 public constant ROLE_ACCEPTANCE_VALIDITY = 7 days;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  mapping(address => PendingAcceptance) public pendingAcceptance;

  /*═══════════════════════════════════════════════════════════════╗
  ║                           MODIFIERS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Checks if an account has the keeper role
   */
  modifier onlyKeeper() {
    _checkRole(KEEPER_ROLE, msg.sender);
    _;
  }

  /**
   * @notice Checks if an account has the manager role
   */
  modifier onlyManager() {
    _checkRole(MANAGER_ROLE, msg.sender);
    _;
  }

  /**
   * @notice Checks if an account has the admin role
   */
  modifier onlyAdmin() {
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor() {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(MANAGER_ROLE, msg.sender);
    _setRoleAdmin(KEEPER_ROLE, DEFAULT_ADMIN_ROLE);
    _setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Checks `_acceptance` state for a pending `_role` change
   * @param _acceptance Acceptance data containing a granted role and creation timestamp
   * @param _role Role to check
   */
  function _checkRoleAcceptance(
    PendingAcceptance memory _acceptance,
    bytes32 _role
  ) private view {
    // make sure the role accepted is the same as the pending one
    if (_acceptance.role != _role) {
      revert Unauthorized();
    }
    // grant the keeper role instantly (no attack surface here)
    if (_acceptance.role == KEEPER_ROLE) return;
    if (block.timestamp > (_acceptance.timestamp + ROLE_ACCEPTANCE_TIMELOCK + ROLE_ACCEPTANCE_VALIDITY)) {
      revert AcceptanceExpired();
    }
    if (block.timestamp < (_acceptance.timestamp + ROLE_ACCEPTANCE_TIMELOCK)) {
      revert AcceptanceLocked();
    }
  }

  /**
   * @return Array of `MANAGER` addresses
   */
  function getManagers() external view returns (address[] memory) {
    return getMembers(MANAGER_ROLE);
  }

  /**
   * @return Array of `KEEPER` addresses
   */
  function getKeepers() external view returns (address[] memory) {
    return getMembers(KEEPER_ROLE);
  }

  /**
   * @notice Checks if `_account` is an `ADMIN`
   * @param _account Address of the account to check
   * @return Boolean indicating whether the account has the role
   */
  function isAdmin(address _account) external view returns (bool) {
    return hasRole(DEFAULT_ADMIN_ROLE, _account);
  }

  /**
   * @notice Checks if `_account` is a `MANAGER`
   * @param _account Address of the account to check
   * @return Boolean indicating whether the account has the role
   */
  function isManager(address _account) external view returns (bool) {
    return hasRole(MANAGER_ROLE, _account);
  }

  /**
   * @notice Checks if `_account` is a `KEEPER`
   * @param _account Address of the account to check
   * @return Boolean indicating whether the account has the role
   */
  function isKeeper(address _account) external view returns (bool) {
    return hasRole(KEEPER_ROLE, _account);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Pauses the vault
   */
  function pause() public onlyAdmin {
    _pause();
  }

  /**
   * @notice Unpauses the vault
   */
  function unpause() public onlyAdmin {
    _unpause();
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
  ) public override onlyRole(getRoleAdmin(_role)) {
    require(!hasRole(_role, _account));

    // no acceptance needed for keepers
    if (_role == KEEPER_ROLE) {
      return _grantRole(_role, _account);
    }

    pendingAcceptance[_account] = PendingAcceptance({
      // only get replaced if admin (managers can coexist)
      replacing: _role == DEFAULT_ADMIN_ROLE ? msg.sender : address(0),
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
  ) public override onlyRole(getRoleAdmin(_role)) {
    if (_role == DEFAULT_ADMIN_ROLE) {
      revert Unauthorized();
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

    _checkRoleAcceptance(acceptance, _role);
    if (acceptance.replacing != address(0)) {
      // if replacing, revoke the old role
      _revokeRole(acceptance.role, acceptance.replacing);
    }
    _grantRole(acceptance.role, msg.sender);
    delete pendingAcceptance[msg.sender];
  }
}
