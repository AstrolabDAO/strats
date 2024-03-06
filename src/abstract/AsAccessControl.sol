// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "../libs/AsCast.sol";
import "../libs/AsIterableSet.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsAccessControl - Lighter OZ AccessControlEnumerable
 * @author Astrolab DAO
 * @notice Abstract contract to manage roles and contract pausing
 * @dev keeper (routine operator/bot), manager (elevated 1) and admin (elevated 2-multisig)
 * roles are defined by default
 */
abstract contract AsAccessControl {
    using AsIterableSet for AsIterableSet.Set;
    using AsCast for bytes32;
    using AsCast for address;

    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    error Unauthorized();

    struct RoleState {
        AsIterableSet.Set members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleState) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Modifier to check if the caller has a specific role
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    /**
     * @dev Checks if an account has a specific role
     * @param role The role to check
     * @param account The account to check
     * @return True if the account has the role, false otherwise
     */
    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return _roles[role].members.has(account.toBytes32());
    }

    /**
     * @dev Internal function to check if the sender has a specific role
     * @param role The role to check
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, msg.sender);
    }

    /**
     * @dev Internal function to check if an account has a specific role
     * @param role The role to check
     * @param account The account to check
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) revert Unauthorized();
    }

    /**
     * @dev Get the admin role of a specific role
     * @param role The role to query the admin role of
     * @return The admin role of the queried role
     */
    function getRoleAdmin(bytes32 role) public view virtual returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants a role to an account
     * @param role The role to grant
     * @param account The account to grant the role to
     */
    function grantRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes a role from an account
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    function revokeRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev Renounce a role for the sender account
     * @param role The role to renounce
     * @param account The account renouncing the role
     */
    function renounceRole(bytes32 role, address account) external virtual {
        if (account != msg.sender) revert Unauthorized();
        _revokeRole(role, account);
    }

    /**
     * @dev Internal function to set up a role for an account
     * @param role The role to set up
     * @param account The account to set up the role for
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Internal function to set the admin role for a given role
     * @param role The role to set the admin role of
     * @param adminRole The admin role to be set
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        RoleState storage _role = _roles[role];
        bytes32 previousAdminRole = _role.adminRole;
        _role.adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @dev Internal function to grant a role to an account
     * @param role The role to grant
     * @param account The account to grant the role to
     */
    function _grantRole(bytes32 role, address account) internal virtual {
        RoleState storage _role = _roles[role];
        bytes32 accSig = account.toBytes32();
        if (!_role.members.has(accSig)) {
            _role.members.push(accSig);
            emit RoleGranted(role, account, msg.sender);
        }
    }

    /**
     * @dev Internal function to revoke a role from an account
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        RoleState storage _role = _roles[role];
        bytes32 accSig = account.toBytes32();
        if (_role.members.has(accSig)) {
            _role.members.remove(accSig);
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    /**
     * @dev Gets the members of a specific role
     * @param role The role to get members of
     * @return An array of addresses who are members of the role
     */
    function getMembers(bytes32 role) public view virtual returns (address[] memory) {
        return _roles[role].members.valuesAsAddress();
    }
}
