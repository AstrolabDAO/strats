// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../libs/AsMaths.sol";
import "../../libs/AsTickMaths.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../abstract/StrategyV5Pyth.sol";
import "./interfaces/IRouter.sol";

/// @title KyberSwap Strategy (v5)
/// @notice This contract is a strategy for KyberSwap
/// @dev Basic implementation
contract KyberSwapStrategy is StrategyV5Pyth {
    using SafeERC20 for IERC20;

    // Tokens used
    // Third-party contracts
    IRouter public kyberRouter;
    KyberSwapElasticLM public lm;
    TicksFeesReader public ticksFeesReader;
    AntiSnipAttackPositionManager public npm;
    Pool public pool;
    // Params
    uint24 fee;
    uint256 tokenId;
    uint256 poolId;
    int24 lowerTick;
    int24 upperTick;

    uint256 constant STAKE_SLIPPAGE = 10; // 1% slippage

    // constructor(
    //     Fees memory _fees, // perfFee, mgmtFee, entryFee, exitFee in bps 100% = 10000
    //     address _underlying, // The asset we are using
    //     address[] memory _coreAddresses,
    //     string[] memory _erc20Metadata, // name, symbol of the share and EIP712 version
    //     address _kyberRouter,
    //     address _lm,
    //     address _ticksFeesReader,
    //     address _npm,
    //     address _pool
    // ) StrategyV5(_fees, _underlying, _coreAddresses, _erc20Metadata) {
    //     kyberRouter = IRouter(_kyberRouter);
    //     lm = KyberSwapElasticLM(_lm);
    //     ticksFeesReader = TicksFeesReader(_ticksFeesReader);
    //     npm = AntiSnipAttackPositionManager(_npm);
    //     pool = Pool(_pool);
    //     _setAllowances(MAX_UINT256);
    // }

    constructor(string[3] memory _erc20Metadata) StrategyV5Pyth(_erc20Metadata) {}

    // Interactions

    /// @notice Invests the underlying asset into the pool
    /// @param _amount Max amount of underlying to invest
    /// @param _params Calldata for swap if input != underlying
    function _invest(
        uint256 _amount,
        bytes[] memory _params
    ) internal override returns (uint256 investedAmount, uint256 iouReceived) {
        uint256 assetsToLP = available();
        // The amount we add is capped by _amount

        assetsToLP = AsMaths.min(assetsToLP, _amount);

        if (underlying != inputs[0]) {
            swapper.decodeAndSwap({
                _input: address(underlying),
                _output: address(inputs[0]),
                _amount: inputs[0].balanceOf(address(this)),
                _params: _params[0]
            });
        }
        // Calculate the value of inputs1 compared to inputs0
        (uint160 sqrtP, , , ) = pool.getPoolState();
        (uint128 baseL, , ) = pool.getLiquidityState();

        (uint256 amountLiq0, uint256 amountLiq1) = AsPoolMaths
            .getAmountsForLiquidity(
                sqrtP,
                AsTickMath.getSqrtRatioAtTick(lowerTick),
                AsTickMath.getSqrtRatioAtTick(upperTick),
                baseL
            );
        uint256 needInputs1Value = (_amount * amountLiq1) /
            (amountLiq0 + amountLiq1);
        //////////////
        // TODO: Use NeedInputs1Value to calculate the amount of inputs[0] to swap

        // Swapping half inputs[0] to inputs[1]
        swapper.decodeAndSwap({
            _input: address(inputs[0]),
            _output: address(inputs[1]),
            _amount: underlying.balanceOf(address(this)) / 2,
            _params: _params[1]
        });

        uint256 inputs0Balance = inputs[0].balanceOf(address(this));
        uint256 inputs1Balance = inputs[1].balanceOf(address(this));

        int24[2] memory ticksPrevious;
        (ticksPrevious[0], ticksPrevious[1]) = getPreviousTicks(
            lowerTick,
            upperTick
        );
        if (tokenId == 0) {
            MintParams memory params = MintParams({
                token0: address(inputs[0]),
                token1: address(inputs[1]),
                fee: fee,
                tickLower: lowerTick,
                tickUpper: upperTick,
                ticksPrevious: ticksPrevious,
                amount0Desired: inputs0Balance,
                amount1Desired: inputs1Balance,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

            (tokenId, , , ) = npm.mint(params);
        } else {
            _exitAndWithdrawNFT();

            IncreaseLiquidityParams memory params = IncreaseLiquidityParams({
                tokenId: tokenId,
                ticksPrevious: ticksPrevious,
                amount0Desired: inputs0Balance,
                amount1Desired: inputs1Balance,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

            npm.addLiquidity(params);
        }

        _depositAndJoinNFT();

        // iouReceived = pool.balanceOf(address(this));
        // require(iouReceived >= _minIouReceived, "ERR_MIN_IOU_RECEIVED");
        //TODO: Return
        // return (assetsToLP, iouReceived);
    }

    function _depositAndJoinNFT() internal {
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = tokenId;

        uint256[] memory liqs = new uint256[](1);
        liqs[0] = getLiquidity();

        lm.deposit(nftIds);
        lm.join(poolId, nftIds, liqs);
    }

    function _exitAndWithdrawNFT() internal {
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = tokenId;

        if (isJoined()) {
            uint256[] memory liqs = new uint256[](1);
            (liqs[0], , ) = lm.getUserInfo(tokenId, poolId);
            lm.exit(poolId, nftIds, liqs);
        }

        lm.withdraw(nftIds);
    }

    function _removeLiquidity(uint256 liquidity) internal {
        RemoveLiquidityParams memory params = RemoveLiquidityParams({
            tokenId: tokenId,
            liquidity: uint128(liquidity),
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        npm.removeLiquidity(params);
        npm.transferAllTokens(address(inputs[0]), 0, address(this));
        npm.transferAllTokens(address(inputs[1]), 0, address(this));
    }

    /// @notice Withdraw asset function, can remove all funds in case of emergency
    /// @param _amount The amount of asset to withdraw
    /// @param _params Target router, min amount out and swap data
    /// @return assetsRecovered amount of asset withdrawn
    function _liquidate(
        uint256 _amount,
        bytes[] memory _params
    ) internal override returns (uint256 assetsRecovered) {
        // Calculate the amount of lp token to unstake
        uint256 LPToUnstake = (_amount * stakedLpBalance()) / _invested();
        // calculate minAmounts
        uint minAmount = AsMaths.subBp(_amount, STAKE_SLIPPAGE);
        // Withdraw asset from the pool
        uint256 amountInputs1 = _calcUsdcAmountToSwap(_amount) * 1e12;
        uint256 amountInputs0 = _amount - (amountInputs1 / 1e12);

        _exitAndWithdrawNFT();

        (uint160 sqrtP, , , ) = pool.getPoolState();

        uint128 liquidity = AsPoolMaths.getLiquidityForAmounts(
            sqrtP,
            AsTickMath.getSqrtRatioAtTick(lowerTick),
            AsTickMath.getSqrtRatioAtTick(upperTick),
            amountInputs1,
            amountInputs0
        );

        _removeLiquidity(liquidity);

        // Swap all the inputs[1] to inputs[0]
        swapper.decodeAndSwap(
            address(inputs[0]),
            address(underlying),
            inputs[1].balanceOf(address(this)),
            _params[0]
        );

        return inputs[0].balanceOf(address(this));
    }

    // Utils

    /// @notice Set allowances for third party contracts
    function _setAllowances(uint256 _amount) internal override {
        underlying.approve(address(swapper), _amount);
        inputs[0].approve(address(swapper), _amount);
        inputs[1].approve(address(swapper), _amount);
        inputs[0].approve(address(npm), _amount);
        inputs[1].approve(address(npm), _amount);
        inputs[0].approve(address(kyberRouter), _amount);
        inputs[1].approve(address(kyberRouter), _amount);
        inputs[0].approve(address(lm), _amount);
        inputs[1].approve(address(lm), _amount);
    }

    function _calcUsdcAmountToSwap(
        uint256 _amount
    ) internal view returns (uint256) {
        (uint160 sqrtP, , , ) = pool.getPoolState();
        (uint128 baseL, , ) = pool.getLiquidityState();

        (uint256 amountDai, uint256 amountUsdc) = AsPoolMaths
            .getAmountsForLiquidity(
                sqrtP,
                AsTickMath.getSqrtRatioAtTick(lowerTick),
                AsTickMath.getSqrtRatioAtTick(upperTick),
                baseL
            );
        // uint8 inputs1Decimals = IERC20Metadata(inputs[1]).decimals;
        uint256 needUsdcValue = (_amount * amountDai) /
            ((amountUsdc * uint256(inputs[1].decimals())) /
                uint256(inputs[0].decimals()) +
                amountDai);
        return needUsdcValue;
    }

    // Getters

    function isJoined() internal view returns (bool) {
        uint256[] memory pools = lm.getJoinedPools(tokenId);
        return pools.length > 0;
    }

    function getLiquidity() public view returns (uint128 liquidity) {
        if (tokenId > 0) {
            (Position memory pos, ) = npm.positions(tokenId);
            liquidity = pos.liquidity;
        }
    }

    function getPreviousTicks(
        int24 _lowerTick,
        int24 _upperTick
    ) public view returns (int24 lowerPrevious, int24 upperPrevious) {
        // address ticksFeesReaderAddress = 0x8Fd8Cb948965d9305999D767A02bf79833EADbB3;
        int24[] memory allTicks = ticksFeesReader.getTicksInRange(
            IPoolStorage(address(pool)),
            -887272,
            150
        );

        uint256 l = 0;
        uint256 r = allTicks.length - 1;
        uint256 m = 0;

        while (l + 1 < r) {
            m = (l + r) / 2;
            if (allTicks[m] <= lowerTick) {
                l = m;
            } else {
                r = m;
            }
        }

        if (allTicks[l] <= lowerTick) lowerPrevious = allTicks[l];
        if (allTicks[r] <= lowerTick) lowerPrevious = allTicks[r];

        l = 0;
        r = allTicks.length - 1;

        while (l + 1 < r) {
            m = (l + r) / 2;
            if (allTicks[m] <= upperTick) {
                l = m;
            } else {
                r = m;
            }
        }

        if (allTicks[l] <= upperTick) upperPrevious = allTicks[l];
        if (allTicks[r] <= upperTick) upperPrevious = allTicks[r];
    }

    /// @notice Returns the price of a token compared to another.
    function _getRate(address token) internal pure returns (uint256) {
        //TODO : Use oracle for exchange rate
        return 1;
    }

    /// @notice Returns the investment in asset.
    function _invested() internal view override returns (uint256) {
        // Should return 0 if no lp token is staked
        // if (stakedLpBalance() == 0) {
        //     return 0;
        // } else {
        //     (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        //     uint256 totalLpBalance = pool.totalSupply();
        //     uint256 amount0 = (reserve0 * amountLp) / totalLpBalance;
        //     uint256 amount1 = (reserve1 * amountLp) / totalLpBalance;
        //     // calculates how much asset (inputs[0]) is to be withdrawn with the lp token balance
        //     // not the actual ERC4626 underlying invested balance
        //     return (amount0 + (amount1 * getRate(address(inputs[1]))));
        // }
    }

    /// @notice Returns the investment in lp token.
    function stakedLpBalance() public view returns (uint256) {
        if (tokenId > 0) {
            (Position memory pos, ) = npm.positions(tokenId);
            return pos.liquidity;
        }
    }
}
