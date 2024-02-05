// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsRescuableAbstract - Token rescue extension for payable contracts
 * @author Astrolab DAO
 */
abstract contract AsRescuableAbstract {
    struct RescueRequest {
        uint256 timestamp;
        address receiver;
    }
    mapping(address => RescueRequest) internal rescueRequests;
}
