// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library BitMask {

    error WrongPosition();
    uint256 private constant BITS = type(uint256).max;
    function initialize() internal pure returns (uint256) {
        return 0;
    }
    function setBit(uint256 bitmask, uint8 position) internal pure returns (uint256) {
        if (position > 256) revert WrongPosition();
        return bitmask | (1 << position);
    }
    function getBit(uint256 bitmask, uint8 position) internal pure returns (bool) {
        if (position > 256) revert WrongPosition();
        return (bitmask & (1 << position)) != 0;
    }
    function resetBit(uint256 bitmask, uint8 position) internal pure returns (uint256) {
        if (position > 256) revert WrongPosition();
        return bitmask & ~(1 << position);
    }
    function resetAllBits(uint256 bitmask) internal pure returns (uint256) {
        return bitmask & 0;
    }
    function allBitsSet(uint256 bitmask) internal pure returns (bool) {
        return bitmask == BITS;
    }
}
