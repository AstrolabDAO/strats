// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "./AsCast.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsSet
 * @author Astrolab DAO
 * @dev A library to manage a set of elements stored in a sequential order with efficient operations.
 */
library AsSequentialSet {
    using AsCast for bytes32;
    using AsCast for address;

    error EmptySet();

    /**
     * @dev Struct representing a sequential set.
     * @param data An array of bytes32 elements representing the set.
     * @param index A mapping from bytes32 elements to their index in the data array.
     */
    struct Set {
        bytes32[] data;
        mapping(bytes32 => uint32) index;
    }

    /**
     * @dev Adds an element to the end of the sequential set.
     * @param q The sequential set.
     * @param o The element to be added.
     */
    function push(Set storage q, bytes32 o) internal {
        q.data.push(o);
        q.index[o] = uint32(q.data.length);
    }

    /**
     * @dev Pushes an element of type `uint256` to the set.
     * @param q The set to push the element to.
     * @param o The element to push.
     */
    function push(Set storage q, uint256 o) internal {
        push(q, bytes32(o));
    }

    /**
     * @dev Pushes an element of type `address` to the set.
     * @param q The set to push the element to.
     * @param o The element to push.
     */
    function push(Set storage q, address o) internal {
        push(q, o.toBytes32());
    }

    /**
     * @dev Removes the last element from the sequential set and returns it.
     * @param q The sequential set.
     * @return The last element of the set.
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
     * @dev Removes the first element from the sequential set.
     * @param q The sequential set.
     */
    function shift(Set storage q) internal {
        if (q.data.length == 0) {
            revert EmptySet();
        }
        delete q.index[q.data[0]];
        q.data[0] = q.data[q.data.length - 1];
        q.index[q.data[0]] = 1;
        q.data.pop();
    }

    /**
     * @dev Adds an element to the beginning of the sequential set.
     * @param q The sequential set.
     * @param o The element to be added.
     */
    function unshift(Set storage q, bytes32 o) internal {
        if (q.data.length == 0) {
            q.data.push(o);
        } else {
            q.data[q.data.length - 1] = q.data[0];
            q.index[q.data[0]] = uint32(q.data.length);
            q.data[0] = o;
        }
        q.index[o] = 1;
    }

    /**
     * @dev Inserts an element at a specific index in the sequential set.
     * @param q The sequential set.
     * @param i The index at which to insert.
     * @param o The element to be inserted.
     */
    function insert(Set storage q, uint256 i, bytes32 o) internal {
        require(i <= q.data.length, "Index out of bounds");
        q.data.push(bytes32(0));
        for (uint256 j = q.data.length; j > i; j--) {
            q.data[j] = q.data[j - 1];
            q.index[q.data[j]] = uint32(j + 1);
        }
        q.data[i] = o;
        q.index[o] = uint32(i + 1);
    }

    /**
     * @dev Removes an element at a specific index in the sequential set.
     * @param q The sequential set.
     * @param i The index of the element to be deleted.
     */
    function removeAt(Set storage q, uint256 i) internal {
        require(i < q.data.length, "Index out of bounds");
        if (i < q.data.length - 1) {
            delete q.data[i];
            q.data[i] = q.data[q.data.length - 1];
        }
        q.data.pop();
    }

    /**
     * @dev Removes a raw element from the sequential set.
     * @param q The sequential set.
     * @param o The element to be deleted.
     */
    function remove(Set storage q, bytes32 o) internal {
        uint32 i = q.index[o];
        q.index[o] = 0;
        require(i > 0, "Element not found");
        removeAt(q, i - 1);
    }

    /**
     * @dev Removes an uint256 from the set.
     * @param q The set to remove the element from.
     * @param o The element to be removed.
     */
    function remove(Set storage q, uint256 o) internal {
        remove(q, bytes32(o));
    }

    /**
     * @dev Removes an address from the set.
     * @param q The set to remove the element from.
     * @param o The element to be removed.
     */
    function remove(Set storage q, address o) internal {
        remove(q, o.toBytes32());
    }

    /**
     * @dev Retrieves an element by its index in the sequential set.
     * @param q The sequential set.
     * @param i The index of the element.
     * @return The element at the specified index.
     */
    function getAt(Set storage q, uint256 i) internal view returns (bytes32) {
        require(i < q.data.length);
        return q.data[i];
    }

    /**
     * @dev Retrieves an element by its index in the sequential set.
     * @param q The sequential set.
     * @param i The index of the element.
     * @return The element at the specified index.
     */
    function get(Set storage q, bytes32 i) internal view returns (bytes32) {
        return getAt(q, q.index[i] - 1);
    }

    /**
     * @dev Checks if the sequential set contains a specific element.
     * @param q The sequential set.
     * @param o The element to check for.
     * @return True if the element is in the set, false otherwise.
     */
    function has(Set storage q, bytes32 o) internal view returns (bool) {
        return q.index[o] > 0 && q.index[o] <= q.data.length;
    }

    /**
     * @dev Returns the number of elements in the sequential set.
     * @param q The sequential set.
     * @return The size of the set.
     */
    function size(Set storage q) internal view returns (uint256) {
        return q.data.length;
    }

    /**
     * @dev Returns a copy of all elements in the sequential set as an array.
     * @notice this copies the entire q.data storage to memory, gas cost is hence exponential of the set size
     * should mainly be used by views/static calls (gas free)
     * uncallable if copy(q.data.length) cost > block gaslimit (thousands of entries on most chains)
     * @param q The sequential set.
     * @return An array containing all elements of the set.
     */
    function rawValues(Set storage q) internal view returns (bytes32[] memory) {
        return q.data;
    }

    /**
     * @dev Returns a copy of all elements in the sequential set as an array of uint256.
     * @param q The sequential set.
     * @return values An array of uint256 containing all elements of the set.
     */
    function valuesAsUint(Set storage q) internal view returns (uint256[] memory values) {
        bytes32[] memory data = q.data;
        assembly {
            values := data
        }
    }

    /**
     * @dev Returns a copy of all elements in the sequential set as an array of int256.
     * @param q The sequential set.
     * @return values An array of int256 containing all elements of the set.
     */
    function valuesAsInt(Set storage q) internal view returns (int256[] memory values) {
        bytes32[] memory data = q.data;
        assembly {
            values := data
        }
    }

    /**
     * @dev Returns a copy of all elements in the sequential set as an array of addresses.
     * @notice less efficient than above batch casting
     * @param q The sequential set.
     * @return values An array of addresses containing all elements of the set.
     */
    function valuesAsAddress(Set storage q) internal view returns (address[] memory values) {
        values = new address[](q.data.length);
        for (uint256 i = 0; i < q.data.length; i++) {
            values[i] = q.data[i].toAddress();
        }
    }

    // /**
    //  * @dev Removes zero elements from the tail end of the sequential set.
    //  * @param q The sequential set.
    //  */
    // function _cleanTail(Set storage q) internal {
    //     uint32 n = uint32(q.data.length);
    //     while (n > 0 && q.data[--n] == bytes32(0)) {
    //         q.data.pop();
    //     }
    // }

    // /**
    //  * @dev Removes zero elements from the head of the sequential set, maintaining the set's integrity.
    //  * @param q The sequential set.
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
