// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "../interfaces/IStrategyV5.sol";
import "./StrategyV5Abstract.sol";
import "./As4626.sol";
import "./AsRescuable.sol";

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
contract StrategyV5Agent is StrategyV5Abstract, AsRescuable, As4626 {
    using AsMaths for uint256;
    using AsMaths for int256;
    using SafeERC20 for IERC20;

    constructor() StrategyV5Abstract() {}

    /**
     * @notice Initialize the strategy
     * @param _params StrategyBaseParams struct containing strategy parameters
     */
    function init(StrategyBaseParams calldata _params) public onlyAdmin {
        // setInputs(_params.inputs, _params.inputWeights);
        setRewardTokens(_params.rewardTokens);
        asset = IERC20Metadata(_params.coreAddresses.asset);
        assetDecimals = asset.decimals();
        weiPerAsset = 10**assetDecimals;
        updateSwapper(_params.coreAddresses.swapper);
        As4626.init(_params.erc20Metadata, _params.coreAddresses, _params.fees);
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
        asset.approve(swapperAddress, _amount);
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
    }

    /**
     * @notice Changes the strategy asset token (automatically pauses the strategy)
     * make sure to update the oracles by calling the appropriate updateAsset
     * @param _asset Address of the token
     * @param _swapData Swap callData oldAsset->newAsset
     */
    function updateAsset(address _asset, bytes calldata _swapData) external virtual onlyAdmin {
        if (_asset == address(0)) revert AddressZero();
        if (_asset == address(asset)) return;
        _pause();
        // slippage is checked within Swapper >> no need to use (received, spent)
        swapper.decodeAndSwapBalance(
            address(asset),
            _asset,
            _swapData
        );
        asset = IERC20Metadata(_asset);
        assetDecimals = asset.decimals();
        weiPerAsset = 10**assetDecimals;
        // last.accountedProfit = 0;
        last.accountedAssets = totalAssets();
        last.accountedSupply = totalSupply();
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
        for (uint8 i = 0; i < _rewardTokens.length; i++) {
            rewardTokens[i] = _rewardTokens[i];
            rewardTokenIndex[_rewardTokens[i]] = i+1;
        }
        rewardLength = uint8(_rewardTokens.length);
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
     * @dev Requests a rescue for a specific token
     * Only the admin can call this function
     * @param _token The address of the token to be rescued (use address(1) for native/eth)
     */
    function requestRescue(address _token) external override onlyAdmin {
        _requestRescue(_token);
    }

    /**
     * @dev Rescues a specific token by sending it to the rescueRequest.receiver (admin)
     * Only the admin can call this function
     * @param _token The address of the token to be rescued (use address(1) for native/eth)
     */
    function rescue(address _token) external override onlyManager {
        _rescue(_token);
    }
}
