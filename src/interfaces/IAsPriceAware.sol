// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./IPriceProvider.sol";

interface IAsPriceAware {
  function oracle() external view returns (IPriceProvider);
  function updateOracle(address _oracle) external;
}
