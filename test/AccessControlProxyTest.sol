// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract Impl {
  modifier onlyOwner() {
    console.log("Wrong modifier called");
    _;
  }

  function overriden() public {
    console.log("Wrong overriden called");
    revert();
  }

  function dummy() public onlyOwner returns (bool) {
    overriden();
    console.log("Dummy called");
    return true;
  }
}

contract AccessControlProxyTest is Test {
  address implementation;
  address admin;

  modifier onlyOwner() {
    console.log("Good modifier called");
    require(msg.sender == admin, "Not owner");
    _;
  }

  function overriden() public {
    console.log("Good overriden called");
  }

  function delegate(address to, bytes memory data) public {
    (bool success, bytes memory result) = to.delegatecall(data);
  }

  function testDelegate() public {
    implementation = address(implementation);
    // Set the owner of the implementation contract to a different address
    admin = address(0);
    console.log("Admin: ", admin, "msg.sender: ", msg.sender);

    // Deploy the implementation contract
    Impl _impl = new Impl();

    // Delegate a call to the setOwner function of the implementation contract
    bytes memory data = abi.encodeWithSelector(Impl.dummy.selector);
    delegate(address(implementation), data);
  }
}
