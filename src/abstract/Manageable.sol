// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title Manageable Abstract - OZ AccessControlEnumerable+Pausable extension
 * @author Astrolab DAO
 * @notice Abstract contract to manage roles and contract pausing
 * @dev keeper (routine operator/bot), manager (elevated 1) and admin (elevated 2-multisig)
  * roles are defined by default
 */
abstract contract Manageable is AccessControlEnumerable, Pausable {
	struct Pending {
		address oldAdmin;
		address newAdmin;
		uint256 timestamp;
	}

	// The keeper role can be used to perform automated maintenance
	bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
	// The manager role can be used to perform manual maintenance
	bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
	// The pending period is the time that the new admin has to wait to accept the role
	uint256 private constant PENDING_PERIOD = 2 days;
	// The grace period is the time that the grantee has to accept the role
	uint256 private constant GRACE_PERIOD = 7 days;

	Pending public pending;

	error AdminCantRenounce();
	error AdminRoleError();
	error GracePeriodElapsed(uint256 _graceTimestamp);
	error PendingPeriodNotElapsed(uint256 _pendingTimestamp);

	constructor() {
		// We give the admin role to the account that deploys the contract
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
		// We set the role hierarchy
		_setRoleAdmin(KEEPER_ROLE, DEFAULT_ADMIN_ROLE);
		_setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
	}

	/**
	 * @notice Check if an account has the keeper role
	 */
	modifier onlyKeeper() {
		_checkRole(KEEPER_ROLE, _msgSender());
		_;
	}

	/**
	 * @notice Check if an account has the manager role
	 */
	modifier onlyManager() {
		_checkRole(MANAGER_ROLE, _msgSender());
		_;
	}

	/**
	 * @notice Check if an account has the admin role
	 */
	modifier onlyAdmin() {
		_checkRole(DEFAULT_ADMIN_ROLE, _msgSender());
		_;
	}

	/**
	 * @notice Grant a role to an account
	 *
	 * @dev If the role is admin, the account will have to accept the role
	 * The request will expire after PENDING_PERIOD has passed
	 */
	function grantRole(
		bytes32 role,
		address account
	)
		public
		override(AccessControl, IAccessControl)
		onlyRole(getRoleAdmin(role))
	{
		// If the role is admin, we need an additionnal step to accept the role
		if (role == DEFAULT_ADMIN_ROLE) {
			pending = Pending(msg.sender, account, block.timestamp);
		} else {
			_grantRole(role, account);
		}
	}

	/**
	 * @notice Revokes `role` from the calling account.
	 *
	 * @dev Roles are often managed via {grantRole} and {revokeRole}: this function's
	 * purpose is to provide a mechanism for accounts to lose their privileges
	 * if they are compromised (such as when a trusted device is misplaced).
	 *
	 * To avoid bricking the contract, admin role can't be renounced.
	 * If needed, the admin can grant the role to another account and then revoke the former.
	 */

	function renounceRole(
		bytes32 role,
		address callerConfirmation
	) public override(AccessControl, IAccessControl) {

		require (callerConfirmation == _msgSender(), "Forbidden");
		if (role == DEFAULT_ADMIN_ROLE) revert AdminCantRenounce();

		_revokeRole(role, callerConfirmation);
	}

	/**
	 * @dev Revokes `role` from `account`.
	 *
	 * If `account` had been granted `role`, emits a {RoleRevoked} event.
	 *
	 * Requirements:
	 *
	 * - the caller must have ``role``'s admin role.
	 * - admin role can't revoke itself
	 *
	 * May emit a {RoleRevoked} event.
	 */
	function revokeRole(
		bytes32 role,
		address account
	)
		public
		override(AccessControl, IAccessControl)
		onlyRole(getRoleAdmin(role))
	{
		if (role == DEFAULT_ADMIN_ROLE && account == msg.sender) {
			revert AdminCantRenounce();
		}

		_revokeRole(role, account);
	}

	/**
	 * @notice Accept an admin role and revoke the old admin
	 *
	 * @dev If the role is admin or manager, the account will have to accept the role
	 * The request will expire after PENDING_PERIOD + GRACE_PERIOD has passed
	 * Old admin will be revoked and new admin will be granted
	 */
	function acceptAdminRole() external {
		Pending memory request = pending;

		// Role has to be accepted by the new admin
		if (request.newAdmin != msg.sender) revert AdminRoleError();

		// Acceptance must be done before the grace period is over
		if (block.timestamp > request.timestamp + PENDING_PERIOD + GRACE_PERIOD)
			revert GracePeriodElapsed(
				request.timestamp + PENDING_PERIOD + GRACE_PERIOD
			);

		// Acceptance must be done after the pending period is over
		if (block.timestamp < request.timestamp + PENDING_PERIOD)
			revert PendingPeriodNotElapsed(request.timestamp + PENDING_PERIOD);
		// We revoke the old admin and grant the new one
		_revokeRole(DEFAULT_ADMIN_ROLE, request.oldAdmin);
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
		delete pending;
	}
}
