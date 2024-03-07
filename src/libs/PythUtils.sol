// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.22;

import "../interfaces/IPyth.sol";
import "./AsMaths.sol";

/**
 * @title PythUtils
 * @dev Utilities related to Pyth oracle contracts
 */
library PythUtils {
  using AsMaths for uint256;

  uint8 constant STANDARD_DECIMALS = 18;

  /**
   * @notice Converts a Pyth price to a uint256 value with the specified target decimals
   * @dev Reverts if the price is negative, has an invalid exponent, or targetDecimals is greater than 255
   * @param _price Pyth price to convert
   * @param _targetDecimals Desired number of decimals for the result
   * @return convertedPrice Converted uint256 value
   */
  function toUint256(
    PythStructs.Price memory _price,
    uint8 _targetDecimals
  ) public pure returns (uint256 convertedPrice) {
    require(_price.price >= 0 && _price.expo <= 0 && _price.expo > -256, "Invalid price");

    uint8 feedDecimals = uint8(uint32(-_price.expo));
    uint64 basePrice = uint64(_price.price);

    // debase pyth feed decimals to target decimals
    unchecked {
      _targetDecimals >= feedDecimals
        ? convertedPrice = basePrice * 10 ** uint32(_targetDecimals - feedDecimals)
        : convertedPrice = basePrice / 10 ** uint32(feedDecimals - _targetDecimals);
    }
  }

  /**
   * @dev Retrieves the latest price in USD from Pyth's aggregator
   * @param _feed Pyth aggregator contract
   * @param _validity Validity period in seconds for the retrieved price
   * @param _targetDecimals Target wei decimals of the usd denominated price
   * @return Latest price in USD
   * @dev Throws an error if the retrieved price is not positive or if the validity period has expired
   */
  function getPriceUsd(
    IPythAggregator _pyth,
    bytes32 _feed,
    uint256 _validity,
    uint8 _targetDecimals
  ) internal view returns (uint256) {
    PythStructs.Price memory pythPrice = _pyth.getPrice(_feed);
    uint256 price = toUint256(pythPrice, _targetDecimals);
    require(price > 0 && block.timestamp <= (pythPrice.publishTime + _validity)); // stale price
    return price;
  }

  /**
   * @notice Computes the asset/input exchange rate from Pyth oracle price feeds in bps
   * @dev Used by invested() to compute input->asset (base/quote, eg. USDC/BTC not BTC/USDC)
   * @param _pyth Pyth oracle contract
   * @param _feeds Pyth oracle price feeds [quote,base] eg. [input,asset]
   * @param _decimals Decimals of the price feeds [quote,base] eg. [input,asset]
   * @param _validities Validity periods for the price feeds [quote,base] eg. [input,asset]
   * @return Exchange rate in base wei
   */
  function exchangeRate(
    IPythAggregator _pyth,
    bytes32[2] calldata _feeds, // [quote,base]
    uint8[2] calldata _decimals, // [quote,base]
    uint256[2] calldata _validities
  ) public view returns (uint256) {
    if (_feeds[0] == _feeds[1]) {
      return 10 ** uint256(_decimals[1]);
    } // == weiPerUnit of base == 1:1

    return getPriceUsd(_pyth, _feeds[0], _validities[0], STANDARD_DECIMALS).exchangeRate(
      getPriceUsd(_pyth, _feeds[1], _validities[1], STANDARD_DECIMALS), _decimals[1]
    ); // asset (base) decimals (rate divider)
  }
}
