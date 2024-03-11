// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../libs/AsIterableSet.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsAccessControlAbstract - Astrolab's access controller
 * @author Astrolab DAO
 * @notice Inspired by OZ's AccessControlEnumerable, used for RBAC and contract pausing
 */
abstract contract AsAccessControlAbstract {

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct RoleState {
    AsIterableSet.Set members;
    bytes32 adminRole;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             ERRORS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  error Unauthorized();

  /*═══════════════════════════════════════════════════════════════╗
  ║                             EVENTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  event RoleAdminChanged(
    bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole
  );
  event RoleGranted(
    bytes32 indexed role, address indexed account, address indexed sender
  );
  event RoleRevoked(
    bytes32 indexed role, address indexed account, address indexed sender
  );

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  mapping(bytes32 => RoleState) internal _roles;

  /*═══════════════════════════════════════════════════════════════╗
  ║                           MODIFIERS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  modifier onlyRole(bytes32 role) virtual { revert(); _; }
}
