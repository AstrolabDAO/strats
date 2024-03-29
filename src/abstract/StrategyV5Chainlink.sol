// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "../libs/ChainlinkUtils.sol";
import "../interfaces/IChainlink.sol";
import "./StrategyV5.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title StrategyV5Chainlink - Chainlink Network oracles aware StrategyV5 extension
 * @author Astrolab DAO
 * @notice Extended by strategies requiring price feeds (https://data.chain.link/)
 */
abstract contract StrategyV5Chainlink is StrategyV5 {
    using AsMaths for uint256;
    using SafeERC20 for IERC20;

    // Third party contracts
    mapping (address => IChainlinkAggregatorV3) public feedByAsset;
    mapping (IChainlinkAggregatorV3 => uint8) internal decimalsByFeed;
    mapping (IChainlinkAggregatorV3 => uint256) public validityByFeed; // Price feed validity periods by oracle address

    constructor() StrategyV5() {}

    struct ChainlinkParams {
        address assetFeed;
        uint256 assetFeedValidity;
        address[] inputFeeds;
        uint256[] inputFeedValidities;
    }

    /**
     * @dev Initializes the strategy with the specified parameters
     * @param _params StrategyBaseParams struct containing strategy parameters
     * @param _chainlinkParams Chainlink specific parameters
     */
    function _init(
        StrategyBaseParams calldata _params,
        ChainlinkParams calldata _chainlinkParams
    ) internal onlyAdmin {
        updateChainlink(_chainlinkParams);
        StrategyV5._init(_params);
    }

    /**
     * @dev Sets the validity duration for a single price feed
     * @param _address The address of the token we want the feed for
     * @param _feed The pricefeed address for the token
     * @param _validity The new validity duration in seconds
     */
    function setPriceFeed(address _address, IChainlinkAggregatorV3 _feed, uint256 _validity) public onlyAdmin {
        feedByAsset[_address] = _feed;
        decimalsByFeed[_feed] = feedByAsset[_address].decimals();
        validityByFeed[feedByAsset[_address]] = _validity;
    }

    /**
     * @notice Updates the Chainlink oracle and the input Chainlink ids
     * @param _chainlinkParams Chainlink specific parameters
     */
    function updateChainlink(
        ChainlinkParams calldata _chainlinkParams
    ) public onlyAdmin {
        setPriceFeed(address(asset), IChainlinkAggregatorV3(_chainlinkParams.assetFeed), _chainlinkParams.assetFeedValidity);
        for (uint256 i = 0; i < _chainlinkParams.inputFeeds.length; i++) {
            if (address(inputs[i]) == address(0)) break;
            setPriceFeed(address(inputs[i]), IChainlinkAggregatorV3(_chainlinkParams.inputFeeds[i]), _chainlinkParams.inputFeedValidities[i]);
        }
    }

    /**
     * @notice Changes the strategy asset token (automatically pauses the strategy)
     * @param _asset Address of the token
     * @param _swapData Swap callData oldAsset->newAsset
     * @param _feed Address of the Chainlink price feed
     * @param _validity Validity period in seconds for the price fee
     */
    function updateAsset(
        address _asset,
        bytes calldata _swapData,
        IChainlinkAggregatorV3 _feed,
        uint256 _validity
    ) external onlyAdmin {
        if (address(_feed) == address(0)) revert AddressZero();
        // Price of the old asset
        IChainlinkAggregatorV3 retiredFeed = feedByAsset[address(asset)];
        uint256 retiredPrice = ChainlinkUtils.getPriceUsd(retiredFeed, validityByFeed[retiredFeed], 18);
        setPriceFeed(_asset, _feed, _validity);
        uint256 newPrice = ChainlinkUtils.getPriceUsd(_feed, _validity, 18);
        uint256 rate = retiredPrice.exchangeRate(newPrice, decimals);
        _updateAsset(_asset, _swapData, rate);
    }

    /**
     * @notice Changes the strategy input tokens
     * @param _inputs Array of input token addresses
     * @param _weights Array of input token weights
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
            if (_feeds[i] == address(0)) revert AddressZero();
            setPriceFeed(_inputs[i], IChainlinkAggregatorV3(_feeds[i]), _validities[i]);
        }
        _setInputs(_inputs, _weights);
    }

    /**
     * @notice Computes the asset/input exchange rate from Chainlink oracle price feeds in bps
     * @dev Used by invested() to compute input->asset (base/quote, eg. USDC/BTC not BTC/USDC)
     * @return The amount available for investment
     */
    function exchangeRate(uint8 _index) public view returns (uint256) {
        IChainlinkAggregatorV3 feed = feedByAsset[address(inputs[_index])];
        return
            ChainlinkUtils.exchangeRate(
                [feed, feedByAsset[address(asset)]],
                [inputDecimals[_index], assetDecimals],
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
        uint8 _index
    ) internal view override returns (uint256) {
        return
            _amount.mulDiv(
                10 ** inputDecimals[_index],
                exchangeRate(_index)
            );
    }

    /**
     * @notice Converts input wei amount to asset wei amount
     * @param _amount Input amount in wei
     * @param _index The index of the input token
     * @return Asset amount in wei
     */
    function _inputToAsset(
        uint256 _amount,
        uint8 _index
    ) internal view override returns (uint256) {
        return
            _amount.mulDiv(
                exchangeRate(_index),
                10 ** inputDecimals[_index]
            );
    }

    /**
     * @dev Converts the specified amount of USD (6 decimals) to the input token at the specified index
     * @param _amount The amount of tokens to convert
     * @param _index The index of the input token
     * @return The converted amount of tokens
     */
    function _usdToInput(
        uint256 _amount,
        uint8 _index
    ) internal view returns (uint256) {
        IChainlinkAggregatorV3 feed = feedByAsset[address(inputs[_index])];
        (, int256 price, , uint256 updateTime, ) = feed.latestRoundData();
        if (block.timestamp > (updateTime + validityByFeed[feed]))
            revert InvalidOrStaleValue(updateTime, price);
        return
            _amount.mulDiv(
                10 ** (uint256(decimalsByFeed[feed]) + inputDecimals[_index] - 6),
                uint256(price)
            ); // eg. (1e6+1e8+1e6)-(1e8+1e6) = 1e6
    }

    /**
     * @dev Converts the given amount of tokens to USD (6 decimals) using the specified price feed index
     * @param _amount The amount of tokens to convert
     * @param _index The index of the price feed to use for conversion
     * @return The equivalent amount in USD
     */
    function _inputToUsd(
        uint256 _amount,
        uint8 _index
    ) internal view returns (uint256) {
        IChainlinkAggregatorV3 feed = feedByAsset[address(inputs[_index])];
        (, int256 price, , uint256 updateTime, ) = feed.latestRoundData();
        if (block.timestamp > (updateTime + validityByFeed[feed]))
            revert InvalidOrStaleValue(updateTime, price);
        return
            _amount.mulDiv(
                uint256(price),
                10 ** uint256(decimalsByFeed[feed] + inputDecimals[_index] - 6)
            ); // eg. (1e6+1e8+1e6)-(1e8+1e6) = 1e6
    }
}
