// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../abstract/StrategyV5.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title DummyStrategy - Liquidity providing on Hop
 * @author Astrolab DAO
 * @notice Used to export generic unified StrategyV5+StrategyV5Agent ABI
 */
contract DummyStrategy is StrategyV5 {

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, EIP712 version
     */
    constructor(string[3] memory _erc20Metadata) StrategyV5(_erc20Metadata) {}

    // Struct containing the strategy init parameters
    struct Params { address dummy; }

    /**
     * @dev Initializes the strategy with the specified parameters.
     * @param _params StrategyBaseParams struct containing strategy parameters
     * @param _implementationParams Strategy specific parameters
     */
    function init(
        StrategyBaseParams calldata _params,
        Params calldata _implementationParams
    ) external onlyAdmin {
        StrategyV5._init(_params);
    }

    /**
     * @notice Claim rewards from the reward pool and swap them for underlying
     * @param _params Params array, where _params[0] is minAmountOut
     * @return assetsReceived Amount of assets received
     */
    function _harvest(
        bytes[] memory _params
    ) internal override returns (uint256 assetsReceived) {}

    /**
     * @notice Invests the underlying asset into the pool
     * @param _amount Max amount of underlying to invest
     * @param _params Calldata for swap if input != underlying
     * @return investedAmount Amount invested
     * @return iouReceived Amount of LP tokens received
     */
    function _invest(
        uint256 _amount,
        bytes[] memory _params
    ) internal override returns (uint256 investedAmount, uint256 iouReceived) {}

    /**
     * @notice Withdraw asset function, can remove all funds in case of emergency
     * @param _amount The amount of asset to withdraw
     * @param _params Calldata for the asset swap if needed
     * @return assetsRecovered Amount of asset withdrawn
     */
    function _liquidate(
        uint256 _amount,
        bytes[] memory _params
    ) internal override returns (uint256 assetsRecovered) {}

    /**
     * @notice Returns the investment in asset.
     * @return The amount invested
     */
    function _invested() internal view override returns (uint256) {}

    /**
     * @notice Returns the available HOP rewards
     * @return amounts Array of rewards available for each reward token
     */
    function _rewardsAvailable()
        public
        view
        override
        returns (uint256[] memory amounts)
    {}
}
