// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

abstract contract ERC20Abstract {

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  string public name;
  string public symbol;
  uint8 public decimals;
  bool internal _initialized;

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  // function balanceOf(address account) public view virtual returns (uint256);
  // function totalSupply() public view virtual returns (uint256);
  // function allowance(address owner, address spender) public view virtual returns (uint256);
}
