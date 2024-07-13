// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "./AsCast.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsArrays Library - Astrolab's Array manipulation library
 * @author Astrolab DAO
 */
library AsArrays {
  using AsCast for address;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
 * @notice Returns the sum of all elements in the array
   * @param self Storage array containing uint256 type variables
   * @return value Sum of all elements, does not check for overflow
   */
  function sum(uint256[] storage self) public view returns (uint256 value) {
    assembly {
      let ptr := mload(0x40) // free memory pointer
      mstore(ptr, self.slot) // store the array's slot
      mstore(0x40, add(ptr, 0x20)) // update the free memory pointer
      let len := sload(self.slot) // array length

      for { let i := 0 } lt(i, len) { i := add(i, 1) } {
        let el := sload(add(keccak256(ptr, 0x20), i)) // load each element
        value := add(value, el) // accumulate the sum
      }

      mstore(0x40, add(ptr, 0x20)) // update the free memory pointer
    }
  }

  /**
   * @dev Returns the maximum value in the given array
   * @param self Array to find the maximum value from
   * @return value Maximum value in the array
   */
  function max(uint256[] storage self) public view returns (uint256 value) {
    assembly {
      let ptr := mload(0x40) // free memory pointer
      mstore(ptr, self.slot) // store the array's slot
      mstore(0x40, add(ptr, 0x20)) // update the free memory pointer
      value := sload(keccak256(ptr, 0x20)) // init max value with the first element
      let len := sload(self.slot) // array length

      // iterate over the array
      for { let i := 1 } lt(i, len) { i := add(i, 1) } {
        let el := sload(add(keccak256(ptr, 0x20), i)) // load element
        if gt(el, value) { value := el } // update max value
      }
    }
  }

  /**
   * @dev Returns the minimum value in the given array
   * @param self Array to find the minimum value from
   * @return value Minimum value in the array
   */
  function min(uint256[] storage self) public view returns (uint256 value) {
    assembly {
      let ptr := mload(0x40) // free memory pointer
      mstore(ptr, self.slot) // store the array's slot
      mstore(0x40, add(ptr, 0x20)) // update the free memory pointer
      value := sload(keccak256(ptr, 0x20)) // init min value with the first element
      let len := sload(self.slot) // array length

      // iterate over the array
      for { let i := 1 } lt(i, len) { i := add(i, 1) } {
        let el := sload(add(keccak256(ptr, 0x20), i)) // load element
        if lt(el, value) { value := el } // update min value
      }
    }
  }

  /**
   * @notice Returns a reference to the array
   * @param data array to be referenced
   * @return ptr reference of the array
   */
  function ref(uint256[] memory data) internal pure returns (uint256 ptr) {
    assembly {
      ptr := data
    }
  }

  /**
   * @dev Fills a dynamic array with a specific value
   * @param a Value to fill the array with
   * @param n Size of the array
   * @return arr Filled array
   */
  function fill(uint8 a, uint64 n) internal pure returns (uint8[] memory arr) {
    arr = new uint8[](n);
    for (uint256 i = 0; i < n;) {
      arr[i] = a;
      unchecked {
        i++;
      }
    }
  }

  function fill(bytes32 a, uint64 n) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](n);
    for (uint256 i = 0; i < n;) {
      arr[i] = a;
      unchecked {
        i++;
      }
    }
  }

  function fill(uint256 a, uint64 n) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](n);
    for (uint256 i = 0; i < n;) {
      arr[i] = a;
      unchecked {
        i++;
      }
    }
  }

  /**
   * @dev Converts a value to a one-element array
   * @param a Value to convert to an array
   * @return arr Resulting array
   */
  function toArray(uint8 a) internal pure returns (uint8[] memory arr) {
    arr = new uint8[](1);
    arr[0] = a;
  }

  function toArray(uint8 a, uint8 b) internal pure returns (uint8[] memory arr) {
    arr = new uint8[](2);
    (arr[0], arr[1]) = (a, b);
  }

  function toArray16(uint16 a) internal pure returns (uint16[] memory arr) {
    arr = new uint16[](1);
    arr[0] = a;
  }

  function toArray16(uint16 a, uint16 b) internal pure returns (uint16[] memory arr) {
    arr = new uint16[](2);
    (arr[0], arr[1]) = (a, b);
  }

  function toArray(uint256 a) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](1);
    arr[0] = a;
  }

  function toArray(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](2);
    (arr[0], arr[1]) = (a, b);
  }

  function toArray(
    uint256 a,
    uint256 b,
    uint256 c
  ) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](3);
    (arr[0], arr[1], arr[2]) = (a, b, c);
  }

  function toArray(address a) internal pure returns (address[] memory arr) {
    arr = new address[](1);
    arr[0] = a;
  }

  function toArray(address a, address b) internal pure returns (address[] memory arr) {
    arr = new address[](2);
    (arr[0], arr[1]) = (a, b);
  }

  function toArray(
    address a,
    address b,
    address c
  ) internal pure returns (address[] memory arr) {
    arr = new address[](3);
    (arr[0], arr[1], arr[2]) = (a, b, c);
  }

  function toBytes32Array(address a) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](1);
    arr[0] = a.toBytes32();
  }

  function toBytes32Array(
    address a,
    address b
  ) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](2);
    (arr[0], arr[1]) = (a.toBytes32(), b.toBytes32());
  }

  function toBytes32Array(
    address a,
    address b,
    address c
  ) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](3);
    (arr[0], arr[1], arr[2]) = (a.toBytes32(), b.toBytes32(), c.toBytes32());
  }

  function toArray(bytes32 a) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](1);
    arr[0] = a;
  }

  function toArray(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](2);
    (arr[0], arr[1]) = (a, b);
  }

  function toArray(bytes32 a, bytes32 b, bytes32 c) internal pure returns (bytes32[] memory arr) {
    arr = new bytes32[](3);
    (arr[0], arr[1], arr[2]) = (a, b, c);
  }

  function dynamic(uint256[8] memory fixedArray)
    internal
    pure
    returns (uint256[] memory arr)
  {
    arr = new uint256[](fixedArray.length);
    for (uint256 i = 0; i < fixedArray.length;) {
      arr[i] = fixedArray[i];
      unchecked {
        i++;
      }
    }
  }

  function dynamic(uint16[8] memory fixedArray)
    internal
    pure
    returns (uint16[] memory arr)
  {
    arr = new uint16[](fixedArray.length);
    for (uint256 i = 0; i < fixedArray.length;) {
      arr[i] = fixedArray[i];
      unchecked {
        i++;
      }
    }
  }

  function dynamic(uint8[8] memory fixedArray) internal pure returns (uint8[] memory arr) {
    arr = new uint8[](fixedArray.length);
    for (uint256 i = 0; i < fixedArray.length;) {
      arr[i] = fixedArray[i];
      unchecked {
        i++;
      }
    }
  }
}
