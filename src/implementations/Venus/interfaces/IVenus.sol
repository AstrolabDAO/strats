// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IComptroller {

    function enterMarkets(
        address[] calldata vTokens
    ) external returns (uint[] memory);

    function exitMarket(address vToken) external returns (uint);

    function mintAllowed(
        address vToken,
        address minter,
        uint mintAmount
    ) external returns (uint);

    function mintVerify(
        address vToken,
        address minter,
        uint mintAmount,
        uint mintTokens
    ) external;

    function redeemAllowed(
        address vToken,
        address redeemer,
        uint redeemTokens
    ) external returns (uint);

    function redeemVerify(
        address vToken,
        address redeemer,
        uint redeemAmount,
        uint redeemTokens
    ) external;

    function borrowAllowed(
        address vToken,
        address borrower,
        uint borrowAmount
    ) external returns (uint);

    function borrowVerify(
        address vToken,
        address borrower,
        uint borrowAmount
    ) external;

    function repayBorrowAllowed(
        address vToken,
        address payer,
        address borrower,
        uint repayAmount
    ) external returns (uint);

    function repayBorrowVerify(
        address vToken,
        address payer,
        address borrower,
        uint repayAmount,
        uint borrowerIndex
    ) external;

    function liquidateBorrowAllowed(
        address vTokenBorrowed,
        address vTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external returns (uint);

    function liquidateBorrowVerify(
        address vTokenBorrowed,
        address vTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens
    ) external;

    function seizeAllowed(
        address vTokenCollateral,
        address vTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external returns (uint);

    function seizeVerify(
        address vTokenCollateral,
        address vTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external;

    function transferAllowed(
        address vToken,
        address src,
        address dst,
        uint transferTokens
    ) external returns (uint);

    function transferVerify(
        address vToken,
        address src,
        address dst,
        uint transferTokens
    ) external;

    function liquidateCalculateSeizeTokens(
        address vTokenBorrowed,
        address vTokenCollateral,
        uint repayAmount
    ) external view returns (uint, uint);

    function setMintedVAIOf(address owner, uint amount) external returns (uint);

    function liquidateVAICalculateSeizeTokens(
        address vTokenCollateral,
        uint repayAmount
    ) external view returns (uint, uint);

    function markets(address) external view returns (bool, uint);

    function oracle() external view returns (address);

    function getAccountLiquidity(
        address
    ) external view returns (uint, uint, uint);

    function getAssetsIn(address) external view returns (IVToken[] memory);

    function venusAccrued(address) external view returns (uint);

    function venusSupplySpeeds(address) external view returns (uint);

    function venusBorrowSpeeds(address) external view returns (uint);

    function getAllMarkets() external view returns (IVToken[] memory);

    function venusSupplierIndex(address, address) external view returns (uint);

    function venusInitialIndex() external view returns (uint224);

    function venusBorrowerIndex(address, address) external view returns (uint);

    function venusBorrowState(address) external view returns (uint224, uint32);

    function venusSupplyState(address) external view returns (uint224, uint32);

    function approvedDelegates(
        address borrower,
        address delegate
    ) external view returns (bool);

    function vaiController() external view returns (address);

    function liquidationIncentiveMantissa() external view returns (uint);

    function treasuryAddress() external view returns (address);

    function treasuryPercent() external view returns (uint);

    function protocolPaused() external view returns (bool);

    function mintedVAIs(address user) external view returns (uint);

    function vaiMintRate() external view returns (uint);
}

interface IVAIVault {
    function updatePendingRewards() external;
}

interface IRewardFacet {
    function claimVenus(address holder) external; // all markets+vai

    function claimVenusAsCollateral(address holder) external; // all markets+vai as collateral (auto LP)

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
interface IUnitroller is IComptroller, IRewardFacet {

}

interface IVenusLens {
    struct VenusMarketState {
        uint224 index;
        uint32 block;
    }

    struct VTokenMetadata {
        address vToken;
        uint exchangeRateCurrent;
        uint supplyRatePerBlock;
        uint borrowRatePerBlock;
        uint reserveFactorMantissa;
        uint totalBorrows;
        uint totalReserves;
        uint totalSupply;
        uint totalCash;
        bool isListed;
        uint collateralFactorMantissa;
        address underlyingAssetAddress;
        uint vTokenDecimals;
        uint underlyingDecimals;
        uint venusSupplySpeed;
        uint venusBorrowSpeed;
        uint dailySupplyXvs;
        uint dailyBorrowXvs;
    }

    struct VTokenBalances {
        address vToken;
        uint balanceOf;
        uint borrowBalanceCurrent;
        uint balanceOfUnderlying;
        uint tokenBalance;
        uint tokenAllowance;
    }

    struct VTokenUnderlyingPrice {
        address vToken;
        uint underlyingPrice;
    }

    struct AccountLimits {
        IVToken[] markets;
        uint liquidity;
        uint shortfall;
    }

    struct GovReceipt {
        uint proposalId;
        bool hasVoted;
        bool support;
        uint96 votes;
    }

    struct GovProposal {
        uint proposalId;
        address proposer;
        uint eta;
        address[] targets;
        uint[] values;
        string[] signatures;
        bytes[] calldatas;
        uint startBlock;
        uint endBlock;
        uint forVotes;
        uint againstVotes;
        bool canceled;
        bool executed;
    }

    struct XVSBalanceMetadata {
        uint balance;
        uint votes;
        address delegate;
    }

    struct XVSBalanceMetadataExt {
        uint balance;
        uint votes;
        address delegate;
        uint allocated;
    }

    struct VenusVotes {
        uint blockNumber;
        uint votes;
    }

    struct ClaimVenusLocalVariables {
        uint totalRewards;
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

    function vTokenMetadata(
        IVToken vToken
    ) external returns (VTokenMetadata memory);

    function vTokenMetadataAll(
        IVToken[] calldata vTokens
    ) external returns (VTokenMetadata[] memory);

    function getDailyXVS(
        address payable account,
        address comptrollerAddress
    ) external returns (uint);

    function vTokenBalances(
        IVToken vToken,
        address payable account
    ) external returns (VTokenBalances memory);

    function vTokenBalancesAll(
        IVToken[] calldata vTokens,
        address payable account
    ) external returns (VTokenBalances[] memory);

    function vTokenUnderlyingPrice(
        IVToken vToken
    ) external view returns (VTokenUnderlyingPrice memory);

    function vTokenUnderlyingPriceAll(
        IVToken[] calldata vTokens
    ) external view returns (VTokenUnderlyingPrice[] memory);

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
    function repayBehalfExplicit(
        address borrower,
        address vBnb_
    ) external payable;
}

// IWETH9 equivalent
interface IWbnb {
    function deposit() external payable;

    function withdraw(uint wad) external;
}

interface IInterestRateModel {
    function getBorrowRate(
        uint cash,
        uint borrows,
        uint reserves
    ) external view returns (uint);

    function getSupplyRate(
        uint cash,
        uint borrows,
        uint reserves,
        uint reserveFactorMantissa
    ) external view returns (uint);
}

interface IVBep20 {
    function underlying() external view returns (address);

    function mint(uint mintAmount) external returns (uint);

    function mintBehalf(
        address receiver,
        uint mintAmount
    ) external returns (uint);

    function redeem(uint redeemTokens) external returns (uint);

    function redeemUnderlying(uint redeemAmount) external returns (uint);

    function borrow(uint borrowAmount) external returns (uint);

    function repayBorrow(uint repayAmount) external returns (uint);

    function repayBorrowBehalf(
        address borrower,
        uint repayAmount
    ) external returns (uint);

    function liquidateBorrow(
        address borrower,
        uint repayAmount,
        IVToken vTokenCollateral
    ) external returns (uint);
}

// AAVE aToken equivalent
interface IVToken is IVBep20 {
    struct BorrowSnapshot {
        uint principal;
        uint interestIndex;
    }

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function admin() external view returns (address);

    function pendingAdmin() external view returns (address);

    function interestRateModel() external view returns (IInterestRateModel);

    function reserveFactorMantissa() external view returns (uint);

    function accrualBlockNumber() external view returns (uint);

    function borrowIndex() external view returns (uint);

    function totalBorrows() external view returns (uint);

    function totalReserves() external view returns (uint);

    function totalSupply() external view returns (uint);

    function transfer(address dst, uint amount) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint amount
    ) external returns (bool);

    function approve(address spender, uint amount) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint);

    function balanceOf(address owner) external view returns (uint);

    function balanceOfUnderlying(address owner) external returns (uint);

    function getAccountSnapshot(
        address account
    ) external view returns (uint, uint, uint, uint);

    function borrowRatePerBlock() external view returns (uint);

    function supplyRatePerBlock() external view returns (uint);

    function totalBorrowsCurrent() external returns (uint);

    function borrowBalanceCurrent(address account) external returns (uint);

    function borrowBalanceStored(address account) external view returns (uint);

    function exchangeRateCurrent() external returns (uint);

    function exchangeRateStored() external view returns (uint);

    function getCash() external view returns (uint);

    function accrueInterest() external returns (uint);

    function seize(
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external returns (uint);
}
