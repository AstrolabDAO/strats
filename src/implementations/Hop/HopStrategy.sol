// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../libs/AsMaths.sol";

import "./interfaces/IStableRouter.sol";
import "./interfaces/IStakingRewards.sol";
import "../../abstract/StrategyV5.sol";
import "hardhat/console.sol";

/// @title Hop Strategy (v5)
/// @notice This contract is a strategy for Hop
/// @dev Generic implementation
contract HopStrategy is StrategyV5 {
    using SafeERC20 for IERC20;

    // Tokens used
    IERC20 public lpToken;
    // Third party contracts
    IStableRouter public stableRouter; // SaddleSwap
    IStakingRewards public rewardPool;
    // params
    uint8 tokenIndex;

    constructor(
        string[] memory _erc20Metadata // name, symbol of the share and EIP712 version
    ) StrategyV5(_erc20Metadata) {}

    function initialize(
        Fees memory _fees, // perfFee, mgmtFee, entryFee, exitFee in bps 100% = 10000
        address _underlying, // The asset we are using
        address[] memory _coreAddresses,
        address _lpToken,
        address _rewardPool,
        address _stableRouter,
        uint8 _tokenIndex
    ) external onlyAdmin {
        StrategyV5._initialize(_fees, _underlying, _coreAddresses);
        lpToken = IERC20(_lpToken);
        rewardPool = IStakingRewards(_rewardPool);
        tokenIndex = _tokenIndex;
        stableRouter = IStableRouter(_stableRouter);
        _setAllowances(MAX_UINT256);
    }

    // Interactions

    /// @notice Adds liquidity to AMM and gets more LP tokens.
    /// @param _amount Amount of underlying to invest
    /// @return amount of LP token user minted and received
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

    /// @notice Claim rewards from the reward pool and swap them for underlying
    /// @param _params params[0] = minAmountOut
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

    /// @notice Invests the underlying asset into the pool
    /// @param _amount Max amount of underlying to invest
    /// @param _minIouReceived Min amount of LP tokens to receive
    /// @param _params Calldata for swap if input != underlying
    function _invest(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params
    ) internal override returns (uint256 investedAmount, uint256 iouReceived) {

        uint256 assetsToLp = available();
        console.log("Balance of underlying is ", assetsToLp);

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

    /// @notice Harvest and compound rewards
    /// @param _amount Max amount of underlying to invest
    /// @param _params Calldatas for the rewards swap and the invest if needed
    function _compound(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params
    )
        internal
        override
        returns (uint256 iouReceived, uint256 harvestedRewards)
    {
        harvestedRewards = _harvest(_params);

        // swap back to the underlying asset if needed
        if (underlying != inputs[0]) {
            (harvestedRewards, ) = swapper.decodeAndSwap({
                _input: address(underlying),
                _output: address(inputs[0]),
                _amount: inputs[0].balanceOf(address(this)),
                _params: _params[0]
            });
        }
        (, iouReceived) = _invest({
            _amount: _amount,
            _minIouReceived: _minIouReceived,
            _params: new bytes[](0) // no swap data needed
        });
        return (iouReceived, harvestedRewards);
    }

    /// @notice Withdraw asset function, can remove all funds in case of emergency
    /// @param _amount The amount of asset to withdraw
    /// @return assetsRecovered amount of asset withdrawn
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

    // Utils

    /// @notice Set allowances for third party contracts
    function _setAllowances(uint256 _amount) internal override {
        underlying.approve(address(swapper), _amount);
        inputs[0].approve(address(stableRouter), _amount);
        if (rewardTokens[0] != address(0)) {
            IERC20(rewardTokens[0]).approve(address(swapper), _amount);
        }
        lpToken.approve(address(rewardPool), _amount);
        lpToken.approve(address(stableRouter), _amount);
    }

    // Getters

    /// @notice Returns the investment in asset.
    function _invested() internal view override returns (uint256) {
        // Should return 0 if no lp token is staked
        if (stakedLPBalance() == 0) {
            return 0;
        } else {
            return
                // calculates how much asset (inputs[0]) is to be withdrawn with the lp token balance
                // not the actual ERC4626 underlying invested balance
                (weiPerShare * // eg. 1e6 for usdc
                    stableRouter.getVirtualPrice() *
                    stakedLPBalance()) / 1e36; // 1e18**2 (IOU decimals ** virtualPrice decimals)
        }
    }

    /// @notice Returns the investment in lp token.
    function stakedLPBalance() public view returns (uint256) {
        return IStakingRewards(rewardPool).balanceOf(address(this));
    }

    /// @notice Returns the available HOP rewards
    /// @return rewardsAmounts is an array of rewards available for each reward token.
    /// NOTE: HOP address: 0xc5102fE9359FD9a28f877a67E36B0F050d81a3CC
    function _rewardsAvailable()
        internal
        view
        override
        returns (uint256[] memory rewardsAmounts)
    {
        rewardsAmounts = new uint256[](1);
        rewardsAmounts[0] = IStakingRewards(rewardPool).earned(address(this));
        return rewardsAmounts;
    }
}
