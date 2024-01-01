// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/IBenqi.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title BenqiMultiStake Strategy - Liquidity providing on Benqi
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Sonne (https://benqi.fi/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract BenqiMultiStake is StrategyV5Chainlink {
    using AsMaths for uint256;
    using AsArrays for uint256;
    using SafeERC20 for IERC20;

    // Third party contracts
    IQiToken[8] internal qiTokens; // LP token/pool
    uint8[8] internal qiTokenDecimals; // Decimals of the LP tokens
    IUnitroller internal unitroller;

    constructor() StrategyV5Chainlink() {}

    // Struct containing the strategy init parameters
    struct Params {
        address[] qiTokens;
        address unitroller; // rewards controller
    }

    /**
     * @notice Set the strategy specific parameters
     * @param _params Strategy specific parameters
     */
    function setParams(Params calldata _params) public onlyAdmin {
        unitroller = IUnitroller(_params.unitroller);
        for (uint8 i = 0; i < _params.qiTokens.length; i++) {
            qiTokens[i] = IQiToken(_params.qiTokens[i]);
            qiTokenDecimals[i] = qiTokens[i].decimals();
        }
        _setAllowances(MAX_UINT256);
    }

    /**
     * @dev Initializes the strategy with the specified parameters.
     * @param _baseParams StrategyBaseParams struct containing strategy parameters
     * @param _chainlinkParams Chainlink specific parameters
     * @param _benqiParams Sonne specific parameters
     */
    function init(
        StrategyBaseParams calldata _baseParams,
        ChainlinkParams calldata _chainlinkParams,
        Params calldata _benqiParams
    ) external onlyAdmin {
        for (uint8 i = 0; i < _benqiParams.qiTokens.length; i++) {
            inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
            inputWeights[i] = _baseParams.inputWeights[i];
            inputDecimals[i] = inputs[i].decimals();
        }
        rewardLength = uint8(_baseParams.rewardTokens.length);
        inputLength = uint8(_baseParams.inputs.length);
        setParams(_benqiParams);
        StrategyV5Chainlink._init(_baseParams, _chainlinkParams);
    }

    /**
     * @notice Claim rewards from the third party contracts
     * @return amounts Array of rewards claimed for each reward token
     */
    function claimRewards() public onlyKeeper override returns (uint256[] memory amounts) {
        amounts = new uint256[](rewardLength);
        unitroller.claimReward(0, address(this)); // QI for all markets
        unitroller.claimReward(1, address(this)); // WGAS for all markets

        // wrap native rewards if needed
        _wrapNative();
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

            uint256 iouBefore = qiTokens[i].balanceOf(address(this));
            qiTokens[i].mint(toDeposit);

            uint256 supplied = qiTokens[i].balanceOf(address(this)) - iouBefore;

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

            balance = qiTokens[i].balanceOf(address(this));

            // NB: we could use redeemUnderlying() here
            toLiquidate = AsMaths.min(_inputToStake(_amounts[i], i), balance);

            qiTokens[i].redeem(toLiquidate);

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
            inputs[i].approve(address(qiTokens[i]), _amount);
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
        return _amount.mulDiv(
            qiTokens[_index].exchangeRateStored(),
            inputDecimals[_index]); // eg. 1e8+1e(36-8)-1e18 = 1e18
    }

    /**
     * @notice Convert input to LP/staked LP
     * @return LP value of the input amount
     */
    function _inputToStake(
        uint256 _amount,
        uint8 _index
    ) internal view override returns (uint256) {
        return _amount.mulDiv(
            inputDecimals[_index],
            qiTokens[_index].exchangeRateStored()); // eg. 1e18+1e18-1e(36-8) = 1e8
    }

    /**
     * @notice Returns the invested input converted from the staked LP token
     * @return Input value of the LP/staked balance
     */
    function _stakedInput(
        uint8 _index
    ) internal view override returns (uint256) {
        return _stakeToInput(qiTokens[_index].balanceOf(address(this)), _index);
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
        uint256 mainReward = unitroller.compAccrued(address(this));
        return rewardLength == 1 ? mainReward.toArray() :
            mainReward.toArray(_balance(rewardTokens[1]));
    }
}
