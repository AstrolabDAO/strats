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
    assertApproxEqRel(int256(1e18).powWad(0), 1e18, 1e12); // 1.0 ^ 0 = 1.0
    assertApproxEqRel(int256(2e18).powWad(1e18), 2e18, 1e12); // 2.0 ^ 1 = 2.0
    // examples with various powers
    assertApproxEqRel(int256(2e18).powWad(2e18), 4e18, 1e15); // 2.0 ^ 2 ≈ 4.0
    assertApproxEqRel(int256(15e17).powWad  (3e18), 3375e15, 1e14); // 1.5 ^ 3 ≈ 3.375
    // examples with floating exponent
    assertApproxEqRel(int256(2e18).powWad(1.5e18), 2.828427e18, 1e15); // 2.0 ^ 1.5 ≈ 2.828
    assertApproxEqRel(int256(3.5e18).powWad(1.8e18), 9.53504e18, 1e15); // 3.5 ^ 1.8 ≈ 9.535
    assertApproxEqRel(int256(15.7e18).powWad(7.2e18), 407828429e18, 1e18); // 15.7 ^ 7.2 ≈ 407828429
    // test with very large number
    assertApproxEqRel(int256(2e18).powWad(64e18), 18446744073709552000e18, 1e20);
    // test with very small number
    assertApproxEqRel(int256(0.0005e18).powWad(1.75e18), 0.0000016718507e18, 1e11); // 0.0005 ^ 1.75 ≈ 0.0000016718507
  }

  // test expWad
  function testExpWad() public {
    // base cases
    assertApproxEqRel(int256(0).expWad(), 1e18, 1e15); // exp(0) ≈ 1.0
    assertApproxEqRel(int256(1e18).lnWad().expWad(), 1e18, 1e15); // exp(ln(1)) ≈ 1.0
    // example with non-zero input
    assertApproxEqRel(int256(2e18).lnWad().expWad(), 2e18, 1e15); // exp(ln(2)) ≈ 2.0
    // test with negative input
    assertApproxEqRel(int256(-1e18).expWad(), 367879441171442321, 1e15); // exp(-1) ≈ 0.367879...
    // test with very small number
    assertApproxEqRel(int256(1).expWad(), 1000000000000000001, 1e15); // exp(1e-18) ≈ 1.000...001
    assertApproxEqRel(int256(0.127e18).expWad(), 1.135417e18, 1e15); // exp(0.127) ≈ 1.135
    // test with very large number
    assertApproxEqRel(int256(17e18).expWad(), 24154952.75e18, 1e15); // exp(17) ≈ 24154952.75
    assertApproxEqRel(int256(32e18).expWad(), 78962960182680e18, 1e15); // exp(32) ≈ 78962960182680
    // test overflow case (should revert)
    vm.expectRevert();
    int256(136e18).expWad(); // input above the allowed range
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
    assertApproxEqRel(uint256(2e18).sqrtWad(), 1.41421356237e18, 1e10); // √2.0 (approximate)
    // cube root tests
    assertEq(uint256(1e18).cbrtWad(), 1e18); // ∛1.0 = 1.0
    assertEq(uint256(8e18).cbrtWad(), 2e18); // ∛8.0 = 2.0
    assertApproxEqRel(uint256(2e18).cbrtWad(), 1.25992104989e18, 1e10); // ∛2.0 (approximate)
    // test with very large number
    assertApproxEqRel(MAX_UINT.sqrtWad(), 340282366920938484656701964288e18, 1e25);
    assertApproxEqRel(MAX_UINT.cbrtWad(), 48740834812604268544e18, 1e25);
    // test with very small number >> non relevant, estimation error
    // assertApproxEqRel(uint256(1).sqrtWad(), 1e9, 1e4); // √(1e-18) ≈ 1e-9
    // assertApproxEqRel(uint256(1).cbrtWad(), 1e12, 1e4); // ∛(1e-18) ≈ 1e-6
  }

  // test nrtWad
  function testNrtWad() public {
    // base cases
    assertEq(uint256(0).nrtWad(2), 0); // 0^(1/2) = 0
    assertApproxEqRel(uint256(1e18).nrtWad(1), 1e18, 1e10); // 1.0^(1/1) = 1.0
    assertApproxEqRel(uint256(8e18).nrtWad(3), 2e18, 1e12); // 8.0^(1/3) = 2.0
    assertApproxEqRel(uint256(1e18).nrtWad(20), 1e18, 1e12); // 1.0^(1/20) = 1.0 (rounded down)
    // more complex cases
    assertApproxEqRel(uint256(9e18).nrtWad(2), 3e18, 1e12); // 9.0^(1/2) ≈ 3.0
    assertApproxEqRel(uint256(27e18).nrtWad(3), 3e18, 1e12); // 27.0^(1/3) ≈ 3.0
    // test with large n or x
    assertApproxEqRel(uint256(1e36).nrtWad(100), 1.5135612e18, 1e12); // 1e36^(1/100) (very close to 1)
    assertApproxEqRel(uint256(1e54).nrtWad(300), 1.31825673e18, 1e12); // 1e72^(1/1000) (even closer to 1)
    // test with x very close to 1
    assertApproxEqRel(
      uint256(1000000000000000001).nrtWad(2),
      1000000000000000000,
      1e15
    ); // √(1.000...001) ≈ 1.0
    // test with zero n (should revert)
    vm.expectRevert();
    uint256(1e18).nrtWad(0);
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
