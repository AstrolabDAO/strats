// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IStrategyV5.sol";
import "./StrategyAbstractV5.sol";
import "./As4626.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title StrategyAgentV5 Implementation - back-end contract proxied-to by strategies
 * @author Astrolab DAO
 * @notice This contract is in charge of executing shared strategy logic (accounting, fees, etc.)
 * @dev Make sure all state variables are in StrategyAbstractV5 to match proxy/implementation slots
 */
contract StrategyAgentV5 is StrategyAbstractV5, As4626 {

    using AsMaths for uint256;
    using AsMaths for int256;
    using SafeERC20 for IERC20;

    string[3] DEFAULT_CONSTRUCT = ["", "", ""];

    constructor() StrategyAbstractV5(DEFAULT_CONSTRUCT) {}

    /**
     * @dev Initialize the contract after deployment. Overrides an existing 'init' function from a base contract.
     * @param _fees Structure representing various fees for the contract
     * @param _underlying Address of the underlying asset
     * @param _feeCollector Address of the fee collector
     */
    function init(
        Fees memory _fees,
        address _underlying,
        address _feeCollector
    ) public override onlyAdmin {
        As4626.init(_fees, _underlying, _feeCollector);
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
     * @notice Invests an amount into the strategy via the proxy
     * @dev Delegates the call to the 'invest' function in the IStrategyV5 contract through stratProxy
     * @param _amount The amount to be invested
     * @param _minIouReceived The minimum IOU (I Owe You) to be received from the investment
     * @param _params Additional parameters for the investment, typically passed as generic callData
     * @return investedAmount The actual amount that was invested
     * @return iouReceived The IOU received from the investment
     */
    function invest(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params
    ) public returns (uint256 investedAmount, uint256 iouReceived) {
        return
            IStrategyV5(stratProxy).invest(_amount, _minIouReceived, _params);
    }

    /**
     * @notice Rescue any ERC20 token or ETH that is stuck in the contract
     * @dev Transfers out all ETH from the contract to the sender, and if `_onlyETH` is false, it also transfers the specified ERC20 token
     * @param _token The address of the ERC20 token to be rescued. Ignored if `_onlyETH` is true
     * @param _onlyETH If true, only rescues ETH and ignores ERC20 tokens
     */
    function rescueToken(address _token, bool _onlyETH) external onlyAdmin {
        // send any trapped ETH
        payable(msg.sender).transfer(address(this).balance);

        if (_onlyETH) return;

        if (_token == address(underlying)) revert();
        ERC20 tokenToRescue = ERC20(_token);
        uint256 balance = tokenToRescue.balanceOf(address(this));
        tokenToRescue.transfer(msg.sender, balance);
    }

    /**
     * @notice Withdraw assets denominated in underlying
     * @dev Beware, there's no slippage control - use safeWithdraw if you want it. Overrides the withdraw function in As4626.
     * @param _amount The amount of underlying assets to withdraw
     * @param _receiver The address where the withdrawn assets should be sent
     * @param _owner The owner of the shares being withdrawn
     * @return shares The amount of shares burned in the withdrawal process
     */
    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) public override(As4626) returns (uint256 shares) {
        // This represents the amount of shares that we're about to burn
        shares = convertToShares(_amount);
        _withdraw(_amount, shares, 0, _receiver, _owner);
    }

    /**
     * @dev Overloaded version of withdraw with slippage control. It includes an additional parameter for minimum asset amount control.
     * @param _amount The amount of underlying assets to withdraw
     * @param _minAmount The minimum amount of assets we'll accept to mitigate slippage
     * @param _receiver The address where the withdrawn assets should be sent
     * @param _owner The owner of the shares being withdrawn
     * @return shares The amount of shares burned in the withdrawal process
     */
    function safeWithdraw(
        uint256 _amount,
        uint256 _minAmount,
        address _receiver,
        address _owner
    ) public override returns (uint256 shares) {
        // This represents the amount of shares that we're about to burn
        shares = convertToShares(_amount); // We take fees here
        _withdraw(_amount, shares, _minAmount, _receiver, _owner);
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

    /**
     * @notice Deposits an amount and then invests it, with control over the minimum share amount
     * @dev This function first makes a safe deposit and then invests the deposited amount.
     *      It is restricted to onlyAdmin for execution.
     * @param _amount The amount to be deposited and invested
     * @param _receiver The address where the shares from the deposit should be sent
     * @param _minShareAmount The minimum amount of shares expected from the deposit, used for slippage control
     * @param _params Additional parameters for the investment process
     * @return investedAmount The amount that was actually invested
     * @return iouReceived The IOU received from the investment
     */
    function safeDepositInvest(
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount,
        bytes[] memory _params
    ) external onlyAdmin returns (uint256 investedAmount, uint256 iouReceived) {
        safeDeposit(_amount, _receiver, _minShareAmount);
        return invest(_amount, _minShareAmount, _params);
    }
}
