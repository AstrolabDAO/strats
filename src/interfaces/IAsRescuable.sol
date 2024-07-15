// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IAsRescuable {
  function RESCUE_TIMELOCK() external view returns (uint64);
  function RESCUE_VALIDITY() external view returns (uint64);
  function requestRescue(address _token) external;
  function rescue(address _token) external;
}
