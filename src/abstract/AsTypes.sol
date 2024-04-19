// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsTypes - Astrolab's types
 * @author Astrolab DAO
 */

/*═══════════════════════════════════════════════════════════════╗
║                              TYPES                             ║
╚═══════════════════════════════════════════════════════════════*/

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
  address oracle;
}

// StrategyV5 init params
struct StrategyParams {
  Erc20Metadata erc20Metadata;
  CoreAddresses coreAddresses;
  Fees fees;
  address[] inputs;
  uint16[] inputWeights;
  address[] lpTokens;
  address[] rewardTokens;
  bytes extension;
}

// ERC-7540 Request
struct Erc7540Request {
  uint256 timestamp; // timestamp of the request
  uint256 sharePrice; // share price at request time
  uint256 shares; // amount of shares in the request
  uint256 requestId; // request ID
  address operator; // request owner (can claim the owner's request)
}

// Request context used to manage a vault's asynchronous deposits and redemptions
struct Requests {
  uint256 redemptionLocktime; // locktime for redemption requests = 2 days
  uint256 totalDeposit; // total amount requested for deposit
  uint256 totalRedemption; // total shares requested for redemption (1e12)
  uint256 totalClaimableRedemption; // total shares claimable for redemption (1e12)
  mapping(address => Erc7540Request) byOwner; // mapping of ERC-7540 requests by owner
}

// Epoch context used to keep track of a vault's latest events
struct Epoch {
  // dates
  uint64 feeCollection; // last fee collection timestamp
  uint64 liquidate; // last liquidation timestamp
  uint64 harvest; // last harvest timestamp
  uint64 invest; // last invest timestamp
  // values
  uint256 sharePrice; // last used share sharePrice (at deposit/withdraw/liquidate time)
  uint256 accountedSharePrice; // last accounted share price (at fee collection time)
  uint256 accountedProfit; // last accounted profit (fee collection) 1e12
  uint256 accountedAssets; // last accounted total assets (fee collection)
  uint256 accountedSupply; // last accounted total supply (fee collection)
}

library Errors {
  /*═══════════════════════════════════════════════════════════════╗
  ║                             ERRORS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  error InvalidInitStatus();
  error Unauthorized();
  error FailedDelegateCall();
  error AmountTooHigh(uint256 amount);
  error AmountTooLow(uint256 amount);
  error AddressZero();
  error InvalidData(); // invalid calldata / inputs
  error InvalidOrStaleValue(uint256 updateTime, int256 value);
  error FlashLoanDefault(address borrower, uint256 amount);
  error FlashLoanCallbackFailed();
  error AcceptanceExpired();
  error AcceptanceLocked();
  error ContractNonCompliant();
  error MissingOracle();
}

library Roles {
  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  bytes32 internal constant ADMIN = 0x00;
  bytes32 internal constant KEEPER = keccak256("KEEPER");
  bytes32 internal constant MANAGER = keccak256("MANAGER");
}
