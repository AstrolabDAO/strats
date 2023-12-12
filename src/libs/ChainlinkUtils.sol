// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IChainlink.sol";
import "./AsMaths.sol";

/**
 * @title ChainlinkUtils
 * @dev Utilities related to Chainlink oracle contracts
 */
library ChainlinkUtils {

    using AsMaths for uint256;

    /**
     * @notice Computes the input/asset exchange rate from Chainlink oracle price feeds in _baseDecimals
     * @dev Used by invested() to compute input->asset (base/quote, eg. USDC/BTC not BTC/USDC)
     * @param _priceFeeds Chainlink oracle price feeds [quote,base] eg. [input,asset]
     * @return The amount available for investment
     */
    function assetExchangeRate(IChainlinkAggregatorV3[2] calldata _priceFeeds, uint8 _baseDecimals, uint8 _baseFeedDecimals) public view returns (uint256) {

        if (address(_priceFeeds[0]) == address(_priceFeeds[1]))
            return 10 ** uint256(_baseDecimals); // == weiPerUnit of asset == 1:1

        (uint256 quotePrice, uint256 basePrice) = (
            uint256(_priceFeeds[0].latestAnswer()),
            uint256(_priceFeeds[1].latestAnswer())
        );
        uint256 rate = quotePrice.exchangeRate(basePrice, _baseFeedDecimals); // in _baseFeedDecimals

        if (_baseDecimals == _baseFeedDecimals) {
            return rate; // same decimals >> no conversion needed
        } else if (_baseDecimals > _baseFeedDecimals) {
            // negative feed vs token decimalsOffset >> multiply by 10^(-decimalsOffset)
            return rate * 10**uint256(_baseDecimals - _baseFeedDecimals);
        } else {
            return rate / 10**uint256(_baseFeedDecimals - _baseDecimals);
        }
    }
}
