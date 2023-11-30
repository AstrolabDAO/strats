// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsBitMask Library
 * @author Astrolab DAO
 * @notice Astrolab's bit masking library used to store bools/flags in uint256
 * @dev This library helps with high level bit masking
 */
library AsBitMask {

    /**
     * @dev Throws an error if the specified bit position is invalid.
     */
    error WrongPosition();

    /**
     * @dev Maximum value for bits (all bits set to 1).
     */
    uint256 private constant BITS = type(uint256).max;

    /**
     * @notice Initializes a new bitmask.
     * @return The initialized bitmask.
     */
    function initialize() internal pure returns (uint256) {
        return 0;
    }

    /**
     * @notice Sets a specific bit in the bitmask to 1.
     * @param bitmask The original bitmask.
     * @param position The position of the bit to set (0-indexed).
     * @return The updated bitmask.
     * @dev Throws WrongPosition error if the specified position is invalid.
     */
    function setBit(uint256 bitmask, uint8 position) internal pure returns (uint256) {
        if (position > 256) revert WrongPosition();
        return bitmask | (1 << position);
    }

    /**
     * @notice Gets the value of a specific bit in the bitmask.
     * @param bitmask The bitmask to query.
     * @param position The position of the bit to check (0-indexed).
     * @return True if the bit is set, false otherwise.
     * @dev Throws WrongPosition error if the specified position is invalid.
     */
    function getBit(uint256 bitmask, uint8 position) internal pure returns (bool) {
        if (position > 256) revert WrongPosition();
        return (bitmask & (1 << position)) != 0;
    }

    /**
     * @notice Resets a specific bit in the bitmask to 0.
     * @param bitmask The original bitmask.
     * @param position The position of the bit to reset (0-indexed).
     * @return The updated bitmask.
     * @dev Throws WrongPosition error if the specified position is invalid.
     */
    function resetBit(uint256 bitmask, uint8 position) internal pure returns (uint256) {
        if (position > 256) revert WrongPosition();
        return bitmask & ~(1 << position);
    }

    /**
     * @notice Resets all bits in the bitmask to 0.
     * @param bitmask The original bitmask.
     * @return The updated bitmask.
     */
    function resetAllBits(uint256 bitmask) internal pure returns (uint256) {
        return bitmask & 0;
    }

    /**
     * @notice Checks if all bits in the bitmask are set to 1.
     * @param bitmask The bitmask to check.
     * @return True if all bits are set, false otherwise.
     */
    function allBitsSet(uint256 bitmask) internal pure returns (bool) {
        return bitmask == BITS;
    }
}
