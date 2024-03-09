// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title NoDelegate - Astrolab's delegatecall blocker
 * @author Astrolab DAO
 * @notice Provides a modifier for preventing delegatecalls, inspired by Uniswap and Gnosis's implementations
 */
abstract contract NoDelegate {
  address private immutable root;

  /**
   * @notice Initializes the root address
   */
  constructor() {
    // Immutables are computed in the init code of the contract, and then inlined into the deployed bytecode
    // In other words, this variable won't change when it's checked at runtime
    root = address(this);
  }

  /**
   * @notice Ensures that the executing contract is `root` and not another contract
   */
  function checkNotDelegate() private view {
    require(address(this) == root);
  }

  /**
   * @notice Prevents delegatecall into the modified method
   */
  modifier noDelegate() {
    checkNotDelegate();
    _;
  }
}
