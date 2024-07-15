// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

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
