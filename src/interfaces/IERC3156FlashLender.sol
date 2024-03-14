// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "./IERC3156FlashBorrower.sol";

interface IERC3156FlashLender {

  // Events
  event FlashLoan(address indexed borrower, uint256 amount, uint256 fee);

  // ERC-3156 Flash loan interfaces
  function setMaxLoan(uint256 _amount) external;
  function maxFlashLoan(address _token) external view returns (uint256);
  function flashFee(address _token, address _borrower, uint256 _amount) external view returns (uint256);
  function flashFee(address _token, uint256 _amount) external view returns (uint256);
  function flashLoan(
      IERC3156FlashBorrower _receiver,
      address _token,
      uint256 _amount,
      bytes calldata _data
  ) external returns (bool);
}
