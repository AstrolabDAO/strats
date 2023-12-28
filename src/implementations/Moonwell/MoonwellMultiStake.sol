// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/IMoonwell.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title MoonwellMultiStake Strategy - Liquidity providing on Moonwell (Base & co)
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Moonwell (https://moonwell.fi/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract MoonwellMultiStake is StrategyV5Chainlink {
    using AsMaths for uint256;
    using AsArrays for uint256;
    using SafeERC20 for IERC20;

    // Third party contracts
    IMToken[8] internal mTokens; // LP token/pool
    IUnitroller internal unitroller;

    constructor() StrategyV5Chainlink() {}

    // Struct containing the strategy init parameters
    struct Params {
        address[] mTokens;
        address unitroller; // rewards controller
    }

    /**
     * @notice Set the strategy specific parameters
     * @param _params Strategy specific parameters
     */
    function setParams(Params calldata _params) public onlyAdmin {
        unitroller = IUnitroller(_params.unitroller);
        for (uint8 i = 0; i < _params.mTokens.length; i++) {
            mTokens[i] = IMToken(_params.mTokens[i]);
        }
        _setAllowances(MAX_UINT256);
    }

    /**
     * @dev Initializes the strategy with the specified parameters.
     * @param _baseParams StrategyBaseParams struct containing strategy parameters
     * @param _chainlinkParams Chainlink specific parameters
     * @param _moonwellParams Sonne specific parameters
     */
    function init(
        StrategyBaseParams calldata _baseParams,
        ChainlinkParams calldata _chainlinkParams,
        Params calldata _moonwellParams
    ) external onlyAdmin {
        for (uint8 i = 0; i < _moonwellParams.mTokens.length; i++) {
            inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
            inputWeights[i] = _baseParams.inputWeights[i];
            inputDecimals[i] = inputs[i].decimals();
        }
        rewardLength = uint8(_baseParams.rewardTokens.length);
        inputLength = uint8(_baseParams.inputs.length);
        setParams(_moonwellParams);
        StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
    }

    /**
     * @notice Claim rewards from the reward pool and swap them for asset
     * @param _params Swaps calldata
     * @return assetsReceived Amount of assets received
     */
    function _harvest(
        bytes[] memory _params
    ) internal virtual override nonReentrant returns (uint256 assetsReceived) {
        // only supports WELL rewards
        unitroller.claimReward(address(this)); // WELL for all markets+vai
        uint256 balance;

        for (uint8 i = 0; i < rewardLength; i++) {
            balance = IERC20Metadata(rewardTokens[i]).balanceOf(
                address(this)
            );
            if (rewardTokens[i] != address(asset)) {
                if (balance < 10) return 0;
                (uint256 received, ) = swapper.decodeAndSwap({
                    _input: rewardTokens[i],
                    _output: address(asset),
                    _amount: balance,
                    _params: _params[i]
                });
                assetsReceived += received;
            } else {
                assetsReceived += balance;
            }
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

            uint256 iouBefore = mTokens[i].balanceOf(address(this));
            mTokens[i].mint(toDeposit);

            uint256 supplied = mTokens[i].balanceOf(address(this)) - iouBefore;

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
        uint256 balance;

        for (uint8 i = 0; i < inputLength; i++) {
            if (_amounts[i] < 10) continue;

            balance = mTokens[i].balanceOf(address(this));

            // NB: we could use redeemUnderlying() here
            toLiquidate = AsMaths.min(_inputToStake(_amounts[i], i), balance);

            mTokens[i].redeem(toLiquidate);
            
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
        for (uint8 i = 0; i < inputLength; i++)
            inputs[i].approve(address(mTokens[i]), _amount);
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
        return _amount.mulDiv(mTokens[_index].exchangeRateStored(), 1e18);
    }

    /**
     * @notice Convert input to LP/staked LP
     * @return LP value of the input amount
     */
    function _inputToStake(
        uint256 _amount,
        uint8 _index
    ) internal view override returns (uint256) {
        return _amount.mulDiv(1e18, mTokens[_index].exchangeRateStored());
    }

    /**
     * @notice Returns the invested input converted from the staked LP token
     * @return Input value of the LP/staked balance
     */
    function _stakedInput(
        uint8 _index
    ) internal view override returns (uint256) {
        return _stakeToInput(mTokens[_index].balanceOf(address(this)), _index);
    }

    /**
     * @notice Returns the available rewards
     * @return amounts Array of rewards available for each reward token
     */
    function rewardsAvailable()
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        IMultiRewardDistributor distributor = IMultiRewardDistributor(
            unitroller.rewardDistributor()
        );
        // return unitroller.rewardAccrued(address(this)).toArray();
        // return distributor.getOutstandingRewardsForUser(address(this));
        MultiRewardDistributorCommon.RewardWithMToken[] memory pendingRewards
            = distributor.getOutstandingRewardsForUser(address(this));

        amounts = new uint256[](rewardLength);

        for (uint i = 0; i < pendingRewards.length; i++) {
            for (uint j = 0; j < pendingRewards[i].rewards.length; j++) {
                MultiRewardDistributorCommon.RewardInfo memory info
                    = pendingRewards[i].rewards[j];
                address token = info.emissionToken;
                uint8 index = rewardTokenIndex[token];
                if (index == 0) continue;
                amounts[index-1] += info.totalAmount;
                info.totalAmount;
            }
        }

        return amounts;
    }
}
