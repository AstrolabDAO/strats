// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "./AsTypes.sol";
import "../libs/AsMaths.sol";
import "./AsPermissioned.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title PriceProvider Abstract - Oracle adapter extended by ChainlinkProvider/PythProvider/RedstoneProvider
 * @author Astrolab DAO
 * @notice Retrieves, validates and converts price feeds from underlying oracles
 */
abstract contract PriceProvider is AsPermissioned {
  using AsMaths for uint256;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            CONSTANTS                           ║
  ╚═══════════════════════════════════════════════════════════════*/

  uint256 public constant USD_DECIMALS = 18;
  uint256 public constant WEI_PER_USD = 10 ** USD_DECIMALS;

  /*═══════════════════════════════════════════════════════════════╗
  ║                             STORAGE                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  mapping(address => uint8) internal _decimalsByAsset;
  mapping(address => uint256) public validityByAsset;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) AsPermissioned(_accessController) {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Checks if the oracle has a price feed for a given `_asset`
   * @param _asset Address of the asset
   * @return True if the oracle has a price feed for the asset
   */
  function hasFeed(address _asset) public view virtual returns (bool);

  /**
   * @notice Converts one unit of `_asset` token to USD or vice versa in bps
   * @param _asset Address of the base token
   * @param _invert Invert the quote
   * @return USD amount equivalent to one `_asset` tokens or vice versa
   */
  function _toUsdBp(address _asset, bool _invert) internal view virtual returns (uint256);

  function toUsdBp(address _asset) public view returns (uint256) {
    return _toUsdBp(_asset, false);
  }

  function fromUsdBp(address _asset) public view returns (uint256) {
    return _toUsdBp(_asset, true);
  }

  function toUsdBp(address _asset, uint256 _amount) public view returns (uint256) {
    return toUsdBp(_asset) * _amount;
  }

  function fromUsdBp(address _asset, uint256 _amount) public view returns (uint256) {
    return fromUsdBp(_asset) * _amount;
  }

  /**
   * @notice Converts one unit of `_asset` token to USD or vice versa
   * @param _asset Address of the base token
   * @return USD amount equivalent to one `_asset` tokens or vice versa
   */
  function toUsd(address _asset) public view returns (uint256) {
    return toUsdBp(_asset) / AsMaths.BP_BASIS;
  }

  function toUsd(address _asset, uint256 _amount) public view returns (uint256) {
    return toUsdBp(_asset, _amount) / AsMaths.BP_BASIS;
  }

  function fromUsd(address _asset) public view returns (uint256) {
    return fromUsdBp(_asset) / AsMaths.BP_BASIS;
  }

  function fromUsd(address _asset, uint256 _amount) public view returns (uint256) {
    return fromUsdBp(_asset, _amount) / AsMaths.BP_BASIS;
  }

  /**
   * @notice Converts `_amount` of `_base` tokens to `_quote` wei
   * @param _base Address of the base token
   * @param _quote Address of the quote token
   * @param _amount Amount of tokens to convert
   * @return Amount of `_quote` wei equivalent to `_amount` of `_base` tokens
   */
  function convert(
    address _base,
    uint256 _amount,
    address _quote
  ) public view returns (uint256) {
    if (_quote == _base) {
      return 10 ** uint256(_decimalsByAsset[_base]) * _amount;
    }
    return
      fromUsd(_quote, toUsdBp(_base, _amount)) / (10 ** USD_DECIMALS * AsMaths.BP_BASIS);
  }

  /**
   * @notice Computes the `_base` per `_quote` exchange rate in `_quote` bps
   * @param _base Address of the base token
   * @param _quote Address of the quote token
   * @return Exchange rate in `_quote` bps
   */
  function exchangeRateBp(address _base, address _quote) public view returns (uint256) {
    return convert(_base, AsMaths.BP_BASIS, _quote);
  }

  /**
   * @notice Computes the `_base` per `_quote` exchange rate in `_quote` wei
   * @param _base Address of the base token
   * @param _quote Address of the quote token
   * @return Exchange rate in `_quote` wei
   */
  function exchangeRate(address _base, address _quote) public view returns (uint256) {
    return convert(_base, 1, _quote);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Registers the price feed for a given `_asset` asset
   * @param _asset Feed base token address
   * @param _feed Price feed ID whether address or encoded bytes
   * @param _validity Feed validity period in seconds
   */
  function _setFeed(address _asset, bytes32 _feed, uint256 _validity) internal virtual;

  /**
   * @notice Registers the price feed for a given `_asset` asset
   * @param _asset Feed base token address
   * @param _feed Price feed ID whether address or encoded bytes
   * @param _validity Feed validity period in seconds
   */
  function setFeed(address _asset, bytes32 _feed, uint256 _validity) external onlyAdmin {
    _setFeed(_asset, _feed, _validity);
  }

  /**
   * @notice Batch registers price feeds for given `_assets`
   * @param _assets Feed base token addresses
   * @param _feeds Price feed IDs whether addresses or encoded bytes
   * @param _validities Feed validity periods in seconds
   */
  function _setFeeds(
    address[] memory _assets,
    bytes32[] memory _feeds,
    uint256[] memory _validities
  ) internal {
    if (_assets.length != _feeds.length || _assets.length != _validities.length) {
      revert Errors.InvalidData();
    }
    for (uint256 i = 0; i < _assets.length;) {
      _setFeed(_assets[i], _feeds[i], _validities[i]);
      unchecked {
        i++;
      }
    }
  }

  /**
   * @notice Batch registers price feeds for given `_assets`
   * @param _assets Feed base token addresses
   * @param _feeds Price feed IDs whether addresses or encoded bytes
   * @param _validities Feed validity periods in seconds
   */
  function setFeeds(
    address[] memory _assets,
    bytes32[] memory _feeds,
    uint256[] memory _validities
  ) external onlyAdmin {
    _setFeeds(_assets, _feeds, _validities);
  }

  /**
   * @notice Updates the oracle internals
   * @param _params Encoded oracle specific parameters
   */
  function _update(bytes calldata _params) internal virtual;

  /**
   * @notice Updates the oracle internals
   * @param _params Encoded oracle specific parameters
   */
  function update(bytes calldata _params) external onlyAdmin {
    _update(_params);
  }
}
