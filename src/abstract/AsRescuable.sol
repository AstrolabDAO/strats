// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Proxy.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsRescuable Abstract - Token rescue extension for payable contracts
 * @author Astrolab DAO
 */
abstract contract AsRescuable {

    struct RescueRequest {
        uint256 timestamp;
        address receiver;
    }

    event RescueRequest(address indexed token, address indexed receiver, uint256 timestamp);
    event Rescue(address indexed token, uint256 amount, address indexed receiver, uint256 timestamp);
    error RescueRequestStale();
    error RescueRequestLocked();

    mapping(address => RescueRequest) public rescueRequests;
    uint256 constant RESCUE_TIMELOCK = 2 days;
    uint256 constant RESCUE_VALIDITY = 7 days;

    // to be overriden with the proper access control by inheriting contracts
    function rescue(address _token) external virtual {}

    // address(1) is used to represent native tokens
    function _rescue(address _token) internal {
        // check if rescue is pending
        RescueRequest req = rescueRequests[_token];
        if (req.timestamp != 0) {
            require(req.receiver == msg.sender);

            // check if 24h passed
            if (block.timestamp > (req.timestamp + RESCUE_TIMELOCK))
                revert RescueRequestLocked();
            if (block.timestamp < (req.timestamp + RESCUE_TIMELOCK + RESCUE_VALIDITY)) // valid until
                revert RescueRequestStale();

            uint256 amount;
            // send to receiver
            if (_token == address(1)) {
                amount = address(this).balance;
                payable(req.receiver).transfer(amount);
            } else {
                amount = IERC20(_token).balanceOf(address(this));
                IERC20(_token).safeTransfer(req.receiver, amount);
            }
            // reset pending rescue
            delete rescueRequests[_token];
            emit Rescue(_token, amount, req.receiver, block.timestamp);
        } else {
            // set pending rescue
            rescueRequests[_token] = RescueRequest({
                receiver: msg.sender,
                timestamp: block.timestamp
            });
            emit RescueRequest(_token, msg.sender, block.timestamp);
        }
        rescueRequests[_token] = RescueRequest({
            receiver: msg.sender,
            timestamp: block.timestamp,
            token: _token
        });
    }

    receive() external payable {} // safe to receive native tokens as rescuable
}
