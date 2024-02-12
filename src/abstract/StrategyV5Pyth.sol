// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "../libs/SafeERC20.sol";
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
    using SafeERC20 for IERC20;
    using PythUtils for PythStructs.Price;
    using PythUtils for uint256;

    // Third party contracts
    IPythAggregator internal pyth; // Pyth oracle
    bytes32 internal assetFeed; // Pyth id of the asset asset
    bytes32[8] internal inputFeeds; // Pyth id of the inputs
    mapping (address => bytes32) feedByAsset; // PythId by asset
    mapping (bytes32 => uint256) public validityByFeed; // Price feed validity periods by oracle address

    constructor() StrategyV5() {}

    struct PythParams {
        address pyth;
        bytes32 assetFeed;
        uint256 assetValidity;
        bytes32[] inputFeeds;
        uint256[] inputValidities;
    }

    /**
     * @dev Initializes the strategy with the specified parameters.
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
            revert InvalidCalldata();
        feedByAsset[_address] = _feed;
        validityByFeed[_feed] = _validity;
    }

    /**
     * @notice Updates the Pyth oracle and the input Pyth ids
     * @param _pythParams Pyth specific parameters
     */
    function updatePyth(PythParams calldata _pythParams) public onlyAdmin {
        pyth = IPythAggregator(_pythParams.pyth);
        if (!pyth.priceFeedExists(_pythParams.assetFeed))
            revert InvalidCalldata();

        assetFeed = _pythParams.assetFeed;

        for (uint256 i = 0; i < _pythParams.inputFeeds.length; i++) {
            if (address(inputs[i]) == address(0)) break;
            setPriceFeed(address(inputs[i]), _pythParams.inputFeeds[i], _pythParams.inputValidities[i]);
        }
    }

    /**
     * @notice Changes the strategy asset token (automatically pauses the strategy)
     * @param _asset Address of the token
     * @param _swapData Swap callData oldAsset->newAsset
     * @param _feed Pyth price feed id
     */
    function updateAsset(
        address _asset,
        bytes calldata _swapData,
        bytes32 _feed
    ) external onlyAdmin {
        if (_feed == bytes32(0)) revert AddressZero();
        assetFeed = _feed;
        _updateAsset(_asset, _swapData);
    }

    /**
     * @notice Changes the strategy input tokens
     * @param _inputs Array of input token addresses
     * @param _weights Array of input token weights
     * @param _feeds Array of Pyth price feed ids
     */
    function setInputs(
        address[] calldata _inputs,
        uint16[] calldata _weights,
        bytes32[] calldata _feeds
    ) external onlyAdmin {
        for (uint256 i = 0; i < _inputs.length; i++) {
            if (address(inputs[i]) == address(0)) break;
            inputFeeds[i] = _feeds[i];
        }
        _setInputs(_inputs, _weights);
    }

    /**
     * @notice Computes the asset/input exchange rate from Pyth oracle price feeds in bps
     * @dev Used by invested() to compute input->asset (base/quote, eg. USDC/BTC not BTC/USDC)
     * @return The amount available for investment
     */
    function assetExchangeRate(uint8 _index) public view returns (uint256) {
        if (inputFeeds[_index] == assetFeed) return weiPerShare; // == weiPerUnit of asset == 1:1
        (PythStructs.Price memory inputPrice, PythStructs.Price memory assetPrice) = (
            pyth.getPrice(inputFeeds[_index]),
            pyth.getPrice(assetFeed)
        );
        require(
            block.timestamp <= (inputPrice.publishTime + validityByFeed[inputFeeds[_index]])
             &&
            block.timestamp <= (assetPrice.publishTime + validityByFeed[assetFeed])
        , "Stale price");

        uint256 inputPriceWei = inputPrice.toUint256(inputDecimals[_index]); // input (quote) price in wei
        uint256 assetPriceWei = assetPrice.toUint256(assetDecimals); // asset (base) price in wei
        uint256 rate = inputPriceWei.exchangeRate(assetPriceWei, assetDecimals); // asset (base) decimals (rate divider)
        return rate;
    }
}
