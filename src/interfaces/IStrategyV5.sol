// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "./IAs4626.sol";

interface IStrategyV5Abstract is IAs4626 {
    function swapper() external view returns (address);

    function agent() external view returns (address);

    function stratProxy() external view returns (address);

    function inputs() external view returns (address[8] memory);

    function inputWeights() external view returns (uint16[8] memory);

    function rewardTokens() external view returns (address[8] memory);

    function inputLength() external view returns (uint8);

    function rewardLength() external view returns (uint8);
}

interface IStrategyV5 is IStrategyV5Abstract {
    function claimRewards() external returns (uint256[] memory amounts);

    function rewardsAvailable()
        external
        view
        returns (uint256[] memory amounts);

    function previewInvest(
        uint256 _amount
    ) external view returns (uint256[8] memory amounts);

    function previewLiquidate(
        uint256 _amount
    ) external view returns (uint256[8] memory amounts);

    function invest(
        uint256[8] calldata _amounts,
        bytes[] calldata _params
    ) external returns (uint256 investedAmount, uint256 iouReceived);

    function harvest(bytes[] calldata _params) external returns (uint256 amount);

    function compound(
        uint256[8] calldata _amounts,
        uint256 _minIouReceived,
        bytes[] memory _harvestParams,
        bytes[] memory _investParams
    ) external returns (uint256 iouReceived, uint256 harvestedRewards);

    function liquidate(
        uint256[8] calldata _amount,
        uint256 _minLiquidity,
        bool _panic,
        bytes[] calldata _params
    ) external returns (uint256 liquidityAvailable);

    function liquidateRequest(uint256 _amount) external returns (uint256);

    function rescueToken(address _token, bool _onlyETH) external;

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
