// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./Types.sol";

interface IAaveV3Pool {
  // Events
  event MintUnbacked(
    address indexed reserve,
    address user,
    address indexed onBehalfOf,
    uint256 amount,
    uint16 indexed referralCode
  );

  event BackUnbacked(
    address indexed reserve,
    address indexed backer,
    uint256 amount,
    uint256 fee
  );

  event Supply(
    address indexed reserve,
    address user,
    address indexed onBehalfOf,
    uint256 amount,
    uint16 indexed referralCode
  );

  event Withdraw(
    address indexed reserve,
    address indexed user,
    address indexed to,
    uint256 amount
  );

  event Borrow(
    address indexed reserve,
    address user,
    address indexed onBehalfOf,
    uint256 amount,
    DataTypes.InterestRateMode interestRateMode,
    uint256 borrowRate,
    uint16 indexed referralCode
  );

  event Repay(
    address indexed reserve,
    address indexed user,
    address indexed repayer,
    uint256 amount,
    bool useATokens
  );

  event SwapBorrowRateMode(
    address indexed reserve,
    address indexed user,
    DataTypes.InterestRateMode interestRateMode
  );

  event IsolationModeTotalDebtUpdated(address indexed asset, uint256 totalDebt);

  event UserEModeSet(address indexed user, uint8 categoryId);

  event ReserveUsedAsCollateralEnabled(
    address indexed reserve,
    address indexed user
  );

  event ReserveUsedAsCollateralDisabled(
    address indexed reserve,
    address indexed user
  );

  event RebalanceStableBorrowRate(
    address indexed reserve,
    address indexed user
  );

  event FlashLoan(
    address indexed target,
    address initiator,
    address indexed asset,
    uint256 amount,
    DataTypes.InterestRateMode interestRateMode,
    uint256 premium,
    uint16 indexed referralCode
  );

  event LiquidationCall(
    address indexed collateralAsset,
    address indexed debtAsset,
    address indexed user,
    uint256 debtToCover,
    uint256 liquidatedCollateralAmount,
    address liquidator,
    bool receiveAToken
  );

  event ReserveDataUpdated(
    address indexed reserve,
    uint256 liquidityRate,
    uint256 stableBorrowRate,
    uint256 variableBorrowRate,
    uint256 liquidityIndex,
    uint256 variableBorrowIndex
  );

  event MintedToTreasury(address indexed reserve, uint256 amountMinted);

  // Functions
  function mintUnbacked(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
  ) external;

  function backUnbacked(address asset, uint256 amount, uint256 fee) external;

  function supply(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
  ) external;

  function supplyWithPermit(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode,
    uint256 deadline,
    uint8 permitV,
    bytes32 permitR,
    bytes32 permitS
  ) external;

  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external returns (uint256);

  function borrow(
    address asset,
    uint256 amount,
    uint256 interestRateMode,
    uint16 referralCode,
    address onBehalfOf
  ) external;

  function repay(
    address asset,
    uint256 amount,
    uint256 interestRateMode,
    address onBehalfOf
  ) external returns (uint256);

  function repayWithPermit(
    address asset,
    uint256 amount,
    uint256 interestRateMode,
    address onBehalfOf,
    uint256 deadline,
    uint8 permitV,
    bytes32 permitR,
    bytes32 permitS
  ) external returns (uint256);

  function repayWithATokens(
    address asset,
    uint256 amount,
    uint256 interestRateMode
  ) external returns (uint256);

  function swapBorrowRateMode(address asset, uint256 interestRateMode) external;

  function rebalanceStableBorrowRate(address asset, address user) external;

  function setUserUseReserveAsCollateral(
    address asset,
    bool useAsCollateral
  ) external;

  function liquidationCall(
    address collateralAsset,
    address debtAsset,
    address user,
    uint256 debtToCover,
    bool receiveAToken
  ) external;

  function flashLoan(
    address receiverAddress,
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata interestRateModes,
    address onBehalfOf,
    bytes calldata params,
    uint16 referralCode
  ) external;

  function flashLoanSimple(
    address receiverAddress,
    address asset,
    uint256 amount,
    bytes calldata params,
    uint16 referralCode
  ) external;

  function getUserAccountData(
    address user
  )
    external
    view
    returns (
      uint256 totalCollateralBase,
      uint256 totalDebtBase,
      uint256 availableBorrowsBase,
      uint256 currentLiquidationThreshold,
      uint256 ltv,
      uint256 healthFactor
    );

  function initReserve(
    address asset,
    address aTokenAddress,
    address stableDebtAddress,
    address variableDebtAddress,
    address interestRateStrategyAddress
  ) external;

  function dropReserve(address asset) external;

  function setReserveInterestRateStrategyAddress(
    address asset,
    address rateStrategyAddress
  ) external;

  function setConfiguration(
    address asset,
    DataTypes.ReserveConfigurationMap calldata configuration
  ) external;

  function getConfiguration(
    address asset
  ) external view returns (DataTypes.ReserveConfigurationMap memory);

  function getUserConfiguration(
    address user
  ) external view returns (DataTypes.UserConfigurationMap memory);

  function getReserveNormalizedIncome(
    address asset
  ) external view returns (uint256);

  function getReserveNormalizedVariableDebt(
    address asset
  ) external view returns (uint256);

  function getReserveData(
    address asset
  ) external view returns (DataTypes.ReserveData memory);

  function finalizeTransfer(
    address asset,
    address from,
    address to,
    uint256 amount,
    uint256 balanceFromBefore,
    uint256 balanceToBefore
  ) external;

  function getReservesList() external view returns (address[] memory);

  function getReserveAddressById(uint16 id) external view returns (address);

  function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider);

  function updateBridgeProtocolFee(uint256 bridgeProtocolFee) external;

  function updateFlashloanPremiums(
    uint128 flashLoanPremiumTotal,
    uint128 flashLoanPremiumToProtocol
  ) external;

  function configureEModeCategory(
    uint8 id,
    DataTypes.EModeCategory memory config
  ) external;

  function getEModeCategoryData(
    uint8 id
  ) external view returns (DataTypes.EModeCategory memory);

  function setUserEMode(uint8 categoryId) external;

  function getUserEMode(address user) external view returns (uint256);

  function resetIsolationModeTotalDebt(address asset) external;

  function MAX_STABLE_RATE_BORROW_SIZE_PERCENT()
    external
    view
    returns (uint256);

  function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);

  function BRIDGE_PROTOCOL_FEE() external view returns (uint256);

  function FLASHLOAN_PREMIUM_TO_PROTOCOL() external view returns (uint128);

  function MAX_NUMBER_RESERVES() external view returns (uint16);

  function mintToTreasury(address[] calldata assets) external;

  function rescueTokens(address token, address to, uint256 amount) external;

  function deposit(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
  ) external;
}

interface IRewardsController {
  function claimAllRewardsToSelf(
    address[] calldata assets
  )
    external
    returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}

interface IFlashLoanReceiver {
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external returns (bool);

  function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider);

  function POOL() external view returns (IAaveV3Pool);
}

interface IFlashLoanSimpleReceiver {
  function executeOperation(
    address asset,
    uint256 amount,
    uint256 premium,
    address initiator,
    bytes calldata params
  ) external returns (bool);

  function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider);

  function POOL() external view returns (IAaveV3Pool);
}

interface IPoolAddressesProvider {
  // Events
  event MarketIdSet(string indexed oldMarketId, string indexed newMarketId);

  event PoolUpdated(address indexed oldAddress, address indexed newAddress);

  event PoolConfiguratorUpdated(
    address indexed oldAddress,
    address indexed newAddress
  );

  event PriceOracleUpdated(
    address indexed oldAddress,
    address indexed newAddress
  );

  event ACLManagerUpdated(
    address indexed oldAddress,
    address indexed newAddress
  );

  event ACLAdminUpdated(address indexed oldAddress, address indexed newAddress);

  event PriceOracleSentinelUpdated(
    address indexed oldAddress,
    address indexed newAddress
  );

  event PoolDataProviderUpdated(
    address indexed oldAddress,
    address indexed newAddress
  );

  event ProxyCreated(
    bytes32 indexed id,
    address indexed proxyAddress,
    address indexed implementationAddress
  );

  event AddressSet(
    bytes32 indexed id,
    address indexed oldAddress,
    address indexed newAddress
  );

  event AddressSetAsProxy(
    bytes32 indexed id,
    address indexed proxyAddress,
    address oldImplementationAddress,
    address indexed newImplementationAddress
  );

  // Functions
  function getMarketId() external view returns (string memory);

  function setMarketId(string calldata newMarketId) external;

  function getAddress(bytes32 id) external view returns (address);

  function setAddressAsProxy(
    bytes32 id,
    address newImplementationAddress
  ) external;

  function setAddress(bytes32 id, address newAddress) external;

  function getPool() external view returns (address);

  function setPoolImpl(address newPoolImpl) external;

  function getPoolConfigurator() external view returns (address);

  function setPoolConfiguratorImpl(address newPoolConfiguratorImpl) external;

  function getPriceOracle() external view returns (address);

  function setPriceOracle(address newPriceOracle) external;

  function getACLManager() external view returns (address);

  function setACLManager(address newAclManager) external;

  function getACLAdmin() external view returns (address);

  function setACLAdmin(address newAclAdmin) external;

  function getPriceOracleSentinel() external view returns (address);

  function setPriceOracleSentinel(address newPriceOracleSentinel) external;

  function getPoolDataProvider() external view returns (address);

  function setPoolDataProvider(address newDataProvider) external;
}

interface IPriceOracleGetter {
  // Functions
  function BASE_CURRENCY() external view returns (address);

  function BASE_CURRENCY_UNIT() external view returns (uint256);

  function getAssetPrice(address asset) external view returns (uint256);
}

interface IAaveOracle is IPriceOracleGetter {
  // Events
  event BaseCurrencySet(address indexed baseCurrency, uint256 baseCurrencyUnit);

  event AssetSourceUpdated(address indexed asset, address indexed source);

  event FallbackOracleUpdated(address indexed fallbackOracle);

  // Functions
  function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider);

  function setAssetSources(
    address[] calldata assets,
    address[] calldata sources
  ) external;

  function setFallbackOracle(address fallbackOracle) external;

  function getAssetsPrices(
    address[] calldata assets
  ) external view returns (uint256[] memory);

  function getSourceOfAsset(address asset) external view returns (address);

  function getFallbackOracle() external view returns (address);
}
