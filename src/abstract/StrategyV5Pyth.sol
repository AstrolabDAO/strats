// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libs/AsMaths.sol";
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
    IPyth internal pyth; // Pyth oracle
    bytes32 internal underlyingPythId; // Pyth id of the underlying asset
    bytes32[8] internal inputPythIds; // Pyth id of the inputs
    uint8 internal underlyingDecimals; // Decimals of the underlying asset
    uint8[8] internal inputDecimals; // Decimals of the input asset

    struct PythParams {
        address pyth;
        bytes32 underlyingPythId;
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
        pyth = IPyth(_pythParams.pyth);
        underlyingPythId = _pythParams.underlyingPythId;
        underlyingDecimals = underlying.decimals();

        for (uint256 i = 0; i < _pythParams.inputPythIds.length; i++) {
            if (address(inputs[i]) == address(0)) break;
            inputPythIds[i] = _pythParams.inputPythIds[i];
            inputDecimals[i] = inputs[i].decimals();
        }
    }

    /**
     * @notice Computes the underlying/input exchange rate from Pyth oracle price feeds in bps
     * @dev Used by invested() to compute input->underlying (base/quote, eg. USDC/BTC not BTC/USDC)
     * @return The amount available for investment
     */
    function underlyingExchangeRate(uint8 inputId) public view returns (uint256) {
        if (inputPythIds[inputId] == underlyingPythId)
            return weiPerShare; // == weiPerUnit of underlying == 1:1
        return pyth.getPrice(inputPythIds[inputId]).toUint256(inputDecimals[inputId]) // input (quote) price in wei
                .exchangeRate(
                    pyth.getPrice(underlyingPythId).toUint256(underlyingDecimals), // underlying (base) price in wei
                    underlyingDecimals); // underlying (base) decimals (rate divider)
    }
}