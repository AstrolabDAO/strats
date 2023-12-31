// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "../../libs/AsArrays.sol";
import "../../abstract/StrategyV5Chainlink.sol";
import "./interfaces/v3/ICompoundV3.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title CompoundV3MultiStake Strategy - Liquidity providing on Compound V3 (Base & co)
 * @author Astrolab DAO
 * @notice Liquidity providing strategy for Compound (https://compound.finance/)
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract CompoundV3MultiStake is StrategyV5Chainlink {
    using AsMaths for uint256;
    using AsArrays for uint256;
    using SafeERC20 for IERC20;

    // Third party contracts
    IComet[8] internal cTokens; // LP token/pool
    ICometRewards public cometRewards;

    constructor() StrategyV5Chainlink() {}

    // Struct containing the strategy init parameters
    struct Params {
        address[] cTokens;
        address cometRewards; // rewards controller
    }

    /**
     * @notice Set the strategy specific parameters
     * @param _params Strategy specific parameters
     */
    function setParams(Params calldata _params) public onlyAdmin {
        // unitroller = IUnitroller(_params.unitroller);
        cometRewards = ICometRewards(_params.cometRewards);

        for (uint8 i = 0; i < _params.cTokens.length; i++) {
            cTokens[i] = IComet(_params.cTokens[i]);
        }
        _setAllowances(MAX_UINT256);
    }

    /**
     * @dev Initializes the strategy with the specified parameters.
     * @param _baseParams StrategyBaseParams struct containing strategy parameters
     * @param _chainlinkParams Chainlink specific parameters
     * @param _compoundParams Sonne specific parameters
     */
    function init(
        StrategyBaseParams calldata _baseParams,
        ChainlinkParams calldata _chainlinkParams,
        Params calldata _compoundParams
    ) external onlyAdmin {
        for (uint8 i = 0; i < _compoundParams.cTokens.length; i++) {
            inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
            inputWeights[i] = _baseParams.inputWeights[i];
            inputDecimals[i] = inputs[i].decimals();
        }
        rewardLength = uint8(_baseParams.rewardTokens.length);
        inputLength = uint8(_baseParams.inputs.length);
        setParams(_compoundParams);
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

        uint256 balance;

        for (uint8 i = 0; i < rewardLength; i++) {
            cometRewards.claim(address(cTokens[i]), address(this), true);
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

            uint256 iouBefore = cTokens[i].balanceOf(address(this));
            cTokens[i].supply(address(inputs[i]), toDeposit);

            uint256 supplied = cTokens[i].balanceOf(address(this)) - iouBefore;

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

            balance = cTokens[i].balanceOf(address(this));

            // NB: we could use redeemUnderlying() here
            toLiquidate = AsMaths.min(_inputToStake(_amounts[i], i), balance);

            cTokens[i].withdraw(address(inputs[i]), toLiquidate);
            
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
            inputs[i].approve(address(cTokens[i]), _amount);
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
        return cTokens[_index].balanceOf(address(this));
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
        amounts = new uint256[](rewardLength);

        for (uint i = 0; i < cTokens.length; i++) {
            if (address(cTokens[i]) == address(0)) break;
            amounts[0] = cTokens[i].baseTrackingAccrued(address(cTokens[i]));
        }
        for (uint i = 0; i < rewardLength; i++) {
            amounts[i] += IERC20Metadata(rewardTokens[i]).balanceOf(address(this));
        }

        return amounts;
    }
}
