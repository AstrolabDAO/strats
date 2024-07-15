// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./IAccessController.sol";
import "./IPausable.sol";

interface IAsManageable is IAccessController, IPausable {
  function isAdmin(address _account) external view returns (bool);
  function isManager(address _account) external view returns (bool);
  function isKeeper(address _account) external view returns (bool);

  function ROLE_ACCEPTANCE_TIMELOCK() external view returns (uint256);
  function ROLE_ACCEPTANCE_VALIDITY() external view returns (uint256);
  function pendingChange(address account)
    external
    view
    returns (bytes32 role, address replacing, uint256 timestamp);
}
