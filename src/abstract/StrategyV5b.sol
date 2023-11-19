// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StrategyV5.sol";
import "./StrategyDelegatorV5.sol";

// StrategyV5 + StrategyDelegatorV5 delegator
abstract contract StrategyV5b is StrategyV5 {

    StrategyDelegatorV5 private deleg;

    constructor(
        string[] memory _erc20Metadata // name,symbol,version (EIP712)
    ) StrategyV5(_erc20Metadata) {}

    function _initialize(
        Fees memory _fees,
        address _underlying,
        address[] memory _coreAddresses
    ) internal override {
        StrategyV5._initialize(_fees, _underlying, _coreAddresses);
        deleg = StrategyDelegatorV5(payable(_coreAddresses[3]));
    }

    function setDelegator(address _delegator) external onlyAdmin {
        if (_delegator == address(0)) revert AddressZero();
        deleg = StrategyDelegatorV5(payable(_delegator));
    }

    /// @notice Change the Swapper address, remove allowances and give new ones
    function updateSwapper(
        address _swapper
    ) external onlyAdmin {
        if (_swapper == address(0)) revert AddressZero();
        deleg.setSwapperAllowance(0);
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

    function _setSwapperAllowance(uint256 _value) internal virtual {
        return deleg.setSwapperAllowance(_value);
    }

    function seedLiquidity(uint256 _seedDeposit, uint256 _maxTotalAssets)
        external onlyAdmin
    {
        return deleg.seedLiquidity(_seedDeposit, _maxTotalAssets);
    }

    function rescueToken(address _token, bool _onlyETH) external onlyAdmin {
        return deleg.rescueToken(_token, _onlyETH);
    }

    function swapSafeDeposit(
        address _input,
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount,
        bytes memory _params
    ) external returns (uint256 shares) {
        return deleg.swapSafeDeposit(_input, _amount, _receiver, _minShareAmount, _params);
    }

    // delegate calls to StrategyDelegatorV5
    function safeDepositInvest(
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount,
        bytes[] memory _params
    ) external onlyKeeper
        returns (uint256 investedAmount, uint256 iouReceived)
    {
        return deleg.safeDepositInvest(_amount, _receiver, _minShareAmount, _params);
    }

}
