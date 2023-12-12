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
    bytes32 internal assetPythId; // Pyth id of the asset asset
    bytes32[8] internal inputPythIds; // Pyth id of the inputs

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, version
     */
    constructor(string[3] memory _erc20Metadata) StrategyV5(_erc20Metadata) {}

    struct PythParams {
        address pyth;
        bytes32 assetPythId;
        bytes32[] inputPythIds;
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
     * @notice Updates the Pyth oracle and the input Pyth ids
     * @param _pythParams Pyth specific parameters
     */
    function updatePyth(PythParams calldata _pythParams) public onlyAdmin {
        pyth = IPythAggregator(_pythParams.pyth);
        assetPythId = _pythParams.assetPythId;

        for (uint256 i = 0; i < _pythParams.inputPythIds.length; i++) {
            if (address(inputs[i]) == address(0)) break;
            inputPythIds[i] = _pythParams.inputPythIds[i];
            inputDecimals[i] = inputs[i].decimals();
        }
    }

    /**
     * @notice Changes the strategy asset token (automatically pauses the strategy)
     * @param _asset Address of the token
     * @param _swapData Swap callData oldAsset->newAsset
     * @param _pythId Pyth price feed id
     */
    function updateAsset(address _asset, bytes calldata _swapData, bytes32 _pythId) external onlyAdmin {
        if (_pythId == bytes32(0)) revert AddressZero();
        assetPythId = _pythId;
        _updateAsset(_asset, _swapData);
    }

    /**
     * @notice Computes the asset/input exchange rate from Pyth oracle price feeds in bps
     * @dev Used by invested() to compute input->asset (base/quote, eg. USDC/BTC not BTC/USDC)
     * @return The amount available for investment
     */
    function assetExchangeRate(uint8 inputId) public view returns (uint256) {
        if (inputPythIds[inputId] == assetPythId)
            return weiPerShare; // == weiPerUnit of asset == 1:1
        PythStructs.Price memory inputPrice = pyth.getPriceUnsafe(inputPythIds[inputId]);
        PythStructs.Price memory assetPrice = pyth.getPriceUnsafe(assetPythId);
        uint256 inputPriceWei = inputPrice.toUint256(inputDecimals[inputId]); // input (quote) price in wei
        uint256 assetPriceWei = assetPrice.toUint256(assetDecimals); // asset (base) price in wei
        uint256 rate = AsMaths.exchangeRate(
            inputPriceWei, // asset (base) price in wei
            assetPriceWei, assetDecimals); // asset (base) decimals (rate divider)
        return rate;
    }
}
