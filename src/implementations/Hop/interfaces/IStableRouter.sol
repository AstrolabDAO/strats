// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStableRouter {
    event AddLiquidity(address indexed provider, uint256[] tokenAmounts, uint256[] fees, uint256 invariant, uint256 lpTokenSupply);
    event NewAdminFee(uint256 newAdminFee);
    event NewSwapFee(uint256 newSwapFee);
    event NewWithdrawFee(uint256 newWithdrawFee);
    event RampA(uint256 oldA, uint256 newA, uint256 initialTime, uint256 futureTime);
    event RemoveLiquidity(address indexed provider, uint256[] tokenAmounts, uint256 lpTokenSupply);
    event RemoveLiquidityImbalance(address indexed provider, uint256[] tokenAmounts, uint256[] fees, uint256 invariant, uint256 lpTokenSupply);
    event RemoveLiquidityOne(address indexed provider, uint256 lpTokenAmount, uint256 lpTokenSupply, uint256 boughtId, uint256 tokensBought);
    event StopRampA(uint256 currentA, uint256 time);
    event TokenSwap(address buyer, uint256 tokensSold, uint256 tokensBought, uint128 soldId, uint128 boughtId);

    function addLiquidity(uint256[] calldata amounts, uint256 minToMint, uint256 deadline) external returns (uint256);
    function calculateCurrentWithdrawFee(address user) external view returns (uint256);
    function calculateRemoveLiquidity(address account, uint256 amount) external view returns (uint256[] memory);
    function calculateRemoveLiquidityOneToken(address account, uint256 tokenAmount, uint8 tokenIndex) external view returns (uint256 availableTokenAmount);
    function calculateSwap(uint8 tokenIndexFrom, uint8 tokenIndexTo, uint256 dx) external view returns (uint256);
    function calculateTokenAmount(address account, uint256[] calldata amounts, bool deposit) external view returns (uint256);
    function getA() external view returns (uint256);
    function getAPrecise() external view returns (uint256);
    function getAdminBalance(uint256 index) external view returns (uint256);
    function getDepositTimestamp(address user) external view returns (uint256);
    function getToken(uint8 index) external view returns (address);
    function getTokenBalance(uint8 index) external view returns (uint256);
    function getTokenIndex(address tokenAddress) external view returns (uint8);
    function getVirtualPrice() external view returns (uint256);
    function initialize(
        address[] calldata _pooledTokens,
        uint8[] calldata decimals,
        string calldata lpTokenName,
        string calldata lpTokenSymbol,
        uint256 _a,
        uint256 _fee,
        uint256 _adminFee,
        uint256 _withdrawFee
    ) external;
    function removeLiquidity(uint256 amount, uint256[] calldata minAmounts, uint256 deadline) external returns (uint256[] memory);
    function removeLiquidityImbalance(uint256[] calldata amounts, uint256 maxBurnAmount, uint256 deadline) external returns (uint256);
    function removeLiquidityOneToken(uint256 tokenAmount, uint8 tokenIndex, uint256 minAmount, uint256 deadline) external returns (uint256);
    function swap(uint8 tokenIndexFrom, uint8 tokenIndexTo, uint256 dx, uint256 minDy, uint256 deadline) external returns (uint256);
    function swapStorage() external view returns (uint256 initialA, uint256 futureA, uint256 initialATime, uint256 futureATime, uint256 swapFee, uint256 adminFee, uint256 defaultWithdrawFee, address lpToken);
    function updateUserWithdrawFee(address recipient, uint256 transferAmount) external;
}
