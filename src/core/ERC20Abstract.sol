// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

abstract contract ERC20Abstract {

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  string public name;
  string public symbol;
  uint8 public decimals;
  bool internal _initialized;
}
