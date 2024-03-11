// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

interface IAsAccessControl {
    error Unauthorized();

    event RoleAdminChanged(
        bytes32 indexed role,
        bytes32 indexed previousAdminRole,
        bytes32 indexed newAdminRole
    );
    event RoleGranted(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );
    event RoleRevoked(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );

    function DEFAULT_ADMIN_ROLE() external view; // 0x00
    function hasRole(bytes32 _role, address account) external view returns (bool);
    function _checkRole(bytes32 _role) external view;
    function _checkRole(bytes32 _role, address _account) external view;
    function getRoleAdmin(bytes32 _role) external view returns (bytes32);
    function getMembers(bytes32 _role) external view returns (address[] memory);

    function grantRole(bytes32 _role, address _account) external;
    function revokeRole(bytes32 _role, address _account) external;
    function renounceRole(bytes32 _role) external;
    function _setRoleAdmin(bytes32 _role, bytes32 _adminRole) external;
    function _grantRole(bytes32 _role, address _account) external;
    function _revokeRole(bytes32 _role, address _account) external;
}
