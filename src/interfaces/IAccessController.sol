// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IAccessController {
  event RoleAdminChanged(
    bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole
  );
  event RoleGranted(
    bytes32 indexed role, address indexed account, address indexed sender
  );
  event RoleRevoked(
    bytes32 indexed role, address indexed account, address indexed sender
  );

  function hasRole(bytes32 _role, address account) external view returns (bool);
  function checkRole(bytes32 _role) external view;
  function checkRole(bytes32 _role, address _account) external view;
  function getRoleAdmin(bytes32 _role) external view returns (bytes32);
  function getMembers(bytes32 _role) external view returns (address[] memory);
  function getManagers() external view returns (address[] memory);
  function getKeepers() external view returns (address[] memory);
  function isAdmin(address _account) external view returns (bool);
  function isManager(address _account) external view returns (bool);
  function isKeeper(address _account) external view returns (bool);
  function renounceRole(bytes32 _role) external;
  function grantRole(bytes32 _role, address _account) external;
  function revokeRole(bytes32 _role, address _account) external;
  function acceptRole(bytes32 _role) external;
}
