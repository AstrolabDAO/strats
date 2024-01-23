// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "../abstract/AsTypes.sol";
import "../interfaces/IAs4626.sol";
import "./AsCast.sol";
import "./AsMaths.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsAccounting Library
 * @author Astrolab DAO
 * @notice Accounting library for Astrolab Vaults
 * @dev This library contains functions for calculating fees and PnL
 */
library AsAccounting {
    using AsMaths for uint256;
    using AsCast for uint256;
    using AsCast for int256;

    /**
     * @dev Computes the fees for the given As4626 contract
     * @param self The As4626 contract instance
     * @return assets The total assets of the contract
     * @return price The current share price of the contract
     * @return profit The calculated profit since the last fee collection
     * @return feesAmount The amount of fees to be collected
     */
    function computeFees(
        IAs4626 self
    )
        public
        view
        returns (
            uint256 assets,
            uint256 price,
            uint256 profit,
            uint256 feesAmount
        )
    {
        Epoch memory last = self.last();
        Fees memory fees = self.fees();
        price = self.sharePrice();

        // Calculate the duration since the last fee collection
        uint64 duration = uint64(block.timestamp) - last.feeCollection;

        // Calculate the profit since the last fee collection
        int256 change = int256(price) - int256(last.accountedSharePrice); // 1e? - 1e? = 1e?

        // If called within the same block or the share price decreased, no fees are collected
        if (duration == 0 || change < 0) return (0, 0, 0, 0);

        // relative profit = (change / last price) on a PRECISION_BP_BASIS scale
        profit = uint256(change).mulDiv(
            AsMaths.PRECISION_BP_BASIS,
            last.accountedSharePrice
        ); // 1e? * 1e8 / 1e? = 1e8

        // Calculate management fees as proportion of profits on a PRECISION_BP_BASIS scale
        // NOTE: This is a linear approximation of the accrued profits (SEC_PER_YEAR ~3e11)
        uint256 mgmtFeesRel = profit.mulDiv(
            fees.mgmt * duration,
            AsMaths.SEC_PER_YEAR
        ); // 1e8 * 1e4 * 1e? / 1e? = 1e12

        // Calculate performance fees as proportion of profits on a PRECISION_BP_BASIS scale
        uint256 perfFeesRel = profit * fees.perf; // 1e8 * 1e4 = 1e12

        // Adjust fees if it exceeds profits
        uint256 feesRel = AsMaths.min(
            (mgmtFeesRel + perfFeesRel) / AsMaths.BP_BASIS, // 1e12 / 1e4 = 1e8
            profit
        );

        assets = self.totalAssets();
        // Convert fees to assets
        feesAmount = feesRel.mulDiv(assets, AsMaths.PRECISION_BP_BASIS); // 1e8 * 1e? / 1e8 = 1e? (asset decimals)
        return (assets, price, profit, feesAmount);
    }

    /**
     * @notice Linearization of the accrued profits
     * @dev This is used to calculate the total assets under management
     * @param lastHarvest Timestamp of the last harvest
     * @param expectedProfits Expected profits since the last harvest
     * @param profitCooldown Cooldown period for realizing gains
     * @return The amount of profits that are not yet realized
     */
    function unrealizedProfits(
        uint256 lastHarvest,
        uint256 expectedProfits,
        uint256 profitCooldown
    ) public view returns (uint256) {
        // If the cooldown period is over, gains are realized
        if (lastHarvest + profitCooldown < block.timestamp) {
            return 0;
        }

        // Calculate unrealized profits during cooldown using mulDiv for precision
        uint256 elapsedTime = block.timestamp - lastHarvest;
        uint256 realizedProfits = expectedProfits.mulDiv(
            elapsedTime,
            profitCooldown
        );

        // Return the amount of profits that are not yet realized
        return expectedProfits - realizedProfits;
    }

    /**
     * @notice Check if provided fees are within the allowed maximum fees
     * @param _fees Struct containing fee parameters (performance, management, entry, exit, flash fees)
     * @return Whether the provided fees are within the allowed maximum fees
     */
    function checkFees(
        Fees calldata _fees
    ) public pure returns (bool) {
        return
            _fees.perf <= 5_000 && // 50%
            _fees.mgmt <= 500 && // 5%
            _fees.entry <= 200 && // 2%
            _fees.exit <= 200 && // 2%
            _fees.flash <= 200; // 2%
    }
}