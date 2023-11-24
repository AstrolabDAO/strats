// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@astrolabs/swapper/contracts/Swapper.sol";
import "./StrategyAbstractV5.sol";
import "hardhat/console.sol";

abstract contract StrategyV5 is StrategyAbstractV5, Proxy {

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

    constructor(string[3] memory _erc20Metadata) StrategyAbstractV5(_erc20Metadata) {}

    function _init(
        Fees memory _fees,
        address _underlying,
        address[] memory _coreAddresses
    ) internal {
        console.log("Strategy.init");
        swapper = Swapper(_coreAddresses[1]);
        allocator = _coreAddresses[2];
        agent = _coreAddresses[3];
        inputs[0] = IERC20Metadata(_underlying);
        // delegatecall to
        // As4626.init(_fees, _underlying, _coreAddresses[0]);
        _delegate(agent);
    }

    function _implementation() internal view override returns (address) {
        return agent;
    }

    function setRewardTokens(
        address[] memory _rewardTokens
    ) external onlyManager {
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            inputs[i] = IERC20Metadata(_rewardTokens[i]);
        }
    }

    function setInputs(
        address[] memory _inputs,
        uint256[] memory _weights
    ) external onlyManager {
        for (uint256 i = 0; i < _inputs.length; i++) {
            inputs[i] = IERC20Metadata(_inputs[i]);
        }
        inputWeights = _weights;
    }

    function updateAllocator(address _allocator) external onlyManager {
        allocator = _allocator;
        emit AllocatorUpdated(_allocator);
    }

    function updateAgent(address _agent) external onlyAdmin {
        if (_agent == address(0)) revert AddressZero();
        agent = _agent;
        emit AgentUpdated(_agent);
    }

    function setSwapperAllowance(uint256 _amount) public onlyAdmin {
        address swapperAddress = address(swapper);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            IERC20Metadata(rewardTokens[i]).approve(swapperAddress, _amount);
        }
        for (uint256 i = 0; i < inputs.length; i++) {
            inputs[i].approve(swapperAddress, _amount);
        }
        underlying.approve(swapperAddress, _amount);
        emit SwapperAllowanceSet(_amount);
    }

    /// @notice Change the Swapper address, remove allowances and give new ones
    function updateSwapper(
        address _swapper
    ) external onlyAdmin {
        if (_swapper == address(0)) revert AddressZero();
        setSwapperAllowance(0); // delegate
        // Set new swapper
        swapper = Swapper(_swapper);
        setSwapperAllowance(MAX_UINT256);
        emit SwapperUpdated(_swapper);
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
    /// @return newTotalAssets Total assets in the strategy after unfolding
    function liquidate(
        uint256 _amount,
        uint256 _minLiquidity,
        bool _panic,
        bytes[] memory _params
    )
        external
        onlyInternal
        returns (uint256 liquidityAvailable, uint256 newTotalAssets)
    {
        liquidityAvailable = available();
        uint256 allocated = _invested();
        newTotalAssets = liquidityAvailable + allocated;

        // panic or less assets than requested >> liquidate all
        if (_panic || allocated < _amount) _amount = allocated;

        // if enough cash, withdraw from the protocol
        if (liquidityAvailable < _amount) {
            // liquidate protocol positions
            uint256 liquidated = _liquidate(_amount, _params);
            liquidityAvailable += liquidated;

            // Check that we have enough assets to return
            if ((liquidityAvailable < _minLiquidity) && !_panic)
                revert AmountTooLow(liquidityAvailable);

            // consider lost the delta (probably due to slippage or exit fees)
            newTotalAssets -= (_amount - liquidated);
        }
        return (liquidityAvailable, newTotalAssets);
    }

    // function safeDeposit(
    //     uint256 _amount,
    //     address _receiver,
    //     uint256 _minShareAmount
    // ) public returns (uint256 shares) {
    //     _delegate(agent);
    // }

    // function safeDepositInvest(
    //     uint256 _amount,
    //     address _receiver,
    //     uint256 _minShareAmount,
    //     bytes[] memory _params
    // ) external onlyAdmin
    //     returns (uint256 investedAmount, uint256 iouReceived)
    // {
    //     safeDeposit(_amount, _receiver, _minShareAmount);
    //     return invest(_amount, _minShareAmount, _params);
    // }

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
    function _withdrawRequest(
        uint256 _amount
    ) internal virtual returns (uint256) {}

    /// @notice Order the withdraw request in strategies with lock
    /// @param _amount Amount of debt to unfold
    /// @return assetsRecovered Amount of assets recovered
    function withdrawRequest(
        uint256 _amount
    ) public onlyInternal returns (uint256) {
        return _withdrawRequest(_amount);
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
        emit Harvested(amount, block.timestamp);
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

        emit Invested(_amount, block.timestamp);
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
    ) external onlyKeeper returns (uint256 iouReceived, uint256 harvestedRewards) {
        (iouReceived, harvestedRewards) = _compound(
            _amount,
            _minIouReceived,
            _params
        );
        emit Compounded(_amount, block.timestamp);
    }

    function _setAllowances(uint256 _amount) internal virtual {}

    // implemented by strategies
    function _swapRewards(
        uint256[] memory _minAmountsOut,
        bytes memory _params
    ) internal virtual returns (uint256 amountsOut) {}

}
