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
  using SafeERC20 for IERC20Metadata;

  IUnitroller public unitroller;
  IPoolAddressesProvider public aavePoolProvider;
  uint256 public leverage; // 100 == 1:1 leverage
  uint256 public haircut; // 100bps == 1% haircut

  bytes[] pendingCalldata;

  constructor(address _accessController) StrategyV5(_accessController) {}

  struct Params {
    address unitroller;
    address aavePoolProvider;
    uint16 leverage;
    uint16 haircut;
  }

  function _setParams(bytes memory _params) internal override {
    Params memory params = abi.decode(_params, (Params));
    unitroller = IUnitroller(params.unitroller);
    aavePoolProvider = IPoolAddressesProvider(params.aavePoolProvider);
    _setLeverage(uint256(params.leverage), uint256(params.haircut));
    _setLpTokenAllowances(AsMaths.MAX_UINT256);
    if (inputWeights[1] != 0) {
      revert Errors.Unauthorized(); // full weight on the input[1]->input[0] arbitrage (eg. inputWeights[0] = 9000) input[1] is short-farmed
    }
  }

  function _setLeverage(uint256 _leverage, uint256 _haircut) internal {
    if (_haircut > AsMaths.BP_BASIS || (_leverage * 100) <= _haircut) {
      revert Errors.InvalidData();
    }
    // make sure that max leverage is sound with the cToken max collateral factor
    (, uint256 ltv, ) = unitroller.markets(address(inputs[0])); // base 1e18
    uint256 maxLeverage = (100 * 1e18) / (1e18 - ltv); // base 100 eg. 500 == 5:1
    if (maxLeverage <= _leverage) {
      revert Errors.Unauthorized();
    }
    leverage = uint256(_leverage);
    haircut = uint256(_haircut);
  }

  function setLeverage(uint256 _leverage, uint256 _haircut) external onlyAdmin {
    _setLeverage(_leverage, _haircut);
  }

  function _previewInvestSwapAddons(
    uint256 _amount
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
    from[0] = address(inputs[1]); // eg. FDUSD
    to[0] = address(inputs[0]); // eg. USDC
    amounts[0] = (_amount * leverage) / 100;
  }

  function _afterInvest(
    uint256 _amount,
    bytes[] calldata _params
  ) internal override {
    // no need to repay flashloan
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

    uint256 leveragedAmount = (_amount * leverage) / 100;

    // flashloan to leverage amount[0] converted in input[0] (eg. USDC)
    IAavePool(aavePoolProvider.getPool()).flashLoanSimple(
      address(this),
      address(inputs[0]),
      leveragedAmount,
      "",
      0 // project identifier eg. for fee exemption
    );
    // cf. executeOperation() for the flashloan callback
  }

  // AAVE FlashLoanReceiverSimple implementation (executed in _stake())
  function executeOperation(
    address token,
    uint256 leveragedAmount,
    uint256 fee,
    address initiator,
    bytes calldata params
  ) external returns (bool) {
    address lender = aavePoolProvider.getPool();
    if (msg.sender != lender) {
      revert Errors.Unauthorized();
    }

    // deposit the input[0] tokens (eg. USDC) as collateral
    IVToken(address(lpTokens[0])).mint(leveragedAmount);

    // convert collateral from input[0] (eg. USDC) to input[1] (eg. FDUSD)
    leveragedAmount = _priceAwareStorage().oracle.convert(
      address(inputs[0]),
      leveragedAmount,
      address(inputs[1])
    );

    // compute target borrow
    uint256 borrowAmount = leveragedAmount
      .mulDiv(
        unitroller.markets(address(inputs[0])).collateralFactorMantissa, // max borrow
        1e18
      )
      .mulDiv(AsMaths.BP_BASIS - haircut, AsMaths.BP_BASIS); // haircut
    // borrow the input[1] tokens (eg. FDUSD) against the collateral (1/(1-LTV) == leverage)

    IVToken(address(lpTokens[1])).borrow(borrowAmount);

    // swap the borrowed tokens (eg. FDUSD) to input[0] (eg. USDC)
    (uint256 received, uint256 spent) = swapper.decodeAndSwap({
      _input: address(asset),
      _output: address(inputs[1]),
      _amount: borrowAmount,
      _params: pendingCalldata
    });

    // approve the lending pool to get back leveragedAmount+fee (eg. USDC) with the swap proceeds+leftover cash balance
    inputs[0].safeApprove(lender, leveragedAmount + fee);
  }

  function _beforeInvest(
    uint256[8] calldata _amounts,
    bytes[] calldata _params
  ) internal override {
    bytes memory cp = _params[2];
    if (cp.length > 0) {
      delete pendingCalldata;
      pendingCalldata.push(cp);
    } else {
      revert Errors.InvalidData(); // missing calldata
    }
  }

  function _unstake(uint256 _index, uint256 _amount) internal override {
    IVToken(address(lpTokens[_index])).redeem(_amount);
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

  function rewardsAvailable()
    public
    view
    override
    returns (uint256[] memory amounts)
  {
    uint256 mainReward = unitroller.venusAccrued(address(this));
    return
      _rewardLength == 1
        ? mainReward.toArray()
        : mainReward.toArray(_balance(rewardTokens[1]));
  }

  function claimRewards() public override returns (uint256[] memory amounts) {
    amounts = new uint256[](_rewardLength);
    unitroller.claimVenus(address(this)); // claim for all markets
    // wrap native rewards if needed
    _wrapNative();
    for (uint256 i = 0; i < _rewardLength; i++) {
      amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
    }
  }
}
