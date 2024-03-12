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
    /// @solidity memory-safe-assembly
    assembly {
      _selector := and(_selector, 0xffffffff) // clear selector bytes after 4
      let ptr := mload(0x40) // get free ptr
      mstore(ptr, _selector) // store selector first
      calldatacopy(add(ptr, 0x4), _data.offset, _data.length) // copy _data after the selector
      mstore(0x40, add(ptr, _data.length)) // update free ptr
      success :=
        delegatecall(
          gas(),
          _implementation, // implementation address
          ptr, // inputs
          _data.length, // input size
          0, // output location
          0 // output size
        )
      let size := returndatasize() // return data size
      ptr := mload(0x40) // free ptr
      mstore(ptr, size) // store the size of the return data
      returndatacopy(add(ptr, 0x20), 0, size) // copy the return data after the size
      mstore(0x40, add(ptr, add(size, 0x20))) // update the free memory pointer
      switch success
      case 0 { revert(ptr, size) }
      default { result := ptr }
    }
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
    /// @solidity memory-safe-assembly
    assembly {
      _selector := and(_selector, 0xffffffff) // clear selector bytes after 4
      let ptr := mload(0x40) // get free ptr
      mstore(ptr, _selector) // store selector first
      // mstore(add(ptr, 0x4), add(_data, 0x20)) // store the actual data location
      // let size := mload(_data) // load the _data size
      for { let i := 0x20 } lt(i, mload(_data)) { i := add(i, 0x20) } {
          // Copy the input data after the selector
          mstore(add(ptr, i), mload(add(_data, i)))
      }

      let size := add(mload(_data), 0x4) // Calculate the total input size (selector + data size)

      success :=
        delegatecall(
          gas(),
          _implementation, // implementation address
          ptr, // inputs stored at callData + 0x4 (data pointer slot)
          size, // input size (data pointer + data size)
          0, // output location
          0 // output size
        )
      size := returndatasize() // return data size
      ptr := mload(0x40) // free ptr
      mstore(ptr, size) // store the size of the return data
      returndatacopy(add(ptr, 0x20), 0, size) // copy the return data after the size
      mstore(0x40, add(ptr, add(size, 0x20))) // update the free memory pointer
      switch success
      case 0 { revert(ptr, size) }
      default { result := ptr }
    }
  }
  // to match with the payable fallback (not necessary but pleases compiler)

  receive() external payable {}
}
