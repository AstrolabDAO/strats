// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IAccessController.sol";
import "./AsPermissioned.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsManageable Abstract - Lighter OZ AccessControlEnumerable+Pausable extension
 * @author Astrolab DAO
 * @notice Abstract contract to check roles against AccessController and contract pausing
 */
contract AsManageable is AsPermissioned, Pausable, ReentrancyGuard {
  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) AsPermissioned(_accessController) {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                        PAUSING LOGIC                           ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Unpauses the contract, resuming all operations
   */
  function unpause() public onlyAdmin {
    _unpause();
  }

  /**
   * @notice Pauses the contract, partially freezing operations
   */
  function pause() public onlyAdmin {
    _pause();
  }
}
