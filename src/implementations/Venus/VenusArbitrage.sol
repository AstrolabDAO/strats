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
    uint256 haircut; // 100bps == 1% haircut
  }

  Params public params;

  bytes private _pendingInvestCalldata;
  bytes private _pendingLiquidateCalldata;

  constructor(address _accessController) StrategyV5(_accessController) {}

  function _setParams(bytes memory _params) internal override {
    params = abi.decode(_params, (Params));
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
    if (inputWeights[1] != 0) {
      revert Errors.Unauthorized(); // full weight on the input[1]->input[0] arbitrage (eg. inputWeights[0] = 9000) input[1] is short-farmed
    }
    params.unitroller.enterMarkets(address(lpTokens[0]).toArray(address(lpTokens[1])));
  }

  function _setLeverage(uint256 _l, uint256 _haircut) internal {
    if (_haircut > AsMaths.BP_BASIS || _l * 100 <= _haircut) {
      revert Errors.InvalidData();
    }
    // make sure that max leverage is sound with the cToken max collateral factor
    (, uint256 ltv, ) = params.unitroller.markets(address(lpTokens[0])); // base 1e18
    uint256 maxLeverage = (100 * 1e18) / (1e18 - ltv); // base 100 eg. 500 == 5:1
    if (maxLeverage <= _l) {
      revert Errors.Unauthorized();
    }
    params.leverage = _l;
    params.haircut = _haircut;
  }

  function setLeverage(uint256 _l, uint256 _haircut) external onlyAdmin {
    _setLeverage(_l, _haircut);
  }

  function _previewInvestSwapAddons(
    uint256[8] calldata _previewAmounts
  )
    internal
    override
    returns (
      address[8] memory from,
      address[8] memory to,
      uint256[8] memory amounts
    )
  {
    IPriceProvider oracle = _priceAwareStorage().oracle;
    uint256 flashLoanAmount = oracle
      .convert(address(asset), _previewAmounts[0], address(inputs[0]))
      .mulDiv(params.leverage, 100);

    from[0] = address(inputs[1]); // eg. FDUSD
    to[0] = address(inputs[0]); // eg. USDC
    amounts[0] = oracle.convert(
      address(inputs[1]),
      flashLoanAmount.mulDiv(params.leverage - 100, params.leverage).subBp(params.haircut), // borrow cap
      address(inputs[0])
    );
  }

  function _beforeInvest(
    uint256[8] calldata,
    bytes[] calldata _params
  ) internal override {
    if (_params.length > 1) {
      _pendingInvestCalldata = _params[2];
    } else {
      revert Errors.InvalidData(); // missing calldata
    }
  }

  function _stake(uint256 _index, uint256 _amount) internal override {
    if (_index > 0) {
      return; // no need to stake input[1] tokens (eg. FDUSD)
    }
    // context
    // - _amounts[0] == assets to invest in input[0] (eg. USDC)
    // - _amounts[1] == 0 (inputWeight[1] == 0 given that all weight is on [0])
    // - _amounts[2] == leveraged arbitrage swap amount in input[1] tokens (eg. FDUSD)
    // - _params[0] == swap calldata for asset->input[0] (eg. USDC)
    // - _params[1] == 0x00 empty swap calldata for asset->input[1]
    // - _params[2] == arbitrage swap calldata addon for input[1]->input[0] (eg. FDUSD->USDC)

    uint256 leveragedAmount = (_amount * params.leverage) / 100;

    // flashloan to leverage amount[0] converted in input[0] (eg. USDC)
    IAavePool(params.aavePoolProvider.getPool()).flashLoanSimple(
      address(this),
      address(inputs[0]), // eg. USDC to be deposited
      leveragedAmount,
      abi.encode(true), // investing
      0 // project identifier eg. for fee exemption
    );
    // cf. executeOperation() with _investing == true for the flashloan callback
  }

  function _leverage(uint256 _loan, uint256 _due) internal {
    IPriceProvider oracle = _priceAwareStorage().oracle;
    // deposit the input[0] tokens (eg. USDC) as collateral
    IVToken(address(lpTokens[0])).mint(_loan);

    // convert collateral from input[0] (eg. USDC) to input[1] target debt (eg. FDUSD)
    uint256 borrowAmount = _debtForSupply(_loan);

    // borrow the input[1] tokens (eg. FDUSD) against the collateral (1/(1-LTV) == leverage)
    IVToken(address(lpTokens[1])).borrow(borrowAmount);

    // swap the borrowed tokens (eg. FDUSD) to input[0] (eg. USDC)
    (uint256 received, uint256 spent) = swapper.decodeAndSwap({
      _input: address(inputs[1]),
      _output: address(inputs[0]),
      _amount: borrowAmount,
      _params: _pendingInvestCalldata
    });

    // swap slippage check
    if (
      oracle.convert(address(inputs[0]), received, address(inputs[1])) <
      spent.subBp(_4626StorageExt().maxSlippageBps)
    ) {
      revert Errors.AmountTooLow(received);
    }

    // if input[0] != asset, deposit the dust back into the pool
    if (received > _due && address(inputs[0]) != address(asset)) {
      IVToken(address(lpTokens[0])).mint(received - _due);
    }
    // we end up with just enough input[0] (swapped from invested assets + input[1]) to pay the flashloan back
  }

  function _deleverage(uint256 _loan, uint256 _due) internal {
    // repay debt
    IVToken(address(lpTokens[1])).repayBorrow(_loan);

    // deleverage
    IVToken(address(lpTokens[0])).redeem(_supplyForDebt(_loan));

    // swap enough to pay the flashloan back
    (uint256 received, ) = swapper.decodeAndSwap({
      _input: address(inputs[0]),
      _output: address(inputs[1]),
      _amount: _loan,
      _params: _pendingLiquidateCalldata
    });

    if (received < _due) {
      revert Errors.AmountTooLow(received);
    }

    // if asset != input[1], use dust to repay a bit more debt
    if ((received - _due) > 0 && address(asset) != address(inputs[1])) {
      IVToken(address(lpTokens[1])).repayBorrow(received - _due);
    }
    // we end up with just enough input[1] to pay the flashloan back and input[0] to satisfy the liquidate() call
  }

  // AAVE FlashLoanReceiverSimple implementation (executed in _stake())
  function executeOperation(
    address _token,
    uint256 _loan,
    uint256 _fee,
    address,
    bytes calldata _investing
  ) external returns (bool) {
    address lender = params.aavePoolProvider.getPool();
    if (msg.sender != lender) {
      revert Errors.Unauthorized();
    }

    uint256 due = _loan + _fee;

    // check if investing or liquidating
    abi.decode(_investing, (bool))
      ? _leverage(_loan, due)
      : _deleverage(_loan, due);

    // approve the lending pool to get back loan+fee with the op proceeds+leftover cash balance
    IERC20Metadata(_token).forceApprove(lender, due);
    return true;
  }

  function _afterInvest(
    uint256 _amount,
    bytes[] calldata _params
  ) internal override {
    // no need to repay flashloan
  }

  function _toRepay(uint256 _liquidatedAmount) internal view returns (uint256) {
    uint256 debtEquivalent = _liquidatedAmount
      .mulDiv(params.leverage - 100, 100)
      .subBp(params.haircut); // in assets

    return
      _priceAwareStorage().oracle.convert(
        address(asset),
        debtEquivalent,
        address(inputs[1])
      ); // in input[1] (eg. FDUSD)
  }

  function _debtForSupply(uint256 _cash) internal view returns (uint256) {
    return
      _priceAwareStorage()
        .oracle
        .convert(address(inputs[0]), _cash, address(inputs[1]))
        .mulDiv(params.leverage - 100, params.leverage)
        .subBp(params.haircut);
  }

  function _supplyForDebt(uint256 _debt) internal view returns (uint256) {
    return
      _priceAwareStorage()
        .oracle
        .convert(
          address(inputs[1]),
          _debt.revAddBp(params.haircut),
          address(inputs[0])
        )
        .mulDiv(params.leverage, params.leverage - 100);
  }

  function _toFlashBorrow(
    uint256 _repaidAmount
  ) internal view returns (uint256) {
    return
      _priceAwareStorage()
        .oracle
        .convert(address(inputs[1]), _repaidAmount, address(inputs[0]))
        .addBp(_4626StorageExt().maxSlippageBps); // in input[0] (eg. USDC)
  }

  function _previewLiquidateSwapAddons(
    uint256[8] calldata _previewAmounts
  )
    internal
    override
    returns (
      address[8] memory from,
      address[8] memory to,
      uint256[8] memory amounts
    )
  {
    from[0] = address(inputs[0]); // eg. USDC
    to[0] = address(inputs[1]); // eg. FDUSD
    amounts[0] = _toRepay(_previewAmounts[0]).addBp(
      _4626StorageExt().maxSlippageBps
    ); // add slippage to make sure we can pay fees + slippage
  }

  function _beforeLiquidate(
    uint256[8] calldata,
    bytes[] calldata _params
  ) internal override {
    if (_params.length > 1) {
      _pendingLiquidateCalldata = _params[2];
    } else {
      revert Errors.InvalidData(); // missing calldata
    }
  }

  function _unstake(uint256 _index, uint256 _amount) internal override {
    if (_index > 0) {
      return; // no need to unstake input[1] tokens (eg. FDUSD)
    }

    // flashloan to leverage amount[0] converted in input[0] (eg. USDC)
    IAavePool(params.aavePoolProvider.getPool()).flashLoanSimple(
      address(this),
      address(inputs[1]), // eg. FDUSD to be repaid
      _toRepay(_amount),
      abi.encode(false), // liquidating
      0 // project identifier eg. for fee exemption
    );
    // cf. executeOperation() with _investing == false for the flashloan callback
  }

  function _stakeToInput(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return
      _amount.mulDiv(
        IVToken(address(lpTokens[_index])).exchangeRateStored(),
        1e18
      ); // eg. 1e12*1e(36-8)/1e18 = 1e18
  }

  function _inputToStake(
    uint256 _amount,
    uint256 _index
  ) internal view override returns (uint256) {
    return
      _amount.mulDiv(
        1e18,
        IVToken(address(lpTokens[_index])).exchangeRateStored()
      ); // eg. 1e18*1e18/1e(36-8) = 1e12
  }

  function _investedInput(
    uint256 _index
  ) internal view override returns (uint256) {
    if (_index > 0) {
      return 0; // no need to unstake input[1] tokens (eg. FDUSD)
    }
    return
      _stakeToInput(
        IERC20Metadata(lpTokens[0]).balanceOf(address(this)), // cash in input[1]
        _index
      ).subMax0(
          _priceAwareStorage().oracle.convert(
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
    for (uint256 i = 0; i < _rewardLength;) {
      unchecked {
        amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
        i++;
      }
    }
  }
}
