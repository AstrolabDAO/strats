// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./AsCast.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsMaths Library
 * @author Astrolab DAO - Astrolab's Maths library inspired by many (oz, abdk, prb, uniswap...)
 */
library AsMaths {
  using AsCast for uint256;
  using AsCast for int256;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

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

  /*═══════════════════════════════════════════════════════════════╗
  ║                             ERRORS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  error MathOverflowedMulDiv(); // overflow during multiplication or division

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  // Constants
  uint256 internal constant BP_BASIS = 100_00; // 50% == 5_000 == 5e3
  uint256 internal constant PRECISION_BP_BASIS = BP_BASIS ** 2; // 50% == 50_000_000 == 5e7
  uint256 internal constant SEC_PER_YEAR = 31_556_952; // 365.2425 days, more precise than 365 days const
  uint256 internal constant MAX_UINT256 = type(uint256).max;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Subtracts a certain proportion from a given amount
   * @param amount Initial amount
   * @param basisPoints Proportion to subtract
   * @return Result of subtracting the proportion
   */
  function subBp(uint256 amount, uint256 basisPoints) internal pure returns (uint256) {
    return mulDiv(amount, BP_BASIS - basisPoints, BP_BASIS);
  }

  /**
   * @notice Adds a certain proportion to a given amount
   * @param amount Initial amount
   * @param basisPoints Proportion to add
   * @return Result of adding the proportion
   */
  function addBp(uint256 amount, uint256 basisPoints) internal pure returns (uint256) {
    return mulDiv(amount, BP_BASIS + basisPoints, BP_BASIS);
  }

  /**
   * @notice Calculates the proportion of a given amount
   * @param amount Initial amount
   * @param basisPoints Proportion to calculate
   * @return Calculated proportion of the amount /BP_BASIS
   */
  function bp(uint256 amount, uint256 basisPoints) internal pure returns (uint256) {
    return mulDiv(amount, basisPoints, BP_BASIS);
  }

  /**
   * @notice Calculates the proportion of a given amount (inverted)
   * @param amount Initial amount
   * @param basisPoints Proportion to calculate
   * @return Calculated proportion of the amount /BP_BASIS
   */
  function revBp(uint256 amount, uint256 basisPoints) internal pure returns (uint256) {
    return mulDiv(amount, basisPoints, BP_BASIS - basisPoints);
  }

  /**
   * @notice Calculates the precise proportion of a given amount
   * @param amount Initial amount
   * @param basisPoints Proportion to calculate
   * @return Calculated proportion of the amount /PRECISION_BP_BASIS
   */
  function precisionBp(
    uint256 amount,
    uint256 basisPoints
  ) internal pure returns (uint256) {
    return mulDiv(amount, basisPoints, PRECISION_BP_BASIS);
  }

  /**
   * @notice Calculates the reverse of adding a certain proportion to a given amount
   * @param amount Initial amount
   * @param basisPoints Proportion to reverse add
   * @return Result of reverse adding the proportion
   */
  function revAddBp(uint256 amount, uint256 basisPoints) internal pure returns (uint256) {
    return mulDiv(amount, BP_BASIS, BP_BASIS - basisPoints);
  }

  /**
   * @notice Calculates the reverse of subtracting a certain proportion from a given amount
   * @param amount Initial amount
   * @param basisPoints Proportion to reverse subtract
   * @return Result of reverse subtracting the proportion
   */
  function revSubBp(uint256 amount, uint256 basisPoints) internal pure returns (uint256) {
    return mulDiv(amount, BP_BASIS, BP_BASIS + basisPoints);
  }

  /**
   * @notice Checks if the difference between two values is within a specified range
   * @param a First value
   * @param b Second value
   * @param val Allowable difference
   * @return Boolean indicating if the difference is within the specified range
   */
  function within(uint256 a, uint256 b, uint256 val) internal pure returns (bool) {
    return diff(a, b) <= val;
  }

  /**
   * @notice Checks if the difference between two values is within 1
   * @param a First value
   * @param b Second value
   * @return Boolean indicating if the difference is within 1
   */
  function within1(uint256 a, uint256 b) internal pure returns (bool) {
    return within(a, b, 1);
  }

  /**
   * @notice Calculates the absolute difference between two values
   * @param a First value
   * @param b Second value
   * @return Absolute difference between the two values
   */
  function diff(uint256 a, uint256 b) internal pure returns (uint256) {
    unchecked {
      return a > b ? a - b : b - a;
    }
  }

  /**
   * @notice Subtracts a value from another with a minimum of 0
   * @param a Initial value
   * @param b Value to subtract
   * @return Result of subtracting the value, with a minimum of 0
   */
  function subMax0(uint256 a, uint256 b) internal pure returns (uint256) {
    unchecked {
      return a >= b ? a - b : 0;
    }
  }

  /**
   * @notice Subtracts one integer from another with a requirement that the result is non-negative
   * @param a Initial integer
   * @param b Integer to subtract
   * @return Result of subtracting the integer, with a requirement that the result is non-negative
   */
  function subNoNeg(int256 a, int256 b) internal pure returns (int256) {
    if (a < b) revert AsCast.ValueOutOfCastRange();
    return a - b; // no unchecked since if b is very negative, a - b might overflow
  }

  /**
   * @notice Multiplies two unsigned integers and round down to the nearest whole number
   * @dev Uses unchecked to handle potential overflow situations
   * @param a First unsigned integer
   * @param b Second unsigned integer
   * @return Result of multiplying and rounding down
   */
  function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 product = a * b;
    unchecked {
      return product / 1e18;
    }
  }

  /**
   * @notice Multiplies two signed integers and round down to the nearest whole number
   * @dev Uses unchecked to handle potential overflow situations
   * @param a First signed integer
   * @param b Second signed integer
   * @return Result of multiplying and rounding down
   */
  function mulDown(int256 a, int256 b) internal pure returns (int256) {
    int256 product = a * b;
    unchecked {
      return product / 1e18;
    }
  }

  /**
   * @notice Divides one unsigned integer by another and round down to the nearest whole number
   * @dev Uses unchecked to handle potential overflow situations
   * @param a Numerator
   * @param b Denominator
   * @return Result of dividing and rounding down
   */
  function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 aInflated = a * 1e18;
    unchecked {
      return aInflated / b;
    }
  }

  /**
   * @notice Divides one signed integer by another and round down to the nearest whole number
   * @dev Uses unchecked to handle potential overflow situations
   * @param a Numerator
   * @param b Denominator
   * @return Result of dividing and rounding down
   */
  function divDown(int256 a, int256 b) internal pure returns (int256) {
    int256 aInflated = a * 1e18;
    unchecked {
      return aInflated / b;
    }
  }

  /**
   * @notice Divides one unsigned integer by another and round up to the nearest whole number
   * @dev Uses unchecked to handle potential overflow situations
   * @param a Numerator
   * @param b Denominator
   * @return Result of dividing and rounding up
   */
  function rawDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
    return (a + b - 1) / b;
  }

  /**
   * @notice Gets the absolute value of a signed integer
   * @param x Input signed integer
   * @return Absolute value of the input
   */
  function abs(int256 x) internal pure returns (uint256) {
    return x == type(int256).min ? uint256(type(int256).max) + 1 : uint256(x > 0 ? x : -x);
  }

  /**
   * @notice Negates a signed integer
   * @param x Input signed integer
   * @return Negated value of the input
   */
  function neg(int256 x) internal pure returns (int256) {
    return x * -1;
  }

  /**
   * @notice Negates an unsigned integer
   * @param x Input unsigned integer
   * @return Negated value of the input as a signed integer
   */
  function neg(uint256 x) internal pure returns (int256) {
    return x.toInt256() * -1;
  }

  function max(uint256 x, uint256 y) internal pure returns (uint256) {
    return x > y ? x : y;
  }

  function max(int256 x, int256 y) internal pure returns (int256) {
    return x > y ? x : y;
  }

  function min(uint256 x, uint256 y) internal pure returns (uint256) {
    return x < y ? x : y;
  }

  function min(int256 x, int256 y) internal pure returns (int256) {
    return x < y ? x : y;
  }

  /**
   * @notice Checks if two unsigned integers are approximately equal within a specified tolerance
   * @dev Uses `mulDown` for the comparison to handle precision loss
   * @param a First unsigned integer
   * @param b Second unsigned integer
   * @param eps Maximum allowable difference between `a` and `b`
   * @return Boolean indicating whether the two values are approximately equal
   */
  function approxEq(uint256 a, uint256 b, uint256 eps) internal pure returns (bool) {
    return mulDown(b, 1e18 - eps) <= a && a <= mulDown(b, 1e18 + eps);
  }

  /**
   * @notice Checks if one unsigned integer is approximately greater than another within a specified tolerance
   * @dev Uses `mulDown` for the comparison to handle precision loss
   * @param a First unsigned integer
   * @param b Second unsigned integer
   * @param eps Maximum allowable difference between `a` and `b`
   * @return Boolean indicating whether `a` is approximately greater than `b`
   */
  function approxGt(uint256 a, uint256 b, uint256 eps) internal pure returns (bool) {
    return a >= b && a <= mulDown(b, 1e18 + eps);
  }

  /**
   * @notice Checks if one unsigned integer is approximately less than another within a specified tolerance
   * @dev Uses `mulDown` for the comparison to handle precision loss
   * @param a First unsigned integer
   * @param b Second unsigned integer
   * @param eps Maximum allowable difference between `a` and `b`
   * @return Boolean indicating whether `a` is approximately less than `b`
   */
  function approxLt(uint256 a, uint256 b, uint256 eps) internal pure returns (bool) {
    return a <= b && a >= mulDown(b, 1e18 - eps);
  }

  /**
   * @notice Attempts to add two unsigned integers with overflow protection
   * @dev Uses unchecked to handle potential overflow situations
   * @param a First unsigned integer
   * @param b Second unsigned integer
   * @return Tuple with a boolean indicating success and the result of the addition
   */
  function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
    unchecked {
      uint256 c = a + b;
      if (c < a) {
        // overflow occurred
        return (false, 0);
      }
      return (true, c);
    }
  }

  /**
   * @notice Attempts to subtract one unsigned integer from another with overflow protection
   * @dev Uses unchecked to handle potential overflow situations
   * @param a First unsigned integer
   * @param b Second unsigned integer
   * @return Tuple with a boolean indicating success and the result of the subtraction
   */
  function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
    unchecked {
      if (b > a) {
        // underflow occurred
        return (false, 0);
      }
      return (true, a - b);
    }
  }

  /**
   * @notice Attempts to multiply two unsigned integers with overflow protection
   * @dev Uses unchecked to handle potential overflow situations
   * @param a First unsigned integer
   * @param b Second unsigned integer
   * @return Tuple with a boolean indicating success and the result of the multiplication
   */
  function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
    unchecked {
      // gas optimization: this is cheaper than requiring 'a' not being zero, but the
      // benefit is lost if 'b' is also tested
      // see: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
      if (a == 0) {
        return (true, 0);
      }
      uint256 c = a * b;
      if (c / a != b) {
        // overflow occurred
        return (false, 0);
      }
      return (true, c);
    }
  }

  /**
   * @dev Returnss the division of two unsigned integers, with a division by zero flag
   * @param a Numerator
   * @param b Denominator
   * @return Tuple with a boolean indicating success and the result of the division
   */
  function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
    unchecked {
      if (b == 0) return (false, 0);
      return (true, a / b);
    }
  }

  /**
   * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag
   * @param a Numerator
   * @param b Denominator
   * @return Tuple with a boolean indicating success and the result of the remainder
   */
  function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
    unchecked {
      if (b == 0) return (false, 0);
      return (true, a % b);
    }
  }

  /**
   * @dev Returns the average of two numbers. Result is rounded towards zero
   * @param a First number
   * @param b Second number
   * @return Average of the two numbers
   */
  function average(uint256 a, uint256 b) internal pure returns (uint256) {
    // (a + b) / 2 can overflow
    return (a & b) + (a ^ b) / 2;
  }

  /**
   * @dev Returns the ceiling of the division of two numbers
   *
   * This differs from standard division with `/` in that it rounds towards infinity instead
   * of rounding towards zero
   * @param a Numerator
   * @param b Denominator
   * @return Ceiling of the division
   */
  function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
    if (b == 0) {
      // guarantee the same behavior as in a regular Solidity division
      return a / b;
    }

    // (a + b - 1) / b can overflow on addition, so we distribute
    return a == 0 ? 0 : (a - 1) / b + 1;
  }

  /**
   * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or
   * denominator == 0
   * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv) with further edits by
   * Uniswap Labs also under MIT license
   * @param x Numerator
   * @param y Numerator
   * @param denominator Denominator
   * @return result Result of floor(x * y / denominator)
   */
  function mulDiv(
    uint256 x,
    uint256 y,
    uint256 denominator
  ) internal pure returns (uint256 result) {
    unchecked {
      // 512-bit multiply [prod1 prod0] = x * y
      // compute the product mod 2^256 and mod 2^256 - 1, then use
      // the Chinese Remainder Theorem to reconstruct the 512 bit result
      // the result is stored in two 256
      // variables such that product = prod1 * 2^256 + prod0
      uint256 prod0 = x * y; // least significant 256 bits of the product
      uint256 prod1; // most significant 256 bits of the product
      assembly {
        let mm := mulmod(x, y, not(0))
        prod1 := sub(sub(mm, prod0), lt(mm, prod0))
      }

      // handle non-overflow cases, 256 by 256 division
      if (prod1 == 0) {
        // solidity will revert if denominator == 0, unlike the div opcode on its own
        // the surrounding unchecked block does not change this fact
        // see https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic
        return prod0 / denominator;
      }

      // make sure the result is less than 2^256, also prevents denominator == 0
      require(denominator > prod1);

      // 512 by 256 division
      // make division exact by subtracting the remainder from [prod1 prod0]
      uint256 remainder;
      assembly {
        // compute remainder using mulmod
        remainder := mulmod(x, y, denominator)

        // subtract 256 bit number from 512 bit number
        prod1 := sub(prod1, gt(remainder, prod0))
        prod0 := sub(prod0, remainder)
      }

      // factor powers of two out of denominator and compute the largest power of two divisor of denominator
      // always >= 1. See https://cs.stackexchange.com/q/138556/92363

      uint256 twos = denominator & (0 - denominator);
      assembly {
        // divide denominator by twos
        denominator := div(denominator, twos)

        // divide [prod1 prod0] by twos
        prod0 := div(prod0, twos)

        // flip twos such that it is 2^256 / twos, if twos is zero, then it becomes one
        twos := add(div(sub(0, twos), twos), 1)
      }

      // shift in bits from prod1 into prod0
      prod0 |= prod1 * twos;

      // invert denominator mod 2^256, now that denominator is an odd number, it has an inverse modulo 2^256 such
      // that denominator * inv = 1 mod 2^256, compute the inverse by starting with a seed that is correct for
      // four bits, that is, denominator * inv = 1 mod 2^4
      uint256 inverse = (3 * denominator) ^ 2;

      // use the Newton-Raphson iteration to improve the precision, thanks to Hensel's lifting lemma, this also
      // works in modular arithmetic, doubling the correct bits in each step
      inverse *= 2 - denominator * inverse; // inverse mod 2^8
      inverse *= 2 - denominator * inverse; // inverse mod 2^16
      inverse *= 2 - denominator * inverse; // inverse mod 2^32
      inverse *= 2 - denominator * inverse; // inverse mod 2^64
      inverse *= 2 - denominator * inverse; // inverse mod 2^128
      inverse *= 2 - denominator * inverse; // inverse mod 2^256

      // because the division is now exact we can divide by multiplying with the modular inverse of denominator
      // this will give us the correct result modulo 2^256
      // since the preconditions guarantee that the outcome is less than 2^256, this is the final result
      // we don't need to compute the high bits of the result and prod1
      // is no longer required
      result = prod0 * inverse;
      return result;
    }
  }

  /**
   * @notice Calculates x * y / denominator with full precision, following the selected rounding direction
   * @param x Numerator
   * @param y Numerator
   * @param denominator Denominator
   * @param rounding Rounding direction
   * @return Result of x * y / denominator with the specified rounding
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
   * @param x Numerator
   * @param y Numerator
   * @param denominator Denominator
   * @return Result of x * y / denominator rounded up
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
   * @param a Input value
   * @return Square root of the input value
   */
  function sqrt(uint256 a) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }

    // for our first guess, we get the biggest power of 2 which is smaller than the square root of the target
    //
    // we know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
    // `msb(a) <= a < 2*msb(a)`
    // this value can be written `msb(a)=2**k` with `k=log2(a)`
    // this can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
    // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
    // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
    //
    // consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit
    uint256 result = 1 << (log2(a) >> 1);

    // at this point `result` is an estimation with one bit of precision
    // we know the true value is a uint128, since it is the square root of a uint256
    // newton's method converges quadratically (precision doubles at every iteration)
    // we thus need at most 7 iteration to turn our partial result with one bit of precision
    // into the expected uint128 result
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
   * @param a Input value
   * @param rounding Rounding direction
   * @return Square root of the input value with the specified rounding
   */
  function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
    unchecked {
      uint256 result = sqrt(a);
      return result + (unsignedRoundsUp(rounding) && result * result < a ? 1 : 0);
    }
  }

  /**
   * @dev Returns the log in base 2 of a positive value rounded towards zero
   * Returns 0 if given 0
   * @param value Input value
   * @return Log in base 2 of the input value
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
   * @dev Returns the log in base 2, following the selected rounding direction, of a positive value
   * Returns 0 if given 0
   * @param value Input value
   * @param rounding Rounding direction
   * @return Log in base 2 of the input value with the specified rounding
   */
  function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
    unchecked {
      uint256 result = log2(value);
      return result + (unsignedRoundsUp(rounding) && 1 << result < value ? 1 : 0);
    }
  }

  /**
   * @dev Returns the log in base 10 of a positive value rounded towards zero
   * Returns 0 if given 0
   * @param value Input value
   * @return Log in base 10 of the input value
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
   * @dev Returns the log in base 10, following the selected rounding direction, of a positive value
   * Returns 0 if given 0
   * @param value Input value
   * @param rounding Rounding direction
   * @return Log in base 10 of the input value with the specified rounding
   */
  function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
    unchecked {
      uint256 result = log10(value);
      return result + (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
    }
  }

  /**
   * @dev Returns the log in base 256 of a positive value rounded towards zero
   * Returns 0 if given 0
   * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string
   * @param value Input value
   * @return Log in base 256 of the input value
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
   * @dev Returns the log in base 256, following the selected rounding direction, of a positive value
   * Returns 0 if given 0
   * @param value Input value
   * @param rounding Rounding direction
   * @return Log in base 256 of the input value with the specified rounding
   */
  function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
    unchecked {
      uint256 result = log256(value);
      return result + (unsignedRoundsUp(rounding) && 1 << (result << 3) < value ? 1 : 0);
    }
  }

  /**
   * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers
   * @param rounding Rounding direction
   * @return Whether the provided rounding mode is considered rounding up for unsigned integers
   */
  function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
    return uint8(rounding) % 2 == 1;
  }

  /**
   * @notice Computes the `_base` per `_quote` exchange rate in bps
   * @param _base Address of the base token
   * @param _baseDecimals Decimals of the base token
   * @param _quote Address of the quote token
   * @return Exchange rate in quote bps
   */
  function exchangeRate(
    uint256 _base,
    uint8 _baseDecimals,
    uint256 _quote
  ) internal pure returns (uint256) {
    require(_quote > 0 && _base > 0);
    return (_quote * (10 ** uint256(_baseDecimals))) / _base;
  }

  /**
   * @dev Calculates the sum of an array of uint256 values
   * @param data The array of uint256 values
   * @return total sum of the array elements
   */
  function sum(uint256[] memory data) internal pure returns (uint256 total) {
    unchecked {
      for (uint256 i = 0; i < data.length; i++) {
        total += data[i];
      }
    }
  }

  function sum(uint256[8] memory data) internal pure returns (uint256 total) {
    unchecked {
      for (uint256 i = 0; i < data.length; i++) {
        total += data[i];
      }
    }
  }

  function sum(int256[] memory data) internal pure returns (int256 total) {
    unchecked {
      for (uint256 i = 0; i < data.length; i++) {
        total += data[i];
      }
    }
  }

  function sum(int256[8] memory data) internal pure returns (int256 total) {
    unchecked {
      for (uint256 i = 0; i < data.length; i++) {
        total += data[i];
      }
    }
  }
}
