// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IComptroller {
    function enterMarkets(
        address[] calldata mTokens
    ) external returns (uint[] memory);

    function exitMarket(address mToken) external returns (uint256);

    function mintAllowed(
        address mToken,
        address minter,
        uint256 mintAmount
    ) external returns (uint256);

    function mintVerify(
        address mToken,
        address minter,
        uint256 mintAmount,
        uint256 mintTokens
    ) external;

    function redeemAllowed(
        address mToken,
        address redeemer,
        uint256 redeemTokens
    ) external returns (uint256);

    function redeemVerify(
        address mToken,
        address redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    ) external;

    function borrowAllowed(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) external returns (uint256);

    function borrowVerify(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) external;

    function repayBorrowAllowed(
        address mToken,
        address payer,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256);

    function repayBorrowVerify(
        address mToken,
        address payer,
        address borrower,
        uint256 repayAmount,
        uint256 borrowerIndex
    ) external;

    function liquidateBorrowAllowed(
        address mTokenBorrowed,
        address mTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256);

    function liquidateBorrowVerify(
        address mTokenBorrowed,
        address mTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount,
        uint256 seizeTokens
    ) external;

    function seizeAllowed(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external returns (uint256);

    function seizeVerify(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external;

    function transferAllowed(
        address mToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external returns (uint256);

    function transferVerify(
        address mToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external;

    function liquidateCalculateSeizeTokens(
        address mTokenBorrowed,
        address mTokenCollateral,
        uint256 repayAmount
    ) external view returns (uint, uint256);
}

interface IComptrollerLens {
    function markets(address) external view returns (bool, uint256);

    function oracle() external view returns (address);

    function getAccountLiquidity(
        address
    ) external view returns (uint256, uint256, uint256);

    function getAssetsIn(address) external view returns (IMToken[] memory);

    function getCompAddress() external view returns (address);

    function claimReward(address holder) external; // all markets+vai

    function claimRewardAsCollateral(address holder) external; // all markets+vai as collateral (auto LP)

    function claimReward(address holder, address[] memory mTokens) external; // specific markets

    function claimReward(
        address[] calldata holders,
        IMToken[] calldata mTokens,
        bool borrowers,
        bool suppliers
    ) external; // specific markets single/dual side (borrow/supply)

    function claimReward(
        address[] calldata holders,
        IMToken[] calldata mTokens,
        bool borrowers,
        bool suppliers,
        bool collateral
    ) external; // specific markets single/dual side (borrow/supply) + collateral yes/no

    // legacy (to be used with moonbeam/moonriver comptrollers)
    function claimReward(uint8 rewardType, address holder) external;

    function claimReward(
        uint8 rewardType,
        address holder,
        address[] memory mTokens
    ) external;

    function claimReward(
        uint8 rewardType,
        address[] calldata holders,
        IMToken[] calldata mTokens,
        bool borrowers,
        bool suppliers
    ) external payable; // specific markets single/dual side (borrow/supply)

    function rewardDistributor() external view returns (address);

    function rewardAccrued(address) external view returns (uint256);

    // legacy (to be used with moonbeam/moonriver comptrollers)
    function rewardAccrued(uint8, address) external view returns (uint256);

    function borrowRewardSpeeds(
        uint8 rewardType,
        address input
    ) external view returns (uint256);

    function supplyRewardSpeeds(
        uint8 rewardType,
        address input
    ) external view returns (uint256);

    function compSupplySpeeds(address) external view returns (uint256);

    function compBorrowSpeeds(address) external view returns (uint256);

    function borrowCaps(address) external view returns (uint256);

    function getExternalRewardDistributorAddress()
        external
        view
        returns (address);
}

interface IExternalRewardDistributorInterface {
    function getRewardTokens() external view returns (address[] memory);

    function rewardTokenExists(address token) external view returns (bool);
}

interface IMTokenStorage {
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

interface IMToken is IMTokenStorage {
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
        address mTokenCollateral,
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
    ) external view returns (uint, uint, uint, uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function supplyRatePerBlock() external view returns (uint256);

    function totalBorrowsCurrent() external returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function borrowBalanceStored(
        address account
    ) external view returns (uint256);

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
        IMToken mTokenCollateral
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

interface ICDelegationStorage {
    function implementation() external view returns (address);
}

interface ICDelegatorInterface is ICDelegationStorage {
    event NewImplementation(
        address oldImplementation,
        address newImplementation
    );

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

interface MultiRewardDistributorCommon {
    struct MarketConfig {
        // The owner/admin of the emission config
        address owner;
        // The emission token
        address emissionToken;
        // Scheduled to end at this time
        uint endTime;
        // Supplier global state
        uint224 supplyGlobalIndex;
        uint32 supplyGlobalTimestamp;
        // Borrower global state
        uint224 borrowGlobalIndex;
        uint32 borrowGlobalTimestamp;
        uint supplyEmissionsPerSec;
        uint borrowEmissionsPerSec;
    }

    struct MarketEmissionConfig {
        MarketConfig config;
        mapping(address => uint) supplierIndices;
        mapping(address => uint) supplierRewardsAccrued;
        mapping(address => uint) borrowerIndices;
        mapping(address => uint) borrowerRewardsAccrued;
    }

    struct RewardInfo {
        address emissionToken;
        uint totalAmount;
        uint supplySide;
        uint borrowSide;
    }

    struct IndexUpdate {
        uint224 newIndex;
        uint32 newTimestamp;
    }

    struct MTokenData {
        uint mTokenBalance;
        uint borrowBalanceStored;
    }

    struct RewardWithMToken {
        address mToken;
        RewardInfo[] rewards;
    }

    // Global index updates
    event GlobalSupplyIndexUpdated(
        IMToken mToken,
        address emissionToken,
        uint newSupplyIndex,
        uint32 newSupplyGlobalTimestamp
    );
    event GlobalBorrowIndexUpdated(
        IMToken mToken,
        address emissionToken,
        uint newIndex,
        uint32 newTimestamp
    );

    // Reward Disbursal
    event DisbursedSupplierRewards(
        IMToken indexed mToken,
        address indexed supplier,
        address indexed emissionToken,
        uint totalAccrued
    );
    event DisbursedBorrowerRewards(
        IMToken indexed mToken,
        address indexed borrower,
        address indexed emissionToken,
        uint totalAccrued
    );

    // Admin update events
    event NewConfigCreated(
        IMToken indexed mToken,
        address indexed owner,
        address indexed emissionToken,
        uint supplySpeed,
        uint borrowSpeed,
        uint endTime
    );
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);
    event NewEmissionCap(uint oldEmissionCap, uint newEmissionCap);
    event NewEmissionConfigOwner(
        IMToken indexed mToken,
        address indexed emissionToken,
        address currentOwner,
        address newOwner
    );
    event NewRewardEndTime(
        IMToken indexed mToken,
        address indexed emissionToken,
        uint currentEndTime,
        uint newEndTime
    );
    event NewSupplyRewardSpeed(
        IMToken indexed mToken,
        address indexed emissionToken,
        uint oldRewardSpeed,
        uint newRewardSpeed
    );
    event NewBorrowRewardSpeed(
        IMToken indexed mToken,
        address indexed emissionToken,
        uint oldRewardSpeed,
        uint newRewardSpeed
    );
    event FundsRescued(address token, uint amount);

    // Pause guardian stuff
    event RewardsPaused();
    event RewardsUnpaused();

    // Errors
    event InsufficientTokensToEmit(
        address payable user,
        address rewardToken,
        uint amount
    );
}

interface IMultiRewardDistributor is MultiRewardDistributorCommon {
    function initialize(address comptroller, address pauseGuardian) external;

    function getCurrentOwner(
        IMToken _mToken,
        address _emissionToken
    ) external view returns (address);

    function getAllMarketConfigs(
        IMToken _mToken
    ) external view returns (MarketConfig[] memory);

    function getConfigForMarket(
        IMToken _mToken,
        address _emissionToken
    ) external view returns (MarketConfig memory);

    function getOutstandingRewardsForUser(
        address _user
    ) external view returns (RewardWithMToken[] memory);

    function updateMarketSupplyIndex(IMToken _mToken) external;

    function disburseSupplierRewards(
        IMToken _mToken,
        address _supplier,
        bool _sendTokens
    ) external;

    function updateMarketBorrowIndex(IMToken _mToken) external;

    function disburseBorrowerRewards(
        IMToken _mToken,
        address _borrower,
        bool _sendTokens
    ) external;

    function pauseRewards() external;

    function unpauseRewards() external;

    // Additional functions related to reward management, administration, and configuration...
}

interface IUnitroller is IComptroller, IComptrollerLens {}
