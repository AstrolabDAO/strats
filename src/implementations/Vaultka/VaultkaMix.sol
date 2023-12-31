// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "../../libs/AsMaths.sol";
// import "../../libs/AsArrays.sol";
// import "../../abstract/StrategyV5Chainlink.sol";
// import "./interfaces/IVodkaV1.sol";
// import "./interfaces/IRumVault.sol";


// /**            _             _       _
//  *    __ _ ___| |_ _ __ ___ | | __ _| |__
//  *   /  ` / __|  _| '__/   \| |/  ` | '  \
//  *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
//  *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
//  *
//  * @title HopMultiStake - Liquidity providing on Vaultka (n stable (max 5), eg. USDC+USDT+DAI)
//  * @author Astrolab DAO
//  * @notice Basic liquidity providing strategy for Hop protocol (https://hop.exchange/)
//  * @dev Underlying->input[0]->LP->rewardPools->LP->input[0]->underlying
//  */
// contract VaultkaMix is StrategyV5Chainlink {
//     using AsMaths for uint256;
//     using AsArrays for uint256;
//     using SafeERC20 for IERC20;

//     // Third party contracts
//     IVodkaV1 public vodka;
//     IRumVault public rumVault;
//     // IERC20Metadata[5] public lpTokens; // LP token of the pool
//     // IStableRouter[5] public stableRouters; // SaddleSwap
//     // IStakingRewards[5] public rewardPools; // Reward pool
//     uint8[5] public tokenIndexes;

//     /**
//      * @param _erc20Metadata ERC20Permit constructor data: name, symbol, EIP712 version
//      */
//     constructor(
//         string[3] memory _erc20Metadata
//     ) StrategyV5Chainlink(_erc20Metadata) {}

//     // Struct containing the strategy init parameters
//     struct Params {
//         address[] lpTokens;
//         address[] rewardPools;
//         address[] stableRouters;
//         uint8[] tokenIndexes;
//     }

//     /**
//      * @dev Initializes the strategy with the specified parameters.
//      * @param _baseParams StrategyBaseParams struct containing strategy parameters
//      * @param _chainlinkParams Chainlink specific parameters
//      * @param _vaultkaParams Hop specific parameters
//      */
//     function init(
//         StrategyBaseParams calldata _baseParams,
//         ChainlinkParams calldata _chainlinkParams,
//         Params calldata _vaultkaParams
//     ) external onlyAdmin {
//         for (uint8 i = 0; i < _vaultkaParams.lpTokens.length; i++) {
//             lpTokens[i] = IERC20Metadata(_vaultkaParams.lpTokens[i]);
//             rewardPools[i] = IStakingRewards(_vaultkaParams.rewardPools[i]);
//             tokenIndexes[i] = _vaultkaParams.tokenIndexes[i];
//             stableRouters[i] = IStableRouter(_vaultkaParams.stableRouters[i]);
//             // these can be set externally by setInputs()
//             inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
//             inputWeights[i] = _baseParams.inputWeights[i];
//             inputDecimals[i] = inputs[i].decimals();
//         }
//         inputLength = uint8(_vaultkaParams.lpTokens.length);
//         rewardTokens[0] = address(_baseParams.rewardTokens[0]); // HOP only
//         rewardLength = 1;

//         underlying = IERC20Metadata(_baseParams.underlying);
//         _setAllowances(MAX_UINT256);
//         StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
//     }

//     /**
//      * @notice Claim rewards from the reward pool and swap them for underlying
//      * @param _params Swaps calldata
//      * @return assetsReceived Amount of assets received
//      */
//     function _harvest(
//         bytes[] memory _params
//     ) internal override nonReentrant returns (uint256 assetsReceived) {
//         // claim the rewards
//         for (uint8 i = 0; i < inputLength; i++) rewardPools[i].getReward();

//         uint256 pendingRewards = IERC20Metadata(rewardTokens[0]).balanceOf(
//             address(this)
//         );
//         if (pendingRewards == 0) return 0;

//         // swap the rewards back into underlying
//         (assetsReceived, ) = swapper.decodeAndSwap(
//             rewardTokens[0], // HOP
//             address(underlying),
//             pendingRewards,
//             _params[0]
//         );
//     }

//     /**
//      * @notice Adds liquidity to the pool, single sided
//      * @param _amount Max amount of underlying to invest
//      * @param _index Index of the input token
//      * @return deposited Amount of LP tokens received
//      */
//     function _addLiquiditySingleSide(
//         uint256 _amount,
//         uint8 _index
//     ) internal returns (uint256 deposited) {
//         deposited = stableRouters[_index].addLiquidity({
//             amounts: tokenIndexes[_index] == 0
//                 ? _amount.toArray(0)
//                 : uint256(0).toArray(_amount), // determine the side from the token index
//             minToMint: 1, // minToMint
//             deadline: block.timestamp // blocktime only
//         });
//     }

//     /**
//      * @notice Invests the underlying asset into the pool
//      * @param _amounts Amounts of underlying to invest in each input
//      * @param _params Swaps calldata
//      * @return investedAmount Amount invested
//      * @return iouReceived Amount of LP tokens received
//      */
//     function _invest(
//         uint256[8] calldata _amounts, // from previewInvest()
//         bytes[] memory _params
//     )
//         internal
//         override
//         nonReentrant
//         returns (uint256 investedAmount, uint256 iouReceived)
//     {
//         uint256 toDeposit;
//         uint256 spent;

//         for (uint8 i = 0; i < inputLength; i++) {
//             if (_amounts[i] < 10) continue;

//             // We deposit the whole asset balance.
//             if (underlying != inputs[i]) {
//                 (toDeposit, spent) = swapper.decodeAndSwap({
//                     _input: address(underlying),
//                     _output: address(inputs[i]),
//                     _amount: _amounts[i],
//                     _params: _params[i]
//                 });
//                 investedAmount += spent;
//             } else {
//                 investedAmount += _amounts[i];
//                 toDeposit = _amounts[i];
//             }

//             // Adding liquidity to the pool with the inputs[0] balance
//             uint256 toStake = _addLiquiditySingleSide(toDeposit, i);

//             // unified slippage check (swap+add liquidity)
//             if (toStake < _inputToStake(toDeposit, i).subBp(maxSlippageBps * 2))
//                 revert AmountTooLow(toStake);

//             rewardPools[i].stake(toStake);

//             // would make more sense to return an array of ious
//             // rather than mixing them like this
//             iouReceived += toStake;
//         }
//     }

//     /**
//      * @notice Withdraw asset function, can remove all funds in case of emergency
//      * @param _amounts Amounts of asset to withdraw
//      * @param _params Swaps calldata
//      * @return assetsRecovered Amount of asset withdrawn
//      */
//     function _liquidate(
//         uint256[8] calldata _amounts, // from previewLiquidate()
//         bytes[] memory _params
//     ) internal override nonReentrant returns (uint256 assetsRecovered) {
//         uint256 toLiquidate;
//         uint256 recovered;

//         for (uint8 i = 0; i < inputLength; i++) {
//             if (_amounts[i] < 10) continue;

//             toLiquidate = _underlyingToStake(_amounts[i], i);
//             rewardPools[i].withdraw(toLiquidate);

//             recovered = stableRouters[i].removeLiquidityOneToken({
//                 tokenAmount: lpTokens[i].balanceOf(address(this)),
//                 tokenIndex: tokenIndexes[i],
//                 minAmount: 1, // slippage is checked after swap
//                 deadline: block.timestamp
//             });

//             // swap the unstaked tokens (inputs[0]) for the underlying asset if different
//             if (inputs[i] != underlying) {
//                 (recovered, ) = swapper.decodeAndSwap({
//                     _input: address(inputs[i]),
//                     _output: address(underlying),
//                     _amount: recovered,
//                     _params: _params[i]
//                 });
//             }

//             // unified slippage check (unstake+remove liquidity+swap out)
//             if (recovered < _amounts[i].subBp(maxSlippageBps * 2))
//                 revert AmountTooLow(recovered);

//             assetsRecovered += recovered;
//         }
//     }

//     /**
//      * @notice Set allowances for third party contracts (except rewardTokens)
//      * @param _amount Allowance amount
//      */
//     function _setAllowances(uint256 _amount) internal override {
//         for (uint8 i = 0; i < inputLength; i++) {
//             inputs[i].approve(address(stableRouters[i]), _amount);
//             lpTokens[i].approve(address(rewardPools[i]), _amount);
//             lpTokens[i].approve(address(stableRouters[i]), _amount);
//         }
//     }

//     /**
//      * @notice Returns the investment in underlying asset
//      * @return total Amount invested
//      */
//     function _invested() internal view override returns (uint256 total) {
//         for (uint8 i = 0; i < inputLength; i++) {
//             uint256 staked = rewardPools[i].balanceOf(address(this));
//             if (staked < 10) continue;
//             total += _stakeToUnderlying(staked, i);
//         }
//     }

//     /**
//      * @notice Convert LP/staked LP to input
//      * @return Input value of the LP amount
//      */
//     function _stakeToInput(
//         uint256 _amount,
//         uint8 _index
//     ) internal view override returns (uint256) {
//         return
//             _amount.mulDiv(
//                 stableRouters[_index].getVirtualPrice(),
//                 10 ** (36 - inputDecimals[_index])
//             ); // 1e18 == lpToken[i] decimals
//     }

//     /**
//      * @notice Convert input to LP/staked LP
//      * @return LP value of the input amount
//      */
//     function _inputToStake(
//         uint256 _amount,
//         uint8 _index
//     ) internal view override returns (uint256) {
//         return
//             _amount.mulDiv(
//                 10 ** (36 - inputDecimals[_index]),
//                 stableRouters[_index].getVirtualPrice()
//             );
//     }

//     /**
//      * @notice Returns the invested input converted from the staked LP token
//      * @return Input value of the LP/staked balance
//      */
//     function _stakedInput(
//         uint8 _index
//     ) internal view override returns (uint256) {
//         return
//             _stakeToInput(rewardPools[_index].balanceOf(address(this)), _index);
//     }

//     /**
//      * @notice Returns the invested underlying converted from the staked LP token
//      * @return Underlying value of the LP/staked balance
//      */
//     function _stakedUnderlying(
//         uint8 _index
//     ) internal view override returns (uint256) {
//         return
//             _stakeToUnderlying(
//                 rewardPools[_index].balanceOf(address(this)),
//                 _index
//             );
//     }

//     /**
//      * @notice Returns the available HOP rewards
//      * @return amounts Array of rewards available for each reward token
//      */
//     function _rewardsAvailable()
//         public
//         view
//         override
//         returns (uint256[] memory amounts)
//     {
//         amounts = uint256(0).toArray();
//         for (uint8 i = 0; i < rewardLength; i++)
//             amounts[0] += rewardPools[i].earned(address(this));
//     }
// }
