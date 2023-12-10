library AsCast {

    /**
     * @notice Convert an unsigned integer to a signed integer.
     * @dev Requires the input to be within the valid range for a signed integer.
     * @param x The input unsigned integer.
     * @return The input value as a signed integer.
     */
    function toInt(uint256 x) internal pure returns (int256) {
        require(
            x <= uint256(type(int256).max),
            "Value out of range for int256"
        );
        return int256(x);
    }

    /**
     * @notice Convert a signed integer to a signed 128-bit integer.
     * @dev Requires the input to be within the valid range for a signed 128-bit integer.
     * @param x The input signed integer.
     * @return The input value as a signed 128-bit integer.
     */
    function toInt128(int256 x) internal pure returns (int128) {
        require(
            type(int128).min <= x && x <= type(int128).max,
            "Value out of range for int128"
        );
        return int128(x);
    }

    /**
     * @notice Convert an unsigned integer to a signed 128-bit integer.
     * @dev Calls `toInt` to perform the conversion.
     * @param x The input unsigned integer.
     * @return The input value as a signed 128-bit integer.
     */
    function toInt128(uint256 x) internal pure returns (int128) {
        return toInt128(toInt(x));
    }

    /**
     * @notice Convert a signed integer to an unsigned integer.
     * @dev Requires the input to be non-negative.
     * @param x The input signed integer.
     * @return The input value as an unsigned integer.
     */
    function toUint(int256 x) internal pure returns (uint256) {
        require(x >= 0, "Negative value cannot be converted to uint256");
        return uint256(x);
    }

    /**
     * @notice Convert an unsigned integer to a 32-bit unsigned integer.
     * @dev Requires the input to be within the valid range for a 32-bit unsigned integer.
     * @param x The input unsigned integer.
     * @return The input value as a 32-bit unsigned integer.
     */
    function toUint32(uint256 x) internal pure returns (uint32) {
        require(x <= type(uint32).max, "Value out of range for uint32");
        return uint32(x);
    }

    /**
     * @notice Convert an unsigned integer to a 112-bit unsigned integer.
     * @dev Requires the input to be within the valid range for a 112-bit unsigned integer.
     * @param x The input unsigned integer.
     * @return The input value as a 112-bit unsigned integer.
     */
    function toUint112(uint256 x) internal pure returns (uint112) {
        require(x <= type(uint112).max, "Value out of range for uint112");
        return uint112(x);
    }

    /**
     * @notice Convert an unsigned integer to a 96-bit unsigned integer.
     * @dev Requires the input to be within the valid range for a 96-bit unsigned integer.
     * @param x The input unsigned integer.
     * @return The input value as a 96-bit unsigned integer.
     */
    function toUint96(uint256 x) internal pure returns (uint96) {
        require(x <= type(uint96).max, "Value out of range for uint96");
        return uint96(x);
    }

    /**
     * @notice Convert an unsigned integer to a 128-bit unsigned integer.
     * @dev Requires the input to be within the valid range for a 128-bit unsigned integer.
     * @param x The input unsigned integer.
     * @return The input value as a 128-bit unsigned integer.
     */
    function toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max, "Value out of range for uint128");
        return uint128(x);
    }

    /**
     * @dev Converts an address to bytes32.
     * @param addr The address to be converted.
     * @return The bytes32 representation of the address.
     */
    function toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /**
     * @dev Converts a bytes32 value to an address.
     * @param b The bytes32 value to convert.
     * @return The converted address.
     */
    function toAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }
}
