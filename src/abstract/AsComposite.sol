// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.17;

import "../libs/AsArrays.sol";
import "../abstract/StrategyV5.sol";
import "../interfaces/IAs4626.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsComposite - Liquidity providing on primitives
 * @author Astrolab DAO
 * @notice Liquidity providing for network specific AsPrimitives
 * @dev Asset->inputs->LPs->inputs->asset
 */
contract AsComposite is StrategyV5 {
    //TODO: Tbd if used or not
    using AsMaths for uint256;
    using AsArrays for uint256;
    using SafeERC20 for IERC20;

    // Third party contracts
    address[8] public primitives;

    constructor() StrategyV5() {}

    // Struct containing the compopsite init parameters
    //TODO: Tbd if needed or pass directly to init address[]
    struct Params {
        address[] primitives;
    }

    /**
     * @dev Initializes the strategy with the specified parameters
     * @param _baseParams CompositeBaseParams struct containing composite parameters
     * @param _compositeParams Sonne specific parameters
     */
    function init(
        StrategyBaseParams calldata _baseParams,
        Params calldata _compositeParams
    ) external onlyAdmin {
        for (uint8 i = 0; i < _compositeParams.primitives.length; i++) {
            inputs[i] = IERC20Metadata(_baseParams.inputs[i]);
            inputWeights[i] = _baseParams.inputWeights[i];
            inputDecimals[i] = inputs[i].decimals();
        }
        inputLength = uint8(_baseParams.inputs.length);
        for (uint8 i = 0; i < _compositeParams.primitives.length; i++) {
            primitives[i] = _compositeParams.primitives[i];
        }
        _setAllowances(MAX_UINT256);
        StrategyV5._init(_baseParams);
    }

    /**
     * @notice Changes the strategy input tokens
     * @param _newInputs Array of input token addresses
     * @param _primitives Array of primitives addresses
     * @param _weights Array of input token weights
     */
    function setInputs(
        address[] calldata _newInputs,
        address[] calldata _primitives,
        uint16[] calldata _weights
    ) external onlyAdmin {
        for (uint256 i = 0; i < _primitives.length; i++) {
            primitives[i] = _primitives[i];
        }
        _setAllowances(MAX_UINT256);
        _setInputs(_newInputs, _weights); // from StrategyV5
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

            IAs4626 primitive = IAs4626(primitives[i]);
            uint256 iouBefore = primitive.balanceOf(address(this));
            primitive.deposit(toDeposit, address(this));

            uint256 supplied = primitive.balanceOf(address(this)) - iouBefore;

            // unified slippage check (swap+add liquidity)
            if (
                supplied < _inputToStake(toDeposit, i).subBp(maxSlippageBps * 2)
            ) revert AmountTooLow(supplied);

            // NB: better return ious[]
            iouReceived += supplied;
        }
    }

    /**
     * @notice Withdraw asset function, can remove all funds in case of emergency
     * @param _amounts Amounts of asset to withdraw in primitives, and in primitives pools
     * @param _params Swaps calldata for primitives and for primitives pools
     * @return assetsRecovered Amount of asset withdrawn
     */
    function liquidatePrimitives(
        uint256[8][8] calldata _amounts, // from previewLiquidate()
        uint256[] calldata _minLiquidity,
        bytes[][] memory _params
    ) external nonReentrant onlyKeeper returns (uint256 assetsRecovered) {
        uint256 toLiquidate;
        uint256 recovered;
        uint256 balance;

        for (uint8 i = 0; i < inputLength; i++) {
            IAs4626 primitive = IAs4626(primitives[i]);
            balance = primitive.balanceOf(address(this));

            recovered = primitive.withdraw(
                IStrategyV5(primitives[i]).liquidate(
                    _amounts[i],
                    _minLiquidity[i],
                    false,
                    _params[i]
                ),
                address(this),
                address(this)
            );

            assetsRecovered += recovered;
        }
    }

    /**
     * @notice Initiate a liquidate request for assets
     * @param _amounts Amounts of asset to liquidate in primitives
     * @param _operator Address initiating the requests in primitives
     * @param _owner The owner of the shares to be redeemed in primitives
     */
    function requestLiquidate(
        uint256[] calldata _amounts,
        address _operator,
        address _owner
    ) external nonReentrant whenNotPaused onlyManager returns (uint256 amountRequested) {
        for (uint8 i = 0; i < primitives.length; i++) {
            IAs4626(primitives[i]).requestWithdraw(
                _amounts[i],
                _operator,
                _owner
            );
            req.liquidate[i] = _amounts[i];
            amountRequested += _amounts[i];
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
        // here inputLength is the same as primitives.length
        for (uint8 i = 0; i < inputLength; i++) {
            if (_amounts[i] < 10) continue;

            IAs4626 primitive = IAs4626(primitives[i]);
            balance = primitive.balanceOf(address(this));

            // NB: we could use redeemUnderlying() here
            toLiquidate = AsMaths.min(_inputToStake(_amounts[i], i), balance);

            if (req.liquidate[i] > 0) {
                recovered = primitive.withdraw(
                    (AsMaths.min(req.liquidate[i], _amounts[i])),
                    address(this),
                    address(this)
                );
            } else {
                revert Unauthorized();
            }
            // unified slippage check (unstake+remove liquidity+swap out)
            if (
                recovered <
                _amounts[i].subBp(maxSlippageBps * 2)
            ) revert AmountTooLow(recovered);

            assetsRecovered += recovered;
        }
    }

    /**
     * @notice Set allowances for third party contracts (except rewardTokens)
     * @param _amount Allowance amount
     */
    function _setAllowances(uint256 _amount) internal override {
        // here inputLength is the same as primitives.length
        for (uint8 i = 0; i < inputLength; i++)
            inputs[i].approve(address(primitives[i]), _amount);
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
     * @notice Returns the invested input converted from the staked LP token
     * @return Input value of the LP/staked balance
     */
    function _stakedInput(
        uint8 _index
    ) internal view override returns (uint256) {
        return IAs4626(primitives[_index]).balanceOf(address(this));
    }

        /**
     * @notice Returns the investment in asset asset for the specified input
     * @return total Amount invested
     */
    function invested(uint8 _index) public view override returns (uint256) {
        return
            IAs4626(primitives[_index]).convertToAssets(
                IAs4626(primitives[_index]).balanceOf(address(this))
            );
    }

    /**
     * @notice Convert LP/staked LP to input
     * @param _amount Amount of LP/staked LP
     * @return Input value of the LP amount
     */
    function _stakeToInput(
        uint256 _amount,
        uint8 _index
    ) internal view override returns (uint256) {
        return IAs4626(primitives[_index]).convertToAssets(_amount);
    }

    /**
     * @notice Convert input to LP/staked LP
     * @return LP value of the input amount
     */
    function _inputToStake(
        uint256 _amount,
        uint8 _index
    ) internal view override returns (uint256) {
        return IAs4626(primitives[_index]).convertToShares(_amount);
    }
}
