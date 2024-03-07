// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.22;

abstract contract ERC20Abstract {
  string public name;
  string public symbol;
  uint8 public decimals;
  bool internal _initialized;
}
