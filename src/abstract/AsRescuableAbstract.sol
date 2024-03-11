// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsRescuableAbstract - Astrolab's token rescuer for payable contracts
 * @author Astrolab DAO
 */
abstract contract AsRescuableAbstract {

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct RescueRequest {
    uint256 timestamp;
    address receiver;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  uint64 public constant RESCUE_TIMELOCK = 2 days;
  uint64 public constant RESCUE_VALIDITY = 7 days;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  mapping(address => RescueRequest) internal _rescueRequests;
}
