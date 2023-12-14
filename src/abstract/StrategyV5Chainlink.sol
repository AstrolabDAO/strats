// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "../libs/ChainlinkUtils.sol";
import "../interfaces/IChainlink.sol";
import "./StrategyV5.sol";

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
    IChainlinkAggregatorV3 internal assetPriceFeed; // Aggregator contract of the asset asset
    IChainlinkAggregatorV3[8] internal inputPriceFeeds; // Aggregator contract of the inputs
    uint8 internal assetFeedDecimals; // Decimals of the asset asset
    uint8[8] internal inputFeedDecimals; // Decimals of the input asset

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, version
     */
    constructor(string[3] memory _erc20Metadata) StrategyV5(_erc20Metadata) {}

    struct ChainlinkParams {
        address assetPriceFeed;
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
        assetPriceFeed = IChainlinkAggregatorV3(_ChainlinkParams.assetPriceFeed);
        assetFeedDecimals = assetPriceFeed.decimals();

        for (uint256 i = 0; i < _ChainlinkParams.inputPriceFeeds.length; i++) {
            if (address(inputs[i]) == address(0)) break;
            inputPriceFeeds[i] = IChainlinkAggregatorV3(_ChainlinkParams.inputPriceFeeds[i]);
            inputFeedDecimals[i] = inputPriceFeeds[i].decimals();
        }
    }

    /**
     * @notice Changes the strategy asset token (automatically pauses the strategy)
     * @param _asset Address of the token
     * @param _swapData Swap callData oldAsset->newAsset
     * @param _priceFeed Address of the Chainlink price feed
     */
    function updateAsset(address _asset, bytes calldata _swapData, address _priceFeed) external onlyAdmin {
        if (_priceFeed == address(0)) revert AddressZero();
        assetPriceFeed = IChainlinkAggregatorV3(_priceFeed);
        assetFeedDecimals = assetPriceFeed.decimals();
        _updateAsset(_asset, _swapData);
    }

    /**
     * @notice Computes the asset/input exchange rate from Chainlink oracle price feeds in bps
     * @dev Used by invested() to compute input->asset (base/quote, eg. USDC/BTC not BTC/USDC)
     * @return The amount available for investment
     */
    function assetExchangeRate(uint8 _index) public view returns (uint256) {
        return ChainlinkUtils.assetExchangeRate(
            [inputPriceFeeds[_index], assetPriceFeed], assetDecimals, assetFeedDecimals);
    }

    /**
     * @notice Converts asset wei amount to input wei amount
     * @return Input amount in wei
     */
    function _assetToInput(uint256 _amount, uint8 _index) internal view override returns (uint256) {
        return _amount.mulDiv(10**inputDecimals[_index], assetExchangeRate(_index));
    }

    /**
     * @notice Converts input wei amount to asset wei amount
     * @return Asset amount in wei
     */
    function _inputToAsset(uint256 _amount, uint8 _index) internal view override returns (uint256) {
        return _amount.mulDiv(assetExchangeRate(_index), 10**inputDecimals[_index]);
    }
}
