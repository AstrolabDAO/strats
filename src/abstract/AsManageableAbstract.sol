// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "./AsAccessControlAbstract.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsManageableAbstract - Lighter OZ AccessControlEnumerable+Pausable extension
 * @author Astrolab DAO
 * @notice Abstract contract to manage roles and contract pausing
 * @notice Default roles are KEEPER (operator/bot), MANAGER (elevated DAO member) and ADMIN (elevated DAO council multisig)
 */
abstract contract AsManageableAbstract is AsAccessControlAbstract {

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  uint256 private _status; // OZ's ReentrancyGuard slot
  bool private _paused; // OZ's Pausable slot
  mapping(address => bytes) public pendingAcceptance;

  /*═══════════════════════════════════════════════════════════════╗
  ║                           MODIFIERS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  modifier whenNotPaused() virtual { _; }
  modifier nonReentrant() virtual { _; }
  modifier onlyKeeper() virtual { _; }
  modifier onlyManager() virtual { _; }
  modifier onlyAdmin() virtual { _; }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  function paused() public view virtual returns (bool) { return _paused; }
  function pause() public virtual {}
  function unpause() public virtual {}
}
