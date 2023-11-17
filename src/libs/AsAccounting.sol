// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "../abstract/AsTypes.sol";
import "./AsMaths.sol";

library AsAccounting {
    using AsMaths for uint256;

    /// @notice Calculates performance and management fees based on vault profits and elapsed time.
    /// @return perfFeesAmount The calculated performance fee.
    /// @return mgmtFeesAmount The calculated management fee.
    /// @return profit The vault profit since the last feeCollectedAt.
    function computeFees(
        uint256 totalAssets,
        uint256 sharePrice,
        uint256 BPS_BASIS,
        Fees calldata fees,
        Checkpoint calldata feeCollectedAt
    )
        public
        view
        returns (uint256 perfFeesAmount, uint256 mgmtFeesAmount, uint256 profit)
    {
        uint256 duration = block.timestamp - feeCollectedAt.timestamp;
        if (duration == 0) return (0, 0, 0); // No fees if called within the same block
        profit =
            AsMaths.max(feeCollectedAt.sharePrice, sharePrice)
            - feeCollectedAt.sharePrice;
        if (profit == 0) return (0, 0, 0); // No fees for no profits

        uint256 mgmtFeesRel = sharePrice.mulDiv(
            fees.mgmt * duration,
            BPS_BASIS * 365 days
        );
        uint256 perfFeesRel = profit.mulDiv(fees.perf, BPS_BASIS);

        // Adjust management fee if it exceeds profits after performance fee
        if (mgmtFeesRel + perfFeesRel > profit) {
            mgmtFeesRel = profit - perfFeesRel;
        }

        // Convert fees to assets
        perfFeesAmount = perfFeesRel.mulDiv(totalAssets, sharePrice);
        mgmtFeesAmount = mgmtFeesRel.mulDiv(totalAssets, sharePrice);

        return (perfFeesAmount, mgmtFeesAmount, profit);
    }

    /// @notice Linearization of the accrued profits
    /// @dev This is used to calculate the total assets under management
    /// @return The amount of profits that are not yet realized
    function unrealizedProfits(
        uint256 lastUpdate,
        uint256 expectedProfits,
        uint256 profitCooldown
    ) public view returns (uint256) {
        if (lastUpdate + profitCooldown < block.timestamp) {
            return 0; // Gains are realized if cooldown is over
        }
        // Calculate unrealized pnl during cooldown using mulDiv for precision
        uint256 elapsedTime = block.timestamp - lastUpdate;
        uint256 realizedProfits = expectedProfits.mulDiv(
            elapsedTime,
            profitCooldown
        );
        return expectedProfits - realizedProfits;
    }

    function checkFees(Fees calldata _fees, Fees calldata _maxFees) public pure returns (bool) {
        return
            _fees.perf <= _maxFees.perf &&
            _fees.mgmt <= _maxFees.mgmt &&
            _fees.entry <= _maxFees.entry &&
            _fees.exit <= _maxFees.exit;
    }

}
