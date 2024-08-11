// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./IClearingV2.sol";

// Interface IUniProxy
interface IUniProxy {
  // View Functions
  function clearance() external view returns (IClearingV2);

  function owner() external view returns (address);

  function getDepositAmount(
    address pos,
    address token,
    uint256 _deposit
  ) external view returns (uint256 amountStart, uint256 amountEnd);

  // State-Changing Functions
  function deposit(
    uint256 deposit0,
    uint256 deposit1,
    address to,
    address pos,
    uint256[4] memory minIn
  ) external returns (uint256 shares);

  function transferClearance(address newClearance) external;

  function transferOwnership(address newOwner) external;
}
