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
     * @notice Claim rewards from the third party contracts
     * @return amounts Array of rewards claimed for each reward token
     */
    function claimRewards() public onlyKeeper override returns (uint256[] memory amounts) {
        amounts = new uint256[](rewardLength);
        unitroller.claimReward(0, address(this)); // WELL for all markets
        unitroller.claimReward(1, address(this)); // WGAS for all markets

        // wrap native rewards if needed
        _wrapNative();
        for (uint8 i = 0; i < rewardLength; i++) {
            amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
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
