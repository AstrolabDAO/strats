// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

struct Fees {
    uint64 perf;
    uint64 mgmt;
    uint64 entry;
    uint64 exit;
}

struct Checkpoint {
    uint256 timestamp;
    uint256 sharePrice;
}
