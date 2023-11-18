// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@astrolabs/swapper/contracts/Swapper.sol";
import "./interfaces/IAllocator.sol";
import "./As4626.sol";

abstract contract StrategyV5 is As4626 {
    using AsMaths for uint256;
    using AsMaths for int256;
    using SafeERC20 for IERC20;

    event Harvested(uint256 amount, uint256 timestamp);
    event Compounded(uint256 amount, uint256 timestamp);
    event Invested(uint256 amount, uint256 timestamp);
    event SwapperUpdated(address indexed swapper);
    event SwapperAllowanceReset();
    event SwapperAllowanceSet();

    error FailedToSwap(string reason);

    address public allocator;
    uint256 public lastHarvest;

    // inputs are assets being used to farm, asset is swapped into inputs
    IERC20[16] public inputs;
    // inputs weight in bps vs underlying asset
    // (eg. 80% USDC, 20% DAI -> [8000, 2000] ->
    // swap 20% USDC->DAI on deposit, swap 20% DAI->USDC on withdraw)
    uint256[] public inputWeights;

    // reward tokens are the tokens harvested at compound and liquidate times
    // available reward amounts are available rewardsAvailable()
    // and swapped back into inputs at compound of liquidate time////
    address[16] public rewardTokens;
    Swapper public swapper;

    constructor(
        Fees memory _fees, // perfFee, mgmtFee, entryFee, exitFee in bps 100% = 10000
        address _underlying, // The asset we are using
        address[] memory _coreAddresses,
        string[] memory _erc20Metadata // name,symbol,version (EIP712)
    ) As4626(_fees, _underlying, _coreAddresses[0], _erc20Metadata) {
        swapper = Swapper(_coreAddresses[1]);
        allocator = _coreAddresses[2];
        inputs[0] = IERC20(underlying);
    }

    modifier onlyInternal() {
        internalCheck();
        _;
    }

    function internalCheck() internal view {
        if (!(hasRole(KEEPER_ROLE, msg.sender) || msg.sender == allocator))
            revert Unauthorized();
    }

    function setRewardTokens(
        address[] memory _rewardTokens
    ) external onlyManager {
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            inputs[i] = IERC20(_rewardTokens[i]);
        }
    }

    function setInputs(
        address[] memory _inputs,
        uint256[] memory _weights
    ) external onlyManager {
        for (uint256 i = 0; i < _inputs.length; i++) {
            inputs[i] = IERC20(_inputs[i]);
        }
        inputWeights = _weights;
    }

    function setAllocator(address _allocator) external onlyManager {
        allocator = _allocator;
    }

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
        uint256 allocated = invested();
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
                revert SlippageTooHigh(liquidityAvailable, _minLiquidity);

            // consider lost the delta (probably due to slippage or exit fees)
            newTotalAssets -= (_amount - liquidated);
        }
        return (liquidityAvailable, newTotalAssets);
    }

    // @inheritdoc _withdraw
    /// @notice Withdraw assets denominated in underlying
    /// @dev Beware, there's no slippage control - use safeWithdraw if you want it
    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) external override(As4626) returns (uint256 shares) {
        // This represents the amount of shares that we're about to burn
        shares = convertToShares(_amount);
        _withdraw(_amount, shares, 0, _receiver, _owner);
        if (_receiver == address(allocator))
            IAllocator(allocator).updateStrategyDebt(assetsOf(_receiver));
    }

    // @inheritdoc withdraw
    /// @dev Overloaded version with slippage control
    /// @param _minAmount The minimum amount of assets we'll accept
    function safeWithdraw(
        uint256 _amount,
        uint256 _minAmount,
        address _receiver,
        address _owner
    ) public override returns (uint256 shares) {
        // This represents the amount of shares that we're about to burn
        shares = convertToShares(_amount); // We take fees here
        _withdraw(_amount, shares, _minAmount, _receiver, _owner);
        if (_receiver == address(allocator))
            IAllocator(allocator).updateStrategyDebt(assetsOf(_receiver));
    }

    // TODO: implement liquidateWithdraw()

    /// @notice Order the withdraw request in strategies with lock
    /// @param _amount Amount of debt to unfold
    /// @return assetsRecovered Amount of assets recovered
    // TODO: Check when StratV5 is done that it works with locked strats
    function withdrawRequest(
        uint256 _amount
    ) external onlyInternal returns (uint256) {
        return _withdrawRequest(_amount);
    }

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

    /// @notice Harvest rewards from the protocol
    /// @param _params generic callData (eg. SwapperParams)
    /// @return amount of underlying assets received (after swap)
    function harvest(bytes[] memory _params) external returns (uint256 amount) {
        amount = _harvest(_params);
        emit Harvested(amount, block.timestamp);
    }

    /// @notice Compound assets in the protocol
    /// @dev abstract function to be implemented by the strategy
    /// @param _amount amount of assets to be compounded
    /// @param _params generic callData (eg. SwapperParams)
    function compound(
        uint256 _amount,
        uint _minIouReceived,
        bytes[] memory _params
    ) external returns (uint256 iouReceived, uint256 harvestedRewards) {
        (iouReceived, harvestedRewards) = _compound(
            _amount,
            _minIouReceived,
            _params
        );
        emit Compounded(_amount, block.timestamp);
    }

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

    /// @notice Change the Swapper address, remove allowances and give new ones
    function updateSwapper(
        address _swapper
    ) external onlyAdmin {
        if (_swapper == address(0)) revert AddressZero();
        _setSwapperAllowance(0);
        // Set new swapper
        swapper = Swapper(_swapper);
        _setSwapperAllowance(MAX_UINT256);
        emit SwapperUpdated(_swapper);
    }


    /// @notice Give allowances for the Swapper
    /// @param _value amount of allowances to give
    function setSwapperAllowance(uint256 _value) external onlyAdmin {
        _setSwapperAllowance(_value);
    }

    /// @notice Give allowances for the Swapper
    function _setSwapperAllowance(uint256 _value) internal {
        address swapperAddress = address(swapper);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            IERC20(rewardTokens[i]).approve(swapperAddress, _value);
        }
        for (uint256 i = 0; i < inputs.length; i++) {
            inputs[i].approve(swapperAddress, _value);
        }
        underlying.approve(swapperAddress, _value);
        emit SwapperAllowanceSet();
    }

    /// @notice deposits and invests liquidity in one transaction
    /// @param _amount amount of underlying to be deposited
    /// @param _minShareAmount minimum amount of shares to be minted
    /// @param _params generic callData (eg. SwapperParams)
    /// @return investedAmount in underlying tokens and iouReceived
    function safeDepositInvest(
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount,
        bytes[] memory _params
    )
        external
        onlyKeeper
        returns (uint256 investedAmount, uint256 iouReceived)
    {
        safeDeposit(_amount, _receiver, _minShareAmount);
        return invest(_amount, _minShareAmount, _params);
    }

    /// @notice deposits and invests liquidity in one transaction
    /// @param _input asset to be swapped into underlying
    /// @param _amount amount of _input to be swapped
    /// @param _minShareAmount minimum amount of shares to be minted
    /// @param _params encoded routerAddress+minAmount+callData (from SwapperParams)
    function swapSafeDeposit(
        address _input,
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount,
        bytes memory _params
    ) external onlyKeeper returns (uint256 shares) {
        uint256 underlyingAmount = _amount;
        if (_input != address(underlying)) {
            underlyingAmount = swapper.decodeAndSwap(
                _input,
                underlying,
                _amount,
                _params
            );
        }
        return safeDeposit(underlyingAmount, _receiver, _minShareAmount);
    }

    /// Abstract functions to be implemented by the strategy

    /// @notice withdraw assets from the protocol
    /// @param _amount amount of assets to withdraw
    /// @param _params generic callData (eg. SwapperParams)
    /// @return assetsRecovered amount of assets withdrawn
    function _liquidate(
        uint256 _amount,
        bytes[] memory _params
    ) internal virtual returns (uint256 assetsRecovered) {}

    function _withdrawRequest(
        uint256 _amount
    ) internal virtual returns (uint256) {}

    function _harvest(
        bytes[] memory _params
    ) internal virtual returns (uint256 amount) {}

    function _invest(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params
    ) internal virtual returns (uint256 investedAmount, uint256 iouReceived) {}

    function _compound(
        uint256 _amount,
        uint256 minIouReceived,
        bytes[] memory _params
    )
        internal
        virtual
        returns (uint256 iouReceived, uint256 harvestedRewards)
    {}

    function decodeSwapperParams(
        bytes memory _params
    )
        internal
        pure
        returns (address target, uint256 minAmount, bytes memory callData)
    {
        return abi.decode(_params, (address, uint256, bytes));
    }

    function _rewardsAvailable()
        internal
        view
        virtual
        returns (uint256[] memory rewardAmounts)
    {}

    function _setAllowances(uint256 _amount) internal virtual {}

    function _swapRewards() internal virtual {}

    function _swapRewards(
        uint256[] memory _minAmountsOut,
        bytes memory _params
    ) internal virtual returns (uint256 amountsOut) {}
}
