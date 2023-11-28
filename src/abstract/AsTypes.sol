// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

struct Fees {
    uint64 perf;
    uint64 mgmt;
    uint64 entry;
    uint64 exit;
}

struct Checkpoint {
    uint256 accountedSharePrice;
    uint256 feeCollection;
    uint256 liquidate;
    uint256 harvest;
}

struct Erc7540Request {
    uint256 depositAmount;
    uint256 redeemAmount;
    address operator; // receiver/claimer
    uint256 timestamp;
    uint256 sharePrice;
}
