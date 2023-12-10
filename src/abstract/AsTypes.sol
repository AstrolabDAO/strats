// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

// As4626 fee structure
struct Fees {
    uint64 perf; // Performance fee
    uint64 mgmt; // Management fee
    uint64 entry; // Entry fee
    uint64 exit; // Exit fee
}

// StrategyV5 init params
struct StrategyBaseParams {
    Fees fees;
    address underlying;
    address[3] coreAddresses;
    address[] inputs;
    uint16[] inputWeights;
    address[] rewardTokens;
}

// ERC7540 Requests used by strategies to manage asynchronous deposits and redemptions
struct Requests {
    uint256 redemptionLocktime; // Locktime for redemption requests = 2 days
    uint256 totalDeposit; // Total amount requested for deposit
    uint256 totalRedemption; // Total amount requested for redemption
    uint256 totalUnderlying; // Total underlying requested
    uint256 totalClaimableRedemption; // Total amount claimable for redemption
    uint256 totalClaimableUnderlying; // Total claimable underlying
    mapping(address => Erc7540Request) byOperator; // Mapping of ERC7540 requests by operator
}

// Checkpoint used to by strategies to keep track of latest events
struct Checkpoint {
    uint256 accountedSharePrice; // Last accounted share price (fee collection) from the checkpoint
    uint256 feeCollection; // Last fee collection timestamp from the checkpoint
    uint256 liquidate; // Last liquidation timestamp from the checkpoint
    uint256 harvest; // Last harvest timestamp from the checkpoint
}

// ERC7540 Request
struct Erc7540Request {
    uint256 shares; // Amount of shares in the request
    address operator; // Request owner (can claim the owner's request)
    uint256 timestamp; // Timestamp of the request
    uint256 sharePrice; // Share price at request time
}
