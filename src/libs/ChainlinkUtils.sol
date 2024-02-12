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
     * @param _feeds Chainlink oracle price feeds [quote,base] eg. [input,asset]
     * @return The amount available for investment
     */
    function assetExchangeRate(
        IChainlinkAggregatorV3[2] calldata _feeds,
        uint8 _baseDecimals,
        uint8 _baseFeedDecimals,
        uint256 validityPeriod
    ) public view returns (uint256) {
        if (address(_feeds[0]) == address(_feeds[1]))
            return 10 ** uint256(_baseDecimals); // == weiPerUnit of asset == 1:1

        (, int256 quotePrice, , uint quoteUpdateTime, ) = _feeds[0].latestRoundData();
        (, int256 basePrice, , uint baseUpdateTime, ) = _feeds[1].latestRoundData();

        require(
            quotePrice > 0 && block.timestamp <= (quoteUpdateTime + validityPeriod) &&
            basePrice > 0 && block.timestamp <= (baseUpdateTime + validityPeriod),
            "Stale price");

        uint256 rate = uint256(quotePrice).exchangeRate(uint256(basePrice), _baseFeedDecimals); // in _baseFeedDecimals
        return _baseDecimals >= _baseFeedDecimals ?
            rate * 10 ** uint256(_baseDecimals - _baseFeedDecimals) :
            rate / 10 ** uint256(_baseFeedDecimals - _baseDecimals);
    }
}