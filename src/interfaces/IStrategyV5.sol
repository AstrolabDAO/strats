// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IStrategyV5Agent.sol";
import "./IAsProxy.sol";
import "./IAsRescuable.sol";

interface IStrategyV5 is IStrategyV5Agent, IAsProxy, IAsRescuable {
  // Custom types defined in StrategyV5Abstract and StrategyV5
  struct AgentStorageExt {
    address delegator;
    uint256 maxLoan;
    uint256 totalLent;
  }

  // Errors defined in StrategyV5Abstract
  error InvalidOrStaleValue(uint256 updateTime, int256 value);

  // Events defined in StrategyV5Abstract
  event Invest(uint256 amount, uint256 timestamp);
  event Harvest(uint256 amount, uint256 timestamp);
  event Liquidate(uint256 amount, uint256 liquidityAvailable, uint256 timestamp);

  // Interface methods
  function updateAgent(address _agent) external;
  function liquidateRequest(uint256 _amount) external returns (uint256);
  function invest(
    uint256[8] calldata _amounts,
    bytes[] calldata _params
  ) external returns (uint256 investedAmount, uint256 iouReceived);
  function liquidate(
    uint256[8] calldata _amounts,
    uint256 _minLiquidity,
    bool _panic,
    bytes[] calldata _params
  ) external returns (uint256 assetsRecovered);
  function claimRewards() external returns (uint256[] memory);
  function harvest(bytes[] calldata _params) external returns (uint256 assetsReceived);
  function rewardsAvailable() external view returns (uint256[] memory);
  function compound(
    uint256[8] calldata _amounts,
    bytes[] calldata _harvestParams,
    bytes[] calldata _investParams
  ) external returns (uint256 iouReceived, uint256 harvestedRewards);
  function requestRescue(address _token) external;
  function rescue(address _token) external;

  function invested(uint256 _index) external view returns (uint256);
  function invested() external view returns (uint256);
  function available() external view returns (uint256);

  function setInputs(address[] calldata _inputs, uint16[] calldata _weights) external;
  function updateAsset(
    address _asset,
    bytes calldata _swapData,
    uint256 _priceFactor
  ) external;

  function previewLiquidate(uint256 _amount) external returns (uint256[8] memory amounts);
  function previewInvest(uint256 _amount) external returns (uint256[8] memory amounts);
}
