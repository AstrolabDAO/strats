// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsBitMask Library - Astrolab's bit masking library
 * @author Astrolab DAO
 */
library AsBitMask {
  /*═══════════════════════════════════════════════════════════════╗
  ║                             ERRORS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  error WrongPosition();

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  uint256 private constant BITS = type(uint256).max; // maximum value for bits (all bits set to 1)

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return Initializes a new bitmask to 0x0
   */
  function initialize() internal pure returns (uint256) {
    return 0;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Sets a specific bit in `_bitmask` to 1
   * @param _bitmask Target bitmask
   * @param position Position of the bit to set (0-indexed)
   * @return Updated bitmask
   */
  function setBit(uint256 _bitmask, uint8 position) internal pure returns (uint256) {
    if (position > 256) revert WrongPosition();
    return _bitmask | (1 << position);
  }

  /**
   * @notice Gets the value of a specific bit in `_bitmask`
   * @param _bitmask Bitmask to query
   * @param position Position of the bit to check (0-indexed)
   * @return Boolean indicating if the bit is set
   */
  function getBit(uint256 _bitmask, uint8 position) internal pure returns (bool) {
    if (position > 256) revert WrongPosition();
    return (_bitmask & (1 << position)) != 0;
  }

  /**
   * @notice Resets a specific bit in `_bitmask` to 0
   * @param _bitmask Target bitmask
   * @param position Position of the bit to reset (0-indexed)
   * @return Updated bitmask
   * @dev Throws WrongPosition error if the specified position is invalid
   */
  function resetBit(uint256 _bitmask, uint8 position) internal pure returns (uint256) {
    if (position > 256) revert WrongPosition();
    return _bitmask & ~(1 << position);
  }

  /**
   * @notice Resets all bits in `_bitmask` to 0
   * @param _bitmask Target bitmask
   * @return Updated `_bitmask`
   */
  function resetAllBits(uint256 _bitmask) internal pure returns (uint256) {
    return _bitmask & 0;
  }

  /**
   * @notice Checks if all bits in the _bitmask are set to 1
   * @param _bitmask The bitmask to check
   * @return Boolean indicating if all bits are set
   */
  function allBitsSet(uint256 _bitmask) internal pure returns (bool) {
    return _bitmask == BITS;
  }
}
