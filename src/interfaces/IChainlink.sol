// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IChainlinkAggregatorV3
 * @dev Interface for consuming prices from the Chainlink Network.
 */
interface IChainlinkAggregatorV3 {
    // Events
    event AnswerUpdated(int256 current, uint256 roundId, uint256 updatedAt);
    event NewRound(uint256 roundId, address startedBy, uint256 startedAt);
    event OwnershipTransferRequested(address from, address to);
    event OwnershipTransferred(address from, address to);

    // Functions
    function acceptOwnership() external;
    function accessController() external view returns (address);
    function aggregator() external view returns (address);
    function confirmAggregator(address _aggregator) external;
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function getAnswer(uint256 _roundId) external view returns (int256);
    function getRoundData(uint256 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function getTimestamp(uint256 _roundId) external view returns (uint256);
    function latestAnswer() external view returns (int256);
    function latestRound() external view returns (uint256);
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function latestTimestamp() external view returns (uint256);
    function owner() external view returns (address payable);
    function phaseAggregators(uint16 index) external view returns (address);
    function phaseId() external view returns (uint16);
    function proposeAggregator(address _aggregator) external;
    function proposedAggregator() external view returns (address);
    function proposedGetRoundData(uint80 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function proposedLatestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function setController(address _accessController) external;
    function transferOwnership(address _to) external;
    function version() external view returns (uint256);
}
