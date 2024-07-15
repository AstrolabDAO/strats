// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/IChainlink.sol";
import "../libs/AsCast.sol";
import "./PriceProvider.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title ChainlinkProvider - Chainlink Network oracles aware ChainlinkProvider extension
 * @author Astrolab DAO
 * @notice Retrieves, validates and converts Chainlink price feeds (https://data.chain.link)
 */
contract ChainlinkProvider is PriceProvider {
  using AsMaths for uint256;
  using AsCast for bytes32;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct Params {
    address[] assets;
    bytes32[] feeds;
    uint256[] validities;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  mapping(address => IChainlinkAggregatorV3) public feedByAsset;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) PriceProvider(_accessController) {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Checks if the oracle has a price feed for a given `_asset`
   * @param _asset Address of the asset
   * @return True if the oracle has a price feed for the asset
   */
  function hasFeed(address _asset) public view override returns (bool) {
    return address(feedByAsset[_asset]) != address(0);
  }

  /**
   * @notice Converts one unit of `_asset` token to USD
   * @param _asset Address of the base token
   * @param _invert Invert the quote
   * @return USD amount equivalent to one `_asset` tokens
   */
  function _toUsdBp(
    address _asset,
    bool _invert
  ) internal view override returns (uint256) {
    IChainlinkAggregatorV3 feed = feedByAsset[_asset];
    if (address(feed) == address(0)) {
      revert Errors.MissingOracle();
    }
    (, int256 basePrice,, uint256 updateTime,) = feed.latestRoundData();
    if (basePrice <= 0 || block.timestamp > (updateTime + validityByAsset[_asset])) {
      revert Errors.InvalidOrStaleValue(updateTime, basePrice);
    }
    uint8 feedDecimals = feed.decimals();
    return _invert
      ? (
        (10 ** (_decimalsByAsset[_asset] + feedDecimals) * AsMaths.BP_BASIS)
          / uint256(basePrice)
      )
      : (
        AsMaths.BP_BASIS * uint256(basePrice) * (10 ** uint32(USD_DECIMALS - feedDecimals))
      );
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Updates the Chainlink oracle and feeds
   * @param _params Encoded Chainlink specific parameters
   */
  function _update(bytes calldata _params) internal override {
    Params memory params = abi.decode(_params, (Params));
    _setFeeds(params.assets, params.feeds, params.validities);
  }

  /**
   * @notice Registers the price feed for a given `_asset` asset
   * @param _asset Feed base token address
   * @param _feed Price feed ID whether address or encoded bytes
   * @param _validity Feed validity period in seconds
   */
  function _setFeed(address _asset, bytes32 _feed, uint256 _validity) internal override {
    IChainlinkAggregatorV3 feed = IChainlinkAggregatorV3(_feed.toAddress());
    feedByAsset[_asset] = feed;
    _decimalsByAsset[_asset] = IERC20Metadata(_asset).decimals();
    validityByAsset[_asset] = _validity;
  }
}
