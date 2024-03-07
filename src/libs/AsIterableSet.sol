// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.22;

import "./AsCast.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsIterableSet
 * @author Astrolab DAO
 * @dev A library to manage a set of elements that can be iterated over from 0 to q.size()
 */
library AsIterableSet {
  using AsCast for bytes32;
  using AsCast for address;

  error EmptySet();
  error OutOfBounds(uint256 index);

  /**
   * @dev Struct representing an iterable set
   * @param data An array of bytes32 elements representing the set
   * @param index A mapping from bytes32 elements to their index in the data array
   */
  struct Set {
    bytes32[] data;
    mapping(bytes32 => uint32) index;
  }

  /**
   * @dev Adds an element to the end of the iterable set
   * @param q The iterable set
   * @param o The element to be added
   */
  function push(Set storage q, bytes32 o) internal {
    require(q.index[o] == 0); // prevent duplicates
    q.data.push(o);
    q.index[o] = uint32(q.data.length);
  }

  /**
   * @dev Pushes an element of type `uint256` to the set
   * @param q The set to push the element to
   * @param o The element to push
   */
  function push(Set storage q, uint256 o) internal {
    push(q, bytes32(o));
  }

  /**
   * @dev Pushes an element of type `address` to the set
   * @param q The set to push the element to
   * @param o The element to push
   */
  function push(Set storage q, address o) internal {
    push(q, o.toBytes32());
  }

  /**
   * @dev Removes the last element from the iterable set and returns it
   * @param q The iterable set
   * @return The last element of the set
   */
  function pop(Set storage q) internal returns (bytes32) {
    if (q.data.length == 0) {
      revert EmptySet();
    }
    bytes32 o = q.data[q.data.length - 1];
    q.data.pop();
    delete q.index[o];
    return o;
  }

  /**
   * @dev Removes the first element from the iterable set
   * @param q The iterable set
   */
  function shift(Set storage q) internal {
    if (q.data.length == 0) {
      revert EmptySet();
    }

    if (q.data.length == 1) {
      // length == 1 >> delete index and pop
      delete q.index[q.data[0]];
      q.data.pop();
    } else {
      // typical shift
      delete q.index[q.data[0]];
      q.data[0] = q.data[q.data.length - 1];
      q.index[q.data[0]] = 1;
      q.data.pop();
    }
  }

  /**
   * @dev Adds an element to the beginning of the iterable set
   * @param q The iterable set
   * @param o The element to be added
   */
  function unshift(Set storage q, bytes32 o) internal {
    if (q.data.length == 0) {
      q.data.push(o);
    } else {
      bytes32 firstElement = q.data[0]; // tmp load the first element in memory
      q.data.push(firstElement); // push it back
      q.index[firstElement] = uint32(q.data.length); // update its index to last
      q.data[0] = o; // use the freed first slot to insert o
      q.index[o] = 1; // freed index
    }
  }

  /**
   * @dev Inserts an element at a specific index in the iterable set
   * @param q The iterable set
   * @param i The index at which to insert
   * @param o The element to be inserted
   */
  function insert(Set storage q, uint256 i, bytes32 o) internal {
    require(q.index[o] == 0); // prevent duplicates
    if (i > q.data.length) {
      revert OutOfBounds(i);
    }

    // if inserting at the end, simply push the new element
    if (i == q.data.length) {
      q.data.push(o);
      q.index[o] = uint32(q.data.length);
    } else {
      // save the displaced element
      bytes32 displacedElement = q.data[i];
      // insert the new element at the specified index
      q.data[i] = o;
      q.index[o] = uint32(i + 1);

      // push the displaced element to the back of the queue
      q.data.push(displacedElement);
      q.index[displacedElement] = uint32(q.data.length);
    }
  }

  /**
   * @dev Removes an element at a specific index in the iterable set
   * @param q The iterable set
   * @param i The index of the element to be deleted
   */
  function removeAt(Set storage q, uint256 i) internal {
    if (i >= q.data.length) {
      revert OutOfBounds(i);
    }

    // get the element to be removed for index cleanup
    bytes32 elementToRemove = q.data[i];

    // if not removing the last element, move the last element to the removed position
    if (i < q.data.length - 1) {
      q.data[i] = q.data[q.data.length - 1];
      // update the index of the moved element to its new position
      q.index[q.data[i]] = uint32(i + 1); // assuming 1-based indexing for the mapping
    }

    // remove the last element (either the moved element or the original if it was the last)
    q.data.pop();

    // clean up the index mapping for the removed element
    delete q.index[elementToRemove];
  }

  /**
   * @dev Removes a raw element from the iterable set
   * @param q The iterable set
   * @param o The element to be deleted
   */
  function remove(Set storage q, bytes32 o) internal {
    uint32 i = q.index[o];
    q.index[o] = 0;
    require(i > 0); // not found
    removeAt(q, i - 1);
  }

  /**
   * @dev Removes an uint256 from the set
   * @param q The set to remove the element from
   * @param o The element to be removed
   */
  function remove(Set storage q, uint256 o) internal {
    remove(q, bytes32(o));
  }

  /**
   * @dev Removes an address from the set
   * @param q The set to remove the element from
   * @param o The element to be removed
   */
  function remove(Set storage q, address o) internal {
    remove(q, o.toBytes32());
  }

  /**
   * @dev Retrieves an element by its index in the iterable set
   * @param q The iterable set
   * @param i The index of the element
   * @return The element at the specified index
   */
  function getAt(Set storage q, uint256 i) internal view returns (bytes32) {
    require(i < q.data.length);
    return q.data[i];
  }

  /**
   * @dev Retrieves an element by its index in the iterable set
   * @param q The iterable set
   * @param i The index of the element
   * @return The element at the specified index
   */
  function get(Set storage q, bytes32 i) internal view returns (bytes32) {
    return getAt(q, q.index[i] - 1);
  }

  /**
   * @dev Checks if the iterable set contains a specific element
   * @param q The iterable set
   * @param o The element to check for
   * @return True if the element is in the set, false otherwise
   */
  function has(Set storage q, bytes32 o) internal view returns (bool) {
    return q.index[o] > 0 && q.index[o] <= q.data.length;
  }

  /**
   * @dev Returns the number of elements in the iterable set
   * @param q The iterable set
   * @return The size of the set
   */
  function size(Set storage q) internal view returns (uint256) {
    return q.data.length;
  }

  /**
   * @dev Returns a copy of all elements in the iterable set as an array
   * @notice this copies the entire q.data storage to memory, gas cost is hence exponential of the set size
   * should mainly be used by views/static calls (gas free)
   * uncallable if copy(q.data.length) cost > block gaslimit (thousands of entries on most chains)
   * @param q The iterable set
   * @return An array containing all elements of the set
   */
  function rawValues(Set storage q) internal view returns (bytes32[] memory) {
    return q.data;
  }

  /**
   * @dev Returns a copy of all elements in the iterable set as an array of uint256
   * @param q The iterable set
   * @return values An array of uint256 containing all elements of the set
   */
  function valuesAsUint(Set storage q) internal view returns (uint256[] memory values) {
    bytes32[] memory data = q.data;
    assembly {
      values := data
    }
  }

  /**
   * @dev Returns a copy of all elements in the iterable set as an array of int256
   * @param q The iterable set
   * @return values An array of int256 containing all elements of the set
   */
  function valuesAsInt(Set storage q) internal view returns (int256[] memory values) {
    bytes32[] memory data = q.data;
    assembly {
      values := data
    }
  }

  /**
   * @dev Returns a copy of all elements in the iterable set as an array of addresses
   * @notice less efficient than above batch casting
   * @param q The iterable set
   * @return values An array of addresses containing all elements of the set
   */
  function valuesAsAddress(Set storage q) internal view returns (address[] memory values) {
    values = new address[](q.data.length);
    unchecked {
      for (uint256 i = 0; i < q.data.length; i++) {
        values[i] = q.data[i].toAddress();
      }
    }
  }

  // /**
  //  * @dev Removes zero elements from the tail end of the iterable set
  //  * @param q The iterable set
  //  */
  // function _cleanTail(Set storage q) internal {
  //     uint32 n = uint32(q.data.length);
  //     while (n > 0 && q.data[--n] == bytes32(0)) {
  //         q.data.pop();
  //     }
  // }

  // /**
  //  * @dev Removes zero elements from the head of the iterable set, maintaining the set's integrity
  //  * @param q The iterable set
  //  */
  // function _cleanHead(Set storage q) internal {
  //     _cleanTail(q);
  //     uint32 n = uint32(q.data.length);
  //     while (n > 0 && q.data[0] == bytes32(0)) {
  //         delete q.data[0];
  //         q.data[0] = q.data[--n];
  //         q.data.pop();
  //     }
  //     q.index[q.data[0]] = 1;
  // }
}
