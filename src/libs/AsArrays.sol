// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsArrays Library
 * @author Astrolab DAO
 * @notice Astrolab's Array manipulation library
 * @dev This library helps with high level array manipulation
 */
library AsArrays {

    /**
     * @notice Returns the sum of all elements in the array
     * @param self Storage array containing uint256 type variables
     * @return value The sum of all elements, does not check for overflow
     */
    function sum(uint256[] storage self) public view returns (uint256 value) {
        assembly {
            let ptr := mload(0x40) // Safe memory pointer
            mstore(ptr, self.slot) // Store the array's slot

            for {
                let i := 0
            } lt(i, sload(self.slot)) {
                i := add(i, 1)
            } {
                let el := sload(add(keccak256(ptr, 0x20), i)) // Load each element
                value := add(value, el) // Accumulate the sum
            }
        }
    }

    /**
     * @dev Returns the maximum value in the given array
     * @param self The array to find the maximum value from
     * @return value The maximum value in the array
     */
    function max(uint256[] storage self) public view returns (uint256 value) {
        assembly {
            let ptr := mload(0x40) // Load the current free memory pointer
            mstore(ptr, self.slot) // Store the array's slot at the safe memory location
            value := sload(keccak256(ptr, 0x20)) // Load the first element of the array

            // Get the array's length
            let len := sload(self.slot)

            // Iterate over the array
            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                // Compute the keccak256 hash of the slot and index to access the array element
                let el := sload(add(keccak256(ptr, 0x20), i))
                // Check if the current element is greater than the current max value
                if gt(el, value) {
                    value := el // Update max value
                }
            }

            // No need to update the free memory pointer since we didn't allocate more memory
        }
    }

    /**
     * @dev Returns the minimum value in the given array
     * @param self The array to find the minimum value from
     * @return value The minimum value in the array
     */
    function min(uint256[] storage self) public view returns (uint256 value) {
        bool initialized;
        assembly {
            let ptr := mload(0x40) // Safe memory pointer
            mstore(ptr, self.slot) // Store the array's slot

            for {
                let i := 0
            } lt(i, sload(self.slot)) {
                i := add(i, 1)
            } {
                let el := sload(add(keccak256(ptr, 0x20), i)) // Load each element
                // Initialize value with the first element or update it if a new minimum is found
                if or(iszero(initialized), lt(el, value)) {
                    value := el
                    initialized := 1
                }
            }
        }
    }

    /**
     * @notice Returns a reference to the array
     * @param data array to be referenced
     * @return ptr reference of the array
     */
    function ref(uint256[] memory data) internal pure returns (uint ptr) {
        assembly {
            ptr := data
        }
    }

    /**
     * @dev Slices a portion of a uint256 array
     * @param data The uint256 array to slice
     * @param begin The starting index of the slice
     * @param length The length of the slice
     * @return The sliced uint256 array
     */
    function slice(
        uint256[] memory data,
        uint256 begin,
        uint256 length
    ) internal pure returns (uint256[] memory) {
        require(data.length >= begin + length); // out of bounds

        uint256[] memory tempArray = new uint256[](length);

        if (length > 0) {
            assembly {
                let src := add(add(data, 0x20), mul(begin, 0x20)) // src start
                let dst := add(tempArray, 0x20) // dst start
                // let copyLength := mul(length, 0x20) // bytes length
                // mcopy(dst, src, copyLength) // <-- cancun
                let end := add(src, length) // end pos
                for { } lt(src, end) { } { // loop until src+length
                    mstore(dst, mload(src)) // copy 32 bytes
                    src := add(src, 0x20) // move src pointer 32 bytes fwd
                    dst := add(dst, 0x20) // move dst pointer 32 bytes fwd
                }
            }
        }

        return tempArray;
    }

    /**
     * @dev Slices a portion of a bytes array
     * @param data The bytes array to slice
     * @param begin The starting index of the slice
     * @param length The length of the slice
     * @return The sliced portion of the bytes array
     */
    function slice(
        bytes memory data,
        uint256 begin,
        uint256 length
    ) internal pure returns (bytes memory) {
        require(data.length >= begin + length); // out of bounds

        bytes memory tempBytes = new bytes(length);

        if (length > 0) {
            assembly {
                let src := add(add(data, 0x20), begin) // src start
                let dst := add(tempBytes, 0x20) // dst start
                // mcopy(dst, src, length) // Use mcopy to copy the data
                let end := add(src, length) // End position of copying based on length
                for { } lt(src, end) { } { // loop until src+length
                    mstore(dst, mload(src)) // copy 32 bytes
                    src := add(src, 0x20) // move src pointer 32 bytes fwd
                    dst := add(dst, 0x20) // move dst pointer 32 bytes fwd
                }
            }
        }

        return tempBytes;
    }

    /**
     * @dev Fills a dynamic array with a specific value
     * @param a The value to fill the array with
     * @param n The size of the array
     * @return arr The filled array
     */
    function fill(uint8 a, uint64 n) internal pure returns (uint8[] memory arr) {
        arr = new uint8[](n); for (uint256 i = 0; i < n; i++) arr[i] = a;
    }

    function fill(bytes32 a, uint64 n) internal pure returns (bytes32[] memory arr) {
        arr = new bytes32[](n); for (uint256 i = 0; i < n; i++) arr[i] = a;
    }

    function fill(uint256 a, uint64 n) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](n); for (uint256 i = 0; i < n; i++) arr[i] = a;
    }

    /**
     * @dev Converts a value to a one-element array
     * @param a The value to convert to an array
     * @return arr The resulting array
     */
    function toArray(uint8 a) internal pure returns (uint8[] memory arr) {
        arr = new uint8[](1); arr[0] = a;
    }

    function toArray(uint8 a, uint8 b) internal pure returns (uint8[] memory arr) {
        arr = new uint8[](2); (arr[0], arr[1]) = (a, b);
    }

    function toArray(uint256 a) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1); arr[0] = a;
    }

    function toArray(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2); (arr[0], arr[1]) = (a, b);
    }

    function toArray(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1); arr[0] = a;
    }

    function toArray(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory arr) {
        arr = new bytes32[](2); (arr[0], arr[1]) = (a, b);
    }
}
