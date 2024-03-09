// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../interfaces/IChainlink.sol";
import "./AsMaths.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title ChainlinkUtils - Utilities related to Chainlink oracle contracts
 * @author Astrolab DAO
 */
library ChainlinkUtils {
  using AsMaths for uint256;

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  uint8 public constant REBASING_DECIMAL = 18;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @dev Retrieves the latest price in USD from Chainlink's aggregator
   * @param _feed Chainlink aggregator contract
   * @param _validity Validity period in seconds for the retrieved price
   * @param _targetDecimals Decimals to convert the retrieved price to
   * @return convertedPrice Latest price in USD
   * @dev Throws an error if the retrieved price is not positive or if the validity period has expired
   */
  function getPriceUsd(
    IChainlinkAggregatorV3 _feed,
    uint256 _validity,
    uint8 _targetDecimals
  ) internal view returns (uint256 convertedPrice) {
    (, int256 basePrice,, uint256 updateTime,) = _feed.latestRoundData();
    uint8 feedDecimals = _feed.decimals();
    require(basePrice > 0 && block.timestamp <= (updateTime + _validity)); // Stale price
    unchecked {
      _targetDecimals >= feedDecimals
        ? convertedPrice = uint256(basePrice) * 10 ** uint32(_targetDecimals - feedDecimals)
        : convertedPrice = uint256(basePrice) / 10 ** uint32(feedDecimals - _targetDecimals);
    }
    return convertedPrice;
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
    if (address(_feeds[0]) == address(_feeds[1])) {
      return 10 ** uint256(_decimals[1]);
    } // == weiPerUnit of asset == 1:1

    return getPriceUsd(_feeds[0], _validities[0], REBASING_DECIMAL).exchangeRate(
      getPriceUsd(_feeds[1], _validities[1], REBASING_DECIMAL), _decimals[1]
    ); // in _baseFeedDecimals
  }
}
