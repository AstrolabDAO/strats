// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../libs/AsMaths.sol";
import "../../abstract/StrategyV5Pyth.sol";
import "./interfaces/IPool.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AaveStrategy - Liquidity providing on Aave
 * @author Astrolab DAO
 * @notice Basic liquidity providing strategy for Aave V3 (https://aave.com/)
 * @dev Underlying->input[0]->LP->input[0]->underlying
 */
contract AaveV3Strategy is StrategyV5Pyth {
    using AsMaths for uint256;
    using SafeERC20 for IERC20;
    using PythUtils for PythStructs.Price;
    using PythUtils for uint256;

    // Third party contracts
    IERC20Metadata public iouToken;
    IPool public pool;

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, EIP712 version
     */
    constructor(string[3] memory _erc20Metadata) As4626Abstract(_erc20Metadata) {}

    // Struct containing the strategy init parameters
    struct Params {
        address iouToken;
        address pool;
    }

    /**
     * @dev Initializes the strategy with the specified parameters.
     * @param _baseParams StrategyBaseParams struct containing strategy parameters
     * @param _pythParams Pyth specific parameters
     * @param _aaveParams Aave specific parameters
     */
    function init(
        StrategyBaseParams calldata _baseParams,
        PythParams calldata _pythParams,
        Params calldata _aaveParams
    ) external onlyAdmin {
        iouToken = IERC20Metadata(_aaveParams.iouToken);
        pool = IPool(_aaveParams.pool);
        underlying = IERC20Metadata(_baseParams.underlying);
        inputs[0] = IERC20Metadata(_baseParams.inputs[0]);
        _setAllowances(MAX_UINT256);
        StrategyV5Pyth._init(_baseParams, _pythParams);
    }

    /**
     * @notice Invests the underlying asset into the pool
     * @param _amount Max amount of underlying to invest
     * @param _minIouReceived Min amount of LP tokens to receive
     * @param _params Calldata for swap if input != underlying
     * @return investedAmount Amount invested
     * @return iouReceived Amount of LP tokens received
     */
    function _invest(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params
    ) internal override returns (uint256 investedAmount, uint256 iouReceived) {
        uint256 assetsToLp = available();
        investedAmount = AsMaths.min(assetsToLp, _amount);

        // The amount we add is capped by _amount
        if (underlying != inputs[0]) {
            // We reuse assetsToLp to store the amount of input tokens to add
            (assetsToLp, investedAmount) = swapper.decodeAndSwap({
                _input: address(underlying),
                _output: address(inputs[0]),
                _amount: investedAmount,
                _params: _params[0]
            });
        }

        if (assetsToLp < 1) revert AmountTooLow(assetsToLp);

        // Adding liquidity to the pool with the inputs[0] balance
        uint256 iouBefore = iouToken.balanceOf(address(this));
        pool.supply({
            asset: address(inputs[0]),
            amount: assetsToLp,
            onBehalfOf: address(this),
            referralCode: 0
        });
        iouReceived = iouToken.balanceOf(address(this)) - iouBefore;

        if (iouReceived < _minIouReceived) revert AmountTooLow(iouReceived);
    }

    /**
     * @notice Withdraw asset function, can remove all funds in case of emergency
     * @param _amount The amount of asset to withdraw
     * @param _params Calldata for the asset swap if needed
     * @return assetsRecovered Amount of asset withdrawn
     */
    function _liquidate(
        uint256 _amount,
        bytes[] memory _params
    ) internal override returns (uint256 assetsRecovered) {
        // Withdraw asset from the pool
        assetsRecovered = pool.withdraw({
            asset: address(inputs[0]),
            amount: _amount,
            to: address(this)
        });

        // swap the unstaked token for the underlying asset if different
        if (inputs[0] != underlying) {
            (assetsRecovered, ) = swapper.decodeAndSwap({
                _input: address(inputs[0]),
                _output: address(underlying),
                _amount: assetsRecovered,
                _params: _params[0]
            });
        }
    }

    /**
     * @notice Set allowances for third party contracts (except rewardTokens)
     * @param _amount The allowance amount
     */
    function _setAllowances(uint256 _amount) internal override {
        inputs[0].approve(address(pool), _amount);
    }

    /**
     * @notice Returns the investment in asset.
     * @dev When borrow/lending integrated need to sub Debt to Collateral:
     * pool.getUserAccountData(address(this)).totalCollateralBase;
     * - pool.getUserAccountData(address(this)).totalDebtBase
     * @return The amount invested
     */
    function _invested() internal view override returns (uint256) {
        // calculates how much asset (inputs[0]) is to be withdrawn with the lp token balance
        // not the actual ERC4626 underlying invested balance
        return
            underlyingExchangeRate(0).mulDiv(
                iouToken.balanceOf(address(this)),
                weiPerShare
            );
    }

    /**
     * @notice Returns the investment in lp token.
     * @return The staked LP balance
     */
    function stakedLpBalance() public view returns (uint256) {
        return iouToken.balanceOf(address(this));
    }
}
