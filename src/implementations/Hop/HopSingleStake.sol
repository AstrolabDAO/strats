// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../libs/AsMaths.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/IStableRouter.sol";
import "./interfaces/IStakingRewards.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title HopSingleStake - Liquidity providing on Hop (single pool)
 * @author Astrolab DAO
 * @notice Basic liquidity providing strategy for Hop protocol (https://hop.exchange/)
 * @dev Underlying->input[0]->LP->rewardPool->LP->input[0]->underlying
 */
contract HopSingleStake is StrategyV5Chainlink {

    using AsMaths for uint256;
    using SafeERC20 for IERC20;

    // Third party contracts
    IERC20Metadata public lpToken; // LP token of the pool
    IStableRouter public stableRouter; // SaddleSwap
    IStakingRewards public rewardPool; // Reward pool
    uint8 public tokenIndex;

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, EIP712 version
     */
    constructor(string[3] memory _erc20Metadata) StrategyV5Chainlink(_erc20Metadata) {}

    // Struct containing the strategy init parameters
    struct Params {
        address lpToken;
        address rewardPool;
        address stableRouter;
        uint8 tokenIndex;
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

        lpToken = IERC20Metadata(_hopParams.lpToken);
        rewardPool = IStakingRewards(_hopParams.rewardPool);
        tokenIndex = _hopParams.tokenIndex;
        stableRouter = IStableRouter(_hopParams.stableRouter);

        // inputs[0] needs to be defined before StrategyV5._init() as required by _setAllowances()
        underlying = IERC20Metadata(_baseParams.underlying);
        inputs[0] = IERC20Metadata(_baseParams.inputs[0]);
        rewardTokens[0] = _baseParams.rewardTokens[0];
        _setAllowances(MAX_UINT256);
        StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
    }

    /**
     * @notice Adds liquidity to AMM and gets more LP tokens.
     * @param _amount Amount of underlying to invest
     * @param _minLpAmount Minimum amount of LP tokens to receive
     * @return amount of LP token user minted and received
     */
    function _addLiquidity(
        uint256 _amount,
        uint256 _minLpAmount
    ) internal returns (uint256) {
        // Formats the inputs for the addLiquidity function.
        uint256[] memory inputsAmount = new uint256[](2);
        inputsAmount[0] = _amount;
        // We deposit the whole asset balance.
        return
            stableRouter.addLiquidity({
                amounts: inputsAmount,
                minToMint: _minLpAmount,
                deadline: block.timestamp
            });
    }

    /**
     * @notice Claim rewards from the reward pool and swap them for underlying
     * @param _params Params array, where _params[0] is minAmountOut
     * @return assetsReceived Amount of assets received
     */
    function _harvest(
        bytes[] memory _params
    ) internal override returns (uint256 assetsReceived) {
        // Claiming the rewards
        rewardPool.getReward();

        uint256 pendingRewards = IERC20(rewardTokens[0]).balanceOf(
            address(this)
        );
        if (pendingRewards == 0) return 0;
        // Swapping the rewards
        (assetsReceived, ) = swapper.decodeAndSwap(
            rewardTokens[0],
            address(underlying),
            pendingRewards,
            _params[0]
        );
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
        iouReceived = _addLiquidity({
            _amount: assetsToLp,
            _minLpAmount: _minIouReceived
        });

        rewardPool.stake(iouReceived);
        if (iouReceived < _minIouReceived)
            revert AmountTooLow(iouReceived);
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

        // Calculate the amount of lp token to unstake
        uint256 lpToUnstake = (_amount * stakedLpBalance()) / _invested();
        // Unstake the lp token
        rewardPool.withdraw(lpToUnstake);

        assetsRecovered = stableRouter.removeLiquidityOneToken({
            tokenAmount: lpToken.balanceOf(address(this)),
            // tokenIndex: 0,
            tokenIndex: tokenIndex,
            minAmount: 1, // checked after receiving
            deadline: block.timestamp
        });

        // swap the unstaked tokens (inputs[0]) for the underlying asset if different
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
        inputs[0].approve(address(stableRouter), _amount);
        lpToken.approve(address(rewardPool), _amount);
        lpToken.approve(address(stableRouter), _amount);
    }

    /**
     * @notice Returns the investment in asset.
     * @return The amount invested
     */
    function _invested() internal view override returns (uint256) {
        // Should return 0 if no lp token is staked
        if (stakedLpBalance() == 0) {
            return 0;
        } else {
            return
                // calculates how much asset (inputs[0]) is to be withdrawn with the lp token balance
                // converted to the underlying asset, not the actual ERC4626 underlying invested balance
                underlyingExchangeRate(0).mulDiv(stableRouter.getVirtualPrice() * stakedLpBalance(), 1e36); // 1e18**2 (IOU decimals ** virtualPrice decimals)
        }
    }

    /**
     * @notice Returns the investment in lp token.
     * @return The staked LP balance
     */
    function stakedLpBalance() public view returns (uint256) {
        return IStakingRewards(rewardPool).balanceOf(address(this));
    }

    /**
     * @notice Returns the available HOP rewards
     * @return rewardsAmounts Array of rewards available for each reward token
     */
    function _rewardsAvailable()
        public
        view
        override
        returns (uint256[] memory rewardsAmounts)
    {
        rewardsAmounts = new uint256[](1);
        rewardsAmounts[0] = IStakingRewards(rewardPool).earned(address(this));
        return rewardsAmounts;
    }
}
