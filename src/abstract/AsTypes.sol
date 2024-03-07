// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.22;

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
}
// address allocator;

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
  uint256 timestamp; // timestamp of the request
  uint256 sharePrice; // share price at request time
  address operator; // request owner (can claim the owner's request)
  uint256 shares; // amount of shares in the request
  uint256 requestId; // request ID
}

// ERC7540 Requests used by strategies to manage asynchronous deposits and redemptions
struct Requests {
  uint256 redemptionLocktime; // locktime for redemption requests = 2 days
  uint256 totalDeposit; // total amount requested for deposit
  uint256 totalRedemption; // total shares requested for redemption (1e8)
  uint256 totalClaimableRedemption; // total shares claimable for redemption (1e8)
  mapping(address => Erc7540Request) byOwner; // mapping of ERC7540 requests by owner
}

// Epoch used to by strategies to keep track of latest events
struct Epoch {
  // dates
  uint64 feeCollection; // last fee collection timestamp
  uint64 liquidate; // last liquidation timestamp
  uint64 harvest; // last harvest timestamp
  uint64 invest; // last invest timestamp
  // values
  uint256 sharePrice; // last used share sharePrice (at deposit/withdraw/liquidate time)
  uint256 accountedSharePrice; // last accounted share price (at fee collection time)
  uint256 accountedProfit; // last accounted profit (fee collection) 1e8
  uint256 accountedAssets; // last accounted total assets (fee collection)
  uint256 accountedSupply; // last accounted total supply (fee collection)
}
