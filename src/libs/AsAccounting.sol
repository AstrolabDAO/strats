// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../abstract/AsTypes.sol";
import "../interfaces/IAs4626.sol";
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
  uint256 public constant MAX_MGMT_FEE = 500; // 5%
  uint256 public constant MAX_ENTRY_FEE = 200; // 2%
  uint256 public constant MAX_EXIT_FEE = 200; // 2%
  uint256 public constant MAX_FLASH_LOAN_FEE = 200; // 2%

  /*═══════════════════════════════════════════════════════════════╗
  ║                              VIEWS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @dev Computes the fees for an As4626 instance
   * @param self As4626 contract instance
   * @return assets Total assets of the contract
   * @return price Current share price of the contract
   * @return profit Calculated profit since the last fee collection
   * @return feesAmount Amount of fees to be collected
   */
  function computeFees(IAs4626 self)
    public
    view
    returns (uint256 assets, uint256 price, uint256 profit, uint256 feesAmount)
  {
    Epoch memory last = self.last();
    Fees memory fees = self.fees();
    price = self.sharePrice();

    // calculate the duration since the last fee collection
    uint64 duration = uint64(block.timestamp) - last.feeCollection;

    // calculate the profit since the last fee collection
    int256 change = int256(price) - int256(last.accountedSharePrice); // 1e? - 1e? = 1e?

    // if called within the same block or the share price decreased, no fees are collected
    if (duration == 0 || change < 0) return (0, price, 0, 0);

    // relative profit = (change / last price) on a _PRECISION_BP_BASIS scale
    profit = uint256(change).mulDiv(AsMaths._PRECISION_BP_BASIS, last.accountedSharePrice); // 1e? * 1e12 / 1e? = 1e12

    // calculate management fees as proportion of profits on a _PRECISION_BP_BASIS scale
    // NOTE: this is a linear approximation of the accrued profits (_SEC_PER_YEAR ~3e11)
    uint256 mgmtFeesRel = profit.mulDiv(fees.mgmt * duration, AsMaths._SEC_PER_YEAR); // 1e12 * 1e4 * 1e? / 1e? = 1e12

    // calculate performance fees as proportion of profits on a _PRECISION_BP_BASIS scale
    uint256 perfFeesRel = profit * fees.perf; // 1e12 * 1e4 = 1e12

    // adjust fees if it exceeds profits
    uint256 feesRel = AsMaths.min(
      (mgmtFeesRel + perfFeesRel) / AsMaths._BP_BASIS, // 1e12 / 1e4 = 1e12
      profit
    );

    assets = self.totalAssets();
    // convert fees to assets
    feesAmount = feesRel.mulDiv(assets, AsMaths._PRECISION_BP_BASIS); // 1e12 * 1e? / 1e12 = 1e? (asset decimals)
    return (assets, price, profit, feesAmount);
  }

  /**
   * @notice Computes the unrealized profits by accruing `_expectedProfits` linearly over `_profitCooldown`
   * @param lastHarvest Timestamp of the last harvest
   * @param _expectedProfits Expected profits since the last harvest, unrealized
   * @param _profitCooldown Cooldown period for realizing gains
   * @return Amount of profits that are not yet realized
   */
  function unrealizedProfits(
    uint256 lastHarvest,
    uint256 _expectedProfits,
    uint256 _profitCooldown
  ) public view returns (uint256) {
    // if the cooldown period is over, gains are realized
    if (lastHarvest + _profitCooldown < block.timestamp) {
      return 0;
    }

    // calculate unrealized profits during cooldown using mulDiv for precision
    uint256 elapsedTime = block.timestamp - lastHarvest;
    uint256 realizedProfits = _expectedProfits.mulDiv(elapsedTime, _profitCooldown);

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
