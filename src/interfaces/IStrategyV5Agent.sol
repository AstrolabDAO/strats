// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import "./IAs4626.sol";
import "./IERC3156FlashLender.sol";
import "../abstract/AsTypes.sol";

interface IStrategyV5Agent is IAs4626, IERC3156FlashLender {
    // Custom types from inherited contracts and StrategyV5Agent specific
    struct StrategyBaseParams {
        Erc20Metadata erc20Metadata;
        CoreAddresses coreAddresses;
        Fees fees;
        address[] inputs;
        uint16[] inputWeights;
        address[] rewardTokens;
    }

    // Initialization function
    function init(StrategyBaseParams calldata _params) external;

    // View functions
    function totalAssets() external view returns (uint256);
    function available() external view returns (uint256);
    function availableClaimable() external view returns (uint256);
    function availableBorrowable() external view returns (uint256);
    function maxRedeem(address _owner) external view returns (uint256);

    // Setters
    function setExemption(address _account, bool _isExempt) external;
    function setSwapperAllowance(uint256 _amount, bool _inputs, bool _rewards, bool _asset) external;
    function updateSwapper(address _swapper) external;
    function updateAsset(address _asset, bytes calldata _swapData, uint256 _priceFactor) external;
    function setInputWeights(uint16[] calldata _weights) external;
    function setInputs(address[] calldata _inputs, uint16[] calldata _weights) external;
    function setRewardTokens(address[] calldata _rewardTokens) external;
}
