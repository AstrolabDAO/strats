// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

interface IAsProxy {
  function initialized() external view returns (bool);
  function implementation() external view returns (address);
  function supportsInterface(bytes4 _interfaceId) external pure returns (bool);
}
