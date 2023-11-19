// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@astrolabs/swapper/contracts/Swapper.sol";
import "./interfaces/IAllocator.sol";
import "./As4626.sol";

abstract contract StrategyV5 is As4626 {
    using AsMaths for uint256;
    using AsMaths for int256;
    using SafeERC20 for IERC20;

    event Harvested(uint256 amount, uint256 timestamp);
    event Compounded(uint256 amount, uint256 timestamp);
    event Invested(uint256 amount, uint256 timestamp);
    event SwapperUpdated(address indexed swapper);
    event SwapperAllowanceReset();
    event SwapperAllowanceSet();

    error FailedToSwap(string reason);

    address public allocator;
    uint256 public lastHarvest;

    // inputs are assets being used to farm, asset is swapped into inputs
    IERC20Metadata[16] public inputs;
    // inputs weight in bps vs underlying asset
    // (eg. 80% USDC, 20% DAI -> [8000, 2000] ->
    // swap 20% USDC->DAI on deposit, swap 20% DAI->USDC on withdraw)
    uint256[] public inputWeights;

    // reward tokens are the tokens harvested at compound and liquidate times
    // available reward amounts are available rewardsAvailable()
    // and swapped back into inputs at compound of liquidate time////
    address[16] public rewardTokens;
    Swapper public swapper;

    constructor(
        string[] memory _erc20Metadata // name,symbol,version (EIP712)
    ) As4626(_erc20Metadata) {}

    function _initialize(
        Fees memory _fees,
        address _underlying,
        address[] memory _coreAddresses
    ) internal virtual {
        As4626._initialize(_fees, _underlying, _coreAddresses[0]);
        swapper = Swapper(_coreAddresses[1]);
        allocator = _coreAddresses[2];
        inputs[0] = IERC20Metadata(_underlying);
    }

    modifier onlyInternal() {
        internalCheck();
        _;
    }

    function internalCheck() internal view {
        if (!(hasRole(KEEPER_ROLE, msg.sender) || msg.sender == allocator))
            revert Unauthorized();
    }

    function setRewardTokens(
        address[] memory _rewardTokens
    ) external onlyManager {
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            inputs[i] = IERC20Metadata(_rewardTokens[i]);
        }
    }

    function setInputs(
        address[] memory _inputs,
        uint256[] memory _weights
    ) external onlyManager {
        for (uint256 i = 0; i < _inputs.length; i++) {
            inputs[i] = IERC20Metadata(_inputs[i]);
        }
        inputWeights = _weights;
    }

    function setAllocator(address _allocator) external onlyManager {
        allocator = _allocator;
    }

    /// @notice amount of reward tokens available and not yet harvested
    /// @dev abstract function to be implemented by the strategy
    /// @return rewardAmounts amount of reward tokens available
    function rewardsAvailable()
        external
        view
        returns (uint256[] memory rewardAmounts)
    {
        return _rewardsAvailable();
    }

    // implemented by strategies
    function _liquidate(
        uint256 _amount,
        bytes[] memory _params
    ) internal virtual returns (uint256 assetsRecovered) {}

    // implemented by strategies
    function _withdrawRequest(
        uint256 _amount
    ) internal virtual returns (uint256) {}

    // implemented by strategies
    function _harvest(
        bytes[] memory _params
    ) internal virtual returns (uint256 amount) {}

    // implemented by strategies
    function _invest(
        uint256 _amount,
        uint256 _minIouReceived,
        bytes[] memory _params
    ) internal virtual returns (uint256 investedAmount, uint256 iouReceived) {}

    // implemented by strategies
    function _compound(
        uint256 _amount,
        uint256 minIouReceived,
        bytes[] memory _params
    )
        internal
        virtual
        returns (uint256 iouReceived, uint256 harvestedRewards)
    {}

    function compound(
        uint256 _amount,
        uint _minIouReceived,
        bytes[] memory _params
    ) external onlyKeeper returns (uint256 iouReceived, uint256 harvestedRewards) {
        (iouReceived, harvestedRewards) = _compound(
            _amount,
            _minIouReceived,
            _params
        );
        emit Compounded(_amount, block.timestamp);
    }

    // implemented by strategies
    function _rewardsAvailable()
        internal
        view
        virtual
        returns (uint256[] memory rewardAmounts)
    {}

    function _setAllowances(uint256 _amount) internal virtual {}

    // implemented by strategies
    function _swapRewards(
        uint256[] memory _minAmountsOut,
        bytes memory _params
    ) internal virtual returns (uint256 amountsOut) {}

}
