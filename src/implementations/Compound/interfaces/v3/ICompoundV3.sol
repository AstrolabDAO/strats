// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IComet {

  // Types
  struct AssetInfo {
    uint8 offset;
    address asset;
    address priceFeed;
    uint64 scale;
    uint64 borrowCollateralFactor;
    uint64 liquidateCollateralFactor;
    uint64 liquidationFactor;
    uint128 supplyCap;
  }

  struct UserBasic {
    int104 principal;
    uint64 baseTrackingIndex;
    uint64 baseTrackingAccrued;
    uint16 assetsIn;
    uint8 _reserved;
  }

  // Events

  // Functions
  function supply(address asset, uint256 amount) external;

  function supplyTo(address dst, address asset, uint256 amount) external;

  function supplyFrom(
    address from,
    address dst,
    address asset,
    uint256 amount
  ) external;

  function transfer(address dst, uint256 amount) external returns (bool);

  function transferFrom(
    address src,
    address dst,
    uint256 amount
  ) external returns (bool);

  function transferAsset(address dst, address asset, uint256 amount) external;

  function transferAssetFrom(
    address src,
    address dst,
    address asset,
    uint256 amount
  ) external;

  function withdraw(address asset, uint256 amount) external;

  function withdrawTo(address to, address asset, uint256 amount) external;

  function withdrawFrom(
    address src,
    address to,
    address asset,
    uint256 amount
  ) external;

  function approveThis(address manager, address asset, uint256 amount) external;

  function withdrawReserves(address to, uint256 amount) external;

  function absorb(address absorber, address[] calldata accounts) external;

  function buyCollateral(
    address asset,
    uint256 minAmount,
    uint256 baseAmount,
    address recipient
  ) external;

  function quoteCollateral(
    address asset,
    uint256 baseAmount
  ) external view returns (uint256);

  function getAssetInfo(uint8 i) external view returns (AssetInfo memory);

  function getAssetInfoByAddress(
    address asset
  ) external view returns (AssetInfo memory);

  function getCollateralReserves(address asset) external view returns (uint256);

  function getReserves() external view returns (int256);

  function getPrice(address priceFeed) external view returns (uint256);

  function isBorrowCollateralized(address account) external view returns (bool);

  function isLiquidatable(address account) external view returns (bool);

  function totalSupply() external view returns (uint256);

  function totalBorrow() external view returns (uint256);

  function balanceOf(address owner) external view returns (uint256);

  function borrowBalanceOf(address account) external view returns (uint256);

  function pause(
    bool supplyPaused,
    bool transferPaused,
    bool withdrawPaused,
    bool absorbPaused,
    bool buyPaused
  ) external;

  function isSupplyPaused() external view returns (bool);

  function isTransferPaused() external view returns (bool);

  function isWithdrawPaused() external view returns (bool);

  function isAbsorbPaused() external view returns (bool);

  function isBuyPaused() external view returns (bool);

  function accrueAccount(address account) external;

  function getSupplyRate(uint256 utilization) external view returns (uint64);

  function getBorrowRate(uint256 utilization) external view returns (uint64);

  function getUtilization() external view returns (uint256);

  function governor() external view returns (address);

  function pauseGuardian() external view returns (address);

  function baseToken() external view returns (address);

  function baseTokenPriceFeed() external view returns (address);

  function extensionDelegate() external view returns (address);

  function supplyKink() external view returns (uint256);

  function supplyPerSecondInterestRateSlopeLow()
    external
    view
    returns (uint256);

  function supplyPerSecondInterestRateSlopeHigh()
    external
    view
    returns (uint256);

  function supplyPerSecondInterestRateBase() external view returns (uint256);

  function borrowKink() external view returns (uint256);

  function borrowPerSecondInterestRateSlopeLow()
    external
    view
    returns (uint256);

  function borrowPerSecondInterestRateSlopeHigh()
    external
    view
    returns (uint256);

  function borrowPerSecondInterestRateBase() external view returns (uint256);

  function storeFrontPriceFactor() external view returns (uint256);

  function baseScale() external view returns (uint256);

  function trackingIndexScale() external view returns (uint256);

  function baseTrackingSupplySpeed() external view returns (uint256);

  function baseTrackingBorrowSpeed() external view returns (uint256);

  function baseMinForRewards() external view returns (uint256);

  function baseBorrowMin() external view returns (uint256);

  function targetReserves() external view returns (uint256);

  function numAssets() external view returns (uint8);

  function decimals() external view returns (uint8);

  function initializeStorage() external;

  function baseTrackingAccrued(address account) external view returns (uint64);
}

interface ICometRewards {

  // Types
  struct RewardOwed {
    address token;
    uint256 owed;
  }

  struct RewardConfig {
    address token;
    uint64 rescaleFactor;
    bool shouldUpscale;
    uint256 multiplier;
  }

  // Events

  // Functions
  function withdrawToken(address token, address to, uint256 amount) external;

  function claim(address comet, address src, bool shouldAccrue) external;

  function claimTo(
    address comet,
    address src,
    address to,
    bool shouldAccrue
  ) external;

  function getRewardOwed(
    address comet,
    address account
  ) external returns (RewardOwed memory);

  function rewardConfig(
    address comet
  ) external view returns (RewardConfig memory);
}

interface ICometRewardsLegacy {

  // Types
  struct RewardConfig {
    address token;
    uint64 rescaleFactor;
    bool shouldUpscale;
  }

  // Events

  // Functions
  function rewardConfig(
    address comet
  ) external view returns (RewardConfig memory);
}
