// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "./AsCast.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsMaths Library
 * @author Astrolab DAO
 * @notice Astrolab's Maths library inspired by many (oz, abdk, prb, uniswap...)
 * @dev This library helps with high level maths
 */
library AsMaths {
    using AsCast for uint256;
    using AsCast for int256;

    // Constants
    uint256 internal constant BP_BASIS = 100_00; // 50% == 5_000 == 5e3
    uint256 internal constant PRECISION_BP_BASIS = BP_BASIS ** 2; // 50% == 50_000_000 == 5e7
    uint256 internal constant SEC_PER_YEAR = 31_556_952; // 365.2425 days, more precise than 365 days const

    /**
     * @notice Subtract a certain proportion from a given amount
     * @param amount The initial amount
     * @param basisPoints The proportion to subtract
     * @return The result of subtracting the proportion
     */
    function subBp(
        uint256 amount,
        uint256 basisPoints
    ) internal pure returns (uint256) {
        return mulDiv(amount, BP_BASIS - basisPoints, BP_BASIS);
    }

    /**
     * @notice Add a certain proportion to a given amount
     * @param amount The initial amount
     * @param basisPoints The proportion to add
     * @return The result of adding the proportion
     */
    function addBp(
        uint256 amount,
        uint256 basisPoints
    ) internal pure returns (uint256) {
        return mulDiv(amount, BP_BASIS + basisPoints, BP_BASIS);
    }

    /**
     * @notice Calculate the proportion of a given amount
     * @param amount The initial amount
     * @param basisPoints The proportion to calculate
     * @return The calculated proportion of the amount /BP_BASIS
     */
    function bp(
        uint256 amount,
        uint256 basisPoints
    ) internal pure returns (uint256) {
        return mulDiv(amount, basisPoints, BP_BASIS);
    }

    /**
     * @notice Calculate the proportion of a given amount (inverted)
     * @param amount The initial amount
     * @param basisPoints The proportion to calculate
     * @return The calculated proportion of the amount /BP_BASIS
     */
    function revBp(
        uint256 amount,
        uint256 basisPoints
    ) internal pure returns (uint256) {
        return mulDiv(amount, basisPoints, BP_BASIS - basisPoints);
    }

    /**
     * @notice Calculate the precise proportion of a given amount
     * @param amount The initial amount
     * @param basisPoints The proportion to calculate
     * @return The calculated proportion of the amount /PRECISION_BP_BASIS
     */
    function precisionBp(
        uint256 amount,
        uint256 basisPoints
    ) internal pure returns (uint256) {
        return mulDiv(amount, basisPoints, PRECISION_BP_BASIS);
    }

    /**
     * @notice Calculate the reverse of adding a certain proportion to a given amount
     * @param amount The initial amount
     * @param basisPoints The proportion to reverse add
     * @return The result of reverse adding the proportion
     */
    function revAddBp(
        uint256 amount,
        uint256 basisPoints
    ) internal pure returns (uint256) {
        return mulDiv(amount, BP_BASIS, BP_BASIS - basisPoints);
    }

    /**
     * @notice Calculate the reverse of subtracting a certain proportion from a given amount
     * @param amount The initial amount
     * @param basisPoints The proportion to reverse subtract
     * @return The result of reverse subtracting the proportion
     */
    function revSubBp(
        uint256 amount,
        uint256 basisPoints
    ) internal pure returns (uint256) {
        return mulDiv(amount, BP_BASIS, BP_BASIS + basisPoints);
    }

    /**
     * @notice Check if the difference between two values is within a specified range
     * @param a The first value
     * @param b The second value
     * @param val The allowable difference
     * @return A boolean indicating if the difference is within the specified range
     */
    function within(
        uint256 a,
        uint256 b,
        uint256 val
    ) internal pure returns (bool) {
        return (diff(a, b) <= val);
    }

    /**
     * @notice Check if the difference between two values is within 1
     * @param a The first value
     * @param b The second value
     * @return A boolean indicating if the difference is within 1
     */
    function within1(uint256 a, uint256 b) internal pure returns (bool) {
        return within(a, b, 1);
    }

    /**
     * @notice Calculate the absolute difference between two values
     * @param a The first value
     * @param b The second value
     * @return The absolute difference between the two values
     */
    function diff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    /**
     * @notice Subtract a value from another with a minimum of 0
     * @param a The initial value
     * @param b The value to subtract
     * @return The result of subtracting the value, with a minimum of 0
     */
    function subMax0(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return (a >= b ? a - b : 0);
        }
    }

    /**
     * @notice Subtract one integer from another with a requirement that the result is non-negative
     * @param a The initial integer
     * @param b The integer to subtract
     * @return The result of subtracting the integer, with a requirement that the result is non-negative
     */
    function subNoNeg(int256 a, int256 b) internal pure returns (int256) {
        if (a < b) revert AsCast.ValueOutOfCastRange();
        return a - b; // no unchecked since if b is very negative, a - b might overflow
    }

    /**
     * @notice Multiply two unsigned integers and round down to the nearest whole number
     * @dev Uses unchecked to handle potential overflow situations
     * @param a The first unsigned integer
     * @param b The second unsigned integer
     * @return The result of multiplying and rounding down
     */
    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 product = a * b;
        unchecked {
            return product / 1e18;
        }
    }

    /**
     * @notice Multiply two signed integers and round down to the nearest whole number
     * @dev Uses unchecked to handle potential overflow situations
     * @param a The first signed integer
     * @param b The second signed integer
     * @return The result of multiplying and rounding down
     */
    function mulDown(int256 a, int256 b) internal pure returns (int256) {
        int256 product = a * b;
        unchecked {
            return product / 1e18;
        }
    }

    /**
     * @notice Divide one unsigned integer by another and round down to the nearest whole number
     * @dev Uses unchecked to handle potential overflow situations
     * @param a The numerator
     * @param b The denominator
     * @return The result of dividing and rounding down
     */
    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 aInflated = a * 1e18;
        unchecked {
            return aInflated / b;
        }
    }

    /**
     * @notice Divide one signed integer by another and round down to the nearest whole number
     * @dev Uses unchecked to handle potential overflow situations
     * @param a The numerator
     * @param b The denominator
     * @return The result of dividing and rounding down
     */
    function divDown(int256 a, int256 b) internal pure returns (int256) {
        int256 aInflated = a * 1e18;
        unchecked {
            return aInflated / b;
        }
    }

    /**
     * @notice Divide one unsigned integer by another and round up to the nearest whole number
     * @dev Uses unchecked to handle potential overflow situations
     * @param a The numerator
     * @param b The denominator
     * @return The result of dividing and rounding up
     */
    function rawDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }

    /**
     * @notice Get the absolute value of a signed integer
     * @param x The input signed integer
     * @return The absolute value of the input
     */
    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x > 0 ? x : -x);
    }

    /**
     * @notice Negate a signed integer
     * @param x The input signed integer
     * @return The negated value of the input
     */
    function neg(int256 x) internal pure returns (int256) {
        return x * (-1);
    }

    /**
     * @notice Negate an unsigned integer
     * @param x The input unsigned integer
     * @return The negated value of the input as a signed integer
     */
    function neg(uint256 x) internal pure returns (int256) {
        return x.toInt() * (-1);
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x > y ? x : y);
    }

    function max(int256 x, int256 y) internal pure returns (int256) {
        return (x > y ? x : y);
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x < y ? x : y);
    }

    function min(int256 x, int256 y) internal pure returns (int256) {
        return (x < y ? x : y);
    }

    /**
     * @notice Check if two unsigned integers are approximately equal within a specified tolerance
     * @dev Uses `mulDown` for the comparison to handle precision loss
     * @param a The first unsigned integer
     * @param b The second unsigned integer
     * @param eps The maximum allowable difference between `a` and `b`
     * @return A boolean indicating whether the two values are approximately equal
     */
    function approxEq(
        uint256 a,
        uint256 b,
        uint256 eps
    ) internal pure returns (bool) {
        return mulDown(b, 1e18 - eps) <= a && a <= mulDown(b, 1e18 + eps);
    }

    /**
     * @notice Check if one unsigned integer is approximately greater than another within a specified tolerance
     * @dev Uses `mulDown` for the comparison to handle precision loss
     * @param a The first unsigned integer
     * @param b The second unsigned integer
     * @param eps The maximum allowable difference between `a` and `b`
     * @return A boolean indicating whether `a` is approximately greater than `b`
     */
    function approxGt(
        uint256 a,
        uint256 b,
        uint256 eps
    ) internal pure returns (bool) {
        return a >= b && a <= mulDown(b, 1e18 + eps);
    }

    /**
     * @notice Check if one unsigned integer is approximately less than another within a specified tolerance
     * @dev Uses `mulDown` for the comparison to handle precision loss
     * @param a The first unsigned integer
     * @param b The second unsigned integer
     * @param eps The maximum allowable difference between `a` and `b`
     * @return A boolean indicating whether `a` is approximately less than `b`
     */
    function approxLt(
        uint256 a,
        uint256 b,
        uint256 eps
    ) internal pure returns (bool) {
        return a <= b && a >= mulDown(b, 1e18 - eps);
    }

    /**
     * @notice Custom error for math overflow during multiplication or division
     */
    error MathOverflowedMulDiv();

    /**
     * @notice Enumeration for rounding modes
     * @dev Four rounding modes: Floor, Ceil, Trunc, Expand
     */
    enum Rounding {
        Floor, // Toward negative infinity
        Ceil, // Toward positive infinity
        Trunc, // Toward zero
        Expand // Away from zero
    }

    /**
     * @notice Attempt to add two unsigned integers with overflow protection
     * @dev Uses unchecked to handle potential overflow situations
     * @param a The first unsigned integer
     * @param b The second unsigned integer
     * @return A tuple with a boolean indicating success and the result of the addition
     */
    function tryAdd(
        uint256 a,
        uint256 b
    ) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) {
                // Overflow occurred
                return (false, 0);
            }
            return (true, c);
        }
    }

    /**
     * @notice Attempt to subtract one unsigned integer from another with overflow protection
     * @dev Uses unchecked to handle potential overflow situations
     * @param a The first unsigned integer
     * @param b The second unsigned integer
     * @return A tuple with a boolean indicating success and the result of the subtraction
     */
    function trySub(
        uint256 a,
        uint256 b
    ) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) {
                // Underflow occurred
                return (false, 0);
            }
            return (true, a - b);
        }
    }

    /**
     * @notice Attempt to multiply two unsigned integers with overflow protection
     * @dev Uses unchecked to handle potential overflow situations
     * @param a The first unsigned integer
     * @param b The second unsigned integer
     * @return A tuple with a boolean indicating success and the result of the multiplication
     */
    function tryMul(
        uint256 a,
        uint256 b
    ) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) {
                return (true, 0);
            }
            uint256 c = a * b;
            if (c / a != b) {
                // Overflow occurred
                return (false, 0);
            }
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag
     * @param a The numerator
     * @param b The denominator
     * @return A tuple with a boolean indicating success and the result of the division
     */
    function tryDiv(
        uint256 a,
        uint256 b
    ) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag
     * @param a The numerator
     * @param b The denominator
     * @return A tuple with a boolean indicating success and the result of the remainder
     */
    function tryMod(
        uint256 a,
        uint256 b
    ) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards zero
     * @param a The first number
     * @param b The second number
     * @return The average of the two numbers
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers
     *
     * This differs from standard division with `/` in that it rounds towards infinity instead
     * of rounding towards zero
     * @param a The numerator
     * @param b The denominator
     * @return The ceiling of the division
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            // Guarantee the same behavior as in a regular Solidity division.
            return a / b;
        }

        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or
     * denominator == 0
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv) with further edits by
     * Uniswap Labs also under MIT license
     * @param x The numerator
     * @param y The numerator
     * @param denominator The denominator
     * @return result The result of floor(x * y / denominator)
     */
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0 = x * y; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            require(denominator > prod1);

            // 512 by 256 division
            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute the largest power of two divisor of denominator.
            // Always >= 1. See https://cs.stackexchange.com/q/138556/92363.

            uint256 twos = denominator & (0 - denominator);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also
            // works in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction
     * @param x The numerator
     * @param y The numerator
     * @param denominator The denominator
     * @param rounding The rounding direction
     * @return The result of x * y / denominator with the specified rounding
     */
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator,
        Rounding rounding
    ) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @notice Calculates x * y / denominator with full precision, rounded up
     * @param x The numerator
     * @param y The numerator
     * @param denominator The denominator
     * @return The result of x * y / denominator rounded up
     */
    function mulDivRoundUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256) {
        return mulDiv(x, y, denominator, Rounding.Ceil);
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded
     * towards zero
     * @param a The input value
     * @return The square root of the input value
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction
     * @param a The input value
     * @param rounding The rounding direction
     * @return The square root of the input value with the specified rounding
     */
    function sqrt(
        uint256 a,
        Rounding rounding
    ) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return
                result +
                (unsignedRoundsUp(rounding) && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2 of a positive value rounded towards zero
     * Returns 0 if given 0
     * @param value The input value
     * @return The log in base 2 of the input value
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value
     * Returns 0 if given 0
     * @param value The input value
     * @param rounding The rounding direction
     * @return The log in base 2 of the input value with the specified rounding
     */
    function log2(
        uint256 value,
        Rounding rounding
    ) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return
                result +
                (unsignedRoundsUp(rounding) && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero
     * Returns 0 if given 0
     * @param value The input value
     * @return The log in base 10 of the input value
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value
     * Returns 0 if given 0
     * @param value The input value
     * @param rounding The rounding direction
     * @return The log in base 10 of the input value with the specified rounding
     */
    function log10(
        uint256 value,
        Rounding rounding
    ) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return
                result +
                (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256 of a positive value rounded towards zero
     * Returns 0 if given 0
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string
     * @param value The input value
     * @return The log in base 256 of the input value
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value
     * Returns 0 if given 0
     * @param value The input value
     * @param rounding The rounding direction
     * @return The log in base 256 of the input value with the specified rounding
     */
    function log256(
        uint256 value,
        Rounding rounding
    ) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return
                result +
                (
                    unsignedRoundsUp(rounding) && 1 << (result << 3) < value
                        ? 1
                        : 0
                );
        }
    }

    /**
     * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers
     * @param rounding The rounding direction
     * @return Whether the provided rounding mode is considered rounding up for unsigned integers
     */
    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }

    /**
     * @notice Calculates the exchange rate in bps (100_00 == 100%) between two prices (in wei)
     * @dev Reverts if either value is zero
     * @param p1 Quote currency price in wei
     * @param p2 Base currency price in wei
     * @param d2 Base decimal places for the second price
     * @return Exchange rate (in bps * 10 ** base decimals)
     */
    function exchangeRate(
        uint256 p1,
        uint256 p2,
        uint8 d2
    ) public pure returns (uint256) {
        require(p1 > 0 && p2 > 0);
        return (p1 * (10 ** uint256(d2))) / p2;
    }
}
