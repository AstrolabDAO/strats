// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../libs/AsMaths.sol";
import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IOracle.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AaveStrategy - Liquidity providing on Aave
 * @author Astrolab DAO
 * @notice Basic liquidity providing strategy for Aave V3 (https://aave.com/)
 * @dev Underlying->inputs->LPs->inputs->underlying
 */
contract HopMultiStake is StrategyV5Chainlink {
    using AsMaths for uint256;
    using AsArrays for uint256;
    using SafeERC20 for IERC20;

    // Third party contracts
    IERC20Metadata[8] internal aTokens; // LP token of the pool
    IPoolAddressesProvider internal poolProvider;

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, EIP712 version
     */
    constructor(
        string[3] memory _erc20Metadata
    ) StrategyV5Chainlink(_erc20Metadata) {}

    // Struct containing the strategy init parameters
    struct Params {
        address[8] aTokens;
        address poolProvider;
    }

    /**
     * @notice Set the strategy specific parameters
     * @param _params Strategy specific parameters
     */
    function setParams(
        Params calldata _params
    ) public onlyAdmin {
        poolProvider = IPoolAddressesProvider(_params.poolProvider);
        for (uint8 i = 0; i < _params.aTokens.length; i++)
            aTokens[i] = IERC20Metadata(_params.aTokens[i]);
        _setAllowances(MAX_UINT256);
    }

    /**
     * @dev Initializes the strategy with the specified parameters.
     * @param _baseParams StrategyBaseParams struct containing strategy parameters
     * @param _chainlinkParams Pyth specific parameters
     * @param _aaveParams Hop specific parameters
     */
    function init(
        StrategyBaseParams calldata _baseParams,
        ChainlinkParams calldata _chainlinkParams,
        Params calldata _aaveParams
    ) external onlyAdmin {
        for (uint8 i = 0; i < _aaveParams.aTokens.length; i++) {
            inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
            inputWeights[i] = _baseParams.inputWeights[i];
            inputDecimals[i] = inputs[i].decimals();
        }
        inputLength = uint8(_aaveParams.aTokens.length);
        underlying = IERC20Metadata(_baseParams.underlying);
        setParams(_aaveParams);
        StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
    }

    /**
     * @notice Claim rewards from the reward pool and swap them for underlying
     * @param _params Swaps calldata
     * @return assetsReceived Amount of assets received
     */
    function _harvest(
        bytes[] memory _params
    ) internal override nonReentrant returns (uint256 assetsReceived) {
    }

    /**
     * @notice Invests the underlying asset into the pool
     * @param _amounts Amounts of underlying to invest in each input
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
        IPool pool = IPool(poolProvider.getPool());

        for (uint8 i = 0; i < inputLength; i++) {
            if (_amounts[i] < 10) continue;

            // We deposit the whole asset balance.
            if (underlying != inputs[i] && _amounts[i] > 10) {
                (toDeposit, spent) = swapper.decodeAndSwap({
                    _input: address(underlying),
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

            uint256 iouBefore = aTokens[i].balanceOf(address(this));
            pool.supply({
                asset: address(inputs[0]),
                amount: toDeposit,
                onBehalfOf: address(this),
                referralCode: 0
            });
            uint256 supplied = aTokens[i].balanceOf(address(this)) - iouBefore;

            // unified slippage check (swap+add liquidity)
            if (supplied < _inputToStake(toDeposit, i).subBp(maxSlippageBps * 2))
                revert AmountTooLow(supplied);

            // TODO: return ious[]
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

        IPool pool = IPool(poolProvider.getPool());
        for (uint8 i = 0; i < inputLength; i++) {
            if (_amounts[i] < 10) continue;

            toLiquidate = _inputToStake(_amounts[i], i);

            pool.withdraw({
                asset: address(inputs[i]),
                amount: toLiquidate,
                to: address(this)
            });

            // swap the unstaked tokens (inputs[0]) for the underlying asset if different
            if (inputs[i] != underlying) {
                (recovered, ) = swapper.decodeAndSwap({
                    _input: address(inputs[i]),
                    _output: address(underlying),
                    _amount: recovered,
                    _params: _params[i]
                });
            }

            // unified slippage check (unstake+remove liquidity+swap out)
            if (
                recovered <
                _inputToUnderlying(_amounts[i], i).subBp(maxSlippageBps * 2)
            ) revert AmountTooLow(recovered);

            assetsRecovered += recovered;
        }
    }

    /**
     * @notice Set allowances for third party contracts (except rewardTokens)
     * @param _amount Allowance amount
     */
    function _setAllowances(uint256 _amount) internal override {
        IPool pool = IPool(poolProvider.getPool());
        for (uint8 i = 0; i < inputLength; i++) {
            inputs[i].approve(address(pool), _amount);
            aTokens[i].approve(address(pool), _amount);
        }
    }

    /**
     * @notice Returns the investment in underlying asset for the specified input
     * @return total Amount invested
     */
    function invested(uint8 _index) public view override returns (uint256) {
        return _inputToUnderlying(investedInput(_index), _index);
    }

    /**
     * @notice Returns the investment in underlying asset for the specified input
     * @return total Amount invested
     */
    function investedInput(
        uint8 _index
    ) public view override returns (uint256) {
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
        return _amount; // 1:1 (rebasing, oracle value based)
    }

    /**
     * @notice Convert input to LP/staked LP
     * @return LP value of the input amount
     */
    function _inputToStake(
        uint256 _amount,
        uint8 _index
    ) internal view override returns (uint256) {
        return _amount; // 1:1 (rebasing, oracle value based)
    }

    /**
     * @notice Returns the invested input converted from the staked LP token
     * @return Input value of the LP/staked balance
     */
    function _stakedInput(
        uint8 _index
    ) internal view override returns (uint256) {
        return aTokens[_index].balanceOf(address(this));
    }

    /**
     * @notice Returns the available HOP rewards
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
