// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "../libs/SafeERC20.sol";

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
    using SafeERC20 for IERC20Metadata;
    struct RescueRequest {
        uint256 timestamp;
        address receiver;
    }

    event RequestRescue(
        address indexed token,
        address indexed receiver,
        uint256 timestamp
    );
    event Rescue(
        address indexed token,
        uint256 amount,
        address indexed receiver,
        uint256 timestamp
    );

    error RescueLocked();
    error RescueExpired();
    error RescueAlreadyUnlocked();

    mapping(address => RescueRequest) public rescueRequests;
    uint64 constant RESCUE_TIMELOCK = 2 days;
    uint64 constant RESCUE_VALIDITY = 7 days;

    /**
     * @dev Checks if a rescue request is locked based on the current timestamp.
     * @param req The rescue request to check.
     * @return A boolean indicating whether the rescue request is locked.
     */
    function _isRescueLocked(RescueRequest memory req) internal view returns (bool) {
        return block.timestamp < (req.timestamp + RESCUE_TIMELOCK);
    }

    /**
     * @dev Checks if a rescue request is stale based on the current timestamp.
     * @param req The rescue request to check.
     * @return A boolean indicating whether the rescue request is stale.
     */
    function _isRescueExpired(RescueRequest memory req) internal view returns (bool) {
        return block.timestamp > (req.timestamp + RESCUE_TIMELOCK + RESCUE_VALIDITY);
    }

    /**
     * @dev Checks if a rescue request is unlocked based on the current timestamp.
     * @param req The rescue request to check.
     * @return A boolean indicating whether the rescue request is unlocked.
     */
    function _isRescueUnlocked(RescueRequest memory req) internal view returns (bool) {
        return !_isRescueExpired(req) && !_isRescueLocked(req);
    }

    /**
     * @dev Requests a rescue for a specific token.
     * @param _token The address of the token to be rescued.
     */
    function _requestRescue(address _token) internal {
        RescueRequest memory req = rescueRequests[_token];
        if (_isRescueUnlocked(req)) revert RescueAlreadyUnlocked();
        // set pending rescue request
        req.receiver = msg.sender;
        req.timestamp = block.timestamp;
        emit RequestRescue(_token, msg.sender, block.timestamp);
    }

    // to be overriden with the proper access control by inheriting contracts
    function requestRescue(address _token) external virtual {}

    /**
     * @dev Internal function to rescue tokens or native tokens (ETH) from the contract.
     * @param _token The address of the token to be rescued. Use address(1) for native tokens (ETH).
     * @notice This function can only be called by the receiver specified in the rescue request.
     * @notice The rescue request must be initiated before the rescue timelock expires.
     * @notice The rescue request remains valid until the rescue validity period expires.
     * @notice If the rescue request is valid, the specified amount of tokens will be transferred to the receiver.
     * @notice If the rescue request is not valid, a new rescue request will be set with the caller as the receiver.
     * @notice Emits a Rescue event when the rescue is successful.
     * @notice Emits a Rescue event when a new rescue request is set.
     */
    function _rescue(address _token) internal {
        RescueRequest storage request = rescueRequests[_token];
        // check if rescue is pending
        if (_isRescueLocked(request)) revert RescueLocked();
        if (_isRescueExpired(request)) revert RescueExpired();
            require(request.receiver == msg.sender);

        uint256 amount;
        // send to receiver
        if (_token == address(1)) {
            amount = address(this).balance;
            payable(request.receiver).transfer(amount);
        } else {
            amount = IERC20Metadata(_token).balanceOf(address(this));
            IERC20Metadata(_token).safeTransfer(request.receiver, amount);
        }
        // reset pending request
        // delete rescueRequests[_token];
        request.timestamp = 0;
        emit Rescue(_token, amount, request.receiver, block.timestamp);
    }

    // to be overriden with the proper access control by inheriting contracts
    function rescue(address _token) external virtual {}
}
