// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@astrolabs/swapper/contracts/interfaces/ISwapper.sol";
import "../interfaces/IWETH9.sol";
import "../interfaces/IStrategyV5.sol";
import "../interfaces/IStrategyV5Agent.sol";
import "./As4626Abstract.sol";
import "../oracles/AsPriceAware.sol";

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
  struct AgentStorage {
    IStrategyV5 delegator;
  }

  struct BaseStorageExt {
    address agent;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             EVENTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  event Invest(uint256 amount, uint256 timestamp);
  event Harvest(uint256 amount, uint256 timestamp);
  event Liquidate(uint256 amount, uint256 liquidityAvailable, uint256 timestamp);

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/
  uint256 internal constant _MAX_INPUTS = 8; // 100% in basis points
  // EIP-7201 keccak256(abi.encode(uint256(keccak256("StrategyV5.agent")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant _AGENT_STORAGE_SLOT =
    0xffe86e2b60bc69a3832641185d195b8ed6fe0e65c6cc390c67dbb9d7cc304300;
  // EIP-7201 keccak256(abi.encode(uint256(keccak256("StrategyV5.ext")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant _EXT_STORAGE_SLOT =
    0x25da31c40a795936c86465edf13c4b2aa77f4e3670b8bdd5625b556504dc9d00;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  // State variables (As4626 extension)
  IWETH9 internal _wgas; // gas/native wrapper contract (immutable set in `init()`)
  ISwapper public swapper; // interface for swapping assets

  IERC20Metadata[8] public inputs; // array of ERC20 tokens used as inputs
  uint8[8] internal _inputDecimals; // strategy inputs decimals
  uint16[8] public inputWeights; // array of input weights weights in basis points (100% = 100_00)
  uint16 internal _totalWeight; // total input weight (max 100%, 100_00bps)
  IERC20Metadata[8] public lpTokens; // array of LP tokens used by inputs
  uint8[8] internal _lpTokenDecimals; // strategy inputs decimals
  address[8] public rewardTokens; // array of reward tokens harvested at compound and liquidate times
  mapping(address => uint256) internal _rewardTokenIndexes; // reward token index by address
  uint8 internal _inputLength; // used length of inputs[] (index of last non-zero element)
  uint8 internal _rewardLength; // used length of rewardTokens[] (index of last non-zero element)

  // NB: DO NOT EXTEND THIS STORAGE, TO PREVENT COLLISION USE `_baseStorage()`

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) As4626Abstract(_accessController) {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return $ Upgradable EIP-7201 agent storage extension slot
   */
  function _agentStorage() internal pure returns (AgentStorage storage $) {
    assembly {
      $.slot := _AGENT_STORAGE_SLOT
    }
  }

  /**
   * @return $ Upgradable EIP-7201 base storage extension slot
   */
  function _baseStorageExt() internal pure returns (BaseStorageExt storage $) {
    assembly {
      $.slot := _EXT_STORAGE_SLOT
    }
  }
}
