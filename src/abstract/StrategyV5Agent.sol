// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IStrategyV5.sol";
import "./StrategyV5Abstract.sol";
import "./As4626.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title StrategyV5Agent Implementation - back-end contract proxied-to by strategies
 * @author Astrolab DAO
 * @notice This contract is in charge of executing shared strategy logic (accounting, fees, etc.)
 * @dev Make sure all state variables are in StrategyV5Abstract to match proxy/implementation slots
 */
contract StrategyV5Agent is StrategyV5Abstract, As4626 {
    using AsMaths for uint256;
    using AsMaths for int256;
    using SafeERC20 for IERC20;

    constructor() StrategyV5Abstract(["", "", ""]) {}

    /**
     * @notice Initialize the strategy
     * @param _params StrategyBaseParams struct containing strategy parameters
     */
    function init(StrategyBaseParams calldata _params) public onlyAdmin {
        // setInputs(_params.inputs, _params.inputWeights);
        // setRewardTokens(_params.rewardTokens);
        updateSwapper(_params.coreAddresses[1]);
        As4626.init(_params.fees, _params.underlying, _params.coreAddresses[0]);
    }

    /**
     * @notice Sets the swapper allowance
     * @param _amount Amount of allowance to set
     */
    function setSwapperAllowance(uint256 _amount) public onlyAdmin {
        address swapperAddress = address(swapper);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == address(0)) break;
            IERC20Metadata(rewardTokens[i]).approve(swapperAddress, _amount);
        }
        for (uint256 i = 0; i < inputs.length; i++) {
            if (address(inputs[i]) == address(0)) break;
            inputs[i].approve(swapperAddress, _amount);
        }
        underlying.approve(swapperAddress, _amount);
        emit SetSwapperAllowance(_amount);
    }

    /**
     * @notice Change the Swapper address, remove allowances and give new ones
     * @param _swapper Address of the new swapper
     */
    function updateSwapper(address _swapper) public onlyAdmin {
        if (_swapper == address(0)) revert AddressZero();
        if (address(swapper) != address(0)) setSwapperAllowance(0);
        swapper = ISwapper(_swapper);
        setSwapperAllowance(MAX_UINT256);
        emit SwapperUpdate(_swapper);
    }

    /**
     * @notice Sets the reward tokens
     * @param _rewardTokens array of reward tokens
     */
    function setRewardTokens(
        address[] memory _rewardTokens
    ) public onlyManager {
        for (uint256 i = 0; i < _rewardTokens.length; i++)
            rewardTokens[i] = _rewardTokens[i];
        for (uint256 i = _rewardTokens.length; i < 16; i++)
            rewardTokens[i] = address(0);
    }

    /**
     * @notice Sets the input tokens (strategy internals)
     * @param _inputs array of input tokens
     * @param _weights array of input weights
     */
    function setInputs(
        address[] memory _inputs,
        uint256[] memory _weights
    ) public onlyManager {
        for (uint256 i = 0; i < _inputs.length; i++) {
            inputs[i] = IERC20Metadata(_inputs[i]);
            inputWeights[i] = _weights[i];
        }
        for (uint256 i = _inputs.length; i < 16; i++) {
            inputs[i] = IERC20Metadata(address(0));
            inputWeights[i] = 0;
        }
    }

    /**
     * @notice Retrieves the share price from the strategy via the proxy
     * @dev Calls sharePrice function on the IStrategyV5 contract through stratProxy
     * @return The current share price from the strategy
     */
    function sharePrice() public view override returns (uint256) {
        return IStrategyV5(stratProxy).sharePrice();
    }

    /**
     * @notice Retrieves the total assets from the strategy via the proxy
     * @dev Calls totalAssets function on the IStrategyV5 contract through stratProxy
     * @return The total assets managed by the strategy
     */
    function totalAssets() public view override returns (uint256) {
        return IStrategyV5(stratProxy).totalAssets();
    }

    /**
     * @notice Invests an amount into the strategy via the proxy
     * @dev Delegates the call to the 'invest' function in the IStrategyV5 contract through stratProxy
     * @param _amount The amount to be invested
     * @param _minIouReceived The minimum IOU (I Owe You) to be received from the investment
     * @param _params Additional parameters for the investment, typically passed as generic callData
     * @return investedAmount The actual amount that was invested
     * @return iouReceived The IOU received from the investment
     */
    function invest(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params
    ) public returns (uint256 investedAmount, uint256 iouReceived) {
        return
            IStrategyV5(stratProxy).invest(_amount, _minIouReceived, _params);
    }

    /**
     * @notice Swaps an input token to the underlying token and then safely deposits it
     * @param _input The address of the input token to be swapped
     * @param _amount The amount of the input token to swap
     * @param _receiver The address where the shares from the deposit should be sent
     * @param _minShareAmount The minimum amount of shares expected from the deposit, used for slippage control
     * @param _params Additional swap parameters
     * @return shares The number of shares received from the deposit
     */
    function swapSafeDeposit(
        address _input,
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount,
        bytes memory _params
    ) external returns (uint256 shares) {
        uint256 underlyingAmount = _amount;
        if (_input != address(underlying)) {
            // Swap logic
            (underlyingAmount, ) = swapper.decodeAndSwap(
                _input,
                address(underlying),
                _amount,
                _params
            );
        }
        return safeDeposit(underlyingAmount, _receiver, _minShareAmount);
    }

    /**
     * @notice Deposits an amount and then invests it, with control over the minimum share amount
     * @dev This function first makes a safe deposit and then invests the deposited amount.
     * It is restricted to onlyAdmin for execution.
     * @param _amount The amount to be deposited and invested
     * @param _receiver The address where the shares from the deposit should be sent
     * @param _minShareAmount The minimum amount of shares expected from the deposit, used for slippage control
     * @param _params Additional parameters for the investment process
     * @return investedAmount The amount that was actually invested
     * @return iouReceived The IOU received from the investment
     */
    function safeDepositInvest(
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount,
        bytes[] memory _params
    ) external onlyAdmin returns (uint256 investedAmount, uint256 iouReceived) {
        safeDeposit(_amount, _receiver, _minShareAmount);
        return invest(_amount, _minShareAmount, _params);
    }
}
