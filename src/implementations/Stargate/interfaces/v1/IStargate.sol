// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface ILPStaking {
  struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
  }

  struct PoolInfo {
    address lpToken;
    uint256 allocPoint;
    uint256 lastRewardBlock;
    uint256 accStargatePerShare;
  }

  function poolInfo(uint256 _index) external view returns (PoolInfo memory);
  function userInfo(uint256 _pid, address _user) external view returns (UserInfo memory);
  function stargate() external view returns (address);
  function deposit(uint256 _pid, uint256 _amount) external;
  function withdraw(uint256 _pid, uint256 _amount) external;
  function massUpdatePools() external;
  function updatePool(uint256 _pid) external;
  function pendingStargate(uint256 _pid, address _user) external view returns (uint256);
}

interface IPool {
  function router() external view returns (address);
  function poolId() external view returns (uint256);
  function token() external view returns (address);
  function totalLiquidity() external view returns (uint256);
  function totalSupply() external view returns (uint256);
  function deltaCredit() external view returns (uint256);
  function convertRate() external view returns (uint256);
  function amountLPtoLD(uint256 _amountLP) external view returns (uint256);
  function balanceOf(address user) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function decimals() external view returns (uint8);
  function localDecimals() external view returns (uint8);
}

interface IStargateRouter {
  function addLiquidity(uint256 _poolId, uint256 _amountLD, address _to) external;
  function instantRedeemLocal(
    uint16 _srcPoolId,
    uint256 _amountLP,
    address _to
  ) external returns (uint256);
  function callDelta(uint256 _poolId, bool _fullMode) external;
  function setDeltaParam(
    uint256 _poolId,
    bool _batched,
    uint256 _swapDeltaBP,
    uint256 _lpDeltaBP,
    bool _defaultSwapMode,
    bool _defaultLPMode
  ) external;
  function sendCredits(
    uint16 _dstChainId,
    uint256 _srcPoolId,
    uint256 _dstPoolId,
    address payable _refundAddress
  ) external;
  function setFees(uint256 _poolId, uint256 _mintFeeBP) external;
}
