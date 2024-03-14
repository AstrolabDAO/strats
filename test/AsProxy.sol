// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/abstract/AsTypes.sol";
import "../src/abstract/AsProxy.sol";

contract Impl {

  function reflect(bytes calldata data) public returns (string memory) {
    Erc20Metadata memory meta = abi.decode(data, (Erc20Metadata));
    console.log(meta.name, meta.symbol, meta.decimals);
    return meta.name;
  }

  function hello() public pure returns (string memory) {
    // console.log(name, symbol, decimals);
    return "hello";
  }

  fallback() external {
    console.log("fallback: no function matched");
  }
}

contract DummyProxy is AsProxy {

  function _implementation() internal view override returns (address) {
    return address(0); // polyfill to satisfy OZ's proxy, unused here
  }

  function init() public returns (address) {
    return address(new Impl());
  }

  function delegateToSelectorMemory(address _impl, bytes4 _selector, bytes memory _data) public returns (bytes memory result) {
    (, result) = _delegateToSelectorMemory(_impl, _selector, _data);
    return result;
  }

  function delegateToSelector(address _impl, bytes4 _selector, bytes calldata _data) public returns (bytes memory result) {
    (, result) = _delegateToSelector(_impl, _selector, _data);
    return result;
  }
}

contract ProxyDelegateTest is Test {

  address public impl;

  function testDelegate() public {

    // Deploy the implementation contract
    DummyProxy _proxy = new DummyProxy();
    impl = _proxy.init(); // link with implementation

    Erc20Metadata memory meta = Erc20Metadata("Ether", "ETH", 18);
    bytes memory params = abi.encode(meta);
    bytes memory result = _proxy.delegateToSelectorMemory(impl, Impl.reflect.selector, params);
    // bytes memory result2 = _proxy.delegateToSelectorMemory(address(this), Impl.reflect.selector, new bytes(1));

    string memory res = abi.decode(result, (string));
    // console.log("res", res);
  }
}
