// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../libs/AsMaths.sol";
import "../../libs/PythUtils.sol";
import "../../abstract/StrategyV5.sol";
import "../../interfaces/IPyth.sol";
import "./interfaces/IStableRouter.sol";
import "./interfaces/IStakingRewards.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title HopStrategy - Liquidity providing on Hop
 * @author Astrolab DAO
 * @notice Basic liquidity providing strategy for Hop protocol (https://hop.exchange/)
 * @dev Underlying->input[0]->LP->rewardPool->LP->input[0]->underlying
 */
contract HopStrategy is StrategyV5 {

    using AsMaths for uint256;
    using SafeERC20 for IERC20;
    using PythUtils for PythStructs.Price;

    struct Params {
        address pyth;
        bytes32 underlyingPythId;
        bytes32 inputPythId;
        address lpToken;
        address rewardPool;
        address stableRouter;
        uint8 tokenIndex;
    }

    // Third party contracts
    IPyth internal pyth; // Pyth oracle
    bytes32 internal underlyingPythId; // Pyth id of the underlying asset
    bytes32 internal inputPythId; // Pyth id of the input asset
    uint8 internal underlyingDecimals; // Decimals of the underlying asset
    uint8 internal inputDecimals; // Decimals of the input asset

    IERC20 public lpToken; // LP token of the pool
    IStableRouter public stableRouter; // SaddleSwap
    IStakingRewards public rewardPool; // Reward pool
    uint8 public tokenIndex;

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, version
     */
    constructor(
        string[3] memory _erc20Metadata // name, symbol of the share and EIP712 version
    ) StrategyV5(_erc20Metadata) {}

    /**
     * @dev Initializes the strategy with the specified parameters.
     * @param _params StrategyBaseParams struct containing strategy parameters
     * @param _hopParams Hop specific parameters
     */
    function init(
        StrategyBaseParams calldata _params,
        Params calldata _hopParams
    ) external onlyAdmin {

        pyth = IPyth(_hopParams.pyth);
        underlyingPythId = _hopParams.underlyingPythId;
        inputPythId = _hopParams.inputPythId;
        underlyingDecimals = IERC20Metadata(underlying).decimals();
        inputDecimals = IERC20Metadata(_params.inputs[0]).decimals();

        lpToken = IERC20(_hopParams.lpToken);
        rewardPool = IStakingRewards(_hopParams.rewardPool);
        tokenIndex = _hopParams.tokenIndex;
        stableRouter = IStableRouter(_hopParams.stableRouter);
        _setAllowances(MAX_UINT256);
        StrategyV5.init(_params);
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
            (assetsToLp, investedAmount) = swapper.decodeAndSwap({
                _input: address(underlying),
                _output: address(inputs[0]),
                _amount: investedAmount,
                _params: _params[0]
            });
        }

        if (assetsToLp < 1) revert AmountTooLow(assetsToLp);

        // Adding liquidity to the pool with the asset balance.
        iouReceived = _addLiquidity({
            _amount: assetsToLp,
            _minLpAmount: _minIouReceived
        });
        // Stake the lp balance in the reward pool.
        rewardPool.stake(iouReceived);
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
        uint256 LPToUnstake = (_amount * stakedLPBalance()) / _invested();
        // Unstake the lp token
        rewardPool.withdraw(LPToUnstake);
        // Calculate the minimum amount of asset to receive
        // Withdraw asset from the pool
        assetsRecovered = stableRouter.removeLiquidityOneToken({
            tokenAmount: lpToken.balanceOf(address(this)),
            // tokenIndex: 0,
            tokenIndex: tokenIndex,
            minAmount: 1, // checked after receiving
            deadline: block.timestamp
        });

        // swap the unstaked token for the underlying asset if different
        if (inputs[0] != underlying) {
            (assetsRecovered, ) = swapper.decodeAndSwap(
                address(inputs[0]),
                address(underlying),
                assetsRecovered,
                _params[0]
            );
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
        if (stakedLPBalance() == 0) {
            return 0;
        } else {
            return
                // calculates how much asset (inputs[0]) is to be withdrawn with the lp token balance
                // converted to the underlying asset, not the actual ERC4626 underlying invested balance
                exchangeRateBp().mulDiv(stableRouter.getVirtualPrice(), 1e6) // eg. usdc: 1e6 * 1e6 (BP_BASIS)
                    .mulDiv(stakedLPBalance(), 1e36); // 1e18**2 (IOU decimals ** virtualPrice decimals)
        }
    }

    /**
     * @notice Computes the underlying/input exchange rate from Pyth oracle price feeds in bps
     * @dev Used by invested() to compute input->underlying (base/quote, eg. USDC/BTC == 1/BTCUSD == )
     * @return The amount available for investment
     */
    function exchangeRateBp() public view returns (uint256) {
        if (underlyingPythId == inputPythId)
            return 10 ** underlyingDecimals * 1e6; // 1e6 (BP_BASIS)
        return PythUtils.exchangeRateBp(
            [pyth.getPrice(underlyingPythId), pyth.getPrice(inputPythId)],
            [underlyingDecimals, inputDecimals]
        );
    }

    /**
     * @notice Returns the investment in lp token.
     * @return The staked LP balance
     */
    function stakedLPBalance() public view returns (uint256) {
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
