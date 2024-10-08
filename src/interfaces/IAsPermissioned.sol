// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/IAccessController.sol";

interface IAsPermissioned {
  function ac() external view returns (IAccessController);
}
