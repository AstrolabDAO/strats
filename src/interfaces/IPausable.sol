// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

interface IPausable {
  function paused() external view returns (bool);
  function pause() external;
  function unpause() external;
}
