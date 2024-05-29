// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.22;

import "../libs/AsArrays.sol";
import "../libs/AsMaths.sol";
import "./StrategyV5.sol";
import "../interfaces/IStrategyV5.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title StrategyV5Composite - Primitives base aggregator strategy
 * @author Astrolab DAO
 * @notice Aggregating network specific primitive strategies positions (acXXX -> apXXX)
 * Can be extended by domain-specific aggregator strategies (eg. acLEND, acDEX, acBRIDGE...)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract StrategyV5Composite is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) StrategyV5(_accessController) {}

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function _setParams(bytes memory _params) internal override {
    // placeholder
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Returns the investment in asset asset for the specified input
   * @return total Amount invested
   */
  function investedInput(uint256 _index) external view override returns (uint256) {
    return _stakedInput(_index);
  }

  /**
   * @notice Returns the invested input converted from the staked LP token
   * @return Input value of the LP/staked balance
   */
  function _stakedInput(uint256 _index) internal view returns (uint256) {
    return IStrategyV5(lpTokens[_index]).balanceOf(address(this));
  }

  /**
   * @notice Convert LP/staked LP to input
   * @param _amount Amount of LP/staked LP
   * @return Input value of the LP amount
   */
  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return IStrategyV5(lpTokens[_index]).convertToAssets(_amount);
  }

  /**
   * @notice Convert input to LP/staked LP
   * @return LP value of the input amount
   */
  function _inputToStake(
    uint256 _amount,
    uint8 _index
  ) internal view override returns (uint256) {
    return IStrategyV5(lpTokens[_index]).convertToShares(_amount);
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            SETTERS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Invests the asset asset into the pool
   * @param _amounts Amounts of asset to invest in each input
   * @param _params Swaps calldata
   * @return totalInvested Amount invested
   */
  function _invest(
    uint256[8] calldata _amounts, // from previewInvest()
    bytes[] calldata _params
  ) internal override nonReentrant returns (uint256 totalInvested) {
    uint256 toDeposit;
    uint256 spent;

    for (uint8 i = 0; i < _inputLength; i++) {
      if (_amounts[i] < 10) continue;

      // We deposit the whole asset balance.
      if (asset != inputs[i] && _amounts[i] > 10) {
        (toDeposit, spent) = swapper.decodeAndSwap({
          _input: address(asset),
          _output: address(inputs[i]),
          _amount: _amounts[i],
          _params: _params[i]
        });
        totalInvested += spent;
        // pick up any input dust (eg. from previous liquidate()), not just the swap output
        totalInvested = inputs[i].balanceOf(address(this));
      } else {
        totalInvested += _amounts[i];
        toDeposit = _amounts[i];
      }

      IStrategyV5 primitive = IStrategyV5(lpTokens[i]);
      uint256 iouBefore = primitive.balanceOf(address(this));
      primitive.deposit(toDeposit, address(this));

      uint256 supplied = primitive.balanceOf(address(this)) - iouBefore;

      // unified slippage check (swap+add liquidity)
      if (
        supplied < _inputToStake(toDeposit, i).subBp(_4626StorageExt().maxSlippageBps * 2)
      ) {
        revert Errors.AmountTooLow(supplied);
      }

      // unchecked {
      //   totalInvested += spent;
      //   i++;
      // }
    }
  }

  /**
   * @notice Withdraw asset function, can remove all funds in case of emergency
   * @param _amounts Amounts of inputs to liquidate in each primitive strategy
   * @param _params Swaps calldata for each primitive strategy (swapping each inputs to assets)
   * @return totalRecovered Amount of asset withdrawn
   */
  function _liquidate(
    uint256[8][8] calldata _amounts, // from previewLiquidate()
    uint256[] calldata _minLiquidity,
    bool _panic,
    bytes[][] memory _params
  ) external returns (uint256 totalRecovered) {
    uint256 recovered;
    uint256 balance;
    uint256 withdrawable;

    for (uint8 i = 0; i < _inputLength; i++) {
      IStrategyV5 primitive = IStrategyV5(lpTokens[i]);
      balance = primitive.balanceOf(address(this));

      withdrawable = AsMaths.min(
        primitive.liquidate(_amounts[i], _minLiquidity[i], _panic, _params[i]), // recovered
        primitive.maxWithdraw(address(this)) // max claimable
      );

      recovered = primitive.withdraw(
        withdrawable,
        address(this),
        address(this)
      );

      totalRecovered += recovered; // no need to check minAmount here, as it's already done in every primitive.liquidate()
    }
    uint256 liquidityAvailable = _availableClaimable().subMax0(
      _req.totalClaimableRedemption.mulDiv(
        last.sharePrice * _weiPerAsset, _WEI_PER_SHARE_SQUARED
      ));
    emit Liquidate(
      totalRecovered,
      liquidityAvailable,
      block.timestamp
    );
  }

  /**
   * @notice Initiate a liquidate request for assets
   * @param _amounts Amounts of asset to liquidate in primitives
   * @param _operator Address initiating the requests in primitives
   * @param _owner The owner of the shares to be redeemed in primitives
   */
  function liquidate(
    uint256[] calldata _amounts,
    uint256 calldata _minLiquidity,
    bool _panic,
    bytes[] memory _params
  ) external override onlyKeeper returns (uint256 amountRequested) {
    for (uint8 i = 0; i < _inputLength; i++) {
      IStrategyV5(lpTokens[i]).requestWithdraw(_amounts[i], _operator, _owner, "0x");
      _req.liquidate[i] += _amounts[i];
      amountRequested += _amounts[i];
    }
  }

  /**
   * @notice Withdraw asset function, can remove all funds in case of emergency
   * @param _amounts Amounts of asset to withdraw
   * @param _params Swaps calldata
   * @return totalRecovered Amount of asset withdrawn
   */
  function _liquidate(
    uint256[8] calldata _amounts, // from previewLiquidate()
    uint256 _minLiquidity,
    bool _panic,
    bytes[] calldata _params
  ) internal override returns (uint256 totalRecovered) {
    uint256 requested;
    IStrategyV5 primitive;
    // here inputLength is the same as primitives.length
    for (uint8 i = 0; i < _inputLength; i++) {
      if (_amounts[i] < 10) continue;

      primitive = IStrategyV5(lpTokens[i]);

      // Determine the minimum amount to compare with the requested amount later
      uint256 minAmount = _req.liquidate[i] > 0 ? _req.liquidate[i].min(_amounts[i]) : 0;

      if (minAmount > 0) {
        requested = primitive.requestWithdraw(minAmount, address(this), address(this));
        _req.liquidate[i] -= requested;
        _req.liquidateTimestamp[i] = block.timestamp;
      } else {
        revert Errors.Unauthorized();
      }

      // Use minAmount for the slippage check
      if (requested < minAmount.subBp(_4626StorageExt().maxSlippageBps * 2)) {
        revert Errors.AmountTooLow(requested);
      }
    }
  }

  /**
   * @notice Stakes or provides `_amount` from `input[_index]` to `lpTokens[_index]`
   * @param _index Index of the input to stake
   * @param _amount Amount of underlying assets to allocate to `inputs[_index]`
   */
  function _stake(uint256 _index, uint256 _amount) internal override {}

  /**
   * @notice Unstakes or liquidates `_amount` of `lpTokens[i]` back to `input[_index]`
   * @param _index Index of the input to liquidate
   * @param _amount Amount of underlying assets to recover from liquidating `inputs[_index]`
   */
  function _unstake(uint256 _index, uint256 _amount) internal override {}
}
