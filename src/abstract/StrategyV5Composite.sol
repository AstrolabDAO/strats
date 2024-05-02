// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.22;

import "../libs/AsArrays.sol";
import "../libs/AsMaths.sol";
import "./StrategyV5.sol";

import "../interfaces/IAs4626.sol";

/**
 * _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title StrategyV5Composite - Liquidity providing on primitives
 * @author Astrolab DAO
 * @notice Liquidity providing for network specific AsPrimitives
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract StrategyV5Composite is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using SafeERC20 for IERC20Metadata;

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  // Third party contracts
  address[8] public _primitives;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) StrategyV5(_accessController) {}

  /**
   * @notice Sets the strategy specific parameters
   * @param _params Strategy specific parameters
   */
  function _setParams(bytes memory _params) internal override {
    (address[8] memory primitives) = abi.decode(_params, (address[8]));
    _primitives = primitives;
    _setAllowances(AsMaths.MAX_UINT256);
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
    return IAs4626(_primitives[_index]).balanceOf(address(this));
  }

  /**
   * @notice Returns the investment in asset asset for the specified input
   * @return total Amount invested
   */
  function invested(uint256 _index) public view override returns (uint256) {
    return IAs4626(_primitives[_index]).convertToAssets(
      IAs4626(_primitives[_index]).balanceOf(address(this))
    );
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
    return IAs4626(_primitives[_index]).convertToAssets(_amount);
  }

  /**
   * @notice Convert input to LP/staked LP
   * @return LP value of the input amount
   */
  //   function _inputToStake(
  //     uint256 _amount,
  //     uint8 _index
  //   ) internal view override returns (uint256) {
  //     return IAs4626(_primitives[_index]).convertToShares(_amount);
  //   }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            SETTERS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Changes the strategy input tokens
   * @param _inputs Array of input token addresses
   * @param _weights Array of input token weights
   * @param _newPrimitives Array of primitives addresses
   */
  function setInputs(
    address[] calldata _inputs,
    uint16[] calldata _weights,
    address[] calldata _newPrimitives
  ) external onlyAdmin {
    // update inputs and lpTokens
    _setInputs(_inputs, _weights, _newPrimitives);
    for (uint256 i = 0; i < _newPrimitives.length; i++) {
      _primitives[i] = _newPrimitives[i];
    }
    _setAllowances(AsMaths.MAX_UINT256);
  }

  /**
   * @notice Sets allowances for third party contracts (except rewardTokens)
   * @param _amount Allowance amount
   */
  function _setAllowances(uint256 _amount) internal override {
    for (uint8 i = 0; i < _inputLength; i++) {
      inputs[i].forceApprove(address(lpTokens[i]), _amount);
    }
  }

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

      IAs4626 primitive = IAs4626(_primitives[i]);
      uint256 iouBefore = primitive.balanceOf(address(this));
      primitive.deposit(toDeposit, address(this));

      uint256 supplied = primitive.balanceOf(address(this)) - iouBefore;

      // unified slippage check (swap+add liquidity)
      if (
        supplied < _inputToStake(toDeposit, i).subBp(_4626StorageExt().maxSlippageBps * 2)
      ) {
        revert Errors.AmountTooLow(supplied);
      }

      //   unchecked {
      //     totalInvested += spent;
      //     i++;
      //   }
    }
  }

  /**
   * @notice Withdraw asset function, can remove all funds in case of emergency
   * @param _amounts Amounts of asset to withdraw in primitives, and in primitives pools
   * @param _params Swaps calldata for primitives and for primitives pools
   * @return assetsRecovered Amount of asset withdrawn
   */
  function liquidatePrimitives(
    uint256[8][8] calldata _amounts, // from previewLiquidate()
    uint256[] calldata _minLiquidity,
    bytes[][] memory _params
  ) external nonReentrant onlyKeeper returns (uint256 assetsRecovered) {
    uint256 recovered;
    uint256 balance;

    for (uint8 i = 0; i < _inputLength; i++) {
      IAs4626 primitive = IAs4626(_primitives[i]);
      balance = primitive.balanceOf(address(this));

      recovered = primitive.withdraw(
        IStrategyV5(_primitives[i]).liquidate(
          _amounts[i], _minLiquidity[i], false, _params[i]
        ),
        address(this),
        address(this)
      );

      assetsRecovered += recovered;
    }
  }

  /**
   * @notice Initiate a liquidate request for assets
   * @param _amounts Amounts of asset to liquidate in primitives
   * @param _operator Address initiating the requests in primitives
   * @param _owner The owner of the shares to be redeemed in primitives
   */
  function requestLiquidate(
    uint256[] calldata _amounts,
    address _operator,
    address _owner
  ) external nonReentrant whenNotPaused onlyManager returns (uint256 amountRequested) {
    for (uint8 i = 0; i < _inputLength; i++) {
      IAs4626(_primitives[i]).requestWithdraw(_amounts[i], _operator, _owner, "0x");
      _req.liquidate[i] += _amounts[i];
      amountRequested += _amounts[i];
    }
  }

  /**
   * @notice Withdraw asset function, can remove all funds in case of emergency
   * @param _amounts Amounts of asset to withdraw
   * @param _params Swaps calldata
   * @return assetsRecovered Amount of asset withdrawn
   */
  function _liquidate(
    uint256[8] calldata _amounts, // from previewLiquidate()
    uint256 _minLiquidity,
    bool _panic,
    bytes[] calldata _params
  ) internal override returns (uint256 assetsRecovered) {
    uint256 recovered;
    IAs4626 primitive;
    // here inputLength is the same as primitives.length
    for (uint8 i = 0; i < _inputLength; i++) {
      if (_amounts[i] < 10) continue;

      primitive = IAs4626(_primitives[i]);

      // Determine the minimum amount to compare with the recovered amount later
      uint256 minAmount = _req.liquidate[i] > 0 ? _req.liquidate[i].min(_amounts[i]) : 0;

      if (minAmount > 0) {
        recovered = primitive.withdraw(minAmount, address(this), address(this));
        _req.liquidate[i] -= recovered;
        _req.liquidateTimestamp[i] = block.timestamp;
      } else {
        revert Errors.Unauthorized();
      }

      // Use minAmount for the slippage check
      if (recovered < minAmount.subBp(_4626StorageExt().maxSlippageBps * 2)) {
        revert Errors.AmountTooLow(recovered);
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
