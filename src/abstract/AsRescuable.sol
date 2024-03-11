// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./AsRescuableAbstract.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsRescuable Abstract - Astrolab's token rescuer for payable contracts
 * @author Astrolab DAO
 */
contract AsRescuable is AsRescuableAbstract {
  using SafeERC20 for IERC20Metadata;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Checks if a rescue request `_req` is locked based on the current timestamp
   * @param _req Rescue request to check
   * @return Boolean indicating whether `_req` is locked
   */
  function _isRescueLocked(RescueRequest memory _req) internal view returns (bool) {
    return block.timestamp < (_req.timestamp + RESCUE_TIMELOCK);
  }

  /**
   * @notice Checks if a rescue request `_req` is stale based on the current timestamp
   * @param _req Rescue request to check
   * @return Boolean indicating whether `_req` is stale
   */
  function _isRescueExpired(RescueRequest memory _req) internal view returns (bool) {
    return block.timestamp > (_req.timestamp + RESCUE_TIMELOCK + RESCUE_VALIDITY);
  }

  /**
   * @notice Checks if a rescue request `_req` is unlocked based on the current timestamp
   * @param _req Rescue request to check
   * @return Boolean indicating whether `_req` is unlocked
   */
  function _isRescueUnlocked(RescueRequest memory _req) internal view returns (bool) {
    return !_isRescueExpired(_req) && !_isRescueLocked(_req);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Requests a rescue for `_token`, setting `msg.sender` as the receiver
   * @param _token Token to be rescued - Use address(1) for native/gas tokens (ETH)
   */
  function _requestRescue(address _token) internal {
    RescueRequest storage _req = _rescueRequests[_token];
    require(!_isRescueUnlocked(_req));
    // set pending rescue request
    _req.receiver = msg.sender;
    _req.timestamp = block.timestamp;
  }

  /**
   * @notice Requests a rescue for `_token`, setting `msg.sender` as the receiver
   * @param _token Token to be rescued - Use address(1) for native/gas tokens (ETH)
   * @dev This should be overriden with the proper access control by inheriting contracts
   */
  function requestRescue(address _token) external virtual {}

  /**
   * @notice Rescues the contract's `_token` (ERC20 or native) full balance by sending it to `req.receiver`if a valid rescue request exists
   * @notice Rescue request must be executed after `RESCUE_TIMELOCK` and before end of validity (`RESCUE_TIMELOCK + RESCUE_VALIDITY`)
   * @param _token Token to be rescued - Use address(1) for native/gas tokens (ETH)
   */
  function _rescue(address _token) internal {
    RescueRequest storage req = _rescueRequests[_token];
    // check if rescue is pending
    require(_isRescueUnlocked(req));

    // reset timestamp to prevent reentrancy
    _rescueRequests[_token].timestamp = 0;

    // send to receiver
    if (_token == address(1)) {
      (bool ok,) = payable(req.receiver).call{value: address(this).balance}("");
      require(ok);
    } else {
      IERC20Metadata(_token).safeTransfer(
        req.receiver, IERC20Metadata(_token).balanceOf(address(this))
      );
    }
    // reset pending request
    delete _rescueRequests[_token];
  }

  /**
   * @notice Rescues the contract's `_token` (ERC20 or native) full balance by sending it to `req.receiver`if a valid rescue request exists
   * @notice Rescue request must be executed after `RESCUE_TIMELOCK` and before end of validity (`RESCUE_TIMELOCK + RESCUE_VALIDITY`)
   * @param _token Token to be rescued - Use address(1) for native/gas tokens (ETH)
   * @dev This should be overriden with the proper access control by inheriting contracts
   */
  function rescue(address _token) external virtual {}
}
