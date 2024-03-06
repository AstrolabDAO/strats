// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "../abstract/StrategyV5.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title DummyStrategy - A dummy strategy for ABI generation purpose
 * @author Astrolab DAO
 * @notice Used to export generic unified StrategyV5+StrategyV5Agent ABI
 */
contract DummyStrategy is StrategyV5 {

    constructor() StrategyV5() {}

    // Struct containing the strategy init parameters
    struct Params { address dummy; }

    function init(
        StrategyBaseParams calldata _params,
        Params calldata _implementationParams
    ) external onlyAdmin {
        StrategyV5._init(_params);
    }

    function _harvest(
        bytes[] calldata _params
    ) internal override returns (uint256 assetsReceived) {}

    function _invest(
        uint256[8] calldata _amounts,
        bytes[] calldata _params
    ) internal override returns (uint256 investedAmount, uint256 iouReceived) {}

    function _liquidate(
        uint256[8] calldata _amounts,
        bytes[] calldata _params
    ) internal override returns (uint256 assetsRecovered) {}

    function invested() public view override returns (uint256) {}

    function invested(uint8 _index) public view override returns (uint256) {}

    function investedInput(uint8 _index) internal view override returns (uint256) {}

    function rewardsAvailable()
        public
        view
        override
        returns (uint256[] memory amounts)
    {}
}
