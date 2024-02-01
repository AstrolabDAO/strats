// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../interfaces/IPyth.sol";
import "./AsMaths.sol";

/**
 * @title PythUtils
 * @dev Utilities related to Pyth oracle contracts
 */
library PythUtils {
    using AsMaths for uint256;

    /**
     * @notice Converts a Pyth price to a uint256 value with the specified target decimals.
     * @dev Reverts if the price is negative, has an invalid exponent, or targetDecimals is greater than 255.
     * @param price The Pyth price to convert.
     * @param targetDecimals The desired number of decimals for the result.
     * @return The converted uint256 value.
     */
    function toUint256(
        PythStructs.Price memory price,
        uint8 targetDecimals
    ) public pure returns (uint256) {

        require (price.price >= 0 && price.expo <= 0 && price.expo > -256, "Invalid price");

        uint8 priceDecimals = uint8(uint32(-price.expo));
        uint64 basePrice = uint64(price.price);
        return targetDecimals >= priceDecimals ?
            basePrice * 10 ** uint32(targetDecimals - priceDecimals) :
            basePrice / 10 ** uint32(priceDecimals - targetDecimals);
    }

    /**
     * @notice Calculates the exchange rate in bps (AsMaths.BP_BASIS == 100%) between two prices (in wei)
     * @dev Reverts if either price is zero.
     * @param prices Array of the two Pyth prices (base and quote, in wei)
     * @param decimals Array of the two prices decimals.
     * @return Exchange rate (in bps * 10 ** base decimals)
     */
    function exchangeRate(
        PythStructs.Price[2] calldata prices,
        uint8[2] calldata decimals
    ) public pure returns (uint256) {
        uint256[2] memory pricesWei = [
            toUint256(prices[0], decimals[0]),
            toUint256(prices[1], decimals[1])
        ];
        return pricesWei[0].exchangeRate(pricesWei[1], decimals[1]);
    }
}
