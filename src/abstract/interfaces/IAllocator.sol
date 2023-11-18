// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAllocator {

	struct Strategy {
		string strategyName;
		bool whitelisted;
		bool panicked;
		uint256 maxDeposit;
		uint256 debt;
	}

	struct StrategyMap {
		string strategyName;
		uint256 maxDeposit;
		uint256 debt;
		uint256 totalAssetsAvailable;
		address entryPoint;
	}

    // Events
    event Withdraw(uint256 request, uint256 recovered, address receiver);
    event ChainDebtUpdate(uint256 newDebt);
    event StrategyAdded(address entryPoint, uint256 maxDeposit, string strategyName);
    event MaxDepositUpdated(address strategyAddress, uint256 maxDeposit);
    event StratPositionUpdated(uint256 currentIndex, uint256 newIndex, address stratAddress);
    event BridgeSuccess(uint256 amount, uint256 crateChainId);
    event StrategyUpdate(address strategy, uint256 newDebt);
    event DepositInStrategy(uint256 amount, address strategy);
    event Losses(address strategy, uint256 loss, uint256 amountMoved);
    event BridgeUpdated(address newBridge);
    event PanicLiquidate(address strategy);
    event PanicSet(address strategy, bool panicked);

    // Errors
    error CantUpdateCrate();
    error NotWhitelisted();
    error MaxDepositReached(address strategy);
    error StrategyAlreadyExists();
    error AddressIsZero();
    error AddressIsNotContract();
    error IncorrectArrayLengths();
    error StrategyPanicked(address strategy);

    // Functions
    function bridgeBackFunds(uint256 _amount, uint256 _minAmount) external payable; // Send back funds to the crate
    function liquidateStrategy(uint256 _amount, uint256 _minAmountOut, address _strategy) external; // Liquidate a strategy partially
    function panicLiquidateStrategy(address _strategy) external; // Liquidate a strategy completely in panic mode
    function retireStrategy(address _strategy) external; // Close a malfunctioning, loss-incurring, or unused strategy
    function dispatchAssets(uint256[] calldata _amounts, address[] calldata _strategies) external; // Dispatch assets to multiple strategies
    function updateStrategyDebt(uint256 _newDebt) external; // Allows a strategy to update its debt
    function updateCrate() external payable; // Communicate total assets to the crate
    function setBridge(address _newBridgeConnector) external; // Set a new bridge connector
    function addNewStrategy(address _entryPoint, uint256 _maxDeposit, string calldata _strategyName) external; // Add a new strategy
    function setMaxDeposit(address _strategyAddress, uint256 _maxDeposit) external; // Change maximum deposit amount for a strategy
    function setPanicked(address _strategyAddress, bool _panicked) external; // Set the panicked state of a strategy
    function totalChainDebt() external view returns (uint256); // View total amount managed by the allocator
    function strategyMap() external view returns (StrategyMap[] memory); // View synthetic representation of strategies
}
