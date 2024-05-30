// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "../interfaces/IPyth.sol";
import "./AsTypes.sol";
import "./PriceProvider.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title PythProvider - Pyth Network oracles aware StrategyV5 extension
 * @author Astrolab DAO
 * @notice Retrieves, validates and converts Pyth price feeds (https://pyth.network/price-feeds)
 */
contract PythProvider is PriceProvider {
  using AsMaths for uint256;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct Params {
    address pyth;
    address[] assets;
    bytes32[] feeds;
    uint256[] validities;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  IPythAggregator internal _pyth; // Pyth oracle
  mapping(address => bytes32) public feedByAsset;

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
    return feedByAsset[_asset] != bytes32(0);
  }

  /**
   * @notice Converts one unit of `_asset` token to USD or vice versa
   * @param _asset Address of the base token
   * @param _invert Invert the quote
   * @return USD amount equivalent to one `_asset` token
   */
  function _toUsdBp(
    address _asset,
    bool _invert
  ) internal view override returns (uint256) {

    bytes32 feed = feedByAsset[_asset];
    if (feed == bytes32(0)) {
      revert Errors.MissingOracle();
    }

    PythStructs.Price memory price = _pyth.getPrice(feed);
    uint256 validity = validityByAsset[_asset];

    if (
      price.price < 0 || price.expo > 12 || price.expo < -12
      || block.timestamp > (price.publishTime + validity)
    ) {
      revert Errors.InvalidOrStaleValue(price.publishTime, price.price);
    }

    uint256 assetDecimals = _decimalsByAsset[_asset];
    uint256 priceValue = uint256(uint64(price.price));
    int256 expo = price.expo;

    if (_invert) {
      int256 decimalOffset = int256(assetDecimals) - expo;
      return decimalOffset >= 0
        ? (10 ** uint256(decimalOffset) * AsMaths.BP_BASIS) / priceValue
        : (AsMaths.BP_BASIS) / (priceValue * 10 ** uint256(-decimalOffset));
    } else {
      return AsMaths.BP_BASIS * priceValue * 10 ** uint256(expo + int256(USD_DECIMALS));
    }
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Updates the Pyth oracle and feeds
   * @param _params Encoded Pyth specific parameters
   */
  function _update(bytes calldata _params) internal override {
    Params memory params = abi.decode(_params, (Params));
    (bool success,) = params.pyth.staticcall(
      abi.encodeWithSelector(IPythAggregator.getValidTimePeriod.selector)
    );
    if (!success) {
      revert Errors.ContractNonCompliant();
    }
    _pyth = IPythAggregator(params.pyth);
    _setFeeds(params.assets, params.feeds, params.validities);
  }

  /**
   * @notice Registers the price feed for a given `_asset` asset
   * @param _asset Feed base token address
   * @param _feed Price feed ID whether address or encoded bytes
   * @param _validity Feed validity period in seconds
   */
  function _setFeed(address _asset, bytes32 _feed, uint256 _validity) internal override {
    if (!_pyth.priceFeedExists(_feed)) {
      revert Errors.MissingOracle();
    }
    feedByAsset[_asset] = _feed;
    _decimalsByAsset[_asset] = IERC20Metadata(_asset).decimals();
    validityByAsset[_asset] = _validity;
  }
}
