// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@astrolabs/registry/interfaces/ISwapper.sol";
import "./StrategyAbstractV5.sol";
import "./AsProxy.sol";
import "../libs/AsArrays.sol";
import "../libs/AsMaths.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title StrategyV5 Abstract - implemented by all strategies
 * @author Astrolab DAO
 * @notice All StrategyV5 calls are delegated to the agent (StrategyAgentV5)
 * @dev Make sure all state variables are in StrategyV5Abstract to match proxy/implementation slots
 */
abstract contract StrategyV5 is StrategyAbstractV5, AsProxy {
    using AsMaths for uint256;
    using AsMaths for int256;
    using AsArrays for bytes[];
    using SafeERC20 for IERC20;

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, version
     */
    constructor(
        string[3] memory _erc20Metadata
    ) StrategyAbstractV5(_erc20Metadata) {}

    /**
     * @notice Initialize the strategy
     * @param _fees fees structure
     * @param _underlying address of the underlying asset
     * @param _coreAddresses array of core addresses: feeCollector, swapper, agent
     */
    function init(
        Fees memory _fees,
        address _underlying,
        address[3] memory _coreAddresses
    ) public onlyAdmin {
        setExemption(msg.sender, true);
        // done in As4626 but required for swapper
        stratProxy = address(this);
        underlying = ERC20(_underlying);
        updateSwapper(_coreAddresses[1]);
        agent = _coreAddresses[2];
        // StrategyAgentV5.init
        _delegateWithSignature(
            agent,
            "init((uint64,uint64,uint64,uint64),address,address)"
        );
    }

    /**
     * @notice Returns the StrategyAgentV5 proxy initialization state
     */
    function initialized() public view override returns (bool) {
        return agent != address(0) && address(underlying) != address(0);
    }

    /**
     * @notice Returns the address of the implementation
     */
    function _implementation() internal view override returns (address) {
        return agent;
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
     * @notice Sets the agent (StrategyAgentV5 implementation)
     * @param _agent The new agent address
     */
    function updateAgent(address _agent) external onlyAdmin {
        if (_agent == address(0)) revert AddressZero();
        agent = _agent;
        emit AgentUpdate(_agent);
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
     * @notice Strategy liquidation (unfolding mechanism)
     * @dev Abstract function to be implemented by the strategy
     * @param _amount Amount of underlyings to liquidate
     * @param _params Generic callData (e.g., SwapperParams)
     * @return assetsRecovered Amount of assets recovered from the liquidation
     */
    function _liquidate(
        uint256 _amount,
        bytes[] memory _params
    ) internal virtual returns (uint256 assetsRecovered) {}

    /**
     * @dev Reverts if slippage is too high unless panic is true. Extends the functionality of the _liquidate function.
     * @param _amount Amount of underlyings to liquidate
     * @param _minLiquidity Minimum amount of assets to receive
     * @param _panic Set to true to ignore slippage when unfolding
     * @param _params Generic callData (e.g., SwapperParams)
     * @return liquidityAvailable Amount of assets available to unfold
     * @return Total assets in the strategy after unfolding
     */
    function liquidate(
        uint256 _amount,
        uint256 _minLiquidity,
        bool _panic,
        bytes[] memory _params
    )
        external
        onlyKeeper
        nonReentrant
        returns (uint256 liquidityAvailable, uint256)
    {
        liquidityAvailable = available();
        uint256 allocated = _invested();

        // pre-liquidation sharePrice
        uint256 price = sharePrice();
        uint256 underlyingRequests = totalPendingRedemptionRequest().mulDiv(
            price,
            weiPerShare
        );

        // if not in panic, liquidate must fulfill minLiquidity+withdrawal requests
        if (!_panic && _amount <
            AsMaths.max(
                minLiquidity.subMax0(liquidityAvailable + allocated),
                underlyingRequests // pending underlying requests
            )
        ) revert AmountTooLow(_amount);

        // pani or less assets than requested >> liquidate all
        if (_panic || _amount > allocated) {
            _amount = allocated;
        }

        uint256 liquidated = 0;

        // if enough cash, withdraw from the protocol
        if (liquidityAvailable < _amount) {
            // liquidate protocol positions
            liquidated = _liquidate(_amount, _params);
            liquidityAvailable += liquidated;

            // Check that we have enough assets to return
            if ((liquidityAvailable < _minLiquidity) && !_panic)
                revert AmountTooLow(liquidityAvailable);
        }

        totalClaimableUnderlying = AsMaths.min(
            totalUnderlyingRequest,
            totalClaimableUnderlying + liquidated
        );

        totalClaimableRedemption = AsMaths.min(
            totalRedemptionRequest,
            totalClaimableUnderlying.mulDiv(weiPerShare, price)
        );

        last.liquidate = block.timestamp;

        emit Liquidate(liquidated, liquidityAvailable, block.timestamp);
        return (liquidityAvailable, totalAssets());
    }

    /**
     * @notice Amount of rewards available to harvest
     * @dev Abstract function to be implemented by the strategy
     * @return rewardAmounts Amount of reward tokens available
     */
    function _rewardsAvailable()
        public
        view
        virtual
        returns (uint256[] memory rewardAmounts)
    {}

    /**
     * @dev Internal function to liquidate a specified amount, to be implemented by strategies
     * @param _amount Amount to be liquidated
     * @return Amount that was liquidated
     */
    function _liquidateRequest(
        uint256 _amount
    ) internal virtual returns (uint256) {}

    /**
     * @notice Order the withdrawal request in strategies with lock
     * @param _amount Amount of debt to unfold
     * @return assetsRecovered Amount of assets recovered
     */
    function liquidateRequest(
        uint256 _amount
    ) external onlyKeeper returns (uint256) {
        return _liquidateRequest(_amount);
    }

    /**
     * @dev Internal function to harvest rewards, to be implemented by strategies
     * @param _params Generic callData (e.g., SwapperParams)
     * @return amount Amount of underlying assets received (after swap)
     */
    function _harvest(
        bytes[] memory _params
    ) internal virtual returns (uint256 amount) {}

    /**
     * @notice Harvest rewards from the protocol
     * @param _params Generic callData (e.g., SwapperParams)
     * @return amount Amount of underlying assets received (after swap)
     */
    function harvest(bytes[] memory _params) public returns (uint256 amount) {
        amount = _harvest(_params);
        // reset expected profits to updated value + amount
        expectedProfits =
            AsAccounting.unrealizedProfits(
                last.harvest,
                expectedProfits,
                profitCooldown
            ) +
            amount;
        last.harvest = block.timestamp;
        emit Harvest(amount, block.timestamp);
    }

    /**
     * @dev Internal function for investment, to be implemented by specific strategies
     * @param _amount Amount to be invested
     * @param _minIouReceived The minimum IOU (I owe you) to be received from the investment
     * @param _params Additional parameters for the investment, typically passed as generic callData
     * @return investedAmount Actual amount that was invested
     * @return iouReceived The IOU received from the investment
     */
    function _invest(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params
    ) internal virtual returns (uint256 investedAmount, uint256 iouReceived) {}

    /**
     * @notice Inputs prices fetched from price aggregator (e.g., 1inch)
     * @dev Abstract function to be implemented by the strategy
     * @param _amount Amount of inputs to be invested
     * @param _minIouReceived Prices of inputs in underlying
     * @param _params Generic callData (e.g., SwapperParams)
     * @return investedAmount Amount invested in the strategy
     * @return iouReceived IOUs received from the investment
     */
    function invest(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params
    ) public returns (uint256 investedAmount, uint256 iouReceived) {
        if (_amount == 0) _amount = available();
        // generic swap execution
        (investedAmount, iouReceived) = _invest(
            _amount,
            _minIouReceived,
            _params
        );

        emit Invest(_amount, block.timestamp);
        return (investedAmount, iouReceived);
    }

    /**
     * @notice Compounds the strategy using SwapData for both harvest and invest
     * @dev Pass a conservative _amount (e.g., available() + 90% of rewards valued in underlying)
     * to ensure the underlying->inputs swaps
     * @param _amount Amount of underlying to be invested (after harvest)
     * @param _minIouReceived Minimum amount of IOU to be received (after invest)
     * @param _params Generic callData (harvest+invest SwapperParams)
     * @return iouReceived IOUs received from the compound operation
     * @return harvestedRewards Amount of rewards harvested
     */
    function _compound(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params // rewardTokens(0...n)->underling() / underlying()->inputs(0...n) with underlyingWeights(0...n)
    ) internal virtual returns (uint256 iouReceived, uint256 harvestedRewards) {
        // we expect the SwapData to cover harvesting + investing
        if (_params.length != (rewardTokens.length + inputs.length))
            revert InvalidCalldata();

        // harvest using the first calldata bytes (swap rewards->underlying)
        harvestedRewards = harvest(_params.slice(0, rewardTokens.length));

        _amount = AsMaths.min(_amount, available());

        (, iouReceived) = _invest({
            _amount: _amount,
            _minIouReceived: _minIouReceived, // 1 by default
            // invest using the second calldata bytes (swap underlying->inputs)
            _params: _params.slice(rewardTokens.length, _params.length) // new bytes[](0) // no swap data needed
        });
        return (iouReceived, harvestedRewards);
    }

    /**
     * @notice Executes the compound operation in the strategy
     * @param _amount Amount to compound in the strategy
     * @param _minIouReceived Minimum IOU to be received
     * @param _params Generic callData for the compound operation
     * @return iouReceived IOUs received from the compound operation
     * @return harvestedRewards Amount of rewards harvested
     */
    function compound(
        uint256 _amount,
        uint _minIouReceived,
        bytes[] memory _params
    )
        external
        onlyKeeper
        returns (uint256 iouReceived, uint256 harvestedRewards)
    {
        (iouReceived, harvestedRewards) = _compound(
            _amount,
            _minIouReceived,
            _params
        );
        emit Compound(_amount, block.timestamp);
    }

    /**
     * @dev Internal virtual function to set allowances, to be implemented by specific strategies
     * @param _amount Amount for which to set the allowances
     */
    function _setAllowances(uint256 _amount) internal virtual {}

    /**
     * @dev Internal virtual function to swap rewards, to be implemented by specific strategies
     * @param _minAmountsOut Minimum amounts out expected from the swap
     * @param _params Additional parameters for the swap operation, typically passed as generic callData
     * @return amountsOut The total amounts out received from the swap
     */
    function _swapRewards(
        uint256[] memory _minAmountsOut,
        bytes memory _params
    ) internal virtual returns (uint256 amountsOut) {}
}
