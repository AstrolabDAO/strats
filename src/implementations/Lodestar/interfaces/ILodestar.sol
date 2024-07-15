// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IComptroller {
  function claimReward(uint8 rewardType, address holder) external;

  function claimComp(address holder) external;

  function claimComp(address holder, ILToken[] memory cTokens) external; // specific markets

  function claimComp(
    address[] calldata holders,
    ILToken[] calldata cTokens,
    bool borrowers,
    bool suppliers
  ) external; // specific markets single/dual side (borrow/supply)

  function borrowAllowed(
    address iToken,
    address borrower,
    uint256 borrowAmount
  ) external view returns (uint256);

  function compAccrued(address holder) external view returns (uint256);

  function enterMarkets(address[] memory _iTokens) external;

  function pendingComptrollerImplementation()
    external
    view
    returns (address implementation);
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
    address borrower, uint256 borrowAmount, uint256 accountBorrows, uint256 totalBorrows
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
    address oldInterestRateModel, address newInterestRateModel
  );
  event NewReserveFactor(
    uint256 oldReserveFactorMantissa, uint256 newReserveFactorMantissa
  );
  event ReservesAdded(address benefactor, uint256 addAmount, uint256 newTotalReserves);
  event ReservesReduced(address admin, uint256 reduceAmount, uint256 newTotalReserves);
  event Transfer(address indexed from, address indexed to, uint256 amount);
  event Approval(address indexed owner, address indexed spender, uint256 amount);

  function transfer(address dst, uint256 amount) external returns (bool);

  function transferFrom(address src, address dst, uint256 amount) external returns (bool);

  function approve(address spender, uint256 amount) external returns (bool);

  function allowance(address owner, address spender) external view returns (uint256);

  function balanceOf(address owner) external view returns (uint256);

  function balanceOfUnderlying(address owner) external returns (uint256);

  function getAccountSnapshot(address account)
    external
    view
    returns (uint256, uint256, uint256, uint256);

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

  function _setPendingAdmin(address payable newPendingAdmin) external returns (uint256);

  function _acceptAdmin() external returns (uint256);

  function _setComptroller(IComptroller newComptroller) external returns (uint256);

  function _setReserveFactor(uint256 newReserveFactorMantissa) external returns (uint256);

  function _reduceReserves(uint256 reduceAmount) external returns (uint256);

  function _setInterestRateModel(address newInterestRateModel) external returns (uint256);
}
