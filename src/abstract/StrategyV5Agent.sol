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

        for (uint256 i = 0; i < rewardLength; i++) {
            if (rewardTokens[i] == address(0)) break;
            IERC20Metadata(rewardTokens[i]).approve(swapperAddress, _amount);
        }
        for (uint256 i = 0; i < inputLength; i++) {
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
     * @notice Changes the strategy underlying token (automatically pauses the strategy)
     * make sure to update the oracles by calling the appropriate updateUnderlying
     * @param _underlying Address of the token
     * @param _swapData Swap callData oldUnderlying->newUnderlying
     */
    function updateUnderlying(address _underlying, bytes calldata _swapData) external virtual onlyAdmin {
        if (_underlying == address(0)) revert AddressZero();
        if (_underlying == address(underlying)) return;
        _pause();
        // slippage is checked within Swapper
        (uint256 received, uint256 spent) = swapper.decodeAndSwap(
            address(underlying),
            _underlying,
            underlying.balanceOf(address(this)),
            _swapData
        );
        emit UnderlyingUpdate(_underlying, spent, received);
        underlying = IERC20Metadata(_underlying);
        shareDecimals = underlying.decimals();
        weiPerShare = 10 ** shareDecimals;
        last.accountedSharePrice = weiPerShare;
    }

    /**
     * @notice Sets the input tokens (strategy internals), make sure to liquidate() them first
     * @param _inputs array of input tokens
     * @param _weights array of input weights
     */
    function setInputs(
        address[] calldata _inputs,
        uint16[] calldata _weights
    ) public onlyManager {
        for (uint8 i = 0; i < _inputs.length; i++) {
            inputs[i] = IERC20Metadata(_inputs[i]);
            inputWeights[i] = _weights[i];
        }
        inputLength = uint8(_inputs.length);
    }

    /**
     * @notice Sets the reward tokens
     * @param _rewardTokens array of reward tokens
     */
    function setRewardTokens(
        address[] calldata _rewardTokens
    ) public onlyManager {
        for (uint8 i = 0; i < _rewardTokens.length; i++)
            rewardTokens[i] = _rewardTokens[i];
        rewardLength = uint8(_rewardTokens.length);
    }

    /**
     * @notice Sets the internal slippage
     * @param _slippageBps array of input tokens
     */
    function setMaxSlippageBps(uint16 _slippageBps) public onlyManager {
        maxSlippageBps = _slippageBps;
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

    function previewInvest(
        uint256 _amount
    ) public view returns (uint256[8] memory amounts) {
        return
            IStrategyV5(stratProxy).previewInvest(_amount);
    }

    function previewLiquidate(
        uint256 _amount
    ) public view returns (uint256[8] memory amounts) {
        return
            IStrategyV5(stratProxy).previewInvest(_amount);
    }
}
