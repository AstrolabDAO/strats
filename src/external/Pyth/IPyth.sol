// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * @title PythStructs
 * @dev Contains data structures used in Pyth contracts
 * cf. https://github.com/pyth-network/pyth-sdk-solidity/blob/main/AbstractPyth.sol
 */
contract PythStructs {
  // Struct representing a price with uncertainty
  struct Price {
    int64 price; // price value
    uint64 conf; // confidence interval
    int32 expo; // price exponent
    uint256 publishTime; // timestamp of price externalation
  }

  // Struct representing an aggregate price feed
  struct PriceFeed {
    bytes32 id; // price feed ID
    Price price; // latest available price
    Price emaPrice; // latest available exponentially-weighted moving average price
  }
}

/**
 * @title PythErrors
 * @dev Contains custom errors used in Pyth contracts
 */
library PythErrors {
  error InvalidArgument(); // invalid function arguments
  error InvalidUpdateDataSource(); // invalid update data source
  error InvalidUpdateData(); // invalid update data
  error InsufficientFee(); // insufficient fee paid
  error NoFreshUpdate(); // no fresh update available
  error PriceFeedNotFoundWithinRange(); // price feed not found within the specified range
  error PriceFeedNotFound(); // price feed not found
  error StalePrice(); // requested price is stale
  error InvalidWormholeVaa(); // invalid Wormhole VAA
  error InvalidGovernanceMessage(); // invalid governance message
  error InvalidGovernanceTarget(); // invalid governance target
  error InvalidGovernanceDataSource(); // invalid governance data source
  error OldGovernanceMessage(); // old governance message
}

/**
 * @title IPythEvents
 * @dev Interface for Pyth contract events
 */
interface IPythEvents {
  event PriceFeedUpdate(
    bytes32 indexed id,
    uint64 publishTime,
    int64 price,
    uint64 conf
  );
  event BatchPriceFeedUpdate(uint16 chainId, uint64 sequenceNumber);
}

/**
 * @title IPythAggregator
 * @dev Interface for consuming prices from the Pyth Network
 */
interface IPythAggregator is IPythEvents {
  function getValidTimePeriod() external view returns (uint256 validTimePeriod);

  function priceFeedExists(bytes32 id) external view returns (bool exists);

  function queryPriceFeed(
    bytes32 id
  ) external view returns (PythStructs.PriceFeed memory priceFeed);

  function getPrice(
    bytes32 id
  ) external view returns (PythStructs.Price memory price);

  function getEmaPrice(
    bytes32 id
  ) external view returns (PythStructs.Price memory price);

  function getPriceUnsafe(
    bytes32 id
  ) external view returns (PythStructs.Price memory price);

  function getPriceNoOlderThan(
    bytes32 id,
    uint256 age
  ) external view returns (PythStructs.Price memory price);

  function getEmaPriceUnsafe(
    bytes32 id
  ) external view returns (PythStructs.Price memory price);

  function getEmaPriceNoOlderThan(
    bytes32 id,
    uint256 age
  ) external view returns (PythStructs.Price memory price);

  function updatePriceFeeds(bytes[] calldata updateData) external payable;

  function updatePriceFeedsIfNecessary(
    bytes[] calldata updateData,
    bytes32[] calldata priceIds,
    uint64[] calldata publishTimes
  ) external payable;

  function getUpdateFee(
    bytes[] calldata updateData
  ) external view returns (uint256 feeAmount);

  function parsePriceFeedUpdates(
    bytes[] calldata updateData,
    bytes32[] calldata priceIds,
    uint64 minPublishTime,
    uint64 maxPublishTime
  ) external payable returns (PythStructs.PriceFeed[] memory priceFeeds);
}
