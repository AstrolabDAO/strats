// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libs/AsMaths.sol";
import "./StrategyV5.sol";
import "../interfaces/IChainlink.sol";

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
    IChainlinkAggregatorV3 internal underlyingPriceFeed; // Aggregator contract of the underlying asset
    IChainlinkAggregatorV3[8] internal inputPriceFeeds; // Aggregator contract of the inputs
    uint8 internal underlyingFeedDecimals; // Decimals of the underlying asset
    uint8[8] internal inputFeedDecimals; // Decimals of the input asset

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, version
     */
    constructor(string[3] memory _erc20Metadata) StrategyV5(_erc20Metadata) {}

    struct ChainlinkParams {
        address underlyingPriceFeed;
        address[] inputPriceFeeds;
    }

    /**
     * @dev Initializes the strategy with the specified parameters.
     * @param _params StrategyBaseParams struct containing strategy parameters
     * @param _ChainlinkParams Chainlink specific parameters
     */
    function _init(
        StrategyBaseParams calldata _params,
        ChainlinkParams calldata _ChainlinkParams
    ) internal onlyAdmin {
        updateChainlink(_ChainlinkParams);
        StrategyV5._init(_params);
    }

    /**
     * @notice Updates the Chainlink oracle and the input Chainlink ids
     * @param _ChainlinkParams Chainlink specific parameters
     */
    function updateChainlink(ChainlinkParams calldata _ChainlinkParams) public onlyAdmin {
        underlyingPriceFeed = IChainlinkAggregatorV3(_ChainlinkParams.underlyingPriceFeed);
        underlyingFeedDecimals = underlyingPriceFeed.decimals();

        for (uint256 i = 0; i < _ChainlinkParams.inputPriceFeeds.length; i++) {
            if (address(inputs[i]) == address(0)) break;
            inputPriceFeeds[i] = IChainlinkAggregatorV3(_ChainlinkParams.inputPriceFeeds[i]);
            inputFeedDecimals[i] = inputPriceFeeds[i].decimals();
        }
    }

    /**
     * @notice Computes the underlying/input exchange rate from Chainlink oracle price feeds in bps
     * @dev Used by invested() to compute input->underlying (base/quote, eg. USDC/BTC not BTC/USDC)
     * @return The amount available for investment
     */
    function underlyingExchangeRate(uint8 _index) public view returns (uint256) {

        if (address(inputs[_index]) == address(underlying))
            return weiPerShare; // == weiPerUnit of underlying == 1:1

        (uint256 inputPrice, uint256 underlyingPrice) = (
            uint256(inputPriceFeeds[_index].latestAnswer()),
            uint256(underlyingPriceFeed.latestAnswer())
        );
        uint256 rate = inputPrice.exchangeRate(underlyingPrice, underlyingFeedDecimals); // in underlyingFeedDecimals

        if (shareDecimals == underlyingFeedDecimals) {
            return rate; // same decimals >> no conversion needed
        } else if (shareDecimals > underlyingFeedDecimals) {
            // negative feed vs token decimalsOffset >> multiply by 10^(-decimalsOffset)
            return rate * 10**uint256(shareDecimals - underlyingFeedDecimals);
        } else {
            return rate / 10**uint256(underlyingFeedDecimals - shareDecimals);
        }
    }

    /**
     * @notice Converts underlying wei amount to input wei amount
     * @return Input amount in wei
     */
    function _underlyingToInput(uint256 _amount, uint8 _index) internal view returns (uint256) {
        return _amount.mulDiv(10**inputDecimals[_index], underlyingExchangeRate(_index));
    }

    /**
     * @notice Converts input wei amount to underlying wei amount
     * @return Underlying amount in wei
     */
    function _inputToUnderlying(uint256 _amount, uint8 _index) internal view returns (uint256) {
        return _amount.mulDiv(underlyingExchangeRate(_index), 10**inputDecimals[_index]);
    }
}
