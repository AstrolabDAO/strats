// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@astrolabs/swapper/contracts/Swapper.sol";
import "./As4626Abstract.sol";

abstract contract StrategyAbstractV5 is As4626Abstract {

    event Harvest(uint256 amount, uint256 timestamp);
    event Compound(uint256 amount, uint256 timestamp);
    event Invest(uint256 amount, uint256 timestamp);
    event Liquidate(uint256 amount, uint256 liquidityAvailable, uint256 timestamp);
    event AgentUpdate(address indexed addr);
    event SwapperUpdate(address indexed addr);
    event AllocatorUpdate(address indexed addr);
    event SetSwapperAllowance(uint256 amount);

    Swapper public swapper;
    address public agent;
    address public stratProxy;
    address public allocator;
    uint256 public lastHarvest;

    // inputs are assets being used to farm, asset is swapped into inputs
    IERC20Metadata[16] public inputs;
    // inputs weight in bps vs underlying asset
    uint256[16] public inputWeights;

    // reward tokens are the tokens harvested at compound and liquidate times
    address[16] public rewardTokens;

    constructor(string[3] memory _erc20Metadata) As4626Abstract(_erc20Metadata) {}
}
