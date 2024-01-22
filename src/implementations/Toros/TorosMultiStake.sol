// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/IDHedge.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title TorosMultiStake Strategy - Liquidity providing on Toros
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Toros (https://toros.finance/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract TorosMultiStake is StrategyV5Chainlink {
    using AsMaths for uint256;
    using AsArrays for uint256;
    using SafeERC20 for IERC20;

    // Third party contracts
    IDHedgePool[8] internal pools;
    uint8[8] internal poolDecimals;
    IDhedgeEasySwapper dHedgeSwapper;

    constructor() StrategyV5Chainlink() {}

    // Struct containing the strategy init parameters
    struct Params {
        address[] pools;
        address dHedgeSwapper;
    }

    /**
     * @notice Set the strategy specific parameters
     * @param _params Strategy specific parameters
     */
    function setParams(
        Params calldata _params
    ) public onlyAdmin {
        dHedgeSwapper = IDhedgeEasySwapper(_params.dHedgeSwapper);
        for (uint8 i = 0; i < _params.pools.length; i++) {
            pools[i] = IDHedgePool(_params.pools[i]);
            poolDecimals[i] = uint8(pools[i].decimals());
        }
        _setAllowances(MAX_UINT256);
    }

    /**
     * @dev Initializes the strategy with the specified parameters.
     * @param _baseParams StrategyBaseParams struct containing strategy parameters
     * @param _chainlinkParams Chainlink specific parameters
     * @param _torosParams Aave specific parameters
     */
    function init(
        StrategyBaseParams calldata _baseParams,
        ChainlinkParams calldata _chainlinkParams,
        Params calldata _torosParams
    ) external onlyAdmin {
        for (uint8 i = 0; i < _torosParams.pools.length; i++) {
            inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
            inputWeights[i] = _baseParams.inputWeights[i];
            inputDecimals[i] = inputs[i].decimals();
        }
        inputLength = uint8(_torosParams.pools.length);
        setParams(_torosParams);
        StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
    }

    /**
     * @notice Invests the asset asset into the pool
     * @param _amounts Amounts of asset to invest in each input
     * @param _params Swaps calldata
     * @return investedAmount Amount invested
     * @return iouReceived Amount of LP tokens received
     */
    function _invest(
        uint256[8] calldata _amounts, // from previewInvest()
        bytes[] memory _params
    )
        internal
        override
        nonReentrant
        returns (uint256 investedAmount, uint256 iouReceived)
    {
        uint256 toDeposit;
        uint256 spent;

        for (uint8 i = 0; i < inputLength; i++) {
            if (_amounts[i] < 10) continue;

            // We deposit the whole asset balance.
            if (asset != inputs[i] && _amounts[i] > 10) {
                (toDeposit, spent) = swapper.decodeAndSwap({
                    _input: address(asset),
                    _output: address(inputs[i]),
                    _amount: _amounts[i],
                    _params: _params[i]
                });
                investedAmount += spent;
                // pick up any input dust (eg. from previous liquidate()), not just the swap output
                toDeposit = inputs[i].balanceOf(address(this));
            } else {
                investedAmount += _amounts[i];
                toDeposit = _amounts[i];
            }
            uint256 expectedIou = _inputToStake(toDeposit, i).subBp(maxSlippageBps);
            uint256 iouBefore = pools[i].balanceOf(address(this));

            dHedgeSwapper.deposit({
                pool: address(pools[i]),
                depositAsset: address(inputs[i]),
                amount: toDeposit,
                poolDepositAsset: address(inputs[i]),
                expectedLiquidityMinted: expectedIou
            });

            uint256 supplied = pools[i].balanceOf(address(this)) - iouBefore;

            // unified slippage check (swap+add liquidity)
            if (supplied < expectedIou)
                revert AmountTooLow(supplied);

            // NB: better return ious[]
            iouReceived += supplied;
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
        bytes[] memory _params
    ) internal override returns (uint256 assetsRecovered) {
        uint256 toLiquidate;
        uint256 recovered;

        for (uint8 i = 0; i < inputLength; i++) {
            if (_amounts[i] < 10) continue;

            toLiquidate = _inputToStake(_amounts[i], i);

            dHedgeSwapper.withdraw({
                pool: address(pools[i]),
                fundTokenAmount: toLiquidate,
                withdrawalAsset: address(inputs[i]),
                expectedAmountOut: _amounts[i].subBp(maxSlippageBps)
            });

            // swap the unstaked tokens (inputs[0]) for the asset asset if different
            if (inputs[i] != asset && toLiquidate > 10) {
                (recovered, ) = swapper.decodeAndSwap({
                    _input: address(inputs[i]),
                    _output: address(asset),
                    _amount: _amounts[i],
                    _params: _params[i]
                });
            } else {
                recovered = toLiquidate;
            }

            // unified slippage check (unstake+remove liquidity+swap out)
            if (
                recovered <
                _inputToAsset(_amounts[i], i).subBp(maxSlippageBps * 2)
            ) revert AmountTooLow(recovered);

            assetsRecovered += recovered;
        }
    }

    /**
     * @notice Set allowances for third party contracts (except rewardTokens)
     * @param _amount Allowance amount
     */
    function _setAllowances(uint256 _amount) internal override {
        for (uint8 i = 0; i < inputLength; i++) {
            inputs[i].approve(address(dHedgeSwapper), _amount);
        }
    }

    /**
     * @notice Returns the investment in asset asset for the specified input
     * @return total Amount invested
     */
    function invested(uint8 _index) public view override returns (uint256) {
        return _inputToAsset(investedInput(_index), _index);
    }

    /**
     * @notice Returns the investment in asset asset for the specified input
     * @return total Amount invested
     */
    function investedInput(
        uint8 _index
    ) internal view override returns (uint256) {
        return _stakedInput(_index);
    }

    /**
     * @notice Convert LP/staked LP to input
     * @return Input value of the LP amount
     */
    function _stakeToInput(
        uint256 _amount,
        uint8 _index
    ) internal view override returns (uint256) {
        return _usdToInput(_amount.mulDiv(pools[_index].tokenPrice(), 1e12), _index);
    }

    /**
     * @notice Convert input to LP/staked LP
     * @return LP value of the input amount
     */
    function _inputToStake(
        uint256 _amount,
        uint8 _index
    ) internal view override returns (uint256) {
        return _inputToUsd(_amount, _index).mulDiv(1e12 * poolDecimals[_index], pools[_index].tokenPrice()); // eg. 1e6+1e12+1e18-1e18 = 1e18
    }

    /**
     * @notice Returns the invested input converted from the staked LP token
     * @return Input value of the LP/staked balance
     */
    function _stakedInput(
        uint8 _index
    ) internal view override returns (uint256) {
        return _stakeToInput(pools[_index].balanceOf(address(this)), _index);
    }

    /**
     * @notice Returns the available rewards
     * @return amounts Array of rewards available for each reward token
     */
    function rewardsAvailable()
        public
        view
        override
        returns (uint256[] memory amounts)
    {
    }
}
