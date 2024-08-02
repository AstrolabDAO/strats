// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AsRescuable} from "../../src/abstract/AsRescuable.sol";
import {StrategyV5Simulator} from "../../src/implementations/StrategyV5Simulator.sol";
import {TestEnvArb} from "./TestEnvArb.sol";

contract AsRescuableTest is TestEnvArb {
  constructor() TestEnvArb(true, true) {}

  function setRescuable(uint256 _value, IERC20 _token) public returns (uint256) {
    AsRescuable asRescuable = AsRescuable(address(new StrategyV5Simulator(address(accessController))));

    vm.prank(rich);
    _token.transfer(address(asRescuable), _value);
    return (_token.balanceOf(address(asRescuable)));
  }

  function setRescuableNative(uint256 _value) public returns (uint256) {
    AsRescuable asRescuable = AsRescuable(address(new StrategyV5Simulator(address(accessController))));

    payable(address(asRescuable)).transfer(_value);
    return address(asRescuable).balance;
  }

  function rescue(IERC20 _token) public {
    vm.startPrank(admin);
    asRescuable.requestRescue(address(_token));
    vm.stopPrank();

    // wait for the RESCUE_TIMELOCK
    vm.warp(block.timestamp + asRescuable.RESCUE_TIMELOCK() + 1);
    vm.startPrank(admin);
    require(_token.balanceOf(address(asRescuable)) > 0, "No balance to rescue");
    asRescuable.rescue(address(_token));
    vm.stopPrank();
    require(_token.balanceOf(address(asRescuable)) == 0, "Rescue failed");
  }

  function rescueRequestRepeatUnlock(IERC20 _token) public {
    uint256 _value = 1000e6;
    setRescuable(_value, _token);

    vm.startPrank(admin);
    asRescuable.requestRescue(address(_token));
    // increase time to unlock the previous request
    vm.warp(block.timestamp + asRescuable.RESCUE_TIMELOCK() + 1);
    // should not be able to make a new request if the previous one is not rescued/expired
    vm.expectRevert();
    asRescuable.requestRescue(address(_token));
    vm.stopPrank();
  }

function rescueNative() public {
    uint256 initialAdminBalance = admin.balance;

    vm.prank(admin);
    asRescuable.requestRescue(address(1)); // request rescue for ETH

    // fast forward past the RESCUE_TIMELOCK
    vm.warp(block.timestamp + asRescuable.RESCUE_TIMELOCK() + 1);

    vm.prank(admin);
    asRescuable.rescue(address(1)); // execute the rescue for ETH

    uint256 finalAdminBalance = admin.balance;

    require(finalAdminBalance > initialAdminBalance, "Rescue failed");
}

  function testAll() public {
    deployDependencies();

    setRescuable(1000e6, IERC20(address(weth)));
    rescue(IERC20(address(weth)));

    setRescuable(1000e6, IERC20(address(wbtc)));
    rescue(IERC20(address(wbtc)));

    setRescuable(1000e6, IERC20(address(usdc)));
    rescueRequestRepeatUnlock(IERC20(address(usdc)));

    setRescuableNative(100e18);
    rescueNative();
  }
}
