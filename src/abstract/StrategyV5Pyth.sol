// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libs/PythUtils.sol";
import "./StrategyV5.sol";
import "../interfaces/IPyth.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title StrategyV5Pyth - Pyth Network oracles aware StrategyV5 extension
 * @author Astrolab DAO
 * @notice Extended by strategies requiring price feeds (https://pyth.network/)
 */
abstract contract StrategyV5Pyth is StrategyV5 {
  using AsMaths for uint256;
  using PythUtils for PythStructs.Price;
  using PythUtils for uint256;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct PythParams {
    address pyth;
    address[] assets;
    bytes32[] feeds;
    uint256[] validities;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  // Third party contracts
  IPythAggregator internal _pyth; // Pyth oracle
  mapping(address => bytes32) public feedByAsset; // PythId by asset
  mapping(bytes32 => uint256) public validityByFeed; // Price feed validity periods by oracle address

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address accessController) StrategyV5(accessController) {}


  /**
   * @dev Initializes the strategy with the specified parameters
   * @param _params StrategyBaseParams struct containing strategy parameters
   * @param _pythParams Pyth specific parameters
   */
  function _init(
    StrategyBaseParams calldata _params,
    PythParams calldata _pythParams
  ) internal onlyAdmin {
    StrategyV5._init(_params);
    updatePyth(_pythParams);
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
    bytes32 _feed,
    uint256 _validity
  ) public onlyAdmin {
    if (!_pyth.priceFeedExists(_feed)) {
      revert Errors.InvalidData();
    }
    feedByAsset[_address] = _feed;
    validityByFeed[_feed] = _validity;
  }

  /**
   * @notice Updates the Pyth oracle and the input Pyth ids
   * @param _params Pyth specific parameters
   */
  function updatePyth(PythParams calldata _params) public onlyAdmin {
    _pyth = IPythAggregator(_params.pyth);
    for (uint256 i = 0; i < _params.assets.length;) {
      setPriceFeed(_params.assets[i], _params.feeds[i], _params.validities[i]);
      unchecked {
        i++;
      }
    }
    for (uint256 i = 0; i < _inputLength;) {
      if (feedByAsset[address(inputs[i])] == bytes32(0)) {
        revert Errors.InvalidData();
      }
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
   * @param _feed Pyth price feed id
   * @param _validity The new validity duration in seconds
   */
  function updateAsset(
    address _asset,
    bytes calldata _swapData,
    bytes32 _feed,
    uint256 _validity
  ) external onlyAdmin {
    if (_feed == bytes32(0)) revert Errors.AddressZero();

    bytes32 assetFeed = feedByAsset[address(asset)];
    uint256 retiredPrice = PythUtils.getPriceUsd(
      _pyth, assetFeed, validityByFeed[assetFeed], PythUtils.REBASING_DECIMAL
    );

    setPriceFeed(_asset, _feed, _validity);

    uint256 newPrice = PythUtils.getPriceUsd(
      _pyth, _feed, validityByFeed[_feed], PythUtils.REBASING_DECIMAL
    ); // same base as prior price

    uint256 rate = retiredPrice.exchangeRate(newPrice, decimals);
    _updateAsset(_asset, _swapData, rate);
  }

  /**
   * @notice Sets the strategy inputs and weights
   * @notice In case of pre-existing inputs, a call to `liquidate()` should precede this in order to not lose track of the strategy's liquidity
   * @param _inputs Array of input addresses
   * @param _weights Array of input weights
   * @param _feeds Array of Pyth price feed ids
   * @param _validities Array of Pyth price feed validity periods
   */
  function setInputs(
    address[] memory _inputs,
    uint16[] memory _weights,
    bytes32[] memory _feeds,
    uint256[] memory _validities
  ) external onlyAdmin {
    for (uint256 i = 0; i < _inputs.length;) {
      if (address(inputs[i]) == address(0)) break;
      setPriceFeed(_inputs[i], _feeds[i], _validities[i]);
      unchecked {
        i++;
      }
    }
    _setInputs(_inputs, _weights);
  }
}
