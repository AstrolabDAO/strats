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
 * @title AsIterableSet - Astrolab's iterable set library
 * @author Astrolab DAO
 */
library AsIterableSet {
  using AsCast for bytes32;
  using AsCast for address;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Struct representing an iterable set
   * @param data An array of bytes32 elements representing the set
   * @param index A mapping from bytes32 elements to their index in the data array
   */
  struct Set {
    bytes32[] data;
    mapping(bytes32 => uint32) index;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             ERRORS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  error EmptySet();
  error OutOfBounds(uint256 index);

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @dev Retrieves an element by its index in the iterable set
   * @param s Target iterable set
   * @param i The index of the element
   * @return The element at the specified index
   */
  function getAt(Set storage s, uint256 i) internal view returns (bytes32) {
    require(i < s.data.length);
    return s.data[i];
  }

  /**
   * @dev Retrieves an element by its index in the iterable set
   * @param s Target iterable set
   * @param i The index of the element
   * @return The element at the specified index
   */
  function get(Set storage s, bytes32 i) internal view returns (bytes32) {
    return getAt(s, s.index[i] - 1);
  }

  /**
   * @dev Checks if the iterable set contains a specific element
   * @param s Target iterable set
   * @param o The element to check for
   * @return True if the element is in the set, false otherwise
   */
  function has(Set storage s, bytes32 o) internal view returns (bool) {
    return s.index[o] > 0 && s.index[o] <= s.data.length;
  }

  /**
   * @dev Returns the number of elements in the iterable set
   * @param s Target iterable set
   * @return The size of the set
   */
  function size(Set storage s) internal view returns (uint256) {
    return s.data.length;
  }

  /**
   * @dev Returns a copy of all elements in the iterable set as an array
   * @notice this copies the entire s.data storage to memory, gas cost is hence exponential of the set size
   * should mainly be used by views/static calls (gas free)
   * uncallable if copy(s.data.length) cost > block gaslimit (thousands of entries on most chains)
   * @param s Target iterable set
   * @return An array containing all elements of the set
   */
  function rawValues(Set storage s) internal view returns (bytes32[] memory) {
    return s.data;
  }

  /**
   * @dev Returns a copy of all elements in the iterable set as an array of uint256
   * @param s Target iterable set
   * @return values An array of uint256 containing all elements of the set
   */
  function valuesAsUint(Set storage s) internal view returns (uint256[] memory values) {
    bytes32[] memory data = s.data;
    assembly {
      values := data
    }
  }

  /**
   * @dev Returns a copy of all elements in the iterable set as an array of int256
   * @param s Target iterable set
   * @return values An array of int256 containing all elements of the set
   */
  function valuesAsInt(Set storage s) internal view returns (int256[] memory values) {
    bytes32[] memory data = s.data;
    assembly {
      values := data
    }
  }

  /**
   * @dev Returns a copy of all elements in the iterable set as an array of addresses
   * @notice less efficient than above batch casting
   * @param s Target iterable set
   * @return values An array of addresses containing all elements of the set
   */
  function valuesAsAddress(Set storage s) internal view returns (address[] memory values) {
    uint256 n = s.data.length;
    values = new address[](n);
    unchecked {
      for (uint256 i = 0; i < n; i++) {
        values[i] = s.data[i].toAddress();
      }
    }
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @dev Adds an element to the end of the iterable set
   * @param s Target iterable set
   * @param o The element to be added
   */
  function push(Set storage s, bytes32 o) internal {
    require(s.index[o] == 0); // prevent duplicates
    s.data.push(o);
    s.index[o] = uint32(s.data.length);
  }

  /**
   * @dev Pushes an element of type `uint256` to the set
   * @param s The set to push the element to
   * @param o The element to push
   */
  function push(Set storage s, uint256 o) internal {
    push(s, bytes32(o));
  }

  /**
   * @dev Pushes an element of type `address` to the set
   * @param s The set to push the element to
   * @param o The element to push
   */
  function push(Set storage s, address o) internal {
    push(s, o.toBytes32());
  }

  /**
   * @dev Removes the last element from the iterable set and returns it
   * @param s Target iterable set
   * @return The last element of the set
   */
  function pop(Set storage s) internal returns (bytes32) {
    if (s.data.length == 0) {
      revert EmptySet();
    }
    bytes32 o = s.data[s.data.length - 1];
    s.data.pop();
    delete s.index[o];
    return o;
  }

  /**
   * @dev Removes the first element from the iterable set
   * @param s Target iterable set
   */
  function shift(Set storage s) internal {
    if (s.data.length == 0) {
      revert EmptySet();
    }

    if (s.data.length == 1) {
      // length == 1 >> delete index and pop
      delete s.index[s.data[0]];
      s.data.pop();
    } else {
      // typical shift
      delete s.index[s.data[0]];
      s.data[0] = s.data[s.data.length - 1];
      s.index[s.data[0]] = 1;
      s.data.pop();
    }
  }

  /**
   * @dev Adds an element to the beginning of the iterable set
   * @param s Target iterable set
   * @param o The element to be added
   */
  function unshift(Set storage s, bytes32 o) internal {
    require(s.index[o] == 0); // prevent duplicates
    if (s.data.length == 0) {
      s.data.push(o);
    } else {
      bytes32 firstElement = s.data[0]; // tmp load the first element in memory
      s.data.push(firstElement); // push it back
      s.index[firstElement] = uint32(s.data.length); // update its index to last
      s.data[0] = o; // use the freed first slot to insert o
    }
    s.index[o] = 1; // update its index to first
  }

  /**
   * @dev Inserts an element at a specific index in the iterable set
   * @param s Target iterable set
   * @param i The index at which to insert
   * @param o The element to be inserted
   */
  function insert(Set storage s, uint256 i, bytes32 o) internal {
    require(s.index[o] == 0); // prevent duplicates
    if (i > s.data.length) {
      revert OutOfBounds(i);
    }

    // if inserting at the end, simply push the new element
    if (i == s.data.length) {
      s.data.push(o);
      s.index[o] = uint32(s.data.length);
    } else {
      // save the displaced element
      bytes32 displacedElement = s.data[i];
      // insert the new element at the specified index
      s.data[i] = o;
      s.index[o] = uint32(i + 1);

      // push the displaced element to the back of the queue
      s.data.push(displacedElement);
      s.index[displacedElement] = uint32(s.data.length);
    }
  }

  /**
   * @dev Removes an element at a specific index in the iterable set
   * @param s Target iterable set
   * @param i The index of the element to be deleted
   */
  function removeAt(Set storage s, uint256 i) internal {
    if (i >= s.data.length) {
      revert OutOfBounds(i);
    }

    // get the element to be removed for index cleanup
    bytes32 elementToRemove = s.data[i];

    // if not removing the last element, move the last element to the removed position
    if (i < s.data.length - 1) {
      s.data[i] = s.data[s.data.length - 1];
      // update the index of the moved element to its new position
      s.index[s.data[i]] = uint32(i + 1); // assuming 1-based indexing for the mapping
    }

    // remove the last element (either the moved element or the original if it was the last)
    s.data.pop();

    // clean up the index mapping for the removed element
    delete s.index[elementToRemove];
  }

  /**
   * @dev Removes a raw element from the iterable set
   * @param s Target iterable set
   * @param o The element to be deleted
   */
  function remove(Set storage s, bytes32 o) internal {
    uint32 i = s.index[o];
    s.index[o] = 0;
    require(i > 0); // not found
    removeAt(s, i - 1);
  }

  /**
   * @dev Removes an uint256 from the set
   * @param s The set to remove the element from
   * @param o The element to be removed
   */
  function remove(Set storage s, uint256 o) internal {
    remove(s, bytes32(o));
  }

  /**
   * @dev Removes an address from the set
   * @param s The set to remove the element from
   * @param o The element to be removed
   */
  function remove(Set storage s, address o) internal {
    remove(s, o.toBytes32());
  }

  // /**
  //  * @dev Removes zero elements from the tail end of the iterable set
  //  * @param s Target iterable set
  //  */
  // function _cleanTail(Set storage s) internal {
  //     uint32 n = uint32(s.data.length);
  //     while (n > 0 && s.data[--n] == bytes32(0)) {
  //         s.data.pop();
  //     }
  // }

  // /**
  //  * @dev Removes zero elements from the head of the iterable set, maintaining the set's integrity
  //  * @param s Target iterable set
  //  */
  // function _cleanHead(Set storage s) internal {
  //     _cleanTail(s);
  //     uint32 n = uint32(s.data.length);
  //     while (n > 0 && s.data[0] == bytes32(0)) {
  //         delete s.data[0];
  //         s.data[0] = s.data[--n];
  //         s.data.pop();
  //     }
  //     s.index[s.data[0]] = 1;
  // }
}
