// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./AsAccessControl.sol";

/**            _             _       _
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
    using AsSequentialSet for AsSequentialSet.Set;

    struct PendingRoleChange {
        bytes32 role; // by default 0x00 == DEFAULT_ADMIN_ROLE
        address replacing;
        uint256 timestamp;
    }

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER");
    uint256 private constant PENDING_PERIOD = 2 days;
    uint256 private constant GRACE_PERIOD = 7 days;

    mapping(address => PendingRoleChange) public pendingChange;

    // Errors
    error GracePeriodElapsed(uint256 graceTimestamp);
    error PendingPeriodNotElapsed(uint256 pendingTimestamp);

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
     *
     * @dev If the role is admin, the account will have to accept the role
     * The request will expire after PENDING_PERIOD has passed
     */
    function grantRole(
        bytes32 role,
        address account
    )
        public
        override
        onlyRole(getRoleAdmin(role))
    {
        if (role == DEFAULT_ADMIN_ROLE || role == MANAGER_ROLE) {
            pendingChange[account] = PendingRoleChange({
                // only get replaced if admin, managers can coexist
                replacing: role == DEFAULT_ADMIN_ROLE
                    ? msg.sender
                    : address(0),
                timestamp: block.timestamp,
                role: role
            });
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
        address caller
    ) public override {
        if (caller != msg.sender)
            revert RoleChangeError();
        if (role == DEFAULT_ADMIN_ROLE) revert Unauthorized();
        _revokeRole(role, caller);
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
        override
        onlyRole(getRoleAdmin(role))
    {
        if ((role == DEFAULT_ADMIN_ROLE) && account == msg.sender) {
            revert Unauthorized();
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
    function acceptRole(bytes32 role) external {
        PendingRoleChange memory request = pendingChange[msg.sender];

        _validateRoleAcceptance(request);
        if (request.replacing != address(0)) {
            // if replacing, revoke the old role
            _revokeRole(request.role, request.replacing);
        }
        _grantRole(role, msg.sender);
        delete pendingChange[msg.sender];
    }

    function _validateRoleAcceptance(
        PendingRoleChange memory request
    ) private view {
        // grant the keeper role instantly (no attack surface here)
        if (request.role == KEEPER_ROLE) return;
        if (block.timestamp > request.timestamp + PENDING_PERIOD + GRACE_PERIOD)
            // shields from default timestamp(0)
            revert GracePeriodElapsed(
                request.timestamp + PENDING_PERIOD + GRACE_PERIOD
            );
        if (block.timestamp < request.timestamp + PENDING_PERIOD)
            revert PendingPeriodNotElapsed(request.timestamp + PENDING_PERIOD);
    }

    function getManagers() external view returns (address[] memory) {
        return getMembers(MANAGER_ROLE);
    }

    function getKeepers() external view returns (address[] memory) {
        return getMembers(KEEPER_ROLE);
    }
}
