// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract Impl {

  modifier onlyOwner() {
    console.log("Wrong modifier called");
    _;
  }

  function dummy() public onlyOwner returns (bool) {
    return true;
  }
}

contract AccessControlProxy is Test{
  address implementation;
  address admin;

  modifier onlyOwner() {
    require(msg.sender == admin, "Caller is not the owner");
    _;
  }

  function delegate(address to, bytes memory data) public onlyOwner {
    (bool success, bytes memory result) = to.delegatecall(data);
  }

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
