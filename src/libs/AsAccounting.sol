// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/IStrategyV5.sol";
import "./AsTypes.sol";
import "./AsCast.sol";
import "./AsMaths.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsAccounting Library - Astrolab's Accounting library
 * @author Astrolab DAO
 */
library AsAccounting {
  using AsMaths for uint256;
  using AsCast for uint256;
  using AsCast for int256;

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  uint256 public constant MAX_PERF_FEE = 5_000; // 50%
  uint256 public constant MAX_MGMT_FEE = 10_00; // 10%
  uint256 public constant MAX_ENTRY_FEE = 200; // 2%
  uint256 public constant MAX_EXIT_FEE = 200; // 2%
  uint256 public constant MAX_FLASH_LOAN_FEE = 200; // 2%

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @dev Computes the management and performance fees for an As4626 instance
   * @param strat As4626 contract instance
   * @return assets Total assets of the contract
   * @return price Current share price of the contract
   * @return profit Calculated profit since the last fee collection in precision bps
   * @return totalFees Fees to be collected in assets, including management, and performance fees
   */
  function claimableDynamicFees(IStrategyV5 strat)
    public
    view
    returns (uint256 assets, uint256 price, uint256 profit, uint256 totalFees)
  {
    Epoch memory last = strat.last();
    Fees memory fees = strat.fees();
    assets = strat.totalAssets();
    price = strat.sharePrice();

    uint256 elapsed = block.timestamp - uint256(last.feeCollection); // time since last collection
    int256 change = int256(price) - int256(last.accountedSharePrice); // raw price change
    if (elapsed == 0 || (change < 0 && fees.mgmt == 0)) {
      return (assets, price, 0, 0); // no fees to collect
    }
    uint256 durationBps = elapsed.mulDiv(AsMaths.PRECISION_BP_BASIS, AsMaths.SEC_PER_YEAR); // relative duration (yearly) in bps
    uint256 profitBps = uint256(change).mulDiv(AsMaths.PRECISION_BP_BASIS, price); // relative profit in bps
    totalFees = assets.mulDiv(
      (profitBps * fees.perf) + (durationBps * fees.mgmt),
      AsMaths.PRECISION_BP_BASIS * AsMaths.BP_BASIS // debase in assets
    ); // perf + mgmt fees
    return (assets, price, profitBps, totalFees);
  }

  /**
   * @notice Computes the unrealized profits by accruing harvested `_expectedProfits` linearly over `_profitCooldown`
   * @param _lastHarvest Timestamp of the last harvest
   * @param _expectedProfits Expected profits since the last harvest, unrealized
   * @param _profitCooldown Cooldown period for realizing gains
   * @return Amount of profits that are not yet realized
   */
  function unrealizedProfits(
    uint256 _lastHarvest,
    uint256 _expectedProfits,
    uint256 _profitCooldown
  ) public view returns (uint256) {
    if (_lastHarvest + _profitCooldown < block.timestamp) {
      return 0; // no profits to realize
    }

    // calculate unrealized profits during cooldown using mulDiv for precision
    uint256 elapsed = block.timestamp - _lastHarvest;
    uint256 realizedProfits = _expectedProfits.mulDiv(elapsed, _profitCooldown);

    // return the amount of profits that are not yet realized
    return _expectedProfits - realizedProfits;
  }

  /**
   * @notice Check if provided fees are within the allowed maximum fees
   * @param _fees Struct containing fee parameters (performance, management, entry, exit, flash fees)
   * @return Whether the provided fees are within the allowed maximum fees
   */
  function checkFees(Fees memory _fees) internal pure returns (bool) {
    return _fees.perf <= MAX_PERF_FEE && _fees.mgmt <= MAX_MGMT_FEE
      && _fees.entry <= MAX_ENTRY_FEE && _fees.exit <= MAX_EXIT_FEE
      && _fees.flash <= MAX_FLASH_LOAN_FEE;
  }
}
