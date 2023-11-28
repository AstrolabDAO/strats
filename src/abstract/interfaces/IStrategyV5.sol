// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IAs4626.sol";

interface IStrategyV5 is IAs4626 {
    function rewardsAvailable() external view returns (uint256[] memory rewardAmounts);
    function invest(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] calldata _params
    ) external returns (uint256 investedAmount, uint256 iouReceived);
    function swapSafeDeposit(
        address _input,
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount,
        bytes calldata _params
    ) external returns (uint256 shares);
    function safeDepositInvest(
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount,
        bytes[] calldata _params
    ) external returns (uint256 investedAmount, uint256 iouReceived);
    function harvest(bytes[] calldata _params) external returns (uint256 amount);
    function compound(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] calldata _params
    ) external returns (uint256 iouReceived, uint256 harvestedRewards);
    function liquidate(
        uint256 _amount,
        uint256 _minLiquidity,
        bool _panic,
        bytes[] calldata _params
    ) external returns (uint256 liquidityAvailable, uint256);
    function liquidateRequest(uint256 _amount) external returns (uint256);
    function rescueToken(address _token, bool _onlyETH) external;
}
