// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

interface IAsRescuable {
  function requestRescue(address _token) external;
  function rescue(address _token) external;
}
