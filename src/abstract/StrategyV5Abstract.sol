// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@astrolabs/swapper/contracts/interfaces/ISwapper.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IWETH9.sol";
import "../interfaces/IStrategyV5.sol";
import "./As4626Abstract.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title StrategyV5 - Astrolab's base Strategy to be extended by implementations
 * @author Astrolab DAO
 * @notice Common strategy back-end extended by implementations, delegating vault logic to StrategyV5Agent
 * @dev All state variables must be here to match the proxy base storage layout (StrategyV5)
 */
abstract contract StrategyV5Abstract is As4626Abstract {

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  // Upgradable strategy agent's storage struct
  struct AgentStorageExt {
    IStrategyV5 delegator;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             ERRORS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  error InvalidOrStaleValue(uint256 updateTime, int256 value);

  /*═══════════════════════════════════════════════════════════════╗
  ║                             EVENTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  event Invest(uint256 amount, uint256 timestamp);
  event Harvest(uint256 amount, uint256 timestamp);
  event Liquidate(uint256 amount, uint256 liquidityAvailable, uint256 timestamp);

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  // Upgrade dedicated storage to prevent collisions (EIP-7201)
  // keccak256(abi.encode(uint256(keccak256("strategy.agent")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 internal constant _AGENT_STORAGE_EXT_SLOT = 0x821ff15c18486d780e69cedd37d14f117c16526e6b0b6969fd23bc9dd7ffc900;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  // State variables (As4626 extension)
  IWETH9 internal _wgas; // gas/native wrapper contract (immutable set in `init()`)
  ISwapper public swapper; // interface for swapping assets
  IStrategyV5 public agent; // strategy agent contract

  IERC20Metadata[8] public inputs; // array of ERC20 tokens used as inputs
  uint8[8] internal _inputDecimals; // strategy inputs decimals
  uint16[8] public inputWeights; // array of input weights weights in basis points (100% = 100_00)
  address[8] public rewardTokens; // array of reward tokens harvested at compound and liquidate times
  mapping(address => uint256) internal _rewardTokenIndexes; // reward token index by address
  uint8 internal _inputLength; // used length of inputs[] (index of last non-zero element)
  uint8 internal _rewardLength; // used length of rewardTokens[] (index of last non-zero element)

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor() As4626Abstract() {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return $ Upgradable agent storage extension slot
   */
  function _agentStorageExt() internal pure returns (AgentStorageExt storage $) {
    assembly { $.slot := _AGENT_STORAGE_EXT_SLOT }
  }

  /**
   * @notice Calculates the total pending redemption requests in shares
   * @dev Returns the difference between _req.totalRedemption and _req.totalClaimableRedemption
   * @return The total amount of pending redemption requests
   */
  function totalPendingRedemptionRequest() public view returns (uint256) {
    return _req.totalRedemption - _req.totalClaimableRedemption;
  }

  /**
   * @notice Calculates the total pending asset requests based on redemption requests
   * @dev Converts the total pending redemption requests to their asset asset value for precision
   * @return The total amount of asset assets requested pending redemption
   */
  function totalPendingAssetRequest() public view returns (uint256) {
    return convertToAssets(totalPendingRedemptionRequest(), false);
  }
}
