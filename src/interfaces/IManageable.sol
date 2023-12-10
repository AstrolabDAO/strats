// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/IAccessControl.sol";

interface IPausable {
    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() external view returns (bool);
}

interface IManageable is IAccessControl, IPausable{
    /**
     * @notice Grants a role to an account
     * @param role The role to be granted
     * @param account The account to which the role will be granted
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @notice Renounces a role from the calling account
     * @param role The role to be renounced
     * @param caller The address confirming the renunciation
     */
    function renounceRole(bytes32 role, address caller) external;

    /**
     * @notice Revokes a role from an account
     * @param role The role to be revoked
     * @param account The account from which the role will be revoked
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @notice Accepts a pending role
     * @param role The role to be accepted
     */
    function acceptRole(bytes32 role) external;

    // View functions for public state variables
    function KEEPER_ROLE() external view returns (bytes32);
    function MANAGER_ROLE() external view returns (bytes32);
    function PENDING_PERIOD() external view returns (uint256);
    function GRACE_PERIOD() external view returns (uint256);
    function pendingChange(address account) external view returns (bytes32 role, address replacing, uint256 timestamp);
}
