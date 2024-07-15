// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsCast Library - Astrolab's type casting library
 * @author Astrolab DAO
 */
library AsCast {
  /*═══════════════════════════════════════════════════════════════╗
  ║                             ERRORS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  error ValueOutOfCastRange();

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @dev Returns the downcasted int8 from int256, reverting on overflow
   * @param value int256 to be downcasted
   * @return downcasted Downcasted int8 value
   * Counterpart to Solidity's `int8` operator
   */
  function toInt8(int256 value) internal pure returns (int8 downcasted) {
    downcasted = int8(value);
    if (downcasted != value) {
      revert ValueOutOfCastRange();
    }
  }

  /**
   * @dev Returns the downcasted int16 from int256, reverting on overflow
   * @param value int256 to be downcasted
   * @return downcasted Downcasted int16 value
   * Counterpart to Solidity's `int16` operator
   */
  function toInt16(int256 value) internal pure returns (int16 downcasted) {
    downcasted = int16(value);
    if (downcasted != value) {
      revert ValueOutOfCastRange();
    }
  }

  /**
   * @dev Returns the downcasted int32 from int256, reverting on overflow
   * @param value int256 to be downcasted
   * @return downcasted Downcasted int32 value
   * Counterpart to Solidity's `int32` operator
   */
  function toInt32(int256 value) internal pure returns (int32 downcasted) {
    downcasted = int32(value);
    if (downcasted != value) {
      revert ValueOutOfCastRange();
    }
  }

  /**
   * @dev Returns the downcasted int64 from int256, reverting on overflow
   * @param value int256 to be downcasted
   * @return downcasted Downcasted int64 value
   * Counterpart to Solidity's `int64` operator
   */
  function toInt64(int256 value) internal pure returns (int64 downcasted) {
    downcasted = int64(value);
    if (downcasted != value) {
      revert ValueOutOfCastRange();
    }
  }

  /**
   * @dev Returns the downcasted int128 from int256, reverting on overflow
   * @param value int256 to be downcasted
   * @return downcasted Downcasted int128 value
   * Counterpart to Solidity's `int128` operator
   */
  function toInt128(int256 value) internal pure returns (int128 downcasted) {
    downcasted = int128(value);
    if (downcasted != value) {
      revert ValueOutOfCastRange();
    }
  }

  /**
   * @dev Returns the downcasted int192 from int256, reverting on overflow
   * @param value int256 to be downcasted
   * @return downcasted Downcasted int192 value
   * Counterpart to Solidity's `int192` operator (not directly supported)
   */
  function toInt192(int256 value) internal pure returns (int192 downcasted) {
    downcasted = int192(value);
    if (downcasted != value) {
      revert ValueOutOfCastRange();
    }
  }

  /**
   * @dev Returns the downcasted int224 from int256, reverting on overflow
   * @param value int256 to be downcasted
   * @return downcasted Downcasted int224 value
   * Counterpart to Solidity's `int224` operator (not directly supported)
   */
  function toInt224(int256 value) internal pure returns (int224 downcasted) {
    downcasted = int224(value);
    if (downcasted != value) {
      revert ValueOutOfCastRange();
    }
  }

  /**
   * @dev Returns the downcasted int256 from uint256, reverting on overflow
   * @param value Uint256 to be downcasted
   * @return downcasted Downcasted int256 value
   * Counterpart to Solidity's `int256` operator
   */
  function toInt256(uint256 value) internal pure returns (int256 downcasted) {
    downcasted = int256(value);
    if (downcasted < 0) {
      revert ValueOutOfCastRange();
    }
  }

  /**
   * @notice Converts an unsigned integer to an 8-bit unsigned integer
   * @dev Requires the input to be within the valid range for an 8-bit unsigned integer
   * @param x Input unsigned integer
   * @return Input value as an 8-bit unsigned integer
   */
  function toUint8(uint256 x) internal pure returns (uint8) {
    if (x > type(uint8).max) revert ValueOutOfCastRange();
    return uint8(x);
  }

  /**
   * @notice Converts an unsigned integer to a 16-bit unsigned integer
   * @dev Requires the input to be within the valid range for a 16-bit unsigned integer
   * @param x Input unsigned integer
   * @return Input value as a 16-bit unsigned integer
   */
  function toUint16(uint256 x) internal pure returns (uint16) {
    if (x > type(uint16).max) revert ValueOutOfCastRange();
    return uint16(x);
  }

  /**
   * @notice Converts an unsigned integer to a 32-bit unsigned integer
   * @dev Requires the input to be within the valid range for a 32-bit unsigned integer
   * @param x Input unsigned integer
   * @return Input value as a 32-bit unsigned integer
   */
  function toUint32(uint256 x) internal pure returns (uint32) {
    if (x > type(uint32).max) revert ValueOutOfCastRange();
    return uint32(x);
  }

  /**
   * @notice Converts an unsigned integer to a 64-bit unsigned integer
   * @dev Requires the input to be within the valid range for a 64-bit unsigned integer
   * @param x Input unsigned integer
   * @return Input value as a 64-bit unsigned integer
   */
  function toUint64(uint256 x) internal pure returns (uint64) {
    if (x > type(uint64).max) revert ValueOutOfCastRange();
    return uint64(x);
  }

  /**
   * @notice Converts an unsigned integer to a 96-bit unsigned integer
   * @dev Requires the input to be within the valid range for a 96-bit unsigned integer
   * @param x Input unsigned integer
   * @return Input value as a 96-bit unsigned integer
   */
  function toUint96(uint256 x) internal pure returns (uint96) {
    if (x > type(uint96).max) revert ValueOutOfCastRange();
    return uint96(x);
  }

  /**
   * @notice Converts an unsigned integer to a 128-bit unsigned integer
   * @dev Requires the input to be within the valid range for a 128-bit unsigned integer
   * @param x Input unsigned integer
   * @return Input value as a 128-bit unsigned integer
   */
  function toUint128(uint256 x) internal pure returns (uint128) {
    if (x > type(uint128).max) revert ValueOutOfCastRange();
    return uint128(x);
  }

  /**
   * @notice Converts an unsigned integer to a 160-bit unsigned integer
   * @dev Requires the input to be within the valid range for a 160-bit unsigned integer
   * @param x Input unsigned integer
   * @return Input value as a 160-bit unsigned integer
   */
  function toUint160(uint256 x) internal pure returns (uint160) {
    if (x > type(uint160).max) revert ValueOutOfCastRange();
    return uint160(x);
  }

  /**
   * @notice Converts an unsigned integer to a 192-bit unsigned integer
   * @dev Requires the input to be within the valid range for a 192-bit unsigned integer
   * @param x Input unsigned integer
   * @return Input value as a 192-bit unsigned integer
   */
  function toUint192(uint256 x) internal pure returns (uint192) {
    if (x > type(uint192).max) revert ValueOutOfCastRange();
    return uint192(x);
  }

  /**
   * @notice Converts an unsigned integer to a 224-bit unsigned integer
   * @dev Requires the input to be within the valid range for a 224-bit unsigned integer
   * @param x Input unsigned integer
   * @return Input value as a 224-bit unsigned integer
   */
  function toUint224(uint256 x) internal pure returns (uint224) {
    if (x > type(uint224).max) revert ValueOutOfCastRange();
    return uint224(x);
  }

  /**
   * @notice Converts an unsigned integer to a 256-bit unsigned integer
   * @dev Requires the input to be within the valid range for a 256-bit unsigned integer
   * @param x Input integer
   * @return Input value as a 256-bit unsigned integer
   */
  function toUint256(int256 x) internal pure returns (uint256) {
    if (x < 0) revert ValueOutOfCastRange();
    return uint256(x);
  }

  /**
   * @dev Converts an address to bytes32
   * @param addr Address to be converted
   * @return Bytes32 representation of the address
   */
  function toBytes32(address addr) internal pure returns (bytes32) {
    return bytes32(uint256(uint160(addr)));
  }

  /**
   * @dev Converts a bytes32 value to an address
   * @param b Bytes32 value to convert
   * @return Converted address
   */
  function toAddress(bytes32 b) internal pure returns (address) {
    return address(toUint160(uint256(b)));
  }
}
