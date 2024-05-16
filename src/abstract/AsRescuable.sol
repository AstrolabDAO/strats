// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./AsPermissioned.sol";

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
abstract contract AsRescuable is AsPermissioned {
  using SafeERC20 for IERC20Metadata;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct RescueRequest {
    uint64 timestamp;
    address receiver;
  }

  struct RescuableStorage {
    mapping(address => RescueRequest) rescueRequests;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  uint64 public constant RESCUE_TIMELOCK = 2 days;
  uint64 public constant RESCUE_VALIDITY = 7 days;

  // EIP-7201 keccak256(abi.encode(uint256(keccak256("AsRescuable.main")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant _STORAGE_SLOT =
    0xcdc3586352dd8d1c1f612724c6bc83986aa6f0f0cfc9ed7d016fc5daa15d1400;

  /*═══════════════════════════════════════════════════════════════╗
  ║                          INITIALIZERS                          ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor() {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return $ Upgradable EIP-7201 storage slot
   */
  function _rescuableRescuableStorage()
    internal
    pure
    returns (RescuableStorage storage $)
  {
    assembly {
      $.slot := _STORAGE_SLOT
    }
  }

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
    RescueRequest storage req = _rescuableRescuableStorage().rescueRequests[_token];
    require(!_isRescueUnlocked(req));
    // set pending rescue request
    req.receiver = msg.sender;
    req.timestamp = uint64(block.timestamp);
  }

  /**
   * @notice Requests a rescue for `_token`, setting `msg.sender` as the receiver
   * @param _token Token to be rescued - Use address(1) for native/gas tokens (ETH)
   * @dev This should be overriden with the proper access control by inheriting contracts
   */
  function requestRescue(address _token) external onlyAdmin {
    _requestRescue(_token);
  }

  /**
   * @notice Rescues the contract's `_token` (ERC20 or native) full balance by sending it to `req.receiver`if a valid rescue request exists
   * @notice Rescue request must be executed after `RESCUE_TIMELOCK` and before end of validity (`RESCUE_TIMELOCK + RESCUE_VALIDITY`)
   * @param _token Token to be rescued - Use address(1) for native/gas tokens (ETH)
   */
  function _rescue(address _token) internal {
    RescuableStorage storage $ = _rescuableRescuableStorage();
    RescueRequest storage req = $.rescueRequests[_token];

    // check if rescue is pending
    require(_isRescueUnlocked(req));

    // reset timestamp to prevent reentrancy
    req.timestamp = 0;

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
    delete $.rescueRequests[_token];
  }

  /**
   * @notice Rescues the contract's `_token` (ERC20 or native) full balance by sending it to `req.receiver`if a valid rescue request exists
   * @notice Rescue request must be executed after `RESCUE_TIMELOCK` and before end of validity (`RESCUE_TIMELOCK + RESCUE_VALIDITY`)
   * @param _token Token to be rescued - Use address(1) for native/gas tokens (ETH)
   * @dev This should be overriden with the proper access control by inheriting contracts
   */
  function rescue(address _token) external onlyManager {
    _rescue(_token);
  }
}
