// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

// As4626 fee structure
struct Fees {
    uint64 perf; // Performance fee
    uint64 mgmt; // Management fee
    uint64 entry; // Entry fee
    uint64 exit; // Exit fee
    uint64 flash; // Flash loan fee
}

struct Erc20Metadata {
    string name;
    string symbol;
    uint8 decimals;
}

struct CoreAddresses {
    address wgas; // wrapped native (WETH/WAVAX...)
    address asset;
    address feeCollector;
    address swapper;
    address agent;
    // address allocator;
}

// StrategyV5 init params
struct StrategyBaseParams {
    Erc20Metadata erc20Metadata;
    CoreAddresses coreAddresses;
    Fees fees;
    address[] inputs;
    uint16[] inputWeights;
    address[] rewardTokens;
}

// ERC7540 Request
struct Erc7540Request {
    uint256 timestamp; // Timestamp of the request
    uint256 sharePrice; // Share price at request time
    address operator; // Request owner (can claim the owner's request)
    uint256 shares; // Amount of shares in the request
}

// ERC7540 Requests used by strategies to manage asynchronous deposits and redemptions
struct Requests {
    uint256 redemptionLocktime; // Locktime for redemption requests = 2 days
    uint256 totalDeposit; // Total amount requested for deposit
    uint256 totalRedemption; // Total shares requested for redemption (1e8)
    uint256 totalClaimableRedemption; // Total shares claimable for redemption (1e8)
    mapping(address => Erc7540Request) byOperator; // Mapping of ERC7540 requests by operator
}

// Epoch used to by strategies to keep track of latest events
struct Epoch {
    // dates
    uint64 feeCollection; // Last fee collection timestamp
    uint64 liquidate; // Last liquidation timestamp
    uint64 harvest; // Last harvest timestamp
    uint64 invest; // Last invest timestamp
    // values
    uint256 sharePrice; // last used share sharePrice (at deposit/withdraw/liquidate time)
    uint256 accountedSharePrice; // Last accounted share price (at fee collection time)
    uint256 accountedProfit; // Last accounted profit (fee collection) 1e8
    uint256 accountedAssets; // Last accounted total assets (fee collection)
    uint256 accountedSupply; // Last accounted total supply (fee collection)
}
