// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/abstract/AsProxy.sol";

contract Impl {

  function hello() public {
    console.log("Hello world");
  }
}

contract AsProxyTest is Test {
  address implementation;

  function testDelegate() public {

    implementation = address(implementation);
    // Set the owner of the implementation contract to a different address
    admin = msg.sender;

    // Deploy the implementation contract
    Impl _impl = new Impl();

    // Delegate a call to the setOwner function of the implementation contract
    bytes memory data = abi.encodeWithSelector(Impl.dummy.selector);
    delegate(address(implementation), data);
  }
}
