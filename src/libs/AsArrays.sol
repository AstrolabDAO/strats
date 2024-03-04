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
            mstore(0x60, self.slot)

            for {
                let i := 0
            } lt(i, sload(self.slot)) {
                i := add(i, 1)
            } {
                value := add(sload(add(keccak256(0x60, 0x20), i)), value)
            }
        }
    }

    /**
     * @notice Returns the max value in an array
     * @param self Storage array containing uint256 type variables
     * @return value The highest value in the array
     */
    function max(uint256[] storage self) public view returns (uint256 value) {
        assembly {
            mstore(0x60, self.slot)
            value := sload(keccak256(0x60, 0x20))

            for {
                let i := 0
            } lt(i, sload(self.slot)) {
                i := add(i, 1)
            } {
                switch gt(sload(add(keccak256(0x60, 0x20), i)), value)
                case 1 {
                    value := sload(add(keccak256(0x60, 0x20), i))
                }
            }
        }
    }

    /// @notice Returns the minimum value in an array
    /// @param self Storage array containing uint256 type variables
    /// @return value The highest value in the array
    function min(uint256[] storage self) public view returns (uint256 value) {
        assembly {
            mstore(0x60, self.slot)
            value := sload(keccak256(0x60, 0x20))

            for {
                let i := 0
            } lt(i, sload(self.slot)) {
                i := add(i, 1)
            } {
                switch gt(sload(add(keccak256(0x60, 0x20), i)), value)
                case 0 {
                    value := sload(add(keccak256(0x60, 0x20), i))
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
     * @notice Returns dereferrenced array (slice) starting at ptr and containing size elements
     * @param ptr reference of the array
     * @return array of given size
     */
    function unref(uint256 ptr, uint256 size) internal pure returns (uint256[] memory) {
        uint256[] memory data = new uint256[](size);
        assembly {
            data := ptr
            // safer:
            // for { let i := 0 } lt(i, size) { i := add(i, 1) } {
            //     mstore(add(data, add(0x20, mul(i, 0x20))), mload(add(ptr, mul(i, 0x20))))
            // }
        }
        return data;
    }

    /**
     * @notice Used to test memory pointers on the current evm
     * @return true - memory ok, false - memory error
     */
    function testRefUnref() internal pure returns (bool) {
        uint256[] memory dt = new uint256[](3);
        for (uint i = 0; i < dt.length; i++) {
            dt[i] = i;
        }
        uint256 wptr = ref(dt);
        uint256[] memory data;
        data = unref(wptr, 3);
        return data.length == 3 && data[0] == 0 && data[1] == 1 && data[2] == 2;
    }

    /**
     * @notice Returns a slice of the array
     * @param self Storage array containing uint256 type variables
     * @param begin Index of the first element to include in the slice
     * @param end Index of the last element to include in the slice
     * @return slice of the array
     */
    function slice(uint256[] memory self, uint256 begin, uint256 end) internal pure returns (uint256[] memory) {
        require(begin < end && end <= self.length);
        return unref(ref(self) + begin * 0x20, end - begin);
    }

    /**
     * @notice Returns a slice of the bytes array
     * @param self Storage array containing uint256 type variables
     * @param begin Index of the first element to include in the slice
     * @return slice of the array
     */
    function slice(bytes[] memory self, uint256 begin, uint256 end)
        internal
        pure
        returns (bytes[] memory)
    {
        require(begin < end && end <= self.length);

        // Calculate the number of elements in the slice
        uint256 sliceLength = end - begin;

        // Allocate a new bytes array for the slice
        bytes[] memory sliceData = new bytes[](sliceLength);

        // Copy the bytes from the original array to the slice
        for (uint256 i = 0; i < sliceLength; i++) {
            sliceData[i] = self[i + begin];
        }

        return sliceData;
    }

    /**
     * @dev Fills a dynamic array with a specific value
     * @param a The value to fill the array with
     * @param n The size of the array
     * @return arr The filled array
     */
    function fill(uint8 a, uint64 n) internal pure returns (uint8[] memory arr) {
        arr = new uint8[](n); for (uint64 i = 0; i < n; i++) arr[i] = a;
    }

    function fill(bytes32 a, uint64 n) internal pure returns (bytes32[] memory arr) {
        arr = new bytes32[](n); for (uint64 i = 0; i < n; i++) arr[i] = a;
    }

    function fill(uint256 a, uint64 n) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](n); for (uint64 i = 0; i < n; i++) arr[i] = a;
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
