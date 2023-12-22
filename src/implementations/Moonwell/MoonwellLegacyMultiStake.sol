// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "../../libs/AsArrays.sol";
import "./MoonwellMultiStake.sol";
import "./interfaces/IMoonwell.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title MoonwellLegacyMultiStake Strategy - Liquidity providing on Moonwell Artemis/Apollo (Moonbeam/Moonriver)
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Moonwell (https://moonwell.fi/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract MoonwellLegacyMultiStake is MoonwellMultiStake {
    using AsMaths for uint256;
    using AsArrays for uint256;
    using SafeERC20 for IERC20;

    constructor() MoonwellMultiStake() {}

    /**
     * @notice Claim rewards from the reward pool and swap them for asset
     * @param _params Swaps calldata
     * @return assetsReceived Amount of assets received
     * @dev cf.
     *  - https://github.com/MoonwellProtocol/venus-protocol-documentation/blob/f6234c6b70c15b847aaf8645991262c8a3b7c4e3/technical-reference/reference-core-pool/comptroller/Diamond/facets/reward-facet.md#L6
     *  - https://github.com/MoonwellProtocol/venus-protocol-documentation/blob/f6234c6b70c15b847aaf8645991262c8a3b7c4e3/technical-reference/reference-isolated-pools/rewards/rewards-distributor.md#L233
     */
    function _harvest(
        bytes[] memory _params
    ) internal override nonReentrant returns (uint256 assetsReceived) {

        unitroller.claimReward(0, address(this)); // WELL for all markets
        unitroller.claimReward(1, address(this)); // WGLMR/WMOVR for all markets

        uint256 balance;
        for (uint8 i = 0; i < rewardLength; i++) {
            balance = IERC20Metadata(rewardTokens[i]).balanceOf(
                address(this)
            );
            if (rewardTokens[i] != address(asset)) {
                if (balance < 10) return 0;
                (uint256 received, ) = swapper.decodeAndSwap({
                    _input: rewardTokens[i],
                    _output: address(asset),
                    _amount: balance,
                    _params: _params[i]
                });
                assetsReceived += received;
            } else {
                assetsReceived += balance;
            }
        }
    }

    /**
     * @notice Returns the available rewards
     * @return amounts Array of rewards available for each reward token
     */
    function rewardsAvailable()
        public
        view
        override
        returns (uint256[] memory amounts)
    {
        return unitroller.rewardAccrued(uint8(0), address(this)) // WELL
            .toArray(unitroller.rewardAccrued(uint8(1), address(this))); // WGLMR/WMOVR
    }
}
