// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStakingRewards {
    // Public variables as external view functions
    function rewardsToken() external view returns (address);
    function stakingToken() external view returns (address);
    function periodFinish() external view returns (uint256);
    function rewardRate() external view returns (uint256);
    function rewardsDuration() external view returns (uint256);
    function lastUpdateTime() external view returns (uint256);
    function rewardPerTokenStored() external view returns (uint256);
    function userRewardPerTokenPaid(address) external view returns (uint256);
    function rewards(address) external view returns (uint256);

    // External and public view functions
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function lastTimeRewardApplicable() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function getRewardForDuration() external view returns (uint256);

    // External and public mutative functions
    function stakeWithPermit(uint256 amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function exit() external;
    function notifyRewardAmount(uint256 reward) external;

    // Events
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}

