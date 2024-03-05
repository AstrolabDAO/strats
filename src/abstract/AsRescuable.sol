// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./AsRescuableAbstract.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsRescuable Abstract - Token rescue extension for payable contracts
 * @author Astrolab DAO
 */
abstract contract AsRescuable is AsRescuableAbstract {

    using SafeERC20 for IERC20Metadata;

    uint64 public constant RESCUE_TIMELOCK = 2 days;
    uint64 public constant RESCUE_VALIDITY = 7 days;

    /**
     * @dev Checks if a rescue request is locked based on the current timestamp
     * @param req The rescue request to check
     * @return A boolean indicating whether the rescue request is locked
     */
    function _isRescueLocked(RescueRequest memory req) internal view returns (bool) {
        return block.timestamp < (req.timestamp + RESCUE_TIMELOCK);
    }

    /**
     * @dev Checks if a rescue request is stale based on the current timestamp
     * @param req The rescue request to check
     * @return A boolean indicating whether the rescue request is stale
     */
    function _isRescueExpired(RescueRequest memory req) internal view returns (bool) {
        return block.timestamp > (req.timestamp + RESCUE_TIMELOCK + RESCUE_VALIDITY);
    }

    /**
     * @dev Checks if a rescue request is unlocked based on the current timestamp
     * @param req The rescue request to check
     * @return A boolean indicating whether the rescue request is unlocked
     */
    function _isRescueUnlocked(RescueRequest memory req) internal view returns (bool) {
        return !_isRescueExpired(req) && !_isRescueLocked(req);
    }

    /**
     * @dev Requests a rescue for a specific token
     * @param _token The address of the token to be rescued
     */
    function _requestRescue(address _token) internal {
        RescueRequest storage req = rescueRequests[_token];
        require(!_isRescueUnlocked(req));
        // set pending rescue request
        req.receiver = msg.sender;
        req.timestamp = block.timestamp;
        // emit RequestRescue(_token, msg.sender, block.timestamp);
    }

    // to be overriden with the proper access control by inheriting contracts
    function requestRescue(address _token) external virtual {}

    /**
     * @dev Internal function to rescue tokens or native tokens (ETH) from the contract
     * @param _token The address of the token to be rescued. Use address(1) for native tokens (ETH)
     * @notice This function can only be called by the receiver specified in the rescue request
     * @notice The rescue request must be initiated before the rescue timelock expires
     * @notice The rescue request remains valid until the rescue validity period expires
     * @notice If the rescue request is valid, the specified amount of tokens will be transferred to the receiver
     * @notice If the rescue request is not valid, a new rescue request will be set with the caller as the receiver
     * @notice Emits a Rescue event when the rescue is successful
     * @notice Emits a Rescue event when a new rescue request is set
     */
    function _rescue(address _token) internal {
        RescueRequest storage req = rescueRequests[_token];
        // check if rescue is pending
        require(_isRescueUnlocked(req));

        // reset timestamp to prevent reentrancy
        rescueRequests[_token].timestamp = 0;

        // send to receiver
        if (_token == address(1)) {
            (bool ok, ) = payable(req.receiver).call{value: address(this).balance}("");
            require(ok);
        } else {
            IERC20Metadata(_token).safeTransfer(req.receiver, IERC20Metadata(_token).balanceOf(address(this)));
        }
        // reset pending request
        delete rescueRequests[_token];
        // emit Rescue(_token, req.receiver, block.timestamp);
    }

    // to be overriden with the proper access control by inheriting contracts
    function rescue(address _token) external virtual {}
}
