// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGaugeV2CL {
  // Events (All events from the ABI)
  event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);
  event Deposit(address indexed user, uint256 amount);
  event Harvest(address indexed user, uint256 reward);
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );
  event RewardAdded(uint256 reward);
  event Withdraw(address indexed user, uint256 amount);

  // Constants (From the ABI)
  function DURATION() external pure returns (uint256); // Constant duration

  // View Functions (Read-only functions)
  function DISTRIBUTION() external view returns (address);

  function TOKEN() external view returns (address);

  function _VE() external view returns (address);

  function _balances(address) external view returns (uint256);

  function _periodFinish() external view returns (uint256);

  function _totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function earned(address account) external view returns (uint256);

  function emergency() external view returns (bool);

  function external_bribe() external view returns (address);

  function feeVault() external view returns (address);

  function fees0() external view returns (uint256);

  function fees1() external view returns (uint256);

  function gaugeRewarder() external view returns (address);

  function internal_bribe() external view returns (address);

  function lastTimeRewardApplicable() external view returns (uint256);

  function lastUpdateTime() external view returns (uint256);

  function owner() external view returns (address);

  function periodFinish() external view returns (uint256);

  function rewardForDuration() external view returns (uint256);

  function rewardPerToken() external view returns (uint256);

  function rewardPerTokenStored() external view returns (uint256);

  function rewardRate() external view returns (uint256);

  function rewardToken() external view returns (address);

  function rewarderPid() external view returns (uint256);

  function rewards(address) external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function userRewardPerTokenPaid(address) external view returns (uint256);

  // State-Changing Functions
  function activateEmergencyMode() external;

  function claimFees() external returns (uint256 claimed0, uint256 claimed1);

  function deposit(uint256 amount) external;

  function depositAll() external;

  function emergencyWithdraw() external;

  function emergencyWithdrawAmount(uint256 _amount) external;

  function getReward() external;

  function getReward(address _user) external;

  function notifyRewardAmount(address token, uint256 reward) external;

  function renounceOwnership() external;

  function setDistribution(address _distribution) external;

  function setFeeVault(address _feeVault) external;

  function setGaugeRewarder(address _gaugeRewarder) external;

  function setInternalBribe(address _int) external;

  function setRewarderPid(uint256 _pid) external;

  function stopEmergencyMode() external;

  function transferOwnership(address newOwner) external;

  function withdraw(uint256 amount) external;

  function withdrawAll() external;

  function withdrawAllAndHarvest() external;
}
