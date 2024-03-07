// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IComptroller {
  function enterMarkets(address[] calldata vTokens) external returns (uint256[] memory);

  function exitMarket(address vToken) external returns (uint256);

  function mintAllowed(
    address vToken,
    address minter,
    uint256 mintAmount
  ) external returns (uint256);

  function mintVerify(
    address vToken,
    address minter,
    uint256 mintAmount,
    uint256 mintTokens
  ) external;

  function redeemAllowed(
    address vToken,
    address redeemer,
    uint256 redeemTokens
  ) external returns (uint256);

  function redeemVerify(
    address vToken,
    address redeemer,
    uint256 redeemAmount,
    uint256 redeemTokens
  ) external;

  function borrowAllowed(
    address vToken,
    address borrower,
    uint256 borrowAmount
  ) external returns (uint256);

  function borrowVerify(address vToken, address borrower, uint256 borrowAmount) external;

  function repayBorrowAllowed(
    address vToken,
    address payer,
    address borrower,
    uint256 repayAmount
  ) external returns (uint256);

  function repayBorrowVerify(
    address vToken,
    address payer,
    address borrower,
    uint256 repayAmount,
    uint256 borrowerIndex
  ) external;

  function liquidateBorrowAllowed(
    address vTokenBorrowed,
    address vTokenCollateral,
    address liquidator,
    address borrower,
    uint256 repayAmount
  ) external returns (uint256);

  function liquidateBorrowVerify(
    address vTokenBorrowed,
    address vTokenCollateral,
    address liquidator,
    address borrower,
    uint256 repayAmount,
    uint256 seizeTokens
  ) external;

  function seizeAllowed(
    address vTokenCollateral,
    address vTokenBorrowed,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external returns (uint256);

  function seizeVerify(
    address vTokenCollateral,
    address vTokenBorrowed,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external;

  function transferAllowed(
    address vToken,
    address src,
    address dst,
    uint256 transferTokens
  ) external returns (uint256);

  function transferVerify(
    address vToken,
    address src,
    address dst,
    uint256 transferTokens
  ) external;

  function liquidateCalculateSeizeTokens(
    address vTokenBorrowed,
    address vTokenCollateral,
    uint256 repayAmount
  ) external view returns (uint256, uint256);

  function setMintedVAIOf(address owner, uint256 amount) external returns (uint256);

  function liquidateVAICalculateSeizeTokens(
    address vTokenCollateral,
    uint256 repayAmount
  ) external view returns (uint256, uint256);

  function markets(address) external view returns (bool, uint256);

  function oracle() external view returns (address);

  function getAccountLiquidity(address) external view returns (uint256, uint256, uint256);

  function getAssetsIn(address) external view returns (IVToken[] memory);

  function venusAccrued(address) external view returns (uint256);

  function venusSupplySpeeds(address) external view returns (uint256);

  function venusBorrowSpeeds(address) external view returns (uint256);

  function getAllMarkets() external view returns (IVToken[] memory);

  function venusSupplierIndex(address, address) external view returns (uint256);

  function venusInitialIndex() external view returns (uint224);

  function venusBorrowerIndex(address, address) external view returns (uint256);

  function venusBorrowState(address) external view returns (uint224, uint32);

  function venusSupplyState(address) external view returns (uint224, uint32);

  function approvedDelegates(
    address borrower,
    address delegate
  ) external view returns (bool);

  function vaiController() external view returns (address);

  function liquidationIncentiveMantissa() external view returns (uint256);

  function treasuryAddress() external view returns (address);

  function treasuryPercent() external view returns (uint256);

  function protocolPaused() external view returns (bool);

  function mintedVAIs(address user) external view returns (uint256);

  function vaiMintRate() external view returns (uint256);
}

interface IVAIBalancerVault {
  function updatePendingRewards() external;
}

interface IRewardFacet {
  function claimVenus(address holder) external;

  function claimVenusAsCollateral(address holder) external;

  function claimVenus(address holder, address[] memory vTokens) external; // specific markets

  function claimVenus(
    address[] calldata holders,
    IVToken[] calldata vTokens,
    bool borrowers,
    bool suppliers
  ) external; // specific markets single/dual side (borrow/supply)

  function claimVenus(
    address[] calldata holders,
    IVToken[] calldata vTokens,
    bool borrowers,
    bool suppliers,
    bool collateral
  ) external; // specific markets single/dual side (borrow/supply) + collateral yes/no

  function _grantXVS(address recipient, uint256 amount) external;

  function getXVSAddress() external pure returns (address);

  function getXVSVTokenAddress() external pure returns (address);
}

// AAVE IRewardsController (IComptroller) diamond equivalent
interface IUnitroller is IComptroller, IRewardFacet {}

interface IVenusLens {
  struct VenusMarketState {
    uint224 index;
    uint32 block;
  }

  struct VTokenMetadata {
    address vToken;
    uint256 exchangeRateCurrent;
    uint256 supplyRatePerBlock;
    uint256 borrowRatePerBlock;
    uint256 reserveFactorMantissa;
    uint256 totalBorrows;
    uint256 totalReserves;
    uint256 totalSupply;
    uint256 totalCash;
    bool isListed;
    uint256 collateralFactorMantissa;
    address underlyingAssetAddress;
    uint256 vTokenDecimals;
    uint256 underlyingDecimals;
    uint256 venusSupplySpeed;
    uint256 venusBorrowSpeed;
    uint256 dailySupplyXvs;
    uint256 dailyBorrowXvs;
  }

  struct VTokenBalances {
    address vToken;
    uint256 balanceOf;
    uint256 borrowBalanceCurrent;
    uint256 balanceOfUnderlying;
    uint256 tokenBalance;
    uint256 tokenAllowance;
  }

  struct VTokenUnderlyingPrice {
    address vToken;
    uint256 underlyingPrice;
  }

  struct AccountLimits {
    IVToken[] markets;
    uint256 liquidity;
    uint256 shortfall;
  }

  struct GovReceipt {
    uint256 proposalId;
    bool hasVoted;
    bool support;
    uint96 votes;
  }

  struct GovProposal {
    uint256 proposalId;
    address proposer;
    uint256 eta;
    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] calldatas;
    uint256 startBlock;
    uint256 endBlock;
    uint256 forVotes;
    uint256 againstVotes;
    bool canceled;
    bool executed;
  }

  struct XVSBalanceMetadata {
    uint256 balance;
    uint256 votes;
    address delegate;
  }

  struct XVSBalanceMetadataExt {
    uint256 balance;
    uint256 votes;
    address delegate;
    uint256 allocated;
  }

  struct VenusVotes {
    uint256 blockNumber;
    uint256 votes;
  }

  struct ClaimVenusLocalVariables {
    uint256 totalRewards;
    uint224 borrowIndex;
    uint32 borrowBlock;
    uint224 supplyIndex;
    uint32 supplyBlock;
  }

  struct PendingReward {
    address vTokenAddress;
    uint256 amount;
  }

  struct RewardSummary {
    address distributorAddress;
    address rewardTokenAddress;
    uint256 totalRewards;
    PendingReward[] pendingRewards;
  }

  function vTokenMetadata(IVToken vToken) external returns (VTokenMetadata memory);

  function vTokenMetadataAll(IVToken[] calldata vTokens)
    external
    returns (VTokenMetadata[] memory);

  function getDailyXVS(
    address payable account,
    address comptrollerAddress
  ) external returns (uint256);

  function vTokenBalances(
    IVToken vToken,
    address payable account
  ) external returns (VTokenBalances memory);

  function vTokenBalancesAll(
    IVToken[] calldata vTokens,
    address payable account
  ) external returns (VTokenBalances[] memory);

  function vTokenUnderlyingPrice(IVToken vToken)
    external
    view
    returns (VTokenUnderlyingPrice memory);

  function vTokenUnderlyingPriceAll(IVToken[] calldata vTokens)
    external
    view
    returns (VTokenUnderlyingPrice[] memory);

  function getAccountLimits(
    IComptroller comptroller,
    address account
  ) external view returns (AccountLimits memory);

  // function getGovReceipts(GovernorAlpha governor, address voter, uint[] memory proposalIds) external view returns (GovReceipt[] memory);
  // function getGovProposals(GovernorAlpha governor, uint[] calldata proposalIds) external view returns (GovProposal[] memory);
  function getXVSBalanceMetadata(
    address xvs,
    address account
  ) external view returns (XVSBalanceMetadata memory);

  function getXVSBalanceMetadataExt(
    address xvs,
    IComptroller comptroller,
    address account
  ) external returns (XVSBalanceMetadataExt memory);

  function getVenusVotes(
    address xvs,
    address account,
    uint32[] calldata blockNumbers
  ) external view returns (VenusVotes[] memory);

  function pendingRewards(
    address holder,
    IComptroller comptroller
  ) external view returns (RewardSummary memory);
}

interface IMaximillion {
  function repayBehalfExplicit(address borrower, address vBnb_) external payable;
}

// IWETH9 equivalent
interface IWbnb {
  function deposit() external payable;

  function withdraw(uint256 wad) external;
}

interface IInterestRateModel {
  function getBorrowRate(
    uint256 cash,
    uint256 borrows,
    uint256 reserves
  ) external view returns (uint256);

  function getSupplyRate(
    uint256 cash,
    uint256 borrows,
    uint256 reserves,
    uint256 reserveFactorMantissa
  ) external view returns (uint256);
}

interface IVBep20 {
  function underlying() external view returns (address);

  function mint(uint256 mintAmount) external returns (uint256);

  function mintBehalf(address receiver, uint256 mintAmount) external returns (uint256);

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
    IVToken vTokenCollateral
  ) external returns (uint256);
}

// AAVE aToken equivalent
interface IVToken is IVBep20 {
  struct BorrowSnapshot {
    uint256 principal;
    uint256 interestIndex;
  }

  function name() external view returns (string memory);

  function symbol() external view returns (string memory);

  function decimals() external view returns (uint8);

  function admin() external view returns (address);

  function pendingAdmin() external view returns (address);

  function interestRateModel() external view returns (IInterestRateModel);

  function reserveFactorMantissa() external view returns (uint256);

  function accrualBlockNumber() external view returns (uint256);

  function borrowIndex() external view returns (uint256);

  function totalBorrows() external view returns (uint256);

  function totalReserves() external view returns (uint256);

  function totalSupply() external view returns (uint256);

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
}
