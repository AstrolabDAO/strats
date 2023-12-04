// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IRumVault {
    // Event declarations
    event SetManagementFee(uint256 mFeePercent, address mFeeReceiver);
    event SetAllowedSenders(address sender, bool allowed);
    event SetBurner(address burner, bool allowed);
    event SetMCPID(uint256 MCPID);
    event DTVLimitSet(uint256 DTVLimit, uint256 DTVSlippage);
    event UpdateMaxAndMinLeverage(uint256 maxLeverage, uint256 minLeverage);
    event ProtocolFeeChanged(
        address feeReceiver,
        uint256 withdrawalFee,
        address waterFeeReceiver,
        uint256 liquidatorsRewardPercentage,
        uint256 fixedFeeSplit,
        uint256 keeperFee,
        uint256 slippageTolerance
    );
    event HMXVestingChanged(address hmxStaking, address vester, address hmx);
    event StrategyContractsChanged(
        address USDC,
        address hmxCalculator,
        address hlpLiquidityHandler,
        address hlpStaking,
        address hlpCompounder,
        address water,
        address MasterChef,
        address hlp,
        address hlpRewardHandler,
        address keeper
    );
    event RequestedOpenPosition(address user, uint256 amount, uint256 timestamp, uint256 orderId);
    event OpenPositionCancelled(address user, uint256 amount, uint256 timestamp, uint256 orderId);
    event FulfilledOpenPosition(
        address user,
        uint256 deposit,
        uint256 receivedHLP,
        uint256 timestamp,
        uint32 positionId,
        uint256 hlpPrice,
        uint256 orderId
    );
    event RequestedClosePosition(address user, uint256 amount, uint256 timestamp, uint256 orderId, uint32 positionId);
    event ClosePositionCancelled(address user, uint256 amount, uint256 timestamp, uint256 orderId, uint32 positionId);
    event FulfilledClosePosition(
        address user,
        uint256 amount,
        uint256 timestamp,
        uint256 position,
        uint256 profits,
        uint256 hlpPrice,
        uint32 positionId,
        uint256 orderId
    );
    event Liquidated(
        address user,
        uint256 positionId,
        address liquidator,
        uint256 amount,
        uint256 reward,
        uint256 orderId
    );
    event USDCHarvested(uint256 amount);

    // External and Public Functions
    function initialize() external;

    function setMFeePercent(uint256 _mFeePercent, address _mFeeReceiver) external;

    function setAllowed(address _sender, bool _allowed) external;

    function setBurner(address _burner, bool _allowed) external;

    function setMCPID(uint256 _MCPID) external;

    function setLeverageParams(
        uint256 _maxLeverage,
        uint256 _minLeverage,
        uint256 _DTVLimit,
        uint256 _DTVSlippage,
        uint256 _debtValueRatio,
        uint256 _timeAdjustment
    ) external;

    function setProtocolFee(
        address _feeReceiver,
        uint256 _withdrawalFee,
        address _waterFeeReceiver,
        uint256 _liquidatorsRewardPercentage,
        uint256 _fixedFeeSplit,
        uint256 _hlpFee,
        uint256 _keeperFee,
        uint256 _slippageTolerance
    ) external;

    function setHMXVesting(address hmxStaking, address vester, address hmx) external;

    function setStrategyAddresses(
        address _USDC,
        address _hmxCalculator,
        address _hlpLiquidityHandler,
        address _hlpStaking,
        address _hlpCompounder,
        address _water,
        address _MasterChef,
        address _hlp,
        address _hlpRewardHandler,
        address _keeper
    ) external;

    function vestEsHmx(uint256 _amount) external;

    function claimVesting(uint256[] calldata indexes) external;

    function cancelVesting(uint256 index) external;

    function getCurrentLeverageAmount(uint256 _positionID, address _user) external view returns (uint256);

    function getHLPPrice(bool _maximise) external view returns (uint256);

    function getAllUsers() external view returns (address[] memory);

    function getNumbersOfPosition(address _user) external view returns (uint256);

    function getUtilizationRate() external view returns (uint256);

    function getPosition(
        uint256 _positionID,
        address _user,
        uint256 hlpPrice
    ) external view returns (uint256, uint256, uint256, uint256, uint256);

    function handleAndCompoundRewards(
        address[] calldata pools,
        address[][] calldata rewarder
    ) external returns (uint256 amount);

    function requestOpenPosition(uint256 _amount, uint16 _leverage) external payable returns (uint256);

    function fulfillOpenCancellation(uint256 orderId) external returns (bool);

    function fulfillOpenPosition(uint256 orderId, uint256 _actualOut) external returns (bool);

    function requestClosePosition(uint32 _positionID) external payable;

    function fulfillCloseCancellation(uint256 orderId) external returns (bool);

    function fulfillClosePosition(uint256 _orderId, uint256 _returnedUSDC) external returns (bool);

    function requestLiquidatePosition(address _user, uint256 _positionID) external payable;

    function fulfillLiquidation(uint256 _orderId, uint256 _returnedUSDC) external;

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function burn(uint256 amount) external;

    function withdrawArb(address _arbToken, address _receiver, uint256 _amount) external;
}
