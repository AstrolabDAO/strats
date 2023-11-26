// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@astrolabs/swapper/contracts/Swapper.sol";
import "./interfaces/IAllocator.sol";
import "./StrategyAbstractV5.sol";
import "./As4626.sol";
import "hardhat/console.sol";

contract StrategyAgentV5 is StrategyAbstractV5, As4626 {

    using AsMaths for uint256;
    using AsMaths for int256;
    using SafeERC20 for IERC20;

    string[3] DEFAULT_CONSTRUCT = ["", "", ""];

    constructor() StrategyAbstractV5(DEFAULT_CONSTRUCT) {}

    /**
     * @dev Initialize the contract after deployment.
     */
    function init(
        Fees memory _fees,
        address _underlying,
        address _feeCollector
    ) public override onlyAdmin {
        console.log("StrategyAgentV5.init");
        As4626.init(_fees, _underlying, _feeCollector);
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
