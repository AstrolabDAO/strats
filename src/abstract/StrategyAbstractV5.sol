// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@astrolabs/swapper/contracts/Swapper.sol";
import "./As4626Abstract.sol";

abstract contract StrategyAbstractV5 is As4626Abstract {

    event Harvested(uint256 amount, uint256 timestamp);
    event Compounded(uint256 amount, uint256 timestamp);
    event Invested(uint256 amount, uint256 timestamp);
    event AgentUpdated(address indexed addr);
    event SwapperUpdated(address indexed addr);
    event AllocatorUpdated(address indexed addr);
    event SwapperAllowanceSet(uint256 amount);

    Swapper public swapper;
    address public agent;
    address public allocator;
    uint256 public lastHarvest;

    // inputs are assets being used to farm, asset is swapped into inputs
    IERC20Metadata[16] public inputs;
    // inputs weight in bps vs underlying asset
    uint256[] public inputWeights;

    // reward tokens are the tokens harvested at compound and liquidate times
    address[16] public rewardTokens;

    constructor(string[3] memory _erc20Metadata) As4626Abstract(_erc20Metadata) {}
}
