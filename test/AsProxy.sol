// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
// import "forge-std/console.sol";
import "../src/abstract/AsProxy.sol";

contract Impl {

  function hello() public returns (string memory) {
    string memory whatever = "hello";
    // console.log(whatever);
    return whatever;
  }
}

contract ProxyDelegateTest is AsProxy, Test {
  address implementation;

  function _implementation() internal view override returns (address) {
    return implementation;
  }

  function testDelegate() public {

    // Deploy the implementation contract
    Impl _impl = new Impl();
    implementation = address(_impl);
    (bool success, bytes memory result) = _delegateToSelectorMemory(implementation, Impl.hello.selector, new bytes(1)); // 0x19ff1d21
    string memory res = abi.decode(result, (string));
    // console.log("res", res);
  }
}
