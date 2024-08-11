// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../external/Curve/ICurvePool.sol";
import "./PriceProvider.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title CurveProvider - Curve adapter to retrieve TWAPs
 * @author Astrolab DAO
 * @notice Retrieves, validates and converts any of Curve pool prices (https://curve.fi)
 */
contract CurveProvider is PriceProvider {
  constructor(address _accessController) PriceProvider(_accessController) {
    revert Errors.NotImplemented();
  }

  function hasFeed(
    address _asset
  ) public view virtual override returns (bool) {}

  function _toUsdBp(
    address _asset,
    bool _invert
  ) internal view virtual override returns (uint256) {}

  function _setFeed(
    address _asset,
    bytes32 _feed,
    uint256 _validity
  ) internal virtual override {}

  function _update(bytes calldata _params) internal virtual override {}
}
