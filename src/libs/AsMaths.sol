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
  uint256 internal constant WAD = 1e18; // 18 decimal fixed-point number
  uint256 internal constant RAY = 1e27; // 27 decimal fixed-point number
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
  function subBp(
    uint256 amount,
    uint256 basisPoints
  ) internal pure returns (uint256) {
    unchecked {
      return mulDiv(amount, BP_BASIS - basisPoints, BP_BASIS);
    }
  }

  /**
   * @notice Adds a certain proportion to a given amount
   * @param amount Initial amount
   * @param basisPoints Proportion to add
   * @return Result of adding the proportion
   */
  function addBp(
    uint256 amount,
    uint256 basisPoints
  ) internal pure returns (uint256) {
    unchecked {
      return mulDiv(amount, BP_BASIS + basisPoints, BP_BASIS);
    }
  }

  /**
   * @notice Calculates the proportion of a given amount
   * @param amount Initial amount
   * @param basisPoints Proportion to calculate
   * @return Calculated proportion of the amount /BP_BASIS
   */
  function bp(
    uint256 amount,
    uint256 basisPoints
  ) internal pure returns (uint256) {
    unchecked {
      return mulDiv(amount, basisPoints, BP_BASIS);
    }
  }

  /**
   * @notice Calculates the proportion of a given amount (inverted)
   * @param amount Initial amount
   * @param basisPoints Proportion to calculate
   * @return Calculated proportion of the amount /BP_BASIS
   */
  function revBp(
    uint256 amount,
    uint256 basisPoints
  ) internal pure returns (uint256) {
    unchecked {
      return mulDiv(amount, basisPoints, BP_BASIS - basisPoints);
    }
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
    unchecked {
      return mulDiv(amount, basisPoints, PRECISION_BP_BASIS);
    }
  }

  /**
   * @notice Calculates the reverse of adding a certain proportion to a given amount
   * @param amount Initial amount
   * @param basisPoints Proportion to reverse add
   * @return Result of reverse adding the proportion
   */
  function revAddBp(
    uint256 amount,
    uint256 basisPoints
  ) internal pure returns (uint256) {
    unchecked {
      return mulDiv(amount, BP_BASIS, BP_BASIS - basisPoints);
    }
  }

  /**
   * @notice Calculates the reverse of subtracting a certain proportion from a given amount
   * @param amount Initial amount
   * @param basisPoints Proportion to reverse subtract
   * @return Result of reverse subtracting the proportion
   */
  function revSubBp(
    uint256 amount,
    uint256 basisPoints
  ) internal pure returns (uint256) {
    unchecked {
      return mulDiv(amount, BP_BASIS, BP_BASIS + basisPoints);
    }
  }

  /**
   * @notice Checks if a value is within a range
   * @param value Value to check
   * @param _min Minimum value
   * @param _max Maximum value
   * @return Boolean indicating if the value is within the range
   */
  function within(uint256 value, uint256 _min, uint256 _max) internal pure returns (bool) {
    unchecked {
      return value >= _min && value <= _max;
    }
  }

  function within(uint32 value, uint32 _min, uint32 _max) internal pure returns (bool) {
    unchecked {
      return value >= _min && value <= _max;
    }
  }

  function within(uint64 value, uint64 _min, uint64 _max) internal pure returns (bool) {
    unchecked {
      return value >= _min && value <= _max;
    }
  }

  function within(int256 value, int256 _min, int256 _max) internal pure returns (bool) {
    unchecked {
      return value >= _min && value <= _max;
    }
  }

  function within32(uint32 value, uint256 _min, uint256 _max) internal pure returns (bool) {
    unchecked {
      return uint256(value) >= _min && uint256(value) <= _max;
    }
  }

  function within64(uint64 value, uint256 _min, uint256 _max) internal pure returns (bool) {
    unchecked {
      return uint256(value) >= _min && uint256(value) <= _max;
    }
  }

  /**
   * @notice Checks if the difference between two values is within a specified range
   * @param a First value
   * @param b Second value
   * @param val Allowable difference
   * @return Boolean indicating if the difference is within the specified range
   */
  function diffWithin(
    uint256 a,
    uint256 b,
    uint256 val
  ) internal pure returns (bool) {
    return diff(a, b) <= val;
  }

  /**
   * @notice Checks if the difference between two values is within 1
   * @param a First value
   * @param b Second value
   * @return Boolean indicating if the difference is within 1
   */
  function diffWithin1(uint256 a, uint256 b) internal pure returns (bool) {
    return diffWithin(a, b, 1);
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
    unchecked {
      return a - b; // no unchecked since if b is very negative, a - b might overflow
    }
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
    return
      x == type(int256).min
        ? uint256(type(int256).max) + 1
        : uint256(x > 0 ? x : -x);
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
  function approxEq(
    uint256 a,
    uint256 b,
    uint256 eps
  ) internal pure returns (bool) {
    return mulDown(b, WAD - eps) <= a && a <= mulDown(b, WAD + eps);
  }

  /**
   * @notice Checks if one unsigned integer is approximately greater than another within a specified tolerance
   * @dev Uses `mulDown` for the comparison to handle precision loss
   * @param a First unsigned integer
   * @param b Second unsigned integer
   * @param eps Maximum allowable difference between `a` and `b`
   * @return Boolean indicating whether `a` is approximately greater than `b`
   */
  function approxGt(
    uint256 a,
    uint256 b,
    uint256 eps
  ) internal pure returns (bool) {
    return a >= b && a <= mulDown(b, WAD + eps);
  }

  /**
   * @notice Checks if one unsigned integer is approximately less than another within a specified tolerance
   * @dev Uses `mulDown` for the comparison to handle precision loss
   * @param a First unsigned integer
   * @param b Second unsigned integer
   * @param eps Maximum allowable difference between `a` and `b`
   * @return Boolean indicating whether `a` is approximately less than `b`
   */
  function approxLt(
    uint256 a,
    uint256 b,
    uint256 eps
  ) internal pure returns (bool) {
    return a <= b && a >= mulDown(b, WAD - eps);
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
   * @notice Returnss the division of two unsigned integers, with a division by zero flag
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
   * @notice Returns the remainder of dividing two unsigned integers, with a division by zero flag
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
   * @notice Returns the average of two numbers. Result is rounded towards zero
   * @param a First number
   * @param b Second number
   * @return Average of the two numbers
   */
  function average(uint256 a, uint256 b) internal pure returns (uint256) {
    // (a + b) / 2 can overflow
    return (a & b) + (a ^ b) / 2;
  }

  /**
   * @notice Returns the ceiling of the division of two numbers
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
   * @notice Returns the square root of a number. If the number is not a perfect square, the value is rounded
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
      return
        result + (unsignedRoundsUp(rounding) && result * result < a ? 1 : 0);
    }
  }

  /**
   * @notice Returns the cube root of a number. If the number is not a perfect cube, the value is rounded
   * towards zero
   * @param a Input value
   * @return s Cube root of the input value
   */
  function cbrt(uint256 a) internal pure returns (uint256 s) {
    /// @solidity memory-safe-assembly
    assembly {
      let r := shl(7, lt(0xffffffffffffffffffffffffffffffff, a))
      r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, a))))
      r := or(r, shl(5, lt(0xffffffff, shr(r, a))))
      r := or(r, shl(4, lt(0xffff, shr(r, a))))
      r := or(r, shl(3, lt(0xff, shr(r, a))))

      s := div(shl(div(r, 3), shl(lt(0xf, shr(r, a)), 0xf)), xor(7, mod(r, 3)))

      s := div(add(add(div(a, mul(s, s)), s), s), 3)
      s := div(add(add(div(a, mul(s, s)), s), s), 3)
      s := div(add(add(div(a, mul(s, s)), s), s), 3)
      s := div(add(add(div(a, mul(s, s)), s), s), 3)
      s := div(add(add(div(a, mul(s, s)), s), s), 3)
      s := div(add(add(div(a, mul(s, s)), s), s), 3)
      s := div(add(add(div(a, mul(s, s)), s), s), 3)

      s := sub(s, lt(div(a, mul(s, s)), s))
    }
  }

  /**
   * @notice Returns the log in base 2 of a positive value rounded towards zero
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
   * @notice Returns the log in base 2, following the selected rounding direction, of a positive value
   * Returns 0 if given 0
   * @param value Input value
   * @param rounding Rounding direction
   * @return Log in base 2 of the input value with the specified rounding
   */
  function log2(
    uint256 value,
    Rounding rounding
  ) internal pure returns (uint256) {
    unchecked {
      uint256 result = log2(value);
      return
        result + (unsignedRoundsUp(rounding) && 1 << result < value ? 1 : 0);
    }
  }

  /**
   * @notice Returns the log in base 10 of a positive value rounded towards zero
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
   * @notice Returns the log in base 10, following the selected rounding direction, of a positive value
   * Returns 0 if given 0
   * @param value Input value
   * @param rounding Rounding direction
   * @return Log in base 10 of the input value with the specified rounding
   */
  function log10(
    uint256 value,
    Rounding rounding
  ) internal pure returns (uint256) {
    unchecked {
      uint256 result = log10(value);
      return
        result + (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
    }
  }

  /**
   * @notice Returns the log in base 256 of a positive value rounded towards zero
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
   * @notice Returns the log in base 256, following the selected rounding direction, of a positive value
   * Returns 0 if given 0
   * @param value Input value
   * @param rounding Rounding direction
   * @return Log in base 256 of the input value with the specified rounding
   */
  function log256(
    uint256 value,
    Rounding rounding
  ) internal pure returns (uint256) {
    unchecked {
      uint256 result = log256(value);
      return
        result +
        (unsignedRoundsUp(rounding) && 1 << (result << 3) < value ? 1 : 0);
    }
  }

  function toWad32(uint32 bps) internal pure returns (uint256) {
    unchecked {
      return uint256(bps) * WAD / BP_BASIS;
    }
  }

  function toWad(uint256 bps) internal pure returns (uint256) {
    unchecked {
      return bps * WAD / BP_BASIS;
    }
  }

  function toBps(uint256 wad) internal pure returns (uint256) {
    unchecked {
      return wad * BP_BASIS / WAD;
    }
  }

  function rayToBps(uint256 ray) internal pure returns (uint256) {
    unchecked {
      return ray * BP_BASIS / RAY;
    }
  }

  function bpsToRay(uint256 bps) internal pure returns (uint256) {
    unchecked {
      return bps * RAY / BP_BASIS;
    }
  }

  /**
   * @notice Equivalent to `x` to the power of `y` denominated in `WAD` with `x` in `WAD`
   * because `x ** y = (e ** ln(x)) ** y = e ** (ln(x) * y)`
   * Note: This function is an approximation
   */
  function powWad(int256 x, int256 y) internal pure returns (int256) {
    if (y == 0) return int256(WAD);
    if (x == 0) return 0;
    if (x == int256(WAD) || y == int256(WAD)) return x;
    unchecked {
      bool isNegative = x < 0 && y % 2 * int256(WAD) == int256(WAD);
      x = x < 0 ? -x : x;
      x = expWad((lnWad(x) * y) / int256(WAD)); // reuse x to store result
      return isNegative ? -x : x;
    }
  }

  /**
   * @notice Returns `exp(x)`, denominated in `WAD`
   * Credit to Remco Bloemen under MIT license: https://2π.com/22/exp-ln
   * Note: This function is an approximation. Monotonically increasing
   */
  function expWad(int256 x) internal pure returns (int256 r) {
    unchecked {
      // When the result is less than 0.5 we return zero
      // This happens when `x <= (log(1e-18) * 1e18) ~ -4.15e19`
      if (x <= -41446531673892822313) return r;

      /// @solidity memory-safe-assembly
      assembly {
        // When the result is greater than `(2**255 - 1) / 1e18` we can not represent it as
        // an int. This happens when `x >= floor(log((2**255 - 1) / 1e18) * 1e18) ≈ 135`
        if iszero(slt(x, 135305999368893231589)) {
          mstore(0x00, 0xa37bfec9) // `ExpOverflow()`
          revert(0x1c, 0x04)
        }
      }

      // `x` is now in the range `(-42, 136) * 1e18`. Convert to `(-42, 136) * 2**96`
      // for more intermediate precision and a binary basis. This base conversion
      // is a multiplication by 1e18 / 2**96 = 5**18 / 2**78
      x = (x << 78) / 5 ** 18;

      // Reduce range of x to (-½ ln 2, ½ ln 2) * 2**96 by factoring out powers
      // of two such that exp(x) = exp(x') * 2**k, where k is an integer
      // Solving this gives k = round(x / log(2)) and x' = x - k * log(2)
      int256 k = ((x << 96) / 54916777467707473351141471128 + 2 ** 95) >> 96;
      x = x - k * 54916777467707473351141471128;

      // `k` is in the range `[-61, 195]`.

      // Evaluate using a (6, 7)-term rational approximation
      // `p` is made monic, we'll multiply by a scale factor later
      int256 y = x + 1346386616545796478920950773328;
      y = ((y * x) >> 96) + 57155421227552351082224309758442;
      int256 p = y + x - 94201549194550492254356042504812;
      p = ((p * y) >> 96) + 28719021644029726153956944680412240;
      p = p * x + (4385272521454847904659076985693276 << 96);

      // We leave `p` in `2**192` basis so we don't need to scale it back up for the division
      int256 q = x - 2855989394907223263936484059900;
      q = ((q * x) >> 96) + 50020603652535783019961831881945;
      q = ((q * x) >> 96) - 533845033583426703283633433725380;
      q = ((q * x) >> 96) + 3604857256930695427073651918091429;
      q = ((q * x) >> 96) - 14423608567350463180887372962807573;
      q = ((q * x) >> 96) + 26449188498355588339934803723976023;

      /// @solidity memory-safe-assembly
      assembly {
        // Div in assembly because solidity adds a zero check despite the unchecked
        // The q polynomial won't have zeros in the domain as all its roots are complex
        // No scaling is necessary because p is already `2**96` too large
        r := sdiv(p, q)
      }

      // r should be in the range `(0.09, 0.25) * 2**96`.

      // We now need to multiply r by:
      // - The scale factor `s ≈ 6.031367120`
      // - The `2**k` factor from the range reduction
      // - The `1e18 / 2**96` factor for base conversion
      // We do this all at once, with an intermediate result in `2**213`
      // basis, so the final right shift is always by a positive amount
      r = int256(
        (uint256(r) * 3822833074963236453042738258902158003155416615667) >>
          uint256(195 - k)
      );
    }
  }

  /**
   * @notice Returns `ln(x)`, denominated in `WAD`
   * Credit to Remco Bloemen under MIT license: https://2π.com/22/exp-ln
   * Note: This function is an approximation. Monotonically increasing
   */
  function lnWad(int256 x) internal pure returns (int256 r) {
    /// @solidity memory-safe-assembly
    assembly {
      // We want to convert `x` from `10**18` fixed point to `2**96` fixed point
      // We do this by multiplying by `2**96 / 10**18`. But since
      // `ln(x * C) = ln(x) + ln(C)`, we can simply do nothing here
      // and add `ln(2**96 / 10**18)` at the end.

      // Compute `k = log2(x) - 96`, `r = 159 - k = 255 - log2(x) = 255 ^ log2(x)`
      r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
      r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
      r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
      r := or(r, shl(4, lt(0xffff, shr(r, x))))
      r := or(r, shl(3, lt(0xff, shr(r, x))))
      // We place the check here for more optimal stack operations
      if iszero(sgt(x, 0)) {
        mstore(0x00, 0x1615e638) // `LnWadUndefined()`
        revert(0x1c, 0x04)
      }
      // forgefmt: disable-next-item
      r := xor(
        r,
        byte(
          and(0x1f, shr(shr(r, x), 0x8421084210842108cc6318c6db6d54be)),
          0xf8f9f9faf9fdfafbf9fdfcfdfafbfcfef9fafdfafcfcfbfefafafcfbffffffff
        )
      )

      // Reduce range of x to (1, 2) * 2**96
      // ln(2^k * x) = k * ln(2) + ln(x)
      x := shr(159, shl(r, x))

      // Evaluate using a (8, 8)-term rational approximation
      // `p` is made monic, we will multiply by a scale factor later
      // forgefmt: disable-next-item
      let p := sub(
        // This heavily nested expression is to avoid stack-too-deep for via-ir
        sar(
          96,
          mul(
            add(
              43456485725739037958740375743393,
              sar(
                96,
                mul(
                  add(
                    24828157081833163892658089445524,
                    sar(96, mul(add(3273285459638523848632254066296, x), x))
                  ),
                  x
                )
              )
            ),
            x
          )
        ),
        11111509109440967052023855526967
      )
      p := sub(sar(96, mul(p, x)), 45023709667254063763336534515857)
      p := sub(sar(96, mul(p, x)), 14706773417378608786704636184526)
      p := sub(mul(p, x), shl(96, 795164235651350426258249787498))
      // We leave `p` in `2**192` basis so we don't need to scale it back up for the division.

      // `q` is monic by convention
      let q := add(5573035233440673466300451813936, x)
      q := add(71694874799317883764090561454958, sar(96, mul(x, q)))
      q := add(283447036172924575727196451306956, sar(96, mul(x, q)))
      q := add(401686690394027663651624208769553, sar(96, mul(x, q)))
      q := add(204048457590392012362485061816622, sar(96, mul(x, q)))
      q := add(31853899698501571402653359427138, sar(96, mul(x, q)))
      q := add(909429971244387300277376558375, sar(96, mul(x, q)))

      // `p / q` is in the range `(0, 0.125) * 2**96`.

      // Finalization, we need to:
      // - Multiply by the scale factor `s = 5.549…`
      // - Add `ln(2**96 / 10**18)`
      // - Add `k * ln(2)`
      // - Multiply by `10**18 / 2**96 = 5**18 >> 78`.

      // The q polynomial is known not to have zeros in the domain
      // No scaling required because p is already `2**96` too large
      p := sdiv(p, q)
      // Multiply by the scaling factor: `s * 5**18 * 2**96`, base is now `5**18 * 2**192`
      p := mul(1677202110996718588342820967067443963516166, p)
      // Add `ln(2) * k * 5**18 * 2**192`
      // forgefmt: disable-next-item
      p := add(
        mul(
          16597577552685614221487285958193947469193820559219878177908093499208371,
          sub(159, r)
        ),
        p
      )
      // Add `ln(2**96 / 10**18) * 5**18 * 2**192`
      p := add(
        600920179829731861736702779321621459595472258049074101567377883020018308,
        p
      )
      // Base conversion: mul `2**18 / 2**192`
      r := sar(174, p)
    }
  }

  /// @notice Returns the square root of `x`, denominated in `WAD`, rounded down
  function sqrtWad(uint256 x) internal pure returns (uint256 z) {
    unchecked {
      if (x <= type(uint256).max / 10 ** 18) return sqrt(x * 10 ** 18);
      z = (1 + sqrt(x)) * 10 ** 9;
      z = (mulDiv(x, 10 ** 18, z) + z) >> 1;
    }
    /// @solidity memory-safe-assembly
    assembly {
      z := sub(z, gt(999999999999999999, sub(mulmod(z, z, x), 1)))
    }
  }

  /// @notice Returns the cube root of `x`, denominated in `WAD`, rounded down
  function cbrtWad(uint256 x) internal pure returns (uint256 z) {
    unchecked {
      if (x <= type(uint256).max / 10 ** 36) return cbrt(x * 10 ** 36);
      z = (1 + cbrt(x)) * 10 ** 12;
      z = (mulDiv(x, 10 ** 36, z * z) + z + z) / 3;
      x = mulDiv(x, 10 ** 36, z * z);
    }
    /// @solidity memory-safe-assembly
    assembly {
      z := sub(z, lt(x, z))
    }
  }

  /// @notice Returns the nth root of `x`, denominated in `WAD`, rounded down
  function nrtWad(uint256 x, uint256 n) internal pure returns (uint256) {
    require(n != 0 && x >= 0);

    if (x == 0) return 0;
    if (x == WAD || n == 1) return x;

    unchecked {
      return uint256(powWad(int256(x), int256(WAD / n))); // x^(1/n) approximation
    }
  }

  /// @notice Returns the factorial of `x`
  function factorial(uint256 x) internal pure returns (uint256 result) {
    /// @solidity memory-safe-assembly
    assembly {
      result := 1
      if iszero(lt(x, 58)) {
        mstore(0x00, 0xaba0f2a2) // `FactorialOverflow()`
        revert(0x1c, 0x04)
      }
      for {

      } x {
        x := sub(x, 1)
      } {
        result := mul(result, x)
      }
    }
  }

  /**
   * @notice Returns whether a provided rounding mode is considered rounding up for unsigned integers
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
   * @notice Calculates the sum of an array of uint256 values
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
