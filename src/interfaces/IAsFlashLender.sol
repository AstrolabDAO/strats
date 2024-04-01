// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "./IAsPermissioned.sol";

interface IAsFlashLender is IAsPermissioned {
  // Events
  event FlashLoan(address indexed borrower, uint256 amount, uint256 fee);

  function claimableFlashFees() external view returns (uint256);
  function maxLoan() external view returns (uint256);
  function totalLent() external view returns (uint256);
  function isLendable(address _asset) external view returns (bool);
  function borrowable() external view returns (uint256);
  function flashFee(
    address _token,
    address _borrower,
    uint256 _amount
  ) external view returns (uint256);
  function flashFee(address _token, uint256 _amount) external view returns (uint256);
  function maxFlashLoan(address _token) external view returns (uint256);
  function setMaxLoan(uint256 _amount) external;
  function flashLoan(
    address _receiver,
    address _token,
    uint256 _amount,
    bytes calldata _data
  ) external returns (bool);
}
