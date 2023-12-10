// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "../abstract/AsTypes.sol";
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
     * @notice Calculates performance and management fees based on vault profits and elapsed time.
     * @param totalAssets Total assets under management in the vault.
     * @param sharePrice Current share price of the vault.
     * @param fees Struct containing fee parameters (performance and management fees).
     * @param last Struct containing checkpoint information from the last fee collection.
     * @return perfFeesAmount The calculated performance fee.
     * @return mgmtFeesAmount The calculated management fee.
     * @return profit The vault profit since the last fee collection.
     */
    function computeFees(
        uint256 totalAssets,
        uint256 sharePrice,
        Fees calldata fees,
        Checkpoint calldata last
    )
        public
        view
        returns (uint256 perfFeesAmount, uint256 mgmtFeesAmount, uint256 profit)
    {
        // Calculate the duration since the last fee collection
        uint256 duration = block.timestamp - last.feeCollection;

        // If called within the same block, return zero fees
        if (duration == 0) return (0, 0, 0);

        // Calculate the profit since the last fee collection
        int256 priceChange = int256(sharePrice) - int256(last.accountedSharePrice);
        if (priceChange < 0)
            // If the share price decreased, no fees are collected
            return (0, 0, 0);

        // relative profit = price change / last price on a BP_BASIS^2 scale
        profit = uint256(priceChange).mulDiv(AsMaths.PRECISION_BP_BASIS, last.accountedSharePrice);

        // Calculate management fees as a percentage of total assets
        // NOTE: This is a linear approximation of the accrued profits on a BP_BASIS^2 scale

        uint256 mgmtFeesRel = sharePrice.mulDiv(
            fees.mgmt * duration,
            AsMaths.SEC_PER_YEAR // approx 3e11
        );

        // Calculate performance fees as a percentage of profits
        uint256 perfFeesRel = profit.bp(fees.perf);

        // Adjust management fee if it exceeds profits after performance fee
        if ((mgmtFeesRel + perfFeesRel) > profit)
            mgmtFeesRel = profit.subMax0(perfFeesRel);

        // Convert fees to assets
        perfFeesAmount = perfFeesRel.mulDiv(totalAssets, AsMaths.PRECISION_BP_BASIS);
        mgmtFeesAmount = mgmtFeesRel.mulDiv(totalAssets, AsMaths.PRECISION_BP_BASIS);

        return (perfFeesAmount, mgmtFeesAmount, profit);
    }

    /**
     * @notice Linearization of the accrued profits
     * @dev This is used to calculate the total assets under management
     * @param lastHarvest Timestamp of the last harvest.
     * @param expectedProfits Expected profits since the last harvest.
     * @param profitCooldown Cooldown period for realizing gains.
     * @return The amount of profits that are not yet realized.
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
     * @notice Check if provided fees are within the allowed maximum fees.
     * @param _fees Struct containing fee parameters (performance, management, entry, exit fees).
     * @param _maxFees Struct containing maximum allowed fee parameters.
     * @return Whether the provided fees are within the allowed maximum fees.
     */
    function checkFees(
        Fees calldata _fees,
        Fees calldata _maxFees
    ) public pure returns (bool) {
        return
            _fees.perf <= _maxFees.perf &&
            _fees.mgmt <= _maxFees.mgmt &&
            _fees.entry <= _maxFees.entry &&
            _fees.exit <= _maxFees.exit;
    }
}

/**
 * @title Uniswap's FixedPoint96
 * @notice see https://en.wikipedia.org/wiki/Q_(number_format)
 * @dev Used in SqrtPriceMath.sol
 */
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96; // Number of bits for representing fixed point numbers
    uint256 internal constant Q96 = 0x1000000000000000000000000; // 2^96, representing 1 in fixed point format
}

/**
 * @title Liquidity amount functions
 * @notice Provides functions for computing liquidity amounts from token amounts and prices
 */
library AsPoolMaths {
    using AsMaths for uint256;
    using AsCast for uint256;
    using AsCast for int256;

    /**
     * @notice Computes the amount of liquidity received for a given amount of token0 and price range
     * @dev Calculates amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
     * @param sqrtRatioAX96 A sqrt price representing the first tick boundary
     * @param sqrtRatioBX96 A sqrt price representing the second tick boundary
     * @param amount0 The amount0 being sent in
     * @return liquidity The amount of returned liquidity
     */
    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = AsMaths.mulDiv(
            sqrtRatioAX96,
            sqrtRatioBX96,
            FixedPoint96.Q96
        );
        return
            amount0
                .mulDiv(intermediate, sqrtRatioBX96 - sqrtRatioAX96)
                .toUint128();
    }

    /**
     * @notice Computes the amount of liquidity received for a given amount of token1 and price range
     * @dev Calculates amount1 / (sqrt(upper) - sqrt(lower)).
     * @param sqrtRatioAX96 A sqrt price representing the first tick boundary
     * @param sqrtRatioBX96 A sqrt price representing the second tick boundary
     * @param amount1 The amount1 being sent in
     * @return liquidity The amount of returned liquidity
     */
    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return
            amount1
                .mulDiv(FixedPoint96.Q96, sqrtRatioBX96 - sqrtRatioAX96)
                .toUint128();
    }

    /**
     * @notice Computes the maximum amount of liquidity received for a given amount of token0, token1, the current
     * pool prices and the prices at the tick boundaries
     * @param sqrtRatioX96 A sqrt price representing the current pool prices
     * @param sqrtRatioAX96 A sqrt price representing the first tick boundary
     * @param sqrtRatioBX96 A sqrt price representing the second tick boundary
     * @param amount0 The amount of token0 being sent in
     * @param amount1 The amount of token1 being sent in
     * @return liquidity The maximum amount of liquidity received
     */
    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = getLiquidityForAmount0(
                sqrtRatioAX96,
                sqrtRatioBX96,
                amount0
            );
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = getLiquidityForAmount0(
                sqrtRatioX96,
                sqrtRatioBX96,
                amount0
            );
            uint128 liquidity1 = getLiquidityForAmount1(
                sqrtRatioAX96,
                sqrtRatioX96,
                amount1
            );

            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(
                sqrtRatioAX96,
                sqrtRatioBX96,
                amount1
            );
        }
    }

    /**
     * @notice Computes the amount of token0 for a given amount of liquidity and a price range
     * @param sqrtRatioAX96 A sqrt price representing the first tick boundary
     * @param sqrtRatioBX96 A sqrt price representing the second tick boundary
     * @param liquidity The liquidity being valued
     * @return amount0 The amount of token0
     */
    function getAmount0ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
            AsMaths.mulDiv(
                uint256(liquidity) << FixedPoint96.RESOLUTION,
                sqrtRatioBX96 - sqrtRatioAX96,
                sqrtRatioBX96
            ) / sqrtRatioAX96;
    }

    /**
     * @notice Computes the amount of token1 for a given amount of liquidity and a price range
     * @param sqrtRatioAX96 A sqrt price representing the first tick boundary
     * @param sqrtRatioBX96 A sqrt price representing the second tick boundary
     * @param liquidity The liquidity being valued
     * @return amount1 The amount of token1
     */
    function getAmount1ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
            AsMaths.mulDiv(
                liquidity,
                sqrtRatioBX96 - sqrtRatioAX96,
                FixedPoint96.Q96
            );
    }

    /**
     * @notice Computes the token0 and token1 value for a given amount of liquidity, the current
     * pool prices and the prices at the tick boundaries
     * @param sqrtRatioX96 A sqrt price representing the current pool prices
     * @param sqrtRatioAX96 A sqrt price representing the first tick boundary
     * @param sqrtRatioBX96 A sqrt price representing the second tick boundary
     * @param liquidity The liquidity being valued
     * @return amount0 The amount of token0
     * @return amount1 The amount of token1
     */
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = getAmount0ForLiquidity(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity
            );
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = getAmount0ForLiquidity(
                sqrtRatioX96,
                sqrtRatioBX96,
                liquidity
            );
            amount1 = getAmount1ForLiquidity(
                sqrtRatioAX96,
                sqrtRatioX96,
                liquidity
            );
        } else {
            amount1 = getAmount1ForLiquidity(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity
            );
        }
    }
}
