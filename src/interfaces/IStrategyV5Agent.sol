// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@astrolabs/swapper/contracts/interfaces/ISwapper.sol";
import "./IWETH9.sol";
import "./IAsFlashLender.sol";
import "./IAsPriceAware.sol";
import "./IAs4626.sol";

interface IStrategyV5Agent is IAs4626, IAsFlashLender, IAsPriceAware {
  // Structs
  struct AgentStorage {
    address delegator;
  }

  // Events
  event Invest(uint256 amount, uint256 timestamp);
  event Harvest(uint256 amount, uint256 timestamp);
  event Liquidate(uint256 amount, uint256 liquidityAvailable, uint256 timestamp);

  // State variables (As4626 extension)
  function _wgas() external view returns (IWETH9);
  function swapper() external view returns (ISwapper);

  function inputs(uint256 index) external view returns (IERC20Metadata);
  function inputWeights(uint256 index) external view returns (uint16);
  function lpTokens(uint256 index) external view returns (IERC20Metadata);
  function rewardTokens(uint256 index) external view returns (address);

  function init(StrategyParams memory _data) external;
  function proxyType() external pure returns (uint256);
  function setExemption(address _account, bool _isExempt) external;
  function setSwapperAllowance(
    uint256 _amount,
    bool _inputs,
    bool _rewards,
    bool _asset
  ) external;
  function updateSwapper(address _swapper) external;
  function updateAsset(
    address _asset,
    bytes memory _swapData,
    uint256 _exchangeRateBp
  ) external;
  function setInputWeights(uint16[] memory _weights) external;
  function setInputs(
    address[] calldata _inputs,
    uint16[] calldata _weights,
    address[] calldata _lpTokens
  ) external;
  function setRewardTokens(address[] memory _rewardTokens) external;
  function available() external view returns (uint256);
  function availableClaimable() external view returns (uint256);
  function totalAssets() external view returns (uint256);
  function maxRedeem(address _owner) external view returns (uint256);
}
