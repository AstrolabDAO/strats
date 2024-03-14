// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/proxy/Proxy.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsProxy Abstract - Astrolab's EIP-897 base proxy
 * @author Astrolab DAO
 * @notice OZ's Proxy extension to manage call delegation
 * @dev Make sure to make proxy/implementation storage slots match when used as UUPS / transparent proxy
 * @dev Extending contracts should implement the ERC-897 `initialized()` and `implementation()` functions
 */
abstract contract AsProxy is Proxy {
  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Delegates a call to `_implementation` contract using function `_selector` and `_data` encoded parameters
   * @param _implementation Address of the implementation contract
   * @param _selector Function selector to delegate to (4 first bytes of `keccak(signature)`)
   * @param _data Encoded parameters to pass to the function
   */
  function _delegateToSelector(
    address _implementation,
    bytes4 _selector,
    bytes calldata _data
  ) internal returns (bool success, bytes memory result) {
    return _implementation.delegatecall(
      abi.encodeWithSelector(_selector, _data)
    );
  }

  /**
   * @notice Delegates a call `_implementation`'s contract using function `_selector` and `_data` memory encoded parameters
   * @param _implementation Address of the implementation contract
   * @param _selector Function selector to delegate to (4 first bytes of `keccak(signature)`)
   * @param _data Encoded parameters to pass to the function
   */
  function _delegateToSelectorMemory(
    address _implementation,
    bytes4 _selector,
    bytes memory _data
  ) internal returns (bool success, bytes memory result) {
    return _implementation.delegatecall(
      abi.encodeWithSelector(_selector, _data)
    );
  }
  // to match with the payable fallback (not necessary but pleases compiler)

  receive() external payable {}
}
