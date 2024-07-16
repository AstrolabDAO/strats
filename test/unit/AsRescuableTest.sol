// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {TestEnvArb} from "./TestEnvArb.sol";
import {ERC20} from "../../src/abstract/ERC20.sol";

contract AsRescuableTest is TestEnvArb {
  constructor() TestEnvArb(true, true) {}

  function setRescuable(
    uint256 _value,
    ERC20 _token
  ) public returns (uint256) {
    deployStrat(zeroFees, 100e6);
    vm.prank(rich);
    _token.transfer(address(strat), _value);
    return (_token.balanceOf(address(strat)));
  }

  function setRescuableNative(uint256 _value) public returns (uint256) {
    deployStrat(zeroFees, 100e6);
    payable(address(strat)).transfer(_value);
    return address(strat).balance;
  }

  function rescue(ERC20 _token) public {
    vm.prank(admin);
    strat.requestRescue(address(_token));
    vm.warp(block.timestamp + strat.RESCUE_TIMELOCK() + 1); // fast forward past the RESCUE_TIMELOCK
    require(_token.balanceOf(address(strat)) > 0, "No balance to rescue");
    vm.prank(admin);
    strat.rescue(address(_token));
    require(_token.balanceOf(address(strat)) == 0, "Rescue failed");
  }

  function rescueRequestRepeatUnlock(ERC20 _token) public {
    uint256 _value = 1000e6;
    setRescuable(_value, _token);
    vm.prank(admin);
    strat.requestRescue(address(_token));
    vm.warp(block.timestamp + strat.RESCUE_TIMELOCK() + 1); // fast forward past the RESCUE_TIMELOCK
    vm.expectRevert(); // should not be able to make a new request if the previous one is not rescued/expired
    vm.prank(admin);
    strat.requestRescue(address(_token));
  }

  function rescueNative() public {
    uint256 initialAdminBalance = admin.balance;
    vm.prank(admin);
    strat.requestRescue(address(1)); // request rescue for ETH
    vm.warp(block.timestamp + strat.RESCUE_TIMELOCK() + 1); // fast forward past the RESCUE_TIMELOCK
    vm.prank(admin);
    strat.rescue(address(1)); // execute the rescue for ETH
    require(admin.balance > initialAdminBalance, "Rescue failed");
  }

  function testAll() public {
    deployDependencies();

    setRescuable(10e18, weth);
    rescue(weth);

    setRescuable(10e8, wbtc);
    rescue(wbtc);

    setRescuable(1000e6, usdc);
    rescueRequestRepeatUnlock(usdc);

    setRescuableNative(10e18);
    rescueNative();
  }
}
