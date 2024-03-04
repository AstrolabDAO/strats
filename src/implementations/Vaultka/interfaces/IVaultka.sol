// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

// Interfaces for AlpVault, RumVault, and VodkaV1
//  openPosition(uint256 _amount, uint256 _leverage, bytes calldata _data, bool _swapSimple, address _inputAsset) VodkaV1/Sake
//  openPosition(address _token, uint256 _amount, uint256 _leverage) AlpVault
//  requestOpenPosition(uint256 _amount, uint16 _leverage) // RumVault

interface IAlpVault {
    /**
     * @dev Struct representing user-specific information for a position in the strategy
     */
    struct UserInfo {
        address user; // User's address
        uint256 deposit; // Amount deposited by the user
        uint256 leverage; // Leverage applied to the position
        uint256 position; // Current position size
        uint256 price; // Price of the asset at the time of the transaction
        bool liquidated; // Flag indicating if the position has been liquidated
        uint256 closedPositionValue; // Value of the closed position
        address liquidator; // Address of the liquidator, if liquidated
        uint256 closePNL; // Profit and Loss from closing the position
        uint256 leverageAmount; // Amount leveraged in the position
        uint256 positionId; // Unique identifier for the position
        bool closed; // Flag indicating if the position is closed
    }

    /**
     * @dev Struct used to store intermediate data during position closure calculations
     */
    struct CloseData {
        uint256 returnedValue; // The amount returned after position closure
        uint256 profits; // The profits made from the closure
        uint256 originalPosAmount; // The original position amount
        uint256 waterRepayment; // The amount repaid to the lending protocol
        uint256 waterProfits; // The profits received from the lending protocol
        uint256 mFee; // Management fee
        uint256 userShares; // Shares allocated to the user
        uint256 toLeverageUser; // Amount provided to the user after leverages
        uint256 currentDTV; // Current debt-to-value ratio
        bool success; // Flag indicating the success of the closure operation
    }

    // @dev StrategyAddresses struct represents addresses used in the strategy
    struct StrategyAddresses {
        address alpDiamond; // ALP Diamond contract
        address smartChef; // Stake ALP
        address apolloXP; // ApolloX token contract
        address masterChef; // ALP-vodka MasterChef contract
        address alpRewardHandler; // ALP Reward Handler contract
    }

    // @dev StrategyMisc struct represents miscellaneous parameters of the strategy
    struct StrategyMisc {
        uint256 MAX_LEVERAGE; // Maximum allowed leverage
        uint256 MIN_LEVERAGE; // Minimum allowed leverage
        uint256 DECIMAL; // Decimal precision
        uint256 MAX_BPS; // Maximum basis points
    }

    // @dev FeeConfiguration struct represents fee-related parameters of the strategy
    struct FeeConfiguration {
        address feeReceiver; // Fee receiver address
        uint256 withdrawalFee; // Withdrawal fee amount
        address waterFeeReceiver; // Water fee receiver address
        uint256 liquidatorsRewardPercentage; // Liquidator's reward percentage
        uint256 fixedFeeSplit; // Fixed fee split amount
    }

    event SetWhitelistedAsset(address token, bool status);
    event SetStrategyAddresses(address diamond, address alpManager, address apolloXP);
    event SetFeeConfiguration(
        address feeReceiver,
        uint256 withdrawalFee,
        address waterFeeReceiver,
        uint256 liquidatorsRewardPercentage,
        uint256 fixedFeeSplit
    );
    event CAKEHarvested(uint256 amount);

    /**
     * @dev Emitted when a position is opened
     * @param user The address of the user who opened the position
     * @param leverageSize The size of the leverage used for the position
     * @param amountDeposited The amount deposited by the user
     * @param podAmountMinted The amount of POD tokens minted for the position
     * @param positionId The ID of the position opened
     * @param time The timestamp when the position was opened
     */
    event OpenPosition(
        address indexed user,
        uint256 leverageSize,
        uint256 amountDeposited,
        uint256 podAmountMinted,
        uint256 positionId,
        uint256 time
    );

    /**
     * @dev Emitted when a position is closed
     * @param user The address of the user who closed the position
     * @param amountAfterFee The amount remaining after fees are deducted
     * @param positionId The ID of the closed position
     * @param timestamp The timestamp when the position was closed
     * @param position The final position after closure
     * @param leverageSize The size of the leverage used for the position
     * @param time The timestamp of the event emission
     */
    event ClosePosition(address user, uint256 amountAfterFee, uint256 positionId, uint256 timestamp, uint256 position, uint256 leverageSize, uint256 time);

    /**
     * @dev Emitted when a position is liquidated
     * @param user The address of the user whose position is liquidated
     * @param positionId The ID of the liquidated position
     * @param liquidator The address of the user who performed the liquidation
     * @param returnedAmount The amount returned after liquidation
     * @param liquidatorRewards The rewards given to the liquidator
     * @param time The timestamp of the liquidation event
     */
    event Liquidated(address user, uint256 positionId, address liquidator, uint256 returnedAmount, uint256 liquidatorRewards, uint256 time);
    event SetBurner(address indexed burner, bool allowed);
    event SetAllowedClosers(address indexed closer, bool allowed);
    event SetAllowedSenders(address indexed sender, bool allowed);
    event MigrateLP(address indexed newLP, uint256 amount);
    event RewardDistributed(uint256 usdcRewards, uint256 toOwner, uint256 toWater, uint256 toAlpUsers);

    /**
     * @dev Opens a new position
     * @param _token The address of the token for the position
     * @param _amount The amount of tokens to be used for the position
     * @param _leverage The leverage multiplier for the position
     *
     * Requirements:
     * - `_leverage` must be within the range of MIN_LEVERAGE to MAX_LEVERAGE
     * - `_amount` must be greater than zero
     * - `_token` must be whitelisted
     *
     * Steps:
     * - Transfers `_amount` of tokens from the caller to this contract
     * - Uses Water contract to lend a leveraged amount based on the provided `_amount` and `_leverage`
     * - Mints Alp tokens using `_token` and `sumAmount` to participate in ApolloX
     * - Deposits minted Alp tokens into the SmartChef contract
     * - Records user information including deposit, leverage, position, etc
     * - Mints POD tokens for the user
     *
     * Emits an OpenPosition event with relevant details
     */
    function openPosition(address _token, uint256 _amount, uint256 _leverage) external;

    /**
     * @dev Closes a position based on provided parameters
     * @param positionId The ID of the position to close
     * @param _user The address of the user holding the position
     *
     * Requirements:
     * - Position must not be liquidated
     * - Position must have enough shares to close
     * - Caller must be allowed to close the position or must be the position owner
     *
     * Steps:
     * - Retrieves user information for the given position
     * - Validates that the position is not liquidated and has enough shares to close
     * - Handles the POD token for the user
     * - Withdraws the staked amount from the Smart Chef contract
     * - Burns Alp tokens to retrieve USDC based on the position amount
     * - Calculates profits, water repayment, and protocol fees
     * - Repays the Water contract if the position is not liquidated
     * - Transfers profits, fees, and protocol fees to the respective receivers
     * - Takes protocol fees if applicable and emits a ClosePosition event
     */
    function closePosition(uint256 positionId, address _user) external;

    /**
     * @dev Liquidates a position based on provided parameters
     * @param _positionId The ID of the position to be liquidated
     * @param _user The address of the user owning the position
     *
     * Requirements:
     * - Position must not be already liquidated
     * - Liquidation request must exist for the provided user
     * - Liquidation should not exceed the predefined debt-to-value limit
     *
     * Steps:
     * - Retrieves user information for the given position
     * - Validates the position for liquidation based on the debt-to-value limit
     * - Handles the POD token for the user
     * - Burns Alp tokens to retrieve USDC based on the position amount
     * - Calculates liquidator rewards and performs debt repayment to the Water contract
     * - Transfers liquidator rewards and emits a Liquidated event
     */
    function liquidatePosition(uint256 _positionId, address _user) external;

    /**
     * @dev Retrieves the current position and its previous value in USDC for a user's specified position
     * @param _positionID The identifier for the user's position
     * @param _shares The number of shares for the position
     * @param _user The user's address
     * @return currentPosition The current position value in USDC
     * @return previousValueInUSDC The previous position value in USDC
     */
    function getCurrentPosition(
        uint256 _positionID,
        uint256 _shares,
        address _user
    ) external view returns (uint256 currentPosition, uint256 previousValueInUSDC);

    /**
     * @dev Retrieves the updated debt values for a user's specified position
     * @param _positionID The identifier for the user's position
     * @param _user The user's address
     * @return currentDTV The current Debt to Value (DTV) ratio
     * @return currentPosition The current position value in USDC
     * @return currentDebt The current amount of debt associated with the position
     */
    function getUpdatedDebt(
        uint256 _positionID,
        address _user
    ) external view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt);

    /**
     * @dev Retrieves the cooling duration of the APL token from the AlpManagerFacet
     * @return The cooling duration in seconds
     */
    function getAlpCoolingDuration() external view returns (uint256);

    /**
     * @dev Retrieves an array containing all registered user addresses
     * @return An array of all registered user addresses
     */
    function getAllUsers() external view returns (address[] memory);

    /**
     * @dev Retrieves the total number of open positions associated with a specific user
     * @param _user The user's address
     * @return The total number of open positions belonging to the specified user
     */
    function getTotalNumbersOfOpenPositionBy(address _user) external view returns (uint256);

    /**
     * @dev Retrieves the current price of the APL token from the AlpManagerFacet
     * @return The current price of the APL token
     */
    function getAlpPrice() external view returns (uint256);
}

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