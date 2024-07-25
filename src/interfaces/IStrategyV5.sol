// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./IStrategyV5Agent.sol";
import "./IAsProxy.sol";

interface IStrategyV5 is IStrategyV5Agent, IAsProxy {
  // Events
  event Harvest(uint256 assetsReceived, uint64 timestamp);

  function simulate(bytes calldata _data) external returns (bytes memory response);
  function agent() external view returns (address);
  function setParams(bytes memory _params) external;
  function init(StrategyParams memory _params) external;
  function rewardsAvailable() external view returns (uint256[] memory);
  function invested(uint256 _index) external view returns (uint256);
  function invested() external view returns (uint256);
  function available() external view returns (uint256);
  function updateAgent(address _agent) external;
  function preview(uint256 _amount, bool _investing) external returns (uint256[8] memory amounts);
  function previewSwapAddons(uint256[] calldata _amounts) external returns (address[] memory from, address[] memory to, uint256[] memory amounts);
  function invest(
    uint256[8] calldata _amounts,
    bytes[] calldata _params
  ) external returns (uint256 totalInvested);
  function liquidate(
    uint256[8] calldata _amounts,
    uint256 _minLiquidity,
    bool _panic,
    bytes[] calldata _params
  ) external returns (uint256 totalRecovered);
  function liquidateRequest(uint256 _amount) external returns (uint256);
  function claimRewards() external returns (uint256[] memory);
  function harvest(bytes[] calldata _params) external returns (uint256 assetsReceived);
  function compound(
    uint256[8] calldata _amounts,
    bytes[] calldata _harvestParams,
    bytes[] calldata _investParams
  ) external returns (uint256 totalHarvested, uint256 totalInvested);
  function updateAsset(
    address _asset,
    bytes memory _swapData,
    uint256 _exchangeRateBp
  ) external;
  function updateAsset(address _asset, bytes memory _swapData) external;
}
