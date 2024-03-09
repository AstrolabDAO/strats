// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

// Native/gas erc20 wrapper
// cf. https://github.com/Uniswap/v3-periphery/blob/main/contracts/interfaces/external/IWETH9.sol
interface IWETH9 is IERC20Metadata {
  function deposit() external payable;
  function withdraw(uint256) external;
}
