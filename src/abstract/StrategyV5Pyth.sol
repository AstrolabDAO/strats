// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libs/PythUtils.sol";
import "./StrategyV5.sol";
import "../interfaces/IPyth.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title StrategyV5Pyth - Pyth Network oracles aware StrategyV5 extension
 * @author Astrolab DAO
 * @notice Extended by strategies requiring price feeds (https://pyth.network/)
 */
abstract contract StrategyV5Pyth is StrategyV5 {
    using AsMaths for uint256;
    using PythUtils for PythStructs.Price;
    using PythUtils for uint256;

    // Third party contracts
    IPythAggregator internal pyth; // Pyth oracle
    mapping (address => bytes32) public feedByAsset; // PythId by asset
    mapping (bytes32 => uint256) public validityByFeed; // Price feed validity periods by oracle address

    constructor() StrategyV5() {}

    struct PythParams {
        address pyth;
        bytes32 assetFeed;
        uint256 assetValidity;
        bytes32[] inputFeeds;
        uint256[] inputFeedValidities;
    }

    /**
     * @dev Initializes the strategy with the specified parameters
     * @param _params StrategyBaseParams struct containing strategy parameters
     * @param _pythParams Pyth specific parameters
     */
    function _init(
        StrategyBaseParams calldata _params,
        PythParams calldata _pythParams
    ) internal onlyAdmin {
        updatePyth(_pythParams);
        StrategyV5._init(_params);
    }

    /**
     * @dev Sets the validity duration for a single price feed
     * @param _address The address of the token we want the feed for
     * @param _feed The pricefeed address for the token
     * @param _validity The new validity duration in seconds
     */
    function setPriceFeed(address _address, bytes32 _feed, uint256 _validity) public onlyAdmin {
        if (!pyth.priceFeedExists(_feed))
            revert InvalidData();
        feedByAsset[_address] = _feed;
        validityByFeed[_feed] = _validity;
    }

    /**
     * @notice Updates the Pyth oracle and the input Pyth ids
     * @param _pythParams Pyth specific parameters
     */
    function updatePyth(PythParams calldata _pythParams) public onlyAdmin {
        pyth = IPythAggregator(_pythParams.pyth);
        setPriceFeed(address(asset), _pythParams.assetFeed, _pythParams.assetValidity);
        for (uint256 i = 0; i < _pythParams.inputFeeds.length; i++) {
            if (address(inputs[i]) == address(0)) break;
            setPriceFeed(address(inputs[i]), _pythParams.inputFeeds[i], _pythParams.inputFeedValidities[i]);
        }
    }

    /**
     * @notice Changes the strategy asset token (automatically pauses the strategy)
     * @param _asset Address of the token
     * @param _swapData Swap callData oldAsset->newAsset
     * @param _feed Pyth price feed id
     * @param _validity The new validity duration in seconds
     */
    function updateAsset(
        address _asset,
        bytes calldata _swapData,
        bytes32 _feed,
        uint256 _validity
    ) external onlyAdmin {
        if (_feed == bytes32(0)) revert AddressZero();

        bytes32 assetFeed = feedByAsset[address(asset)];
        uint256 retiredPrice = PythUtils.getPriceUsd(
            pyth,
            assetFeed,
            validityByFeed[assetFeed],
            18);

        setPriceFeed(_asset, _feed, _validity);

        uint256 newPrice = PythUtils.getPriceUsd(
            pyth,
            _feed,
            validityByFeed[_feed],
            18); // same base as prior price

        uint256 rate = retiredPrice.exchangeRate(newPrice, decimals);
        _updateAsset(_asset, _swapData, rate);
    }

    /**
     * @notice Changes the strategy input tokens
     * @param _inputs Array of input token addresses
     * @param _weights Array of input token weights
     * @param _feeds Array of Pyth price feed ids
     * @param _validities Array of Pyth price feed validity periods
     */
    function setInputs(
        address[] calldata _inputs,
        uint16[] calldata _weights,
        bytes32[] calldata _feeds,
        uint256[] calldata _validities
    ) external onlyAdmin {
        for (uint256 i = 0; i < _inputs.length; i++) {
            if (address(inputs[i]) == address(0)) break;
            setPriceFeed(_inputs[i], _feeds[i], _validities[i]);
        }
        _setInputs(_inputs, _weights);
    }
}
