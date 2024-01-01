// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/IAgave.sol";
import "../Balancer/interfaces/v2/IBalancer.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AgaveMultiStake Strategy - Liquidity providing on Agave
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Agave V3 (https://aave.com/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract AgaveMultiStake is StrategyV5Chainlink {
    using AsMaths for uint256;
    using AsArrays for uint256;
    using SafeERC20 for IERC20;

    // Third party contracts
    IERC20Metadata[8] internal aTokens; // LP token of the pool
    IPoolAddressesProvider internal poolProvider;
    IBalancerVault internal balancerVault;
    bytes32 internal rewardPoolId;

    constructor() StrategyV5Chainlink() {}

    // Struct containing the strategy init parameters
    struct Params {
        address[] aTokens;
        address poolProvider;
        address balancerVault;
        bytes32 rewardPoolId;
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
     * @dev Initializes the strategy with the specified parameters
     * @param _baseParams StrategyBaseParams struct containing strategy parameters
     * @param _chainlinkParams Chainlink specific parameters
     * @param _aaveParams Agave specific parameters
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
        setParams(_aaveParams);
        StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
    }


    /**
     * @dev Internal function to get information about the reward LP
     * @return lp The address of the reward LP
     * @return tokens An array of token addresses in the LP
     * @return balances An array of token balances in the LP
     * @return rewardIndex The index of the AGVE token in the LP
     */
    function _getRewardLpInfo() internal view returns (address lp, address[] memory tokens, uint256[] memory balances, uint8 rewardIndex) {
        (tokens,balances,) = balancerVault.getPoolTokens(rewardPoolId);
        rewardIndex = tokens[0] == rewardTokens[0] ? 0 : 1; // AGVE index in LP
        (lp,) = balancerVault.getPool(rewardPoolId);
    }

    /**
     * @notice Claim rewards from the third party contracts
     * @return amounts Array of rewards claimed for each reward token
     */
    function claimRewards() public onlyKeeper override returns (uint256[] memory amounts) {
        amounts = new uint256[](rewardLength);

        (address lp, address[] memory tokens, , uint8 rewardIndex) = _getRewardLpInfo();

        ExitPoolRequest memory request = ExitPoolRequest({
            assets: tokens,
            minAmountsOut: uint256(0).toArray(0),
            userData: abi.encode(
                WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
                IERC20Metadata(lp).balanceOf(address(this)),
                rewardIndex),
            toInternalBalance: false
        });

        balancerVault.exitPool({
            poolId: rewardPoolId,
            sender: address(this),
            recipient: payable(address(this)),
            request: request
        });

        for (uint8 i = 0; i < rewardLength; i++) {
            amounts[i] = IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
        }
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
        IPool pool = IPool(poolProvider.getLendingPool());

        for (uint8 i = 0; i < inputLength; i++) {
            if (_amounts[i] < 10) continue;

            // We deposit the whole asset balance
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

            uint256 iouBefore = aTokens[i].balanceOf(address(this));
            pool.deposit({
                asset: address(inputs[i]),
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

        IPool pool = IPool(poolProvider.getLendingPool());
        for (uint8 i = 0; i < inputLength; i++) {
            if (_amounts[i] < 10) continue;

            toLiquidate = _inputToStake(_amounts[i], i);

            pool.withdraw({
                asset: address(inputs[i]),
                amount: toLiquidate,
                to: address(this)
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
        IPool pool = IPool(poolProvider.getLendingPool());
        for (uint8 i = 0; i < inputLength; i++) {
            inputs[i].approve(address(pool), _amount);
            aTokens[i].approve(address(pool), _amount);
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
     * @notice Returns the available rewards
     * @return amounts Array of rewards available for each reward token
     */
    function rewardsAvailable()
        public
        view
        override
        returns (uint256[] memory amounts)
    {
        (address lp, , uint256[] memory balances, uint8 rewardIndex) = _getRewardLpInfo();
        uint256 shareOfSupply = IERC20Metadata(lp).balanceOf(address(this)) * 1e18 / IERC20Metadata(lp).totalSupply(); // 1e18+1e18-1e18 = 1e18
        uint256 rewardInPool = balances[rewardIndex]; // 1e18
        uint256[] memory weights = IBalancerManagedPool(lp).getNormalizedWeights();
        uint256 rewardValueOfPool = rewardInPool * (100 / weights[rewardIndex]); // total value of the pool in reward token 1e18
        return ((rewardValueOfPool * shareOfSupply).subBp(200) / 1e18).toArray(); // 1e18+1e18-1e18 = 1e18
    }
}
