// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "forge-std/Test.sol";
import "../../src/libs/AsMaths.sol";

contract AsMathsTest is Test {
  using AsMaths for int256;
  using AsMaths for uint256;

  int256 constant MAX_INT = type(int256).max;
  int256 constant MIN_INT = type(int256).min;
  uint256 constant MAX_UINT = type(uint256).max;

  function setUp() public {}

  // test powWad
  function testPowWad() public {
    // base cases
    assertEq(int256(1e18).powWad(0), 1e18); // 1.0 ^ 0 = 1.0
    assertEq(int256(2e18).powWad(1), 2e18); // 2.0 ^ 1 = 2.0
    // examples with various powers
    assertApproxEqRel(int256(2e18).powWad(2), 4e18, 1e15); // 2.0 ^ 2 ≈ 4.0
    assertApproxEqRel(int256(15e17).powWad(3), 3375e15, 1e14); // 1.5 ^ 3 ≈ 3.375
    // test with negative base (should revert)
    vm.expectRevert();
    int256(-2e18).powWad(2);
    // test with very large number
    assertApproxEqRel(
      int256(1e18).powWad(100),
      26881171418161354484126255515800135873611118773741922415191608,
      1e15
    );
    // test with very small number
    assertApproxEqRel(int256(1e15).powWad(1e18), 0, 1e15); // 0.001 ^ 1 ≈ 0
    // test with fractional power
    assertApproxEqRel(int256(4e18).powWad(5e17), 2e18, 1e15); // 4.0 ^ 0.5 ≈ 2.0
  }

  // test expWad
  function testExpWad() public {
    // base cases
    assertApproxEqRel(int256(0).expWad(), 1e18, 1e15); // exp(0) ≈ 1.0
    assertApproxEqRel(int256(1e18).lnWad().expWad(), 1e18, 1e15); // exp(ln(1)) ≈ 1.0
    // example with non-zero input
    assertApproxEqRel(int256(2e18).lnWad().expWad(), 2e18, 1e15); // exp(ln(2)) ≈ 2.0
    // test overflow case (should revert)
    vm.expectRevert();
    int256(136e18).expWad(); // input above the allowed range
    // test with negative input
    assertApproxEqRel(int256(-1e18).expWad(), 367879441171442321, 1e15); // exp(-1) ≈ 0.367879...
    // test with very small number
    assertApproxEqRel(int256(1).expWad(), 1000000000000000001, 1e15); // exp(1e-18) ≈ 1.000...001
  }

  // test lnWad
  function testLnWad() public {
    // base cases
    assertApproxEqRel(int256(1e18).lnWad(), 0, 1e15); // ln(1) ≈ 0.0
    assertApproxEqRel(int256(1e18).expWad().lnWad(), 1e18, 1e15); // ln(exp(1)) ≈ 1.0
    // example with non-zero input
    assertApproxEqRel(int256(2e18).lnWad(), 693147180559945309, 1e12); // ln(2) ≈ 0.693147...
    // test undefined case for ln(0) (should revert)
    vm.expectRevert();
    int256(0).lnWad(); // ln(0) is undefined
    // test with very large number
    assertApproxEqRel(MAX_INT.lnWad(), 135305999368893231589, 1e12); // ln(2^255 - 1)
    // test with number very close to 1
    assertApproxEqRel(int256(1000000000000000001).lnWad(), 1, 1e15); // ln(1.000...001) ≈ 1e-18
  }

  // test sqrtWad and cbrtWad
  function testSqrtAndCbrtWad() public {
    // square root tests
    assertEq(uint256(1e18).sqrtWad(), 1e18); // √1.0 = 1.0
    assertEq(uint256(4e18).sqrtWad(), 2e18); // √4.0 = 2.0
    assertApproxEqRel(uint256(2e18).sqrtWad(), 1414213562373095048, 1e10); // √2.0 (approximate)
    // cube root tests
    assertEq(uint256(1e18).cbrtWad(), 1e18); // ∛1.0 = 1.0
    assertEq(uint256(8e18).cbrtWad(), 2e18); // ∛8.0 = 2.0
    assertApproxEqRel(uint256(2e18).cbrtWad(), 1259921049894873164, 1e10); // ∛2.0 (approximate)
    // test with very large number
    assertApproxEqRel(
      MAX_UINT.sqrtWad(),
      340282366920938463463374607431768211455,
      1e10
    );
    assertApproxEqRel(MAX_UINT.cbrtWad(), 18446744073709551615, 1e10);
    // test with very small number
    assertApproxEqRel(uint256(1).sqrtWad(), 1e9, 1e10); // √(1e-18) ≈ 1e-9
    assertApproxEqRel(uint256(1).cbrtWad(), 1e6, 1e10); // ∛(1e-18) ≈ 1e-6
  }

  // test nrtWad
  function testNrtWad() public {
    // base cases
    assertEq(uint256(1e18).nrtWad(1), 1e18); // 1.0^(1/1) = 1.0
    assertEq(uint256(0).nrtWad(2), 0); // 0^(1/2) = 0
    assertEq(uint256(8e18).nrtWad(3), 2e18); // 8.0^(1/3) = 2.0
    assertEq(uint256(1e18).nrtWad(20), 1e18); // 1.0^(1/20) = 1.0 (rounded down)
    // more complex cases
    assertApproxEqRel(uint256(9e18).nrtWad(2), 3e18, 1e15); // 9.0^(1/2) ≈ 3.0
    assertApproxEqRel(uint256(27e18).nrtWad(3), 3e18, 1e15); // 27.0^(1/3) ≈ 3.0
    // test with large n
    assertApproxEqRel(uint256(1e36).nrtWad(100), 1000001663669249350, 1e10); // 1e36^(1/100) (very close to 1)
    assertApproxEqRel(uint256(1e72).nrtWad(1000), 1000000000000001666, 1e8); // 1e72^(1/1000) (even closer to 1)
    // test with zero n (should revert)
    vm.expectRevert("Nth root undefined for n = 0");
    uint256(1e18).nrtWad(0);
    // test with very large x
    assertApproxEqRel(
      MAX_UINT.nrtWad(2),
      340282366920938463463374607431768211455,
      1e10
    ); // √(2^256 - 1)
    // test with x very close to 1
    assertApproxEqRel(
      uint256(1000000000000000001).nrtWad(2),
      1000000000000000000,
      1e15
    ); // √(1.000...001) ≈ 1.0
  }

  // test composition of functions
  function testComposition() public {
    // test powWad with sqrtWad
    assertApproxEqRel(int256(uint256(4e18).sqrtWad()).powWad(2e18), 4e18, 1e15); // (√4)^2 ≈ 4
    // test expWad with lnWad
    assertApproxEqRel(int256(2e18).lnWad().expWad(), 2e18, 1e15); // exp(ln(2)) ≈ 2
    // test nrtWad with powWad
    assertApproxEqRel(int256(uint256(16e18).nrtWad(4)).powWad(4e18), 16e18, 1e15); // (∜16)^4 ≈ 16
  }
}
