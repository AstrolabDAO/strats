// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IClearingV2 {
  // Structs
  struct Position {
    bool customRatio;
    bool customTwap;
    bool ratioRemoved;
    bool depositOverride;
    bool twapOverride;
    uint8 version;
    uint32 twapInterval;
    uint256 priceThreshold;
    uint256 deposit0Max;
    uint256 deposit1Max;
    uint256 maxTotalSupply;
    uint256 fauxTotal0;
    uint256 fauxTotal1;
    uint256 customDepositDelta;
  }

  // Events
  event CustomDeposit(address, uint256, uint256, uint256);
  event CustomRatio(address pos, uint256 fauxTotal0, uint256 fauxTotal1);
  event DeltaScaleSet(uint256 _deltaScale);
  event DepositDeltaSet(uint256 _depositDelta);
  event DepositOverrideSet(address pos, bool depositOverride);
  event ListAppended(address pos, address[] listed);
  event ListRemoved(address pos, address listed);
  event PositionAdded(address, uint8);
  event PriceThresholdPosSet(address pos, uint256 _priceThreshold);
  event PriceThresholdSet(uint256 _priceThreshold);
  event RatioRemoved(address pos);
  event TwapCheckSet(bool twapCheck);
  event TwapIntervalSet(uint32 _twapInterval);
  event TwapOverrideSet(
    address pos,
    bool twapOverride,
    uint32 _twapInterval,
    uint256 _priceThreshold
  );

  // View Functions
  function PRECISION() external view returns (uint256);

  function applyRatio(
    address pos,
    address token,
    uint256 total0,
    uint256 total1
  ) external view returns (uint256 ratioStart, uint256 ratioEnd);

  function checkPriceChange(
    address pos,
    uint32 _twapInterval,
    uint256 _priceThreshold
  ) external view returns (uint256 price);

  function clearDeposit(
    uint256 deposit0,
    uint256 deposit1,
    address from,
    address to,
    address pos,
    uint256[4] memory minIn
  ) external view returns (bool cleared);

  function clearShares(
    address pos,
    uint256 shares
  ) external view returns (bool cleared);

  function deltaScale() external view returns (uint256);

  function depositDelta() external view returns (uint256);

  function freeDepositList(address, address) external view returns (bool);

  function getDepositAmount(
    address pos,
    address token,
    uint256 _deposit
  ) external view returns (uint256 amountStart, uint256 amountEnd);

  function getListed(address pos, address i) external view returns (bool);

  function getPositionInfo(address pos) external view returns (Position memory);

  function getSqrtTwapX96(
    address pos,
    uint32 _twapInterval
  ) external view returns (uint160 sqrtPriceX96);

  function owner() external view returns (address);

  function paused() external view returns (bool);

  function positions(address) external view returns (Position memory);

  function priceThreshold() external view returns (uint256);

  function twapCheck() external view returns (bool);

  function twapInterval() external view returns (uint32);

  // State-Changing Functions
  function addPosition(address pos, uint8 version) external;

  function appendList(address pos, address[] memory listed) external;

  function customDeposit(
    address pos,
    uint256 deposit0Max,
    uint256 deposit1Max,
    uint256 maxTotalSupply,
    uint256 customDepositDelta
  ) external;

  function customRatio(
    address pos,
    bool _customRatio,
    uint256 fauxTotal0,
    uint256 fauxTotal1
  ) external;

  function pause(bool _paused) external;

  function removeListed(address pos, address listed) external;

  function removeRatio(address pos) external;

  function setDeltaScale(uint256 _deltaScale) external;

  function setDepositDelta(uint256 _depositDelta) external;

  function setDepositOverride(address pos, bool _depositOverride) external;

  function setPriceThreshold(uint256 _priceThreshold) external;

  function setTwapCheck(bool _twapCheck) external;

  function setTwapInterval(uint32 _twapInterval) external;

  function setTwapOverride(
    address pos,
    bool twapOverride,
    uint32 _twapInterval,
    uint256 _priceThreshold
  ) external;

  function transferOwnership(address newOwner) external;
}
