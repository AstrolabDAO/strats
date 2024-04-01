// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract Erc7201StorageTest is Test {
  function setUp() public {}

  function testComputeMainStorageLocation() public view {
    // Array of strings to be hashed
    string[] memory namespaces = new string[](7);
    namespaces[0] = "As4626.ext";
    namespaces[1] = "StrategyV5.ext";
    namespaces[2] = "StrategyV5.agent";
    namespaces[3] = "AsPriceAware.main";
    namespaces[4] = "AsFlashLender.main";
    namespaces[5] = "AsRescuable.main";
    namespaces[6] = "AsPermissioned.main";

    // Loop through each name, compute its EIP-7210 hash, and log it
    for (uint256 i = 0; i < namespaces.length; i++) {
      bytes32 hash = keccak256(
        abi.encode(uint256(keccak256(abi.encodePacked(namespaces[i]))) - 1)
      ) & ~bytes32(uint256(0xff));
      console.log("Namespace: ", namespaces[i]);
      console.logBytes32(hash);
    }
  }
}
