/**
 * @title Uniswap's FixedPoint96
 * @notice see https://en.wikipedia.org/wiki/Q_(number_format)
 * @dev Used in SqrtPriceMath.sol
 */
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96; // Number of bits for representing fixed point numbers
    uint256 internal constant Q96 = 0x1000000000000000000000000; // 2^96, representing 1 in fixed point format
}