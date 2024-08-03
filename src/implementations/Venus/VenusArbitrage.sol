// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5.sol";
import "./interfaces/IVenus.sol";
import {IPoolAddressesProvider, IAavePool} from "../Aave/interfaces/v3/IAave.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title Venus Arbitrage - Dynamic liquidity providing on Venus
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Venus (https://venus.io/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract VenusArbitrage is StrategyV5 {
  using AsMaths for uint256;
  using AsArrays for uint256;
  using AsArrays for address;
  using SafeERC20 for IERC20Metadata;

  struct Params {
    IUnitroller unitroller;
    IPoolAddressesProvider aavePoolProvider;
    uint256 leverage; // 100 == 1:1 leverage
  }

  struct Pending {
    bool investing;
    bytes data;
  }

  Params public params;

  constructor(address _accessController) StrategyV5(_accessController) {}

  function _setParams(bytes memory _params) internal override {
    params = abi.decode(_params, (Params));
    (, uint256 ltv, ) = params.unitroller.markets(address(lpTokens[0])); // base 1e18
    unchecked {
      if (
        inputWeights[1] != 0 || (100 * 1e18) / (1e18 - ltv) <= params.leverage
      ) {
        // base max leverage check
        revert Errors.Unauthorized();
      }
    }
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
    params.unitroller.enterMarkets(
      address(lpTokens[0]).toArray(address(lpTokens[1]))
    );
  }

  function _leveraged(int256 _cash) internal view returns (int256 result) {
    unchecked {
      return (_cash * int256(params.leverage)) / 100;
    }
  }

  function _debtForSupply(
    uint256 _cash,
    bool _loanOnly
  ) internal view returns (uint256) {
    unchecked {
      return
        oracle().convert(address(inputs[0]), _cash, address(inputs[1])).mulDiv(
          params.leverage - (_loanOnly ? 0 : 100),
          params.leverage
        );
    }
  }

  function _supplyForDebt(
    uint256 _debt,
    bool _loanOnly
  ) internal view returns (uint256) {
    unchecked {
      return
        oracle().convert(address(inputs[1]), _debt, address(inputs[0])).mulDiv(
          params.leverage,
          params.leverage - (_loanOnly ? 0 : 100)
        );
    }
  }

  function _supply0() internal view returns (uint256) {
    return _stakeToInput(lpTokens[0].balanceOf(address(this)), 0);
  }

  function _excessDebt(uint256 _supply) internal view returns (int256) {
    unchecked {
      // compute theoretical debt for the current input0 supply + addon
      return
        int256(
          IVToken(address(lpTokens[1])).borrowBalanceStored(address(this))
        ) - int256(_debtForSupply(_supply, false)); // actual - target
    }
  }

  function _debtNeed(int256 _previewAmount0) internal view returns (uint256) {
    unchecked {
      return
        uint256(
          -AsMaths.min(
            _excessDebt(
              uint256(int256(_supply0()) + _leveraged(_previewAmount0))
            ),
            0
          )
        );
    }
  }

  function _repaymentNeed(
    int256 _previewAmount0
  ) internal view returns (uint256) {
    unchecked {
      return
        uint256(
          AsMaths.max(
            _excessDebt(
              uint256(int256(_supply0()) - _leveraged(_previewAmount0))
            ),
            0
          )
        );
    }
  }

  function _previewSwapAddons(
    uint256[8] calldata _previewAmounts,
    bool _investing
  )
    internal
    view
    override
    returns (
      address[8] memory from,
      address[8] memory to,
      uint256[8] memory amounts
    )
  {
    if (_investing) {
      from[0] = address(inputs[1]); // eg. FDUSD
      to[0] = address(inputs[0]); // eg. USDC
      amounts[0] = _debtNeed(int256(_previewAmounts[0])); // borrow target
      if (address(inputs[0]) != address(asset)) {
        amounts[0] = amounts[0].subBp(_4626StorageExt().maxSlippageBps);
      }
    } else {
      from[0] = address(inputs[0]); // eg. USDC
      to[0] = address(inputs[1]); // eg. FDUSD
      amounts[0] = oracle()
        .convert(
          address(inputs[1]),
          _repaymentNeed(int256(_previewAmounts[0])),
          address(inputs[0])
        )
        .addBp(_4626StorageExt().maxSlippageBps); // repay debt
    }
  }

  function _stake(
    uint256 _amount,
    uint256 _index,
    bytes[] calldata _params
  ) internal override {
    if (_index > 0) {
      return; // no need to stake input[1] tokens (eg. FDUSD)
    }
    // flashloan to leverage amount[0] converted in input[0] (eg. USDC)
    _flashLoan(_amount, true, _params);
    // cf. executeOperation() with _investing == true for the flashloan callback
  }

  function _leverage(
    uint256,
    uint256 _loan,
    uint256 _due,
    bytes memory _addonParams
  ) internal {
    // deposit the input[0] tokens (eg. USDC) as collateral
    unchecked {
      IVToken(address(lpTokens[0])).mint(
        _loan.mulDiv(params.leverage, params.leverage - 100)
      );
    }

    // convert collateral from input[0] (eg. USDC) to input[1] target debt (eg. FDUSD)
    uint256 _debt = _debtForSupply(_loan, true);

    // borrow the input[1] tokens (eg. FDUSD) against the collateral (1/(1-LTV) == leverage)
    IVToken(address(lpTokens[1])).borrow(_debt);

    // swap the borrowed tokens (eg. FDUSD) to input[0] (eg. USDC)
    swapper.decodeAndSwap({
      _input: address(inputs[1]),
      _output: address(inputs[0]),
      _amount: _debt,
      _params: _addonParams
    });

    // // swap slippage check
    // if (
    //   oracle().convert(
    //     address(inputs[0]),
    //     received,
    //     address(inputs[1])
    //   ) < spent.subBp(_4626StorageExt().maxSlippageBps)
    // ) {
    //   revert Errors.AmountTooLow(received);
    // }

    uint256 dust = inputs[0].balanceOf(address(this)); // received + dust
    // deposit inputs[0] dust back into the pool
    if (address(inputs[0]) != address(asset)) {
      unchecked {
        if (dust > _due) {
          IVToken(address(lpTokens[0])).mint(dust - _due);
        } else {
          // if the swap proceeds are less than the due amount, redeem some supply
          IVToken(address(lpTokens[0])).redeemUnderlying(_due - dust);
        }
      }
    }

    // repay inputs[1] debt with dust
    dust = inputs[1].balanceOf(address(this));
    if (address(inputs[1]) != address(asset) && dust > 0) {
      IVToken(address(lpTokens[1])).repayBorrow(dust);
    }

    // we end up with enough input[0] (swapped from invested assets + input[1]) to pay the flashloan back
  }

  function _afterInvest(
    uint256 _amount,
    bytes[] calldata _params
  ) internal override {
    // no need to repay flashloan
  }

  function _unstake(
    uint256 _amount,
    uint256 _index,
    bytes[] calldata _params
  ) internal override {
    if (_index > 0) {
      return; // no need to unstake input[1] tokens (eg. FDUSD)
    }
    uint256 inputAmount = _stakeToInput(_amount, _index);
    // flashloan to leverage amount[0] converted in input[0] (eg. USDC)
    // cf. executeOperation() with _investing == false for the flashloan callback
    _flashLoan(inputAmount, false, _params);
  }

  function _deleverage(
    uint256 _liquidatedAmount0,
    uint256 _loan,
    uint256 _due,
    bytes memory _addonParams
  ) internal {
    // repay debt
    IVToken(address(lpTokens[1])).repayBorrow(_loan);

    // deleverage
    uint256 toRedeem;
    unchecked {
      toRedeem = _supplyForDebt(_loan, false).addBp(
        _4626StorageExt().maxSlippageBps
      );
      _liquidatedAmount0 = _liquidatedAmount0.addBp(5); // .05% addon to absorb price changes since previewSwapAddons()
      IVToken(address(lpTokens[0])).redeemUnderlying(toRedeem); // could also redeem(_inputToStake)
    }

    // swap enough to pay the flashloan back
    (uint256 received, ) = swapper.decodeAndSwap({
      _input: address(inputs[0]),
      _output: address(inputs[1]),
      _amount: toRedeem, // toSwap + _liquidated is sent, the Swapper will send back the difference
      _params: _addonParams
    });

    unchecked {
      // if asset != input[1], use dust to repay a bit more debt
      if (received > _due && address(asset) != address(inputs[1])) {
        IVToken(address(lpTokens[1])).repayBorrow(received - _due);
      }
      uint256 inputBalance = inputs[0].balanceOf(address(this));
      if (inputBalance < _liquidatedAmount0) {
        IVToken(address(lpTokens[0])).redeemUnderlying(
          _liquidatedAmount0 - inputBalance
        );
      }
    }
    // we end up with just enough input[1] to pay the flashloan back and input[0] to satisfy the liquidate() call
  }

  function _afterLiquidate(uint256, bytes[] calldata) internal override {
    // check if we've got leftovers in input[0] after swapping back to assets
    uint256 inputBalance = inputs[0].balanceOf(address(this));
    if (inputBalance > 0 && address(asset) != address(inputs[0])) {
      // if the deleverage proceeds are more than the due amount, repay some debt
      IVToken(address(lpTokens[0])).mint(inputBalance);
    }
  }

  function _flashLoan(
    uint256 _amount,
    bool _investing,
    bytes[] calldata _params
  ) internal {
    if (_params.length < 2) {
      revert Errors.InvalidData(); // missing swap addon calldata
    }

    IAavePool(params.aavePoolProvider.getPool()).flashLoanSimple(
      address(this),
      _investing ? address(inputs[0]) : address(inputs[1]),
      _investing
        ? _supplyForDebt(_debtNeed(int256(_amount)), true)
        : _repaymentNeed(int256(_amount)),
      abi.encode(_investing, _amount, _params[2]), // investing
      0 // project identifier eg. for fee exemption
    );
  }

  // AAVE FlashLoanReceiverSimple implementation
  // - _stake()->executeOperation(_investing=true)->_leverage()
  // - _unstake()->executeOperation(_investing=false)->_deleverage()
  function executeOperation(
    address _token,
    uint256 _loan,
    uint256 _fee,
    address,
    bytes calldata _params
  ) external returns (bool) {
    address lender = params.aavePoolProvider.getPool();
    if (msg.sender != lender) {
      revert Errors.Unauthorized();
    }

    unchecked {
      uint256 due = _loan + _fee;
      // check if investing or liquidating
      (bool investing, uint256 amount, bytes memory addonParams) = abi.decode(
        _params,
        (bool, uint256, bytes)
      );
      investing
        ? _leverage(amount, _loan, due, addonParams)
        : _deleverage(amount, _loan, due, addonParams);
      IERC20Metadata(_token).forceApprove(lender, due);
    }
    // approve the lending pool to get back loan+fee with the op proceeds+leftover cash balance
    return true;
  }

  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    unchecked {
      return
        (_amount * 1e18) /
        IVToken(address(lpTokens[_index])).exchangeRateStored(); // eg. 1e18*1e18/1e(36-8) = 1e12
    }
  }

  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    unchecked {
      return
        (_amount * IVToken(address(lpTokens[_index])).exchangeRateStored()) /
        1e18; // eg. 1e12*1e(36-8)/1e18 = 1e18
    }
  }

  function _investedInput(
    uint256 _index
  ) internal view override returns (uint256) {
    if (_index > 0) {
      return 0; // no need to unstake input[1] tokens (eg. FDUSD)
    }
    return
      _stakeToInput(
        lpTokens[0].balanceOf(address(this)), // cash in input[1]
        0
      ).subMax0(
          oracle().convert(
            address(inputs[1]),
            IVToken(address(lpTokens[1])).borrowBalanceStored(address(this)), // debt in input[1]
            address(inputs[0])
          )
        );
  }

  function rewardsAvailable()
    public
    view
    override
    returns (uint256[] memory amounts)
  {
    uint256 mainReward = params.unitroller.venusAccrued(address(this));
    return
      _rewardLength == 1
        ? mainReward.toArray()
        : mainReward.toArray(_balance(rewardTokens[1]));
  }

  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    params.unitroller.claimVenus(address(this)); // claim for all markets
    // wrap native rewards if needed
    _wrapNative();
    unchecked {
      for (uint256 i = 0; i < _rewardLength; i++) {
        amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
      }
    }
  }
}
