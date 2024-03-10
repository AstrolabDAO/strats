// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract ComputeSlotTest is Test {
  function setUp() public {}
  function testComputeMainStorageLocation() public view {
    bytes32 h = keccak256(abi.encode(uint256(keccak256("as4626.main")) - 1)) & ~bytes32(uint256(0xff));
    console.logBytes32(h);
  }
}
