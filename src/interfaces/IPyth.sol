// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/**
 * @title PythStructs
 * @dev Contains data structures used in Pyth contracts.
 * cf. https://github.com/pyth-network/pyth-sdk-solidity/blob/main/AbstractPyth.sol
 */
contract PythStructs {
    // Struct representing a price with uncertainty
    struct Price {
        int64 price; // Price value
        uint64 conf; // Confidence interval
        int32 expo; // Price exponent
        uint publishTime; // Timestamp of price externalation
    }

    // Struct representing an aggregate price feed
    struct PriceFeed {
        bytes32 id; // Price feed ID
        Price price; // Latest available price
        Price emaPrice; // Latest available exponentially-weighted moving average price
    }
}

/**
 * @title PythErrors
 * @dev Contains custom errors used in Pyth contracts.
 */
library PythErrors {
    error InvalidArgument(); // Invalid function arguments
    error InvalidUpdateDataSource(); // Invalid update data source
    error InvalidUpdateData(); // Invalid update data
    error InsufficientFee(); // Insufficient fee paid
    error NoFreshUpdate(); // No fresh update available
    error PriceFeedNotFoundWithinRange(); // Price feed not found within the specified range
    error PriceFeedNotFound(); // Price feed not found
    error StalePrice(); // Requested price is stale
    error InvalidWormholeVaa(); // Invalid Wormhole VAA
    error InvalidGovernanceMessage(); // Invalid governance message
    error InvalidGovernanceTarget(); // Invalid governance target
    error InvalidGovernanceDataSource(); // Invalid governance data source
    error OldGovernanceMessage(); // Old governance message
}

/**
 * @title IPythEvents
 * @dev Interface for Pyth contract events.
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
 * @dev Interface for consuming prices from the Pyth Network.
 */
interface IPythAggregator is IPythEvents {
    function getValidTimePeriod() external view returns (uint validTimePeriod);
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
        uint age
    ) external view returns (PythStructs.Price memory price);

    function getEmaPriceUnsafe(
        bytes32 id
    ) external view returns (PythStructs.Price memory price);

    function getEmaPriceNoOlderThan(
        bytes32 id,
        uint age
    ) external view returns (PythStructs.Price memory price);

    function updatePriceFeeds(bytes[] calldata updateData) external payable;

    function updatePriceFeedsIfNecessary(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64[] calldata publishTimes
    ) external payable;

    function getUpdateFee(
        bytes[] calldata updateData
    ) external view returns (uint feeAmount);

    function parsePriceFeedUpdates(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64 minPublishTime,
        uint64 maxPublishTime
    ) external payable returns (PythStructs.PriceFeed[] memory priceFeeds);
}
