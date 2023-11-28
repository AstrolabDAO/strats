// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@astrolabs/swapper/contracts/Swapper.sol";
import "./StrategyAbstractV5.sol";
import "./AsProxy.sol";

abstract contract StrategyV5 is StrategyAbstractV5, AsProxy {

    using AsMaths for uint256;
    using AsMaths for int256;
    using SafeERC20 for IERC20;

    modifier onlyInternal() {
        internalCheck();
        _;
    }

    function internalCheck() internal view {
        if (!(hasRole(KEEPER_ROLE, msg.sender) || msg.sender == allocator))
            revert Unauthorized();
    }

    constructor(
        string[3] memory _erc20Metadata
    ) StrategyAbstractV5(_erc20Metadata) {}

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

    function _implementation() internal view override returns (address) {
        return agent;
    }

    function setRewardTokens(
        address[] memory _rewardTokens
    ) public onlyManager {
        for (uint256 i = 0; i < _rewardTokens.length; i++)
            rewardTokens[i] = _rewardTokens[i];
        for (uint256 i = _rewardTokens.length; i < 16; i++)
            rewardTokens[i] = address(0);
    }

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

    function updateAllocator(address _allocator) external onlyManager {
        allocator = _allocator;
        emit AllocatorUpdate(_allocator);
    }

    function updateAgent(address _agent) external onlyAdmin {
        if (_agent == address(0)) revert AddressZero();
        agent = _agent;
        emit AgentUpdate(_agent);
    }

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
    function updateSwapper(address _swapper) public onlyAdmin {
        if (_swapper == address(0)) revert AddressZero();
        if (address(swapper) != address(0)) setSwapperAllowance(0);
        swapper = Swapper(_swapper);
        setSwapperAllowance(MAX_UINT256);
        emit SwapperUpdate(_swapper);
    }

    // implemented by strategies
    function _liquidate(
        uint256 _amount,
        bytes[] memory _params
    ) internal virtual returns (uint256 assetsRecovered) {}

    /// @notice Order to unfold the strategy
    /// If we pass "panic", we ignore slippage and withdraw all
    /// @dev The call will revert if the slippage created is too high
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
    ) external onlyInternal returns (uint256 liquidityAvailable, uint256) {

        liquidityAvailable = available();
        uint256 allocated = _invested();

        uint256 newRedemptionRequests =
            totalRedemptionRequest - totalClaimableRedemption;

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

        last.liquidate = block.timestamp;
        totalClaimableRedemption = AsMaths.min(
            totalRedemptionRequest,
            // cash available to all redemptions
            underlying.balanceOf(address(this))
                - claimableUnderlyingFees
                - AsAccounting.unrealizedProfits(
                    last.harvest,
                    expectedProfits,
                    profitCooldown)
        );
        emit Liquidate(liquidated, liquidityAvailable, block.timestamp);
        return (liquidityAvailable, totalAssets());
    }

    // implemented by strategies
    function _rewardsAvailable()
        internal
        view
        virtual
        returns (uint256[] memory rewardAmounts)
    {}

    /// @notice amount of reward tokens available and not yet harvested
    /// @dev abstract function to be implemented by the strategy
    /// @return rewardAmounts amount of reward tokens available
    function rewardsAvailable()
        external
        view
        returns (uint256[] memory rewardAmounts)
    {
        return _rewardsAvailable();
    }

    // implemented by strategies
    function _liquidateRequest(
        uint256 _amount
    ) internal virtual returns (uint256) {}

    /// @notice Order the withdraw request in strategies with lock
    /// @param _amount Amount of debt to unfold
    /// @return assetsRecovered Amount of assets recovered
    function liquidateRequest(
        uint256 _amount
    ) public onlyInternal returns (uint256) {
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

    // implemented by strategies
    function _compound(
        uint256 _amount,
        uint256 minIouReceived,
        bytes[] memory _params
    )
        internal
        virtual
        returns (uint256 iouReceived, uint256 harvestedRewards)
    {}

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
