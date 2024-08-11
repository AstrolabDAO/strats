// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IComptroller {
  struct CompMarketState {
    uint224 index;
    uint32 block;
  }

  struct Market {
    bool isListed;
    uint256 collateralFactorMantissa;
    bool isComped;
  }

  event ActionPaused(string action, bool pauseState);
  event ActionPaused(address cToken, string action, bool pauseState);
  event CompAccruedAdjusted(
    address indexed user,
    uint256 oldCompAccrued,
    uint256 newCompAccrued
  );
  event CompBorrowSpeedUpdated(address indexed cToken, uint256 newSpeed);
  event CompGranted(address recipient, uint256 amount);
  event CompReceivableUpdated(
    address indexed user,
    uint256 oldCompReceivable,
    uint256 newCompReceivable
  );
  event CompSupplySpeedUpdated(address indexed cToken, uint256 newSpeed);
  event ContributorCompSpeedUpdated(
    address indexed contributor,
    uint256 newSpeed
  );
  event DistributedBorrowerComp(
    address indexed cToken,
    address indexed borrower,
    uint256 compDelta,
    uint256 compBorrowIndex
  );
  event DistributedSupplierComp(
    address indexed cToken,
    address indexed supplier,
    uint256 compDelta,
    uint256 compSupplyIndex
  );
  event Failure(uint256 error, uint256 info, uint256 detail);
  event MarketEntered(address cToken, address account);
  event MarketExited(address cToken, address account);
  event MarketListed(address cToken);
  event NewBorrowCap(address indexed cToken, uint256 newBorrowCap);
  event NewBorrowCapGuardian(
    address oldBorrowCapGuardian,
    address newBorrowCapGuardian
  );
  event NewCloseFactor(
    uint256 oldCloseFactorMantissa,
    uint256 newCloseFactorMantissa
  );
  event NewCollateralFactor(
    address cToken,
    uint256 oldCollateralFactorMantissa,
    uint256 newCollateralFactorMantissa
  );
  event NewLiquidationIncentive(
    uint256 oldLiquidationIncentiveMantissa,
    uint256 newLiquidationIncentiveMantissa
  );
  event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);
  event NewPriceOracle(address oldPriceOracle, address newPriceOracle);
  event NewReserveGuardian(
    address oldReserveGuardian,
    address newReserveGuardian
  );
  event NewSpeedGuardian(address oldSpeedGuardian, address newSpeedGuardian);
  event NewSupplyCap(address indexed cToken, uint256 newSupplyCap);
  event NewSupplyCapGuardian(
    address oldSupplyCapGuardian,
    address newSupplyCapGuardian
  );

  function _become(address unitroller) external;

  function _borrowGuardianPaused() external view returns (bool);

  function _grantComp(address recipient, uint256 amount) external;

  function _mintGuardianPaused() external view returns (bool);

  function _setBorrowCapGuardian(address newBorrowCapGuardian) external;

  function _setBorrowPaused(address cToken, bool state) external returns (bool);

  function _setCloseFactor(
    uint256 newCloseFactorMantissa
  ) external returns (uint256);

  function _setCollateralFactor(
    address cToken,
    uint256 newCollateralFactorMantissa
  ) external returns (uint256);

  function _setCompSpeeds(
    address[] memory cTokens,
    uint256[] memory supplySpeeds,
    uint256[] memory borrowSpeeds
  ) external;

  function _setContributorCompSpeed(
    address contributor,
    uint256 compSpeed
  ) external;

  function _setLiquidationIncentive(
    uint256 newLiquidationIncentiveMantissa
  ) external returns (uint256);

  function _setMarketBorrowCaps(
    address[] memory cTokens,
    uint256[] memory newBorrowCaps
  ) external;

  function _setMarketSupplyCaps(
    address[] memory cTokens,
    uint256[] memory newSupplyCaps
  ) external;

  function _setMintPaused(address cToken, bool state) external returns (bool);

  function _setPauseGuardian(
    address newPauseGuardian
  ) external returns (uint256);

  function _setPriceOracle(address newOracle) external returns (uint256);

  function _setSeizePaused(bool state) external returns (bool);

  function _setSpeedGuardian(address newSpeedGuardian) external;

  function _setSupplyCapGuardian(address newSupplyCapGuardian) external;

  function _setTransferPaused(bool state) external returns (bool);

  function _supportMarket(address cToken) external returns (uint256);

  function accountAssets(address, uint256) external view returns (address);

  function admin() external view returns (address);

  function allMarkets(uint256) external view returns (address);

  function borrowAllowed(
    address cToken,
    address borrower,
    uint256 borrowAmount
  ) external returns (uint256);

  function borrowCapGuardian() external view returns (address);

  function borrowCaps(address) external view returns (uint256);

  function borrowGuardianPaused(address) external view returns (bool);

  function borrowVerify(
    address cToken,
    address borrower,
    uint256 borrowAmount
  ) external;

  function checkMembership(
    address account,
    address cToken
  ) external view returns (bool);

  function claimComp(address holder, address[] memory cTokens) external;

  function claimComp(
    address[] memory holders,
    address[] memory cTokens,
    bool borrowers,
    bool suppliers
  ) external;

  function claimComp(address holder) external;

  function closeFactorMantissa() external view returns (uint256);

  function compAccrued(address) external view returns (uint256);

  function compBorrowSpeeds(address) external view returns (uint256);

  function compBorrowState(
    address
  ) external view returns (uint224 index, uint32 block);

  function compBorrowerIndex(address, address) external view returns (uint256);

  function compContributorSpeeds(address) external view returns (uint256);

  function compInitialIndex() external view returns (uint224);

  function compRate() external view returns (uint256);

  function compReceivable(address) external view returns (uint256);

  function compSpeeds(address) external view returns (uint256);

  function compSupplierIndex(address, address) external view returns (uint256);

  function compSupplySpeeds(address) external view returns (uint256);

  function compSupplyState(
    address
  ) external view returns (uint224 index, uint32 block);

  function comptrollerImplementation() external view returns (address);

  function enableLooping(bool state) external returns (bool);

  function enterMarkets(
    address[] memory cTokens
  ) external returns (uint256[] memory);

  function exitMarket(address cTokenAddress) external returns (uint256);

  function getAccountLiquidity(
    address account
  ) external view returns (uint256, uint256, uint256);

  function getAllMarkets() external view returns (address[] memory);

  function getAssetsIn(
    address account
  ) external view returns (address[] memory);

  function getBlockNumber() external view returns (uint256);

  function getCompAddress() external view returns (address);

  function getHypotheticalAccountLiquidity(
    address account,
    address cTokenModify,
    uint256 redeemTokens,
    uint256 borrowAmount
  ) external view returns (uint256, uint256, uint256);

  function isComptroller() external view returns (bool);

  function isDeprecated(address cToken) external view returns (bool);

  function isLoopingEnabled(address user) external view returns (bool);

  function lastContributorBlock(address) external view returns (uint256);

  function liquidateBorrowAllowed(
    address cTokenBorrowed,
    address cTokenCollateral,
    address liquidator,
    address borrower,
    uint256 repayAmount
  ) external returns (uint256);

  function liquidateBorrowVerify(
    address cTokenBorrowed,
    address cTokenCollateral,
    address liquidator,
    address borrower,
    uint256 actualRepayAmount,
    uint256 seizeTokens
  ) external;

  function liquidateCalculateSeizeTokens(
    address cTokenBorrowed,
    address cTokenCollateral,
    uint256 actualRepayAmount
  ) external view returns (uint256, uint256);

  function liquidationIncentiveMantissa() external view returns (uint256);

  function loopEnabled(address) external view returns (bool);

  function markets(
    address
  )
    external
    view
    returns (bool isListed, uint256 collateralFactorMantissa, bool isComped);

  function maxAssets() external view returns (uint256);

  function mintAllowed(
    address cToken,
    address minter,
    uint256 mintAmount
  ) external returns (uint256);

  function mintGuardianPaused(address) external view returns (bool);

  function mintVerify(
    address cToken,
    address minter,
    uint256 actualMintAmount,
    uint256 mintTokens
  ) external;

  function oracle() external view returns (address);

  function pauseGuardian() external view returns (address);

  function pendingAdmin() external view returns (address);

  function pendingComptrollerImplementation() external view returns (address);

  function redeemAllowed(
    address cToken,
    address redeemer,
    uint256 redeemTokens
  ) external returns (uint256);

  function redeemVerify(
    address cToken,
    address redeemer,
    uint256 redeemAmount,
    uint256 redeemTokens
  ) external pure;

  function repayBorrowAllowed(
    address cToken,
    address payer,
    address borrower,
    uint256 repayAmount
  ) external returns (uint256);

  function repayBorrowVerify(
    address cToken,
    address payer,
    address borrower,
    uint256 actualRepayAmount,
    uint256 borrowerIndex
  ) external;

  function reserveGuardian() external view returns (address);

  function seizeAllowed(
    address cTokenCollateral,
    address cTokenBorrowed,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external returns (uint256);

  function seizeGuardianPaused() external view returns (bool);

  function seizeVerify(
    address cTokenCollateral,
    address cTokenBorrowed,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external;

  function speedGuardian() external view returns (address);

  function supplyCapGuardian() external view returns (address);

  function supplyCaps(address) external view returns (uint256);

  function transferAllowed(
    address cToken,
    address src,
    address dst,
    uint256 transferTokens
  ) external returns (uint256);

  function transferGuardianPaused() external view returns (bool);

  function transferVerify(
    address cToken,
    address src,
    address dst,
    uint256 transferTokens
  ) external;

  function updateContributorRewards(address contributor) external;
}

interface IUnitroller is IComptroller {}

interface ILTokenStorage {
  function name() external view returns (string memory);

  function symbol() external view returns (string memory);

  function decimals() external view returns (uint8);

  function admin() external view returns (address);

  function pendingAdmin() external view returns (address);

  function comptroller() external view returns (address);

  function interestRateModel() external view returns (address);

  function reserveFactorMantissa() external view returns (uint256);

  function accrualBlockNumber() external view returns (uint256);

  function borrowIndex() external view returns (uint256);

  function totalBorrows() external view returns (uint256);

  function totalReserves() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  struct BorrowSnapshot {
    uint256 principal;
    uint256 interestIndex;
  }

  function protocolSeizeShareMantissa() external view returns (uint256);
}

interface ILToken is ILTokenStorage {
  event AccrueInterest(
    uint256 cashPrior,
    uint256 interestAccumulated,
    uint256 borrowIndex,
    uint256 totalBorrows
  );
  event Mint(address minter, uint256 mintAmount, uint256 mintTokens);
  event Redeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);
  event Borrow(
    address borrower,
    uint256 borrowAmount,
    uint256 accountBorrows,
    uint256 totalBorrows
  );
  event RepayBorrow(
    address payer,
    address borrower,
    uint256 repayAmount,
    uint256 accountBorrows,
    uint256 totalBorrows
  );
  event LiquidateBorrow(
    address liquidator,
    address borrower,
    uint256 repayAmount,
    address cTokenCollateral,
    uint256 seizeTokens
  );
  event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);
  event NewAdmin(address oldAdmin, address newAdmin);
  event NewComptroller(address oldComptroller, address newComptroller);
  event NewMarketInterestRateModel(
    address oldInterestRateModel,
    address newInterestRateModel
  );
  event NewReserveFactor(
    uint256 oldReserveFactorMantissa,
    uint256 newReserveFactorMantissa
  );
  event ReservesAdded(
    address benefactor,
    uint256 addAmount,
    uint256 newTotalReserves
  );
  event ReservesReduced(
    address admin,
    uint256 reduceAmount,
    uint256 newTotalReserves
  );
  event Transfer(address indexed from, address indexed to, uint256 amount);
  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 amount
  );

  function transfer(address dst, uint256 amount) external returns (bool);

  function transferFrom(
    address src,
    address dst,
    uint256 amount
  ) external returns (bool);

  function approve(address spender, uint256 amount) external returns (bool);

  function allowance(
    address owner,
    address spender
  ) external view returns (uint256);

  function balanceOf(address owner) external view returns (uint256);

  function balanceOfUnderlying(address owner) external returns (uint256);

  function getAccountSnapshot(
    address account
  ) external view returns (uint256, uint256, uint256, uint256);

  function borrowRatePerBlock() external view returns (uint256);

  function supplyRatePerBlock() external view returns (uint256);

  function totalBorrowsCurrent() external returns (uint256);

  function borrowBalanceCurrent(address account) external returns (uint256);

  function borrowBalanceStored(address account) external view returns (uint256);

  function exchangeRateCurrent() external returns (uint256);

  function exchangeRateStored() external view returns (uint256);

  function getCash() external view returns (uint256);

  function accrueInterest() external returns (uint256);

  function seize(
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external returns (uint256);

  function underlying() external view returns (address);

  function mint(uint256 mintAmount) external returns (uint256);

  function redeem(uint256 redeemTokens) external returns (uint256);

  function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

  function borrow(uint256 borrowAmount) external returns (uint256);

  function repayBorrow(uint256 repayAmount) external returns (uint256);

  function repayBorrowBehalf(
    address borrower,
    uint256 repayAmount
  ) external returns (uint256);

  function liquidateBorrow(
    address borrower,
    uint256 repayAmount,
    ILToken cTokenCollateral
  ) external returns (uint256);

  function sweepToken(address token) external;

  function _addReserves(uint256 addAmount) external returns (uint256);

  function _setPendingAdmin(
    address payable newPendingAdmin
  ) external returns (uint256);

  function _acceptAdmin() external returns (uint256);

  function _setComptroller(
    IComptroller newComptroller
  ) external returns (uint256);

  function _setReserveFactor(
    uint256 newReserveFactorMantissa
  ) external returns (uint256);

  function _reduceReserves(uint256 reduceAmount) external returns (uint256);

  function _setInterestRateModel(
    address newInterestRateModel
  ) external returns (uint256);
}
