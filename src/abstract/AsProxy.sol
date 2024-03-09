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
 */
abstract contract AsProxy is Proxy {

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return Address of the implementation contract (EIP-1967/EIP-897 slot 0)
   */
  function implementation() external view virtual returns (address) {
    return _implementation();
  }

  /**
   * @return EIP-897 proxy type (1 == forwarding, 2 == upgradeable)
   */
  function proxyType() external pure virtual returns (uint256) {
    return 2;
  }

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
  ) internal {
    assembly {
      _selector := and(_selector, 0xffffffff) // clear selector bytes after 4
      let paramsSize := calldataload(_data.offset) // determine _data size from calldata
      let calldataSize := add(0x4, paramsSize) // total calldata size (selector + params)
      let callData := mload(0x40) // free ptr
      mstore(callData, _selector) // store selector in the first 4 bytes
      calldatacopy(add(callData, 0x4), _data.offset, paramsSize) // copy params after the selector in the new calldata
      mstore(0x40, add(callData, calldataSize)) // update free ptr
      let result :=
        delegatecall(
          gas(),
          _implementation, // implementation address
          callData, // inputs
          calldataSize, // input size
          0, // output location
          0 // output size
        )
      let size := returndatasize() // return data size
      let ptr := mload(0x40) // free ptr
      returndatacopy(ptr, 0, size) // copy return data to free ptr
      mstore(0x40, add(ptr, size)) // update free ptr
      switch result
      case 0 { revert(ptr, size) }
      default { return(ptr, size) }
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
  ) internal {
    assembly {
      _selector := and(_selector, 0xffffffff) // clear selector bytes after 4
      let paramsSize := mload(_data) // determine _data size from in-memory array
      let calldataSize := add(0x4, paramsSize) // total calldata size (selector + params)
      let callData := mload(0x40) // free ptr
      mstore(callData, _selector) // store selector in the first 4 bytes
      mstore(0x40, add(callData, calldataSize)) // copy the params to the free memory pointer (post size slot)
      let result :=
        delegatecall(
          gas(),
          _implementation, // implementation address
          add(callData, 0x20), // inputs stored at callData + 0x20 (size slot)
          calldataSize, // input size
          0, // output location
          0 // output size
        )
      let size := returndatasize() // return data size
      let ptr := mload(0x40) // free ptr
      returndatacopy(ptr, 0, size) // copy return data to free ptr
      switch result
      case 0 { revert(ptr, size) }
      default { return(ptr, size) }
    }
  }

  // to match with the payable fallback (not necessary but pleases compiler)
  receive() external payable {}
}
