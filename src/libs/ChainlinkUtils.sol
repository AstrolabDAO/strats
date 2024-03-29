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
     * @dev Retrieves the latest price in USD from Chainlink's aggregator
     * @param _feed Chainlink aggregator contract
     * @param _validity Validity period in seconds for the retrieved price
     * @param _targetDecimals Decimals to convert the retrieved price to
     * @return Latest price in USD
     * @dev Throws an error if the retrieved price is not positive or if the validity period has expired
     */
    function getPriceUsd(IChainlinkAggregatorV3 _feed, uint256 _validity, uint8 _targetDecimals) internal view returns (uint256) {
        (, int256 basePrice, , uint updateTime, ) = _feed.latestRoundData();
        uint8 feedDecimals = _feed.decimals();
        require(basePrice > 0 && block.timestamp <= (updateTime + _validity), "Stale price");

        // debase pyth feed decimals to target decimals
        return _targetDecimals >= feedDecimals ?
            uint256(basePrice) * 10 ** uint32(_targetDecimals - feedDecimals) :
            uint256(basePrice) / 10 ** uint32(feedDecimals - _targetDecimals);
    }

    /**
     * @notice Computes the input/asset exchange rate from Chainlink oracle price feeds in _baseDecimals
     * @dev Used by invested() to compute input->asset (base/quote, eg. USDC/BTC not BTC/USDC)
     * @param _feeds Chainlink oracle price feeds [quote,base] eg. [input,asset]
     * @param _decimals Decimals of the price feeds [quote,base] eg. [input,asset]
     * @param _validities Validity periods for the price feeds [quote,base] eg. [input,asset]
     * @return Exchange rate in base wei
     */
    function exchangeRate(
        IChainlinkAggregatorV3[2] calldata _feeds, // [quote,base]
        uint8[2] calldata _decimals,
        uint256[2] calldata _validities // [quote,base]
    ) public view returns (uint256) {
        if (address(_feeds[0]) == address(_feeds[1]))
            return 10 ** uint256(_decimals[1]); // == weiPerUnit of asset == 1:1

        return getPriceUsd(_feeds[0], _validities[0], 18)
            .exchangeRate(getPriceUsd(_feeds[1], _validities[1], 18),
                _decimals[1]); // in _baseFeedDecimals
    }
}
