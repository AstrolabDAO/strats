// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@astrolabs/swapper/contracts/Swapper.sol";
import "./StrategyAbstractV5.sol";
import "./AsProxy.sol";
import "../libs/AsArrays.sol";
import "../libs/AsMaths.sol";


/// @title StrategyV5 Abstract - inherited by all strategies
/// @author Astrolabs Ltd.
/// @notice All As4626 calls are delegated to the agent (StrategyAgentV5)
/// @dev Ensure memory slots compliance between the agent and StrategyV5 implementations (proxy)
abstract contract StrategyV5 is StrategyAbstractV5, AsProxy {
    using AsMaths for uint256;
    using AsMaths for int256;
    using AsArrays for bytes[];
    using SafeERC20 for IERC20;

    constructor(
        string[3] memory _erc20Metadata
    ) StrategyAbstractV5(_erc20Metadata) {}

    /// @notice Initialize the strategy
    /// @param _fees fees structure
    /// @param _underlying address of the underlying asset
    /// @param _coreAddresses array of core addresses: feeCollector, swapper, allocator, agent
    function init(
        Fees memory _fees,
        address _underlying,
        address[4] memory _coreAddresses
    ) public onlyAdmin {
        setExemption(msg.sender, true);
        // done in As4626 but required for swapper
        stratProxy = address(this);
        underlying = ERC20(_underlying);
        updateSwapper(_coreAddresses[1]);
        allocator = _coreAddresses[2];
        agent = _coreAddresses[3];
        // StrategyAgentV5.init
        _delegateWithSignature(
            agent,
            "init((uint64,uint64,uint64,uint64),address,address)"
        );
    }

    /// @notice Returns the address of the implementation
    function _implementation() internal view override returns (address) {
        return agent;
    }

    /// @notice Sets the reward tokens
    /// @param _rewardTokens array of reward tokens
    function setRewardTokens(
        address[] memory _rewardTokens
    ) public onlyManager {
        for (uint256 i = 0; i < _rewardTokens.length; i++)
            rewardTokens[i] = _rewardTokens[i];
        for (uint256 i = _rewardTokens.length; i < 16; i++)
            rewardTokens[i] = address(0);
    }

    /// @notice Sets the input tokens (strategy internals)
    /// @param _inputs array of input tokens
    /// @param _weights array of input weights
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

    /// @notice Sets the allocator
    function updateAllocator(address _allocator) external onlyManager {
        allocator = _allocator;
        emit AllocatorUpdate(_allocator);
    }

    /// @notice Sets the agent (StrategyAgentV5 implementation)
    function updateAgent(address _agent) external onlyAdmin {
        if (_agent == address(0)) revert AddressZero();
        agent = _agent;
        emit AgentUpdate(_agent);
    }

    /// @notice Sets the swapper allowance
    /// @param _amount amount of allowance to set
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

    /// @notice Change the Swapper address, remove allowances and give new ones
    /// @param _swapper address of the new swapper
    function updateSwapper(address _swapper) public onlyAdmin {
        if (_swapper == address(0)) revert AddressZero();
        if (address(swapper) != address(0)) setSwapperAllowance(0);
        swapper = Swapper(_swapper);
        setSwapperAllowance(MAX_UINT256);
        emit SwapperUpdate(_swapper);
    }

    /// @notice Strategy liquidation (unfolding mechanism)
    /// @dev abstract function to be implemented by the strategy
    /// @param _amount Amount of underlyings to liquidate
    /// @param _params generic callData (eg. SwapperParams)
    function _liquidate(
        uint256 _amount,
        bytes[] memory _params
    ) internal virtual returns (uint256 assetsRecovered) {}

    // @inheritdoc _liquidate
    /// @dev Reverts if slippage is too high unless panic is true
    /// @param _amount Amount of underlyings to liquidate
    /// @param _minLiquidity Minimum amount of assets to receive
    /// @param _panic ignore slippage when unfolding
    /// @param _params generic callData (eg. SwapperParams)
    /// @return liquidityAvailable Amount of assets available to unfold
    /// @return Total assets in the strategy after unfolding
    function liquidate(
        uint256 _amount,
        uint256 _minLiquidity,
        bool _panic,
        bytes[] memory _params
    ) external onlyKeeper returns (uint256 liquidityAvailable, uint256) {

        liquidityAvailable = available();
        uint256 allocated = _invested();

        uint256 newRedemptionRequests = totalRedemptionRequest -
            totalClaimableRedemption;

        _amount += convertToAssets(newRedemptionRequests);

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

        totalClaimableRedemption = maxClaimableRedemption();
        last.liquidate = block.timestamp;

        emit Liquidate(liquidated, liquidityAvailable, block.timestamp);
        return (liquidityAvailable, totalAssets());
    }

    /// @notice Amount of rewards available to harvest
    /// @dev abstract function to be implemented by the strategy
    /// @return rewardAmounts amount of reward tokens available
    function rewardsAvailable()
        public
        view
        virtual
        returns (uint256[] memory rewardAmounts)
    {}

    // implemented by strategies
    function _liquidateRequest(
        uint256 _amount
    ) internal virtual returns (uint256) {}

    /// @notice Order the withdraw request in strategies with lock
    /// @param _amount Amount of debt to unfold
    /// @return assetsRecovered Amount of assets recovered
    function liquidateRequest(
        uint256 _amount
    ) external onlyKeeper returns (uint256) {
        return _liquidateRequest(_amount);
    }

    // implemented by strategies
    function _harvest(
        bytes[] memory _params
    ) internal virtual returns (uint256 amount) {}

    /// @notice Harvest rewards from the protocol
    /// @param _params generic callData (eg. SwapperParams)
    /// @return amount of underlying assets received (after swap)
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

    // implemented by strategies
    function _invest(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params
    ) internal virtual returns (uint256 investedAmount, uint256 iouReceived) {}

    /// @notice Inputs prices fetched from price aggregator (eg. 1inch)
    /// @dev abstract function to be implemented by the strategy
    /// @param _amount amount of inputs to be invested
    /// @param _minIouReceived prices of inputs in underlying
    /// @param _params generic callData (eg. SwapperParams)
    function invest(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params
    ) public returns (uint256 investedAmount, uint256 iouReceived) {
        if (_amount == 0) _amount = available();
        // TODO: check balances before and generic swap
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
     * @dev Pass a conservative _amount (eg. available() + 90% of rewards valued in underlying)
     * in order to ensure the underlying->inputs swaps
     * @param _amount amount of underlying to be invested (after harvest)
     * @param _minIouReceived minimum amount of iou to be received (after invest)
     * @param _params generic callData (harvest+invest SwapperParams)
     */
    function _compound(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params // rewardTokens(0...n)->underling() / underlying()->inputs(0...n) with underlyingWeights(0...n)
    )
        internal
        virtual
        returns (uint256 iouReceived, uint256 harvestedRewards)
    {
        // we expect the SwapData to cover harvesting + investing
        if (_params.length != (rewardTokens.length + inputs.length))
            revert InvalidCalldata();

        // harvest using the first calldata bytes (swap rewards->underlying)
        harvestedRewards = harvest(_params.slice(0, rewardTokens.length));

        // NB: if the underlying balance is < 
        _amount = AsMaths.min(_amount, available());

        (, iouReceived) = _invest({
            _amount: _amount,
            _minIouReceived: _minIouReceived, // 1 by default
            // invest using the second calldata bytes (swap underlying->inputs)
            _params: _params.slice(rewardTokens.length, _params.length) // new bytes[](0) // no swap data needed
        });
        return (iouReceived, harvestedRewards);
    }

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

    function _setAllowances(uint256 _amount) internal virtual {}

    // implemented by strategies
    function _swapRewards(
        uint256[] memory _minAmountsOut,
        bytes memory _params
    ) internal virtual returns (uint256 amountsOut) {}
}
