// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IComptroller {
  function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);

  function exitMarket(address cToken) external returns (uint256);

  function mintAllowed(
    address cToken,
    address minter,
    uint256 mintAmount
  ) external returns (uint256);

  function mintVerify(
    address cToken,
    address minter,
    uint256 mintAmount,
    uint256 mintTokens
  ) external;

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
  ) external;

  function borrowAllowed(
    address cToken,
    address borrower,
    uint256 borrowAmount
  ) external returns (uint256);

  function borrowVerify(address cToken, address borrower, uint256 borrowAmount) external;

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
    uint256 repayAmount,
    uint256 borrowerIndex
  ) external;

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
    uint256 repayAmount,
    uint256 seizeTokens
  ) external;

  function seizeAllowed(
    address cTokenCollateral,
    address cTokenBorrowed,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external returns (uint256);

  function seizeVerify(
    address cTokenCollateral,
    address cTokenBorrowed,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external;

  function transferAllowed(
    address cToken,
    address src,
    address dst,
    uint256 transferTokens
  ) external returns (uint256);

  function transferVerify(
    address cToken,
    address src,
    address dst,
    uint256 transferTokens
  ) external;

  function liquidateCalculateSeizeTokens(
    address cTokenBorrowed,
    address cTokenCollateral,
    uint256 repayAmount
  ) external view returns (uint256, uint256);
}

interface IComptrollerLens {
  function markets(address) external view returns (bool, uint256);

  function oracle() external view returns (address);

  function getAccountLiquidity(address) external view returns (uint256, uint256, uint256);

  function getAssetsIn(address) external view returns (ICToken[] memory);

  function getCompAddress() external view returns (address);

  function claimComp(address holder) external;

  function claimCompAsCollateral(address holder) external;

  function claimComp(address holder, address[] memory cTokens) external; // specific markets

  function claimComp(
    address[] calldata holders,
    ICToken[] calldata cTokens,
    bool borrowers,
    bool suppliers
  ) external; // specific markets single/dual side (borrow/supply)

  function claimComp(
    address[] calldata holders,
    ICToken[] calldata cTokens,
    bool borrowers,
    bool suppliers,
    bool collateral
  ) external; // specific markets single/dual side (borrow/supply) + collateral yes/no

  function compAccrued(address) external view returns (uint256);

  function compSpeeds(address) external view returns (uint256);

  function compSupplySpeeds(address) external view returns (uint256);

  function compBorrowSpeeds(address) external view returns (uint256);

  function borrowCaps(address) external view returns (uint256);

  function getExternalRewardDistributorAddress() external view returns (address);
}

interface IExternalRewardDistributorInterface {
  function getRewardTokens() external view returns (address[] memory);

  function rewardTokenExists(address token) external view returns (bool);
}

interface ICTokenStorage {
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

interface ICToken is ICTokenStorage {
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
    ICToken cTokenCollateral
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

interface ICDelegationStorage {
  function implementation() external view returns (address);
}

interface ICDelegatorInterface is ICDelegationStorage {
  event NewImplementation(address oldImplementation, address newImplementation);

  function _setImplementation(
    address implementation_,
    bool allowResign,
    bytes memory becomeImplementationData
  ) external;
}

interface ICDelegate is ICDelegationStorage {
  function _becomeImplementation(bytes memory data) external;

  function _resignImplementation() external;
}

interface IUnitroller is IComptroller, IComptrollerLens {}
