// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../libs/ChainlinkUtils.sol";
import "../interfaces/IChainlink.sol";
import "./AsTypes.sol";
import "./StrategyV5.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title StrategyV5Chainlink - Chainlink Network oracles aware StrategyV5 extension
 * @author Astrolab DAO
 * @notice Extended by strategies requiring price feeds (https://data.chain.link/)
 */
abstract contract StrategyV5Chainlink is StrategyV5 {
  using AsMaths for uint256;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct ChainlinkParams {
    address assetFeed;
    uint256 assetFeedValidity;
    address[] inputFeeds;
    uint256[] inputFeedValidities;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  // Third party contracts
  mapping(address => IChainlinkAggregatorV3) public feedByAsset;
  mapping(IChainlinkAggregatorV3 => uint8) internal _decimalsByFeed; // price feed decimals by oracle address
  mapping(IChainlinkAggregatorV3 => uint256) public validityByFeed; // price feed validity periods by oracle address

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor() StrategyV5() {}

  /**
   * @dev Initializes the strategy with the specified parameters
   * @param _params StrategyBaseParams struct containing strategy parameters
   * @param _chainlinkParams Chainlink specific parameters
   */
  function _init(
    StrategyBaseParams calldata _params,
    ChainlinkParams calldata _chainlinkParams
  ) internal onlyAdmin {
    StrategyV5._init(_params); // super().init()
    updateChainlink(_chainlinkParams);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Computes the asset/input exchange rate from Chainlink oracle price feeds in bps
   * @dev Used by invested() to compute input->asset (base/quote, eg. USDC/BTC not BTC/USDC)
   * @return The amount available for investment
   */
  function exchangeRate(uint256 _index) public view returns (uint256) {
    IChainlinkAggregatorV3 feed = feedByAsset[address(inputs[_index])];
    return ChainlinkUtils.exchangeRate(
      [feed, feedByAsset[address(asset)]],
      [_inputDecimals[_index], _assetDecimals],
      [validityByFeed[feed], validityByFeed[feedByAsset[address(asset)]]]
    );
  }

  /**
   * @notice Converts asset wei amount to input wei amount
   * @param _amount Asset amount in wei
   * @param _index The index of the input token
   * @return Input amount in wei
   */
  function _assetToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount.mulDiv(10 ** _inputDecimals[_index], exchangeRate(_index));
  }

  /**
   * @notice Converts input wei amount to asset wei amount
   * @param _amount Input amount in wei
   * @param _index The index of the input token
   * @return Asset amount in wei
   */
  function _inputToAsset(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return _amount.mulDiv(exchangeRate(_index), 10 ** _inputDecimals[_index]);
  }

  /**
   * @dev Converts the specified amount of USD (6 decimals) to the input token at the specified index
   * @param _amount The amount of tokens to convert
   * @param _index The index of the input token
   * @return The converted amount of tokens
   */
  function _usdToInput(uint256 _amount, uint256 _index) internal view returns (uint256) {
    IChainlinkAggregatorV3 feed = feedByAsset[address(inputs[_index])];
    (, int256 price,, uint256 updateTime,) = feed.latestRoundData();
    if (block.timestamp > (updateTime + validityByFeed[feed])) {
      revert Errors.InvalidOrStaleValue(updateTime, price);
    }
    return _amount.mulDiv(
      10 ** (uint256(_decimalsByFeed[feed]) + _inputDecimals[_index] - 6), uint256(price)
    ); // eg. (1e6+1e12+1e6)-(1e12+1e6) = 1e6
  }

  /**
   * @dev Converts the given amount of tokens to USD (6 decimals) using the specified price feed index
   * @param _amount The amount of tokens to convert
   * @param _index The index of the price feed to use for conversion
   * @return The equivalent amount in USD
   */
  function _inputToUsd(uint256 _amount, uint256 _index) internal view returns (uint256) {
    IChainlinkAggregatorV3 feed = feedByAsset[address(inputs[_index])];
    return _amount.mulDiv(
      ChainlinkUtils.getPriceUsd(feed, validityByFeed[feed], 6),
      10 ** _inputDecimals[_index]
    );
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @dev Sets the validity duration for a single price feed
   * @param _address The address of the token we want the feed for
   * @param _feed The pricefeed address for the token
   * @param _validity The new validity duration in seconds
   */
  function setPriceFeed(
    address _address,
    IChainlinkAggregatorV3 _feed,
    uint256 _validity
  ) public onlyAdmin {
    feedByAsset[_address] = _feed;
    _decimalsByFeed[_feed] = feedByAsset[_address].decimals();
    validityByFeed[feedByAsset[_address]] = _validity;
  }

  /**
   * @notice Updates the Chainlink oracle and the input Chainlink ids
   * @param _chainlinkParams Chainlink specific parameters
   */
  function updateChainlink(ChainlinkParams calldata _chainlinkParams) public onlyAdmin {
    if (address(asset) == address(0))
      revert Errors.InvalidData();
    setPriceFeed(
      address(asset),
      IChainlinkAggregatorV3(_chainlinkParams.assetFeed),
      _chainlinkParams.assetFeedValidity
    );
    for (uint256 i = 0; i < _chainlinkParams.inputFeeds.length;) {
      if (address(inputs[i]) == address(0)) break;
      setPriceFeed(
        address(inputs[i]),
        IChainlinkAggregatorV3(_chainlinkParams.inputFeeds[i]),
        _chainlinkParams.inputFeedValidities[i]
      );
      unchecked {
        i++;
      }
    }
  }

  /**
   * @notice Updates the strategy underlying asset (critical, automatically pauses the strategy)
   * @notice If the new asset has a different price (USD denominated), a sudden `sharePrice()` change is expected
   * @param _asset Address of the new underlying asset
   * @param _swapData Swap calldata used to exchange the old `asset` for the new `_asset`
   * @param _feed Address of the Chainlink price feed
   * @param _validity Validity period in seconds for the price fee
   */
  function updateAsset(
    address _asset,
    bytes calldata _swapData,
    IChainlinkAggregatorV3 _feed,
    uint256 _validity
  ) external onlyAdmin {
    if (address(_feed) == address(0)) revert Errors.AddressZero();
    // Price of the old asset
    IChainlinkAggregatorV3 retiredFeed = feedByAsset[address(asset)];
    uint256 retiredPrice = ChainlinkUtils.getPriceUsd(
      retiredFeed, validityByFeed[retiredFeed], ChainlinkUtils.REBASING_DECIMAL
    );
    setPriceFeed(_asset, _feed, _validity);
    uint256 newPrice =
      ChainlinkUtils.getPriceUsd(_feed, _validity, ChainlinkUtils.REBASING_DECIMAL);
    uint256 rate = retiredPrice.exchangeRate(newPrice, decimals);
    _updateAsset(_asset, _swapData, rate);
  }

  /**
   * @notice Sets the strategy inputs and weights
   * @notice In case of pre-existing inputs, a call to `liquidate()` should precede this in order to not lose track of the strategy's liquidity
   * @param _inputs Array of input addresses
   * @param _weights Array of input weights
   * @param _feeds Array of Chainlink price feed addresses
   * @param _validities Array of Chainlink price feed validity periods
   */
  function setInputs(
    address[] calldata _inputs,
    uint16[] calldata _weights,
    address[] calldata _feeds,
    uint256[] calldata _validities
  ) internal onlyAdmin {
    for (uint256 i = 0; i < _inputs.length; i++) {
      if (_feeds[i] == address(0)) revert Errors.AddressZero();
      setPriceFeed(_inputs[i], IChainlinkAggregatorV3(_feeds[i]), _validities[i]);
    }
    _setInputs(_inputs, _weights);
  }
}
