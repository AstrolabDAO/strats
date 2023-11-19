// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@astrolabs/swapper/contracts/Swapper.sol";
import "./interfaces/IAllocator.sol";
import "./StrategyV5.sol";

contract StrategyDelegatorV5 is StrategyV5 {
    using AsMaths for uint256;
    using AsMaths for int256;
    using SafeERC20 for IERC20;

    constructor(
        string[] memory _erc20Metadata // name,symbol,version (EIP712)
    ) StrategyV5(_erc20Metadata) {}

    function setSwapperAllowance(uint256 _value) external onlyAdmin {
        address swapperAddress = address(swapper);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            IERC20Metadata(rewardTokens[i]).approve(swapperAddress, _value);
        }
        for (uint256 i = 0; i < inputs.length; i++) {
            inputs[i].approve(swapperAddress, _value);
        }
        underlying.approve(swapperAddress, _value);
        emit SwapperAllowanceSet();
    }

    function seedLiquidity(uint256 _seedDeposit, uint256 _maxTotalAssets) external onlyAdmin {

        if (_seedDeposit < (minLiquidity - totalAssets()))
            revert LiquidityTooLow(_seedDeposit);
        // seed the vault with some assets if it's empty
        setMaxTotalAssets(_maxTotalAssets);
        // 1e8 is the minimum amount of assets to seed the vault (1 USDC or .1Gwei ETH)
        // allowance should be given to the vault before calling this function
        uint256 seedDeposit = minLiquidity;
        if (totalSupply() == 0) {
            _deposit(
                seedDeposit,
                msg.sender,
                (seedDeposit * sharePrice()) / weiPerShare
            );
        }
        _unpause();
    }

    /// @notice Rescue any ERC20 token that is stuck in the contract
    function rescueToken(address _token, bool _onlyETH) external onlyAdmin {

        // send any trapped ETH
        payable(msg.sender).transfer(address(this).balance);

        if (_onlyETH) return;

        if (_token == address(underlying)) revert();
        ERC20 tokenToRescue = ERC20(_token);
        uint256 balance = tokenToRescue.balanceOf(address(this));
        tokenToRescue.transfer(msg.sender, balance);
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
                revert AmountTooLow(liquidityAvailable);

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
    ) public override(As4626) returns (uint256 shares) {
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
    ) public onlyInternal returns (uint256) {
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
    function harvest(bytes[] memory _params) public returns (uint256 amount) {
        amount = _harvest(_params);
        emit Harvested(amount, block.timestamp);
    }

    function safeDepositInvest(
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount,
        bytes[] memory _params
    ) external onlyAdmin
        returns (uint256 investedAmount, uint256 iouReceived)
    {
        safeDeposit(_amount, _receiver, _minShareAmount);
        return invest(_amount, _minShareAmount, _params);
    }

    function swapSafeDeposit(
        address _input,
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount,
        bytes memory _params
    ) external returns (uint256 shares) {
        uint256 underlyingAmount = _amount;
        if (_input != address(underlying)) {
            (underlyingAmount,) = swapper.decodeAndSwap(
                _input,
                address(underlying),
                _amount,
                _params
            );
        }
        return safeDeposit(underlyingAmount, _receiver, _minShareAmount);
    }
}
