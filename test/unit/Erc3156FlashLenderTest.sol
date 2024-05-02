// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {Fees} from "../../src/abstract/AsTypes.sol";
import {AsArrays} from "../../src/libs/AsArrays.sol";
import {AsMaths} from "../../src/libs/AsMaths.sol";
import {IStrategyV5} from "../../src/interfaces/IStrategyV5.sol";
import {IERC3156FlashBorrower} from "../../src/interfaces/IERC3156FlashBorrower.sol";
import {AsFlashLender} from "../../src/abstract/AsFlashLender.sol";
import {ERC20} from "../../src/abstract/ERC20.sol";
import {TestEnvArb} from "./TestEnvArb.sol";

contract Borrower is IERC3156FlashBorrower {
  AsFlashLender lender;
  address initiator;

  constructor(address _lender, address _initiator) {
    lender = AsFlashLender(_lender);
    initiator = _initiator;
  }

  function onFlashLoan(
    address _initiator,
    address _token,
    uint256 _amount,
    uint256 _fee,
    bytes calldata params
  ) external override returns (bytes32) {
    require(msg.sender == address(lender), "Untrusted lender");
    require(
      _initiator == address(initiator) || _initiator == address(this),
      "Untrusted loan initiator"
    );
    uint256 fee = lender.flashFee(_token, _amount);
    uint256 repayment = _amount + fee;
    ERC20(_token).transfer(address(lender), repayment); // pay back the loan after use
    return keccak256("ERC3156FlashBorrower.onFlashLoan");
  }

  function flashBorrow(address _token, uint256 _amount) public {
    bytes memory data = abi.encode("dummy data");
    lender.flashLoan(address(this), _token, _amount, data);
  }
}

contract Erc3156FlashLenderTest is TestEnvArb {
  using AsMaths for uint256;
  using AsArrays for uint256[8];

  constructor() TestEnvArb(true, true) {}

  function usdcFlashLoan(Fees memory _fees, uint256 _minLiquidity) public {
    console.log("--- flash loan test ---");
    uint256 toBorrow = 1000e6;
    deployStrat(_fees, _minLiquidity);

    vm.startPrank(admin);
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(toBorrow, admin); // make sure there's enough to borrow
    strat.setMaxLoan(toBorrow);
    vm.stopPrank();

    Borrower borrower = new Borrower(address(strat), keeper);

    require(strat.isLendable(USDC), "USDC not lendable");
    uint256 maxLoan = strat.maxFlashLoan(USDC);
    require(maxLoan >= toBorrow, "USDC max flash loan too low");
    require(maxLoan <= strat.totalAssets(), "USDC max flash loan too high");

    vm.prank(address(borrower));
    borrower.flashBorrow(USDC, toBorrow);
  }

  function testAll() public {
    deployDependencies();
    Fees memory zeroFees = Fees({perf: 0, mgmt: 0, entry: 0, exit: 0, flash: 0});
    usdcFlashLoan(zeroFees, 1000e6);
  }
}
