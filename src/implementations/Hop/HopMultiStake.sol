// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../libs/AsMaths.sol";
import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/IStableRouter.sol";
import "./interfaces/IStakingRewards.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title HopMultiStake - Liquidity providing on Hop (n stable (max 5), eg. USDC+USDT+DAI)
 * @author Astrolab DAO
 * @notice Basic liquidity providing strategy for Hop protocol (https://hop.exchange/)
 * @dev Underlying->input[0]->LP->rewardPools->LP->input[0]->underlying
 */
contract HopMultiStake is StrategyV5Chainlink {

    using AsMaths for uint256;
    using AsArrays for uint256;
    using SafeERC20 for IERC20;

    // Third party contracts
    IERC20Metadata[5] public lpTokens; // LP token of the pool
    IStableRouter[5] public stableRouters; // SaddleSwap
    IStakingRewards[5] public rewardPools; // Reward pool
    uint8[5] public tokenIndexes;

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, EIP712 version
     */
    constructor(string[3] memory _erc20Metadata) StrategyV5Chainlink(_erc20Metadata) {}

    // Struct containing the strategy init parameters
    struct Params {
        address[] lpTokens;
        address[] rewardPools;
        address[] stableRouters;
        uint8[] tokenIndexes;
    }

    /**
     * @dev Initializes the strategy with the specified parameters.
     * @param _baseParams StrategyBaseParams struct containing strategy parameters
     * @param _chainlinkParams Pyth specific parameters
     * @param _hopParams Hop specific parameters
     */
    function init(
        StrategyBaseParams calldata _baseParams,
        ChainlinkParams calldata _chainlinkParams,
        Params calldata _hopParams
    ) external onlyAdmin {

        for (uint8 i = 0; i < _hopParams.lpTokens.length; i++) {
            lpTokens[i] = IERC20Metadata(_hopParams.lpTokens[i]);
            rewardPools[i] = IStakingRewards(_hopParams.rewardPools[i]);
            tokenIndexes[i] = _hopParams.tokenIndexes[i];
            stableRouters[i] = IStableRouter(_hopParams.stableRouters[i]);
            inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
            inputDecimals[i] = inputs[i].decimals();
            rewardTokens[i] = _baseParams.rewardTokens[i];
        }

        underlying = IERC20Metadata(_baseParams.underlying);
        _setAllowances(MAX_UINT256);
        StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
    }

    /**
     * @notice Claim rewards from the reward pool and swap them for underlying
     * @param _params Params array, where _params[0] is minAmountOut
     * @return assetsReceived Amount of assets received
     */
    function _harvest(
        bytes[] memory _params
    ) internal override returns (uint256 assetsReceived) {

        // claim the rewards
        for (uint8 i = 0; i < rewardPools.length; i++) {
            rewardPools[i].getReward();

            uint256 pendingRewards = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
            if (pendingRewards == 0) return 0;

            // swap the rewards back into underlying
            (assetsReceived, ) = swapper.decodeAndSwap(
                rewardTokens[i],
                address(underlying),
                pendingRewards,
                _params[i]
            );
        }
    }

    /**
     * @notice Invests the underlying asset into the pool
     * @param _amount Max amount of underlying to invest
     * @param _params Calldata for swap if input != underlying
     * @return investedAmount Amount invested
     * @return iouReceived Amount of LP tokens received
     */
    function _invest(
        uint256 _amount,
        bytes[] memory _params
    ) internal override returns (uint256 investedAmount, uint256 iouReceived) {

        _amount = AsMaths.min(available(), _amount);

        uint256 weightedAmount;
        uint256 toDeposit;
        uint256 spent;

        for (uint8 i = 0; i < inputs.length; i++) {

            weightedAmount = _amount.bp(inputWeights[i]);
            if (weightedAmount < 10) continue;

            // We deposit the whole asset balance.
            if (underlying != inputs[i]) {
                (toDeposit, spent) = swapper.decodeAndSwap({
                    _input: address(underlying),
                    _output: address(inputs[i]),
                    _amount: weightedAmount,
                    _params: _params[i]
                });
                investedAmount += spent;
            } else {
                investedAmount += _amount;
                toDeposit = _amount;
            }

            // Adding liquidity to the pool with the inputs[0] balance
            uint256 toStake = stableRouters[i].addLiquidity({
                amounts: toDeposit.toArray(),
                minToMint: 1, // slippage is checked afterwards
                deadline: block.timestamp
            });

            // unified slippage check (swap+add liquidity)
            if (toStake < _inputToStake(toDeposit, i).subBp(maxSlippageBps * 2))
                revert AmountTooLow(toStake);

            rewardPools[i].stake(toStake);

            // would make more sense to return an array of ious
            // rather than mixing them like this
            iouReceived += toStake;
        }
    }

    /**
     * @notice Withdraw asset function, can remove all funds in case of emergency
     * @param _amount Amount of asset to withdraw
     * @param _params Calldata for the asset swap if needed
     * @return assetsRecovered Amount of asset withdrawn
     */
    function _liquidate(
        uint256 _amount,
        bytes[] memory _params
    ) internal override returns (uint256 assetsRecovered) {

        _amount = AsMaths.min(_invested(), _amount);

        uint256 weightedAmount;
        uint256 toLiquidate;
        uint256 recovered;

        for (uint8 i = 0; i < inputs.length; i++) {

            weightedAmount = _amount.bp(inputWeights[i]);
            if (weightedAmount < 10) continue;

            toLiquidate = _underlyingToStake(weightedAmount, i);
            rewardPools[i].withdraw(toLiquidate);

            recovered = stableRouters[i].removeLiquidityOneToken({
                tokenAmount: lpTokens[i].balanceOf(address(this)),
                tokenIndex: tokenIndexes[i],
                minAmount: 1, // slippage is checked after swap
                deadline: block.timestamp
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
            if (recovered < weightedAmount.subBp(maxSlippageBps * 2))
                revert AmountTooLow(recovered);

            assetsRecovered += recovered;
        }
    }

    /**
     * @notice Set allowances for third party contracts (except rewardTokens)
     * @param _amount Allowance amount
     */
    function _setAllowances(uint256 _amount) internal override {
        for (uint8 i = 0; i < inputs.length; i++) {
            inputs[i].approve(address(stableRouters[i]), _amount);
            lpTokens[i].approve(address(rewardPools[i]), _amount);
            lpTokens[i].approve(address(stableRouters[i]), _amount);
        }
    }

    /**
     * @notice Returns the investment in underlying asset
     * @return total Amount invested
     */
    function _invested() internal view override returns (uint256 total) {
        for (uint8 i = 0; i < inputs.length; i++) {
            uint256 staked = rewardPools[i].balanceOf(address(this));
            if (staked < 10) continue;
            total += _stakeToUnderlying(staked, i);
        }
    }

    /**
     * @notice Convert LP/staked LP to input
     * @return Input value of the LP amount
     */
    function _stakeToInput(uint256 _amount, uint8 _index) internal view returns (uint256) {
        return _amount.mulDiv(stableRouters[_index].getVirtualPrice(), 1e18); // 1e18 == lpToken[i] decimals
    }

    /**
     * @notice Convert LP/staked LP to input
     * @return Input value of the LP amount
     */
    function _stakeToUnderlying(uint256 _amount, uint8 _index) internal view returns (uint256) {
        return _inputToUnderlying(_stakeToInput(_amount, _index), _index);
    }

    /**
     * @notice Convert input to LP/staked LP
     * @return LP value of the input amount
     */
    function _inputToStake(uint256 _amount, uint8 _index) internal view returns (uint256) {
        return _amount.mulDiv(1e18, stableRouters[_index].getVirtualPrice());
    }

    /**
     * @notice Convert underlying to LP/staked LP
     * @return LP value of the underlying amount
     */
    function _underlyingToStake(uint256 _amount, uint8 _index) internal view returns (uint256) {
        return _inputToStake(_underlyingToInput(_amount, _index), _index);
    }

    /**
     * @notice Returns the invested input converted from the staked LP token
     * @return Input value of the LP/staked balance
     */
    function _stakedInput(uint8 _index) public view returns (uint256) {
        return _stakeToInput(rewardPools[_index].balanceOf(address(this)), _index);
    }

    /**
     * @notice Returns the invested underlying converted from the staked LP token
     * @return Underlying value of the LP/staked balance
     */
    function _stakedUnderlying(uint8 _index) public view returns (uint256) {
        return _stakeToUnderlying(rewardPools[_index].balanceOf(address(this)), _index);
    }

    /**
     * @notice Returns the available HOP rewards
     * @return amounts Array of rewards available for each reward token
     */
    function _rewardsAvailable()
        public
        view
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](rewardTokens.length);
        for (uint8 i = 0; i < rewardTokens.length; i++) {
            amounts[i] = IStakingRewards(rewardPools[i]).earned(address(this));
        }
    }
}
