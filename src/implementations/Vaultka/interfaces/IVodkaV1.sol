// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IVodkaV1 {
    // Events
    event RewardRouterContractChanged(address newVault, address glpRewardHandler);
    event Deposit(address indexed depositer, uint256 depositTokenAmount, uint256 createdAt, uint256 glpAmount);
    event Withdraw(
        address indexed user,
        uint256 amount,
        uint256 time,
        uint256 glpAmount,
        uint256 profits,
        uint256 glpprice
    );
    event ProtocolFeeChanged(
        address newFeeReceiver,
        uint256 newWithdrawalFee,
        address newWaterFeeReceiver,
        uint256 liquidatorsRewardPercentage,
        uint256 fixedFeeSplit
    );
    event SetAllowedClosers(address indexed closer, bool allowed);
    event SetAllowedSenders(address indexed sender, bool allowed);
    event SetBurner(address indexed burner, bool allowed);
    event UpdateMCAndPID(address indexed newMC, uint256 mcpPid);
    event UpdateMaxAndMinLeverage(uint256 maxLeverage, uint256 minLeverage);
    event OpenRequest(address indexed user, uint256 amountAfterFee);
    event RequestFulfilled(address indexed user, uint256 openAmount, uint256 closedAmount);
    event SetAssetWhitelist(address indexed asset, bool isWhitelisted);
    event Harvested(bool gmx, bool esgmx, bool glp, bool vesting);
    event Liquidated(
        address indexed user,
        uint256 indexed positionId,
        address liquidator,
        uint256 amount,
        uint256 reward
    );
    event ETHHarvested(uint256 amount);
    event SetManagementFee(uint256 indexed mFeePercent, address indexed mFeeReceiver);

    // External and Public Functions
    function initialize(
        address _usdc,
        address _water,
        address _rewardRouterV2,
        address _vault,
        address _rewardsVault
    ) external;

    function setAllowed(address _sender, bool _allowed) external;

    function setMFeePercent(uint256 _mFeePercent, address _mFeeReceiver) external;

    function setAssetWhitelist(address _asset, bool _status) external;

    function setCloser(address _closer, bool _allowed) external;

    function setBurner(address _burner, bool _allowed) external;

    function setMaxAndMinLeverage(uint256 _maxLeverage, uint256 _minLeverage) external;

    function setProtocolFee(
        address _feeReceiver,
        uint256 _withdrawalFee,
        address _waterFeeReceiver,
        uint256 _liquidatorsRewardPercentage,
        uint256 _fixedFeeSplit
    ) external;

    function setStrategyContracts(
        address _rewardRouterV2,
        address _vault,
        address _rewardVault,
        address _glpRewardHandler,
        address _water
    ) external;

    function setStrategyAddresses(
        address _masterChef,
        uint256 _mcPid,
        address _keeper,
        address _kyberRouter
    ) external;

    function setLiquidationThreshold(uint256 _threshold) external;

    function pause() external;

    function unpause() external;

    function transferEsGMX(address _destination) external;

    function getGLPPrice(bool _maximise) external view returns (uint256);

    function getAllUsers() external view returns (address[] memory);

    function getTotalNumbersOfOpenPositionBy(address _user) external view returns (uint256);

    function getAggregatePosition(address _user) external view returns (uint256);

    function getUpdatedDebt(
        uint256 _positionID,
        address _user
    ) external view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt);

    function getCurrentPosition(
        uint256 _positionID,
        uint256 _shares,
        address _user
    ) external view returns (uint256 currentPosition, uint256 previousValueInUSDC);

    function handleAndCompoundRewards() external returns (uint256);

    function openPosition(
        uint256 _amount,
        uint256 _leverage,
        bytes calldata _data,
        bool _swapSimple,
        address _inputAsset
    ) external;

    function closePosition(
        uint256 _positionID,
        address _user,
        bool _sameSwap
    ) external;

    function fulfilledRequestSwap(
        uint256 _positionID,
        bytes calldata _data,
        bool _swapSimple,
        address _outputAsset
    ) external;

    function liquidatePosition(uint256 _positionId, address _user) external;

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function burn(uint256 amount) external;
}